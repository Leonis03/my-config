#!/usr/bin/env bash
# agy-run.sh -- run one headless Antigravity CLI (agy) prompt with least privilege.
#
# The only supported way for an agent to call agy. Raw `agy -p` is unsafe to
# trust from a script: a permission denial ends agy's turn with exit 0 and an
# empty response. This wrapper always runs agy in its terminal sandbox, starts
# from an empty temp workspace unless told otherwise, and turns every outcome
# into an exit code.
#
# Usage:
#   agy-run.sh [options] PROMPT        run one prompt
#   agy-run.sh [options] -             read the prompt from stdin
#   agy-run.sh quota                   remaining quota (no model call)
#   agy-run.sh grants                  list agy's allow / deny rules
#   agy-run.sh grant write DIR         USER ONLY: let agy write inside DIR
#   agy-run.sh grant command PREFIX    USER ONLY: let agy run commands starting with PREFIX
#   agy-run.sh revoke write DIR | revoke command PREFIX
#
# Options:
#   --dir DIR       use DIR as the workspace: readable; writable only if granted
#   --image FILE    copy FILE into the temp workspace and point the prompt at it
#                   (repeatable; with --dir, FILE must already be inside DIR)
#   --model NAME    agy model, see `agy models` (default: agy's own default)
#   --timeout DUR   agy --print-timeout, e.g. 90s, 10m, 1h (default 10m)
#   --keep          keep the temp workspace and print its path
#   --dry-run       print the plan; do not call agy
#
# stdout = agy's response (possibly partial on exit 4/5); stderr = diagnostics,
# ending with one `agy-run: exit=...` summary line.
#
# Exit codes: 0 ok | 1 setup error | 2 usage | 3 agy/API error (quota, auth)
#             4 an action was blocked | 5 empty or incomplete response
#             6 refused by policy (workspace too broad, path missing)

set -uo pipefail

SETTINGS="${AGY_SETTINGS:-$HOME/.gemini/antigravity-cli/settings.json}"
LOG_DIR="${AGY_RUN_LOG_DIR:-${XDG_STATE_HOME:-$HOME/.local/state}/agy-run}"
LOG_KEEP=50
SELF="$(readlink -f -- "$0")"

die()  { printf 'agy-run: error: %s\n' "$1" >&2; exit "${2:-2}"; }
say()  { printf 'agy-run: %s\n' "$*" >&2; }
need() { command -v "$1" >/dev/null 2>&1 || die "$1 not found on PATH" 1; }

need jq

# ---------- agy settings ----------
check_settings() {  # agy silently denies EVERY tool when settings.json is invalid JSON
    [ -f "$SETTINGS" ] || return 0
    jq -e . "$SETTINGS" >/dev/null 2>&1 \
        || die "$SETTINGS is not valid JSON -- agy would silently deny every tool" 1
}

rules() {  # $1 = allow|deny|ask; one rule per line
    [ -f "$SETTINGS" ] || return 0
    jq -r --arg k "$1" '(.permissions[$k] // [])[]' "$SETTINGS"
}

write_granted() {  # true when an allow rule write_file(P) covers $1
    local p
    while IFS= read -r p; do
        p=${p#write_file(}; p=${p%)}
        [ "$p" = '*' ] && return 0
        case "$1/" in "${p%/}/"*) return 0 ;; esac
    done < <(rules allow | grep '^write_file(')
    return 1
}

too_broad() {  # true for / , $HOME and every ancestor of $HOME
    local home; home=$(readlink -f -- "$HOME")
    [ "$1" = / ] && return 0
    case "$home/" in "$1/"*) return 0 ;; esac
    return 1
}

edit_rule() {  # $1 = add|del, $2 = rule; atomic rewrite, one rolling backup
    local tmp
    if [ ! -f "$SETTINGS" ]; then
        mkdir -p "$(dirname "$SETTINGS")" && printf '{}\n' > "$SETTINGS" && chmod 600 "$SETTINGS" \
            || die "cannot create $SETTINGS" 1
    fi
    check_settings
    cp -p -- "$SETTINGS" "$SETTINGS.agy-run.bak" || die "cannot back up $SETTINGS" 1
    tmp=$(mktemp "$SETTINGS.XXXXXX") || die "cannot write next to $SETTINGS" 1
    if [ "$1" = add ]; then
        jq --arg r "$2" 'if any((.permissions.allow // [])[]; . == $r) then .
                         else .permissions.allow = ((.permissions.allow // []) + [$r]) end' \
            "$SETTINGS" > "$tmp"
    else
        jq --arg r "$2" '.permissions.allow = ((.permissions.allow // []) | map(select(. != $r)))' \
            "$SETTINGS" > "$tmp"
    fi || { rm -f "$tmp"; die "jq failed; $SETTINGS unchanged" 1; }
    chmod --reference="$SETTINGS" "$tmp" 2>/dev/null
    mv -- "$tmp" "$SETTINGS" || die "cannot replace $SETTINGS" 1
}

cmd_grants() {
    check_settings
    echo "settings: $SETTINGS"
    local k
    for k in allow deny ask; do
        echo "$k:"; rules "$k" | sed 's/^/  /'
    done
    rules allow | grep -q '(\*)$' && echo "warning: wildcard allow rule(s) -- agy-run cannot confine those"
    rules deny | grep -qx 'write_file(/tmp)' \
        || echo "warning: no deny rule write_file(/tmp) -- agy's file tools can write anywhere in /tmp"
}

cmd_grant() {  # $1 = grant|revoke, $2 = write|command, $3 = target
    local verb=$1 kind=${2:-} target=${3:-} rule
    [ $# -eq 3 ] || die "usage: $verb write DIR | $verb command PREFIX"
    case "$kind" in
        write)
            if [ "$verb" = grant ]; then
                [ -d "$target" ] || die "$target: not a directory" 6
                target=$(readlink -f -- "$target")
                too_broad "$target" && die "$target is / , \$HOME or an ancestor of it -- grant a project directory" 6
                case "$target/" in /tmp/*) say "note: deny rule write_file(/tmp) wins over this grant" ;; esac
            else
                target=$(readlink -f -- "$target" 2>/dev/null || printf '%s' "$target")
            fi
            rule="write_file($target)" ;;
        command)
            [ -n "${target//[[:space:]]/}" ] || die "empty command prefix"
            case "$target" in '*'|regex:*) die "refusing wildcard/regex command rule: $target" 6 ;; esac
            rule="command($target)" ;;
        *) die "usage: $verb write DIR | $verb command PREFIX" ;;
    esac
    if [ "$verb" = grant ]; then edit_rule add "$rule"; else edit_rule del "$rule"; fi
    echo "$verb: $rule"
    echo "allow now:"; rules allow | sed 's/^/  /'
}

cmd_quota() {
    need agy
    local d; d=$(mktemp -d) || die "mktemp failed" 1
    ( cd "$d" && timeout 120 agy -p /quota </dev/null ); local rc=$?
    rm -rf -- "$d"; exit "$rc"
}

case "${1:-}" in
    quota)          cmd_quota ;;
    grants)         cmd_grants; exit 0 ;;
    grant|revoke)   cmd_grant "$@"; exit 0 ;;
    -h|--help)      sed -n '2,/^$/p' "$0" | sed 's/^# \{0,1\}//'; exit 0 ;;
    "")             sed -n '2,/^$/p' "$0" | sed 's/^# \{0,1\}//' >&2; exit 2 ;;
esac

# ---------- run: argument parsing ----------
DIR="" MODEL="" TIMEOUT=10m KEEP=0 DRY=0 PROMPT="" HAVE_PROMPT=0
IMAGES=()
while [ $# -gt 0 ]; do
    case "$1" in
        --dir)      [ $# -ge 2 ] || die "--dir needs a value"; DIR=$2; shift 2 ;;
        --image)    [ $# -ge 2 ] || die "--image needs a value"; IMAGES+=("$2"); shift 2 ;;
        --model)    [ $# -ge 2 ] || die "--model needs a value"; MODEL=$2; shift 2 ;;
        --timeout)  [ $# -ge 2 ] || die "--timeout needs a value"; TIMEOUT=$2; shift 2 ;;
        --keep)     KEEP=1; shift ;;
        --dry-run)  DRY=1; shift ;;
        --)         shift; [ $# -eq 1 ] || die "expected exactly one PROMPT after --"; PROMPT=$1; HAVE_PROMPT=1; shift ;;
        -)          PROMPT=-; HAVE_PROMPT=1; shift ;;
        -*)         die "unknown option: $1 (see --help)" ;;
        *)          [ "$HAVE_PROMPT" -eq 0 ] || die "more than one PROMPT -- quote it"; PROMPT=$1; HAVE_PROMPT=1; shift ;;
    esac
done
[ "$HAVE_PROMPT" -eq 1 ] || die "missing PROMPT (see --help)"
[ "$PROMPT" = - ] && PROMPT=$(cat)
[ -n "${PROMPT//[[:space:]]/}" ] || die "empty prompt"

[[ "$TIMEOUT" =~ ^([0-9]+)([smh])$ ]] || die "--timeout must look like 90s, 10m or 1h"
case "${BASH_REMATCH[2]}" in s) secs=1 ;; m) secs=60 ;; h) secs=3600 ;; esac
HARD=$(( BASH_REMATCH[1] * secs + 120 ))   # agy returns partial output at DUR; this is the backstop

need agy
check_settings

# ---------- workspace ----------
WS="" TEMP_WS=0 IMG_PATHS=()
if [ -n "$DIR" ]; then
    [ -d "$DIR" ] || die "--dir $DIR: not a directory" 6
    WS=$(readlink -f -- "$DIR")
    too_broad "$WS" && die "--dir $WS is / , \$HOME or an ancestor of it -- pick a project directory" 6
    for f in ${IMAGES[@]+"${IMAGES[@]}"}; do
        [ -f "$f" ] || die "--image $f: no such file" 6
        f=$(readlink -f -- "$f")
        case "$f" in "$WS"/*) IMG_PATHS+=("$f") ;; *) die "--image $f is outside --dir $WS" 6 ;; esac
    done
else
    for f in ${IMAGES[@]+"${IMAGES[@]}"}; do [ -f "$f" ] || die "--image $f: no such file" 6; done
    TEMP_WS=1
    if [ "$DRY" -eq 1 ]; then
        WS="${TMPDIR:-/tmp}/agy-run-XXXXXX"
        for f in ${IMAGES[@]+"${IMAGES[@]}"}; do IMG_PATHS+=("$WS/$(basename -- "$f")"); done
    else
        WS=$(mktemp -d "${TMPDIR:-/tmp}/agy-run-XXXXXX") || die "mktemp failed" 1
        [ "$KEEP" -eq 1 ] || trap 'rm -rf -- "$WS"' EXIT
        for f in ${IMAGES[@]+"${IMAGES[@]}"}; do
            b=$(basename -- "$f")
            [ -e "$WS/$b" ] && die "two --image files are named $b -- rename one"
            cp -- "$f" "$WS/$b" && chmod 644 "$WS/$b" || die "cannot copy $f" 1
            IMG_PATHS+=("$WS/$b")
        done
    fi
fi

WRITABLE=no
[ "$TEMP_WS" -eq 0 ] && write_granted "$WS" && WRITABLE=yes

# ---------- prompt ----------
# A command outside the allowlist ends agy's turn, so say plainly when not to use the shell.
NOTE="[agy-run] Workspace: $WS"
if [ "${#IMG_PATHS[@]}" -gt 0 ]; then
    NOTE+=$'\n'"Image files -- open them with your file-viewing tool, not the shell:"
    for f in "${IMG_PATHS[@]}"; do NOTE+=$'\n'"- $f"; done
fi
if [ "$TEMP_WS" -eq 1 ]; then
    NOTE+=$'\n'"Answer directly. Do not run shell commands."
else
    NOTE+=$'\n'"Shell commands run in a sandbox without network access; use them only when needed."
    [ "$WRITABLE" = no ] && NOTE+=" The workspace is read-only."
fi
FULL_PROMPT="$PROMPT"$'\n\n'"$NOTE"

AGY_ARGS=(--sandbox --disable-slash-commands --output-format stream-json --print-timeout "$TIMEOUT")
[ -n "$MODEL" ] && AGY_ARGS+=(--model "$MODEL")
AGY_ARGS+=(-p "$FULL_PROMPT")

if [ "$DRY" -eq 1 ]; then
    echo "workspace: $WS ($([ "$TEMP_WS" -eq 1 ] && echo 'new temp dir, removed afterwards' || echo "--dir, writable=$WRITABLE"))"
    for f in ${IMAGES[@]+"${IMAGES[@]}"}; do echo "image:     $f"; done
    printf 'command:   cd %q && agy' "$WS"; printf ' %q' "${AGY_ARGS[@]:0:${#AGY_ARGS[@]}-2}"; echo ' -p <prompt>'
    echo "prompt:"; printf '%s\n' "$FULL_PROMPT" | sed 's/^/  | /'
    echo "command rules (checked by agy, run inside the sandbox):"; rules allow | grep '^command(' | sed 's/^/  /'
    rules deny | grep -qx 'write_file(/tmp)' \
        || echo "warning: no deny rule write_file(/tmp) -- agy's file tools can write anywhere in /tmp"
    exit 0
fi

# ---------- run ----------
mkdir -p "$LOG_DIR" || die "cannot create $LOG_DIR" 1
STAMP=$(date +%Y%m%d-%H%M%S)-$$
OUT=$LOG_DIR/$STAMP.jsonl ERR=$LOG_DIR/$STAMP.err
( cd "$WS" && timeout -k 10 "$HARD" agy "${AGY_ARGS[@]}" ) >"$OUT" 2>"$ERR" </dev/null
RC=$?
ls -1t "$LOG_DIR"/*.jsonl 2>/dev/null | tail -n +$((LOG_KEEP + 1)) | while IFS= read -r f; do
    rm -f -- "$f" "${f%.jsonl}.err"
done

# ---------- verdict ----------
# fromjson? skips any non-JSON line agy might print to stdout
ev() { jq -rR "fromjson? | $1" "$OUT"; }
RESPONSE=$(ev 'select(.event=="result") | .result.response // empty')
STATUS=$(ev 'select(.event=="result") | .result.status // empty')
USED_MODEL=$(ev 'select(.event=="init") | .init.model // empty')
DENIED=$(ev 'select(.event=="result") | (.result.denied_actions // [])[] | .action')
# Last update of each tool step: state, tool, target, error message, output.
# Fields are joined with \x1f, not tabs: tab is IFS whitespace, so empty fields would collapse.
US=$'\x1f'
STEPS=$(jq -cR 'fromjson? | select(.event=="step_update" and .step_update.step_type=="tool") | .step_update' "$OUT" \
    | jq -rs 'group_by(.step_index) | map(last)[]
              | [ .state, .tool_name,
                  (.tool_info.parameters | .CommandLine // .TargetFile // .AbsolutePath // tostring),
                  (.tool_info.error.message // ""),
                  (.tool_info.output // "" | tostring) ]
              | map(tostring | gsub("[\u001f\t\n\r]"; " ")) | join("\u001f")')
N_TOOLS=$(printf '%s' "$STEPS" | grep -c . )

hint() {  # $1 = action, $2 = target, $3 = error message
    case "$3" in *"deny rule"*) echo "a deny rule in $SETTINGS blocks this"; return ;; esac
    case "$1" in
        write_file)  local d; d=$(dirname -- "$2")
                     [ "$TEMP_WS" -eq 0 ] && case "$2" in "$WS"/*) d=$WS ;; esac
                     echo "needs a write grant; ask the user, who may run: ! bash $SELF grant write $d" ;;
        command|unsandboxed)
                     if rules allow | grep -qxF "command(${2%% *})"; then
                         # the command word is allowed, so the path it writes to is not
                         echo "command is allowlisted but writes outside a granted dir; ask the user, who may run: ! bash $SELF grant write <dir>"
                     else
                         echo "command not allowlisted; ask the user, who may run: ! bash $SELF grant command '${2%% *}'"
                     fi ;;
        read_file)   echo "outside the workspace; pass the file with --image or pick a --dir that contains it" ;;
        *)           echo "no agy-run grant covers '$1'; see $SETTINGS" ;;
    esac
}

BLOCKED=() NOTES=()
while IFS=$US read -r st tool target emsg out; do
    [ -n "$st" ] || continue
    if [ "$st" = ERROR ] && [[ "$emsg" =~ permission\ check\ failed\ for\ ([a-z_]+) ]]; then
        BLOCKED+=("$tool($target) -- $(hint "${BASH_REMATCH[1]}" "$target" "$emsg")")
    elif [ "$st" = ERROR ]; then
        NOTES+=("tool error: $tool($target): ${emsg:0:200}")
    elif [ "$tool" = run_command ] && [[ "$out" =~ (Read-only\ file\ system|Could\ not\ resolve\ host|Failed\ to\ connect\ to\ 127\.0\.0\.1) ]]; then
        NOTES+=("sandbox: $target -> ${BASH_REMATCH[1]}")
    fi
    LAST_TOOL=$tool LAST_TARGET=$target
done <<< "$STEPS"
# A soft-denied tool (headless cannot prompt) may leave no ERROR step: blame the last tool call.
if [ -n "$DENIED" ] && [ "${#BLOCKED[@]}" -eq 0 ]; then
    for a in $DENIED; do
        BLOCKED+=("${LAST_TOOL:-?}(${LAST_TARGET:-?}) [$a] -- $(hint "$a" "${LAST_TARGET:-}" "")")
    done
fi

API_ERR=$(grep -m1 '^AGY_ERROR: ' "$ERR" | sed 's/^AGY_ERROR: //')
FATAL=$(grep -m1 -E '^error: ' "$ERR")
INCOMPLETE=0
grep -qiE 'truncat|timed out|time limit|print-timeout' "$ERR" && INCOMPLETE=1

if [ -n "$API_ERR" ] || [ "$RC" -eq 3 ]; then
    EXIT=3
    short=$(printf '%s' "$API_ERR" | jq -r '.short_error // empty' 2>/dev/null)
    say "agy/API error: ${short:-${FATAL:-exit $RC}}"
    case "$API_ERR" in
        *RESOURCE_EXHAUSTED*) say "quota exhausted: check 'bash $SELF quota'; Gemini and Claude/GPT models have separate pools (--model)" ;;
        *UNAUTHENTICATED*|*"sign in"*) say "login expired: the user must run an interactive 'agy' once" ;;
    esac
elif [ "${#BLOCKED[@]}" -gt 0 ]; then
    EXIT=4
elif [ "$RC" -eq 124 ] || [ "$RC" -eq 137 ]; then
    EXIT=5; say "killed after ${HARD}s (hard timeout)"
elif [ -z "$RESPONSE" ] || [ "$INCOMPLETE" -eq 1 ] || [ "$STATUS" != SUCCESS ] || [ "$RC" -ne 0 ]; then
    EXIT=5
    [ -n "$FATAL" ] && say "$FATAL"
    [ "$INCOMPLETE" -eq 1 ] && say "response may be incomplete (print timeout); raise --timeout"
    [ -z "$RESPONSE" ] && say "empty response (status=${STATUS:-none}, agy exit $RC)"
else
    EXIT=0
fi

for b in ${BLOCKED[@]+"${BLOCKED[@]}"}; do say "BLOCKED $b"; done
for n in ${NOTES[@]+"${NOTES[@]}"}; do say "$n"; done
[ -n "$RESPONSE" ] && printf '%s\n' "$RESPONSE"
ws_desc=$WS; [ "$TEMP_WS" -eq 1 ] && { [ "$KEEP" -eq 1 ] && ws_desc="$WS (temp, kept)" || ws_desc="temp (removed)"; }
say "exit=$EXIT status=${STATUS:-none} model=${USED_MODEL:-?} workspace=$ws_desc writable=$WRITABLE tools=$N_TOOLS blocked=${#BLOCKED[@]} log=$OUT"
exit "$EXIT"
