#!/usr/bin/env bash
# agy-guard.sh -- Claude Code PreToolUse hook: keep the agent on agy-run.sh.
#
# Denies, for Bash:
#   - `agy-run.sh grant ...`           widening agy's access is the user's call
#   - agy with --dangerously-skip-permissions
#   - raw `agy -p/--print/--prompt/-i/--prompt-interactive`   use agy-run.sh
#   - shell writes to agy's permission files (settings.json, config/projects/)
# and for Edit / Write / MultiEdit / NotebookEdit: any edit of those files.
#
# A guardrail against mistakes, not a security boundary: it matches command
# text, so `bash "$X" grant` with X set earlier gets through. Hooks still run in
# bypassPermissions mode, which is why this lives in a hook and not in
# permission rules.
#
# Install (in ~/.claude/settings.json):
#   "hooks": {"PreToolUse": [{"matcher": "Bash|Edit|Write|MultiEdit|NotebookEdit",
#     "hooks": [{"type": "command", "command": "bash ~/.claude/skills/antigravity-cli/scripts/agy-guard.sh"}]}]}
#
# Fails open (allows) when jq is missing or the input is not JSON, so a broken
# guard never blocks every tool call.

set -uo pipefail

command -v jq >/dev/null 2>&1 || exit 0
INPUT=$(cat)
TOOL=$(printf '%s' "$INPUT" | jq -r '.tool_name // empty' 2>/dev/null) || exit 0

AGY_SETTINGS="$HOME/.gemini/antigravity-cli/settings.json"
AGY_PROJECTS="$HOME/.gemini/config/projects"
RUNNER="bash ~/.claude/skills/antigravity-cli/scripts/agy-run.sh"

deny() {
    jq -n --arg r "agy-guard: $1" \
        '{hookSpecificOutput: {hookEventName: "PreToolUse", permissionDecision: "deny", permissionDecisionReason: $r}}'
    exit 0
}

is_agy_config() {  # $1 = path; true for agy's permission files
    local p=$1
    case "$p" in \~/*) p="$HOME/${p#\~/}" ;; esac
    p=$(realpath -m -- "$p" 2>/dev/null) || return 1
    [ "$p" = "$AGY_SETTINGS" ] && return 0
    case "$p" in "$AGY_PROJECTS"/*) return 0 ;; esac
    return 1
}

case "$TOOL" in
    Edit|Write|MultiEdit|NotebookEdit)
        path=$(printf '%s' "$INPUT" | jq -r '.tool_input.file_path // .tool_input.notebook_path // empty')
        [ -n "$path" ] && is_agy_config "$path" \
            && deny "$path holds agy's permissions; only the user changes them, via '$RUNNER grant|revoke ...' (see the antigravity-cli skill)"
        exit 0 ;;
    Bash) ;;
    *) exit 0 ;;
esac

CMD=$(printf '%s' "$INPUT" | jq -r '.tool_input.command // empty')
[ -n "$CMD" ] || exit 0

# Writes to the permission files. Plain reads (cat, jq ., grep) stay allowed.
if { [[ "$CMD" == *antigravity-cli* && "$CMD" == *settings.json* ]] || [[ "$CMD" == *.gemini/config/projects* ]]; } \
    && printf '%s' "$CMD" | grep -qP '>(?!\s*(&|/dev/null))|\b(tee|sponge|cp|mv|rm|ln|install|truncate|dd|rsync|chmod|python3?|node|perl|ruby)\b|sed\s+(-[a-zA-Z]*i|--in-place)'; then
    deny "this command would modify agy's permission files; only the user changes them, via '$RUNNER grant|revoke ...'"
fi

# Walk each simple command (split on ; & | and newlines), token by token.
# Quoted mentions such as grep "agy -p" stay one token (\"agy) and do not match.
while IFS= read -r seg; do
    read -r -a tok <<< "$seg" || true
    agy_at=-1
    for i in "${!tok[@]}"; do
        t=${tok[$i]}
        if [ "$agy_at" -lt 0 ]; then
            w=${t#\$\(}; w=${w#\(}; w=${w#\`}          # $(agy ..., (agy ..., `agy ...
            [ "${w##*/}" = agy ] && agy_at=$i
            case "$t" in *agy-run.sh)
                [ "${tok[$((i + 1))]:-}" = grant ] && deny "'agy-run.sh grant' is for the user to run. Ask them first (AskUserQuestion: which rule, why); if they agree they type: ! $RUNNER grant ..." ;;
            esac
            continue
        fi
        case "$t" in
            --dangerously-skip-permissions)
                deny "agy must not run with --dangerously-skip-permissions; use $RUNNER, which keeps agy sandboxed" ;;
            -p|--print|--print=*|--prompt|--prompt=*|-i|--prompt-interactive|--prompt-interactive=*)
                deny "call agy through $RUNNER (sandboxed, reports blocked actions as exit 4), not 'agy $t' directly" ;;
        esac
    done
done < <(printf '%s\n' "$CMD" | tr ';&|' '\n\n\n')

exit 0
