#!/usr/bin/env bash
# set-deepln.sh -- point the `Host deepln` alias in ~/.ssh/config at a new DeepLN instance.
#
# DeepLN rentals expire (~24h) and each new one gets a fresh domain + port. The
# deepln-setup workflow is: verify the box, then update HostName/Port under `Host deepln`.
# This script does both, and refuses to write a config that points at a dead or
# wrong machine.
#
# Usage:
#   set-deepln.sh 'ssh -p <ssh-port> root@abc123.deepln.com'   # paste the rental string verbatim
#   set-deepln.sh root@abc123.deepln.com <ssh-port>            # host + port
#   set-deepln.sh abc123.deepln.com <ssh-port>                 # port only, user defaults to root
#   set-deepln.sh --show                                  # print current alias + live status
#   set-deepln.sh --no-verify <args>                      # skip reachability/GPU checks
#   set-deepln.sh --expect-gpu 'Tesla T4' <args>          # accept a non-P4 box on purpose
#
# Exit codes: 0 ok | 1 verification failed | 2 usage error | 3 config write failed

set -uo pipefail

CONFIG="${SSH_CONFIG:-$HOME/.ssh/config}"
ALIAS="${DEEPLN_ALIAS:-deepln}"
IDENTITY="${DEEPLN_IDENTITY:-~/.ssh/id_ed25519}"
KEX="curve25519-sha256,diffie-hellman-group-exchange-sha256,ecdh-sha2-nistp256"
EXPECT_GPU="Tesla P4"
VERIFY=1
RETRIES=8

die()  { printf '\033[31merror:\033[0m %s\n' "$1" >&2; exit "${2:-2}"; }
info() { printf '  %s\n' "$*"; }
ok()   { printf '  \033[32m%s\033[0m\n' "$*"; }
warn() { printf '  \033[33m%s\033[0m\n' "$*"; }

# ---------- argument parsing ----------
SHOW=0
ARGS=()
while [ $# -gt 0 ]; do
    case "$1" in
        --show)       SHOW=1; shift ;;
        --no-verify)  VERIFY=0; shift ;;
        --expect-gpu) EXPECT_GPU="${2:-}"; shift 2 ;;
        --retries)    RETRIES="${2:-8}"; shift 2 ;;
        -h|--help)    sed -n '2,20p' "$0" | sed 's/^# \{0,1\}//'; exit 0 ;;
        *)            ARGS+=("$1"); shift ;;
    esac
done

current_field() {  # $1 = field name; prints value from `ssh -G`
    ssh -G "$ALIAS" 2>/dev/null | awk -v f="$(echo "$1" | tr 'A-Z' 'a-z')" 'tolower($1)==f {print $2; exit}'
}

has_block() {  # true when a `Host <alias>` stanza exists in $CONFIG
    [ -f "$CONFIG" ] || return 1
    awk -v a="$ALIAS" 'tolower($1)=="host"{for(i=2;i<=NF;i++) if($i==a){found=1; exit}} END{exit !found}' "$CONFIG"
}

if [ "$SHOW" -eq 1 ]; then
    echo "current alias '$ALIAS':"
    if ! has_block; then
        warn "no 'Host $ALIAS' block in $CONFIG"; exit 0
    fi
    info "HostName $(current_field hostname)"
    info "Port     $(current_field port)"
    info "User     $(current_field user)"
    printf '  Live     '
    if ssh -o BatchMode=yes -o ConnectTimeout=10 "$ALIAS" 'echo reachable' 2>/dev/null | grep -q reachable; then
        gpu=$(ssh -o BatchMode=yes -o ConnectTimeout=10 "$ALIAS" \
              'nvidia-smi --query-gpu=name,compute_cap --format=csv,noheader 2>/dev/null' 2>/dev/null | head -1)
        printf '\033[32mreachable\033[0m  %s\n' "${gpu:-(no nvidia-smi)}"
    else
        printf '\033[31munreachable\033[0m\n'
    fi
    exit 0
fi

[ "${#ARGS[@]}" -gt 0 ] || die "no target given. Try: $(basename "$0") 'ssh -p PORT user@host'  (--help for more)"

# ---------- parse target out of whatever the user pasted ----------
RAW="${ARGS[*]}"
PORT=""; USERHOST=""
# -p PORT  or  -pPORT
if [[ "$RAW" =~ -p[[:space:]]*([0-9]+) ]]; then PORT="${BASH_REMATCH[1]}"; fi
# user@host or bare host (first token containing a dot, ignoring the literal "ssh")
for tok in $RAW; do
    case "$tok" in
        ssh|-p|-[0-9]*|[0-9]*) continue ;;
        *.*) USERHOST="$tok"; break ;;
    esac
done
# trailing bare number = port, when -p was absent
if [ -z "$PORT" ]; then
    for tok in $RAW; do case "$tok" in [0-9][0-9]*) PORT="$tok" ;; esac; done
fi
# host:port form
case "$USERHOST" in *:[0-9]*) PORT="${USERHOST##*:}"; USERHOST="${USERHOST%:*}" ;; esac

USER_="${USERHOST%@*}"; HOST="${USERHOST##*@}"
[ "$USER_" = "$USERHOST" ] && USER_="root"

[ -n "$HOST" ] || die "could not parse a hostname out of: $RAW"
[ -n "$PORT" ] || die "could not parse a port out of: $RAW"
[[ "$PORT" =~ ^[0-9]+$ ]] && [ "$PORT" -ge 1 ] && [ "$PORT" -le 65535 ] || die "invalid port: $PORT"

echo "target:"
info "HostName $HOST"
info "Port     $PORT"
info "User     $USER_"

# ---------- verify before writing ----------
if [ "$VERIFY" -eq 1 ]; then
    echo "verifying (DeepLN DNS is flaky; up to $RETRIES tries):"
    SSH_OPTS=(-o BatchMode=yes -o StrictHostKeyChecking=accept-new -o ConnectTimeout=15
              -o KexAlgorithms="$KEX" -i "${IDENTITY/#\~/$HOME}" -p "$PORT")
    reached=0
    for i in $(seq 1 "$RETRIES"); do
        if out=$(ssh "${SSH_OPTS[@]}" "$USER_@$HOST" 'echo REACHED' 2>&1) && [[ "$out" == *REACHED* ]]; then
            ok "reachable on try $i"; reached=1; break
        fi
        info "retry $i: $(printf '%s' "$out" | tail -1 | cut -c1-70)"
        sleep 4
    done
    [ "$reached" -eq 1 ] || die "host never became reachable -- config NOT changed" 1

    gpu=$(ssh "${SSH_OPTS[@]}" "$USER_@$HOST" \
          'nvidia-smi --query-gpu=name,compute_cap,memory.total --format=csv,noheader 2>/dev/null' 2>/dev/null | head -1)
    if [ -z "$gpu" ]; then
        warn "no nvidia-smi output -- cannot confirm GPU"
    elif [[ "$gpu" == *"$EXPECT_GPU"* ]]; then
        ok "GPU: $gpu"
    else
        die "GPU is '$gpu', expected '$EXPECT_GPU'. Use --expect-gpu to override -- config NOT changed" 1
    fi

    torch=$(ssh "${SSH_OPTS[@]}" "$USER_@$HOST" \
      'source /data/miniconda/etc/profile.d/conda.sh 2>/dev/null && conda activate torch 2>/dev/null;
       python -c "import torch;print(torch.__version__,torch.cuda.is_available())" 2>/dev/null' 2>/dev/null | tail -1)
    [ -n "$torch" ] && ok "torch: $torch" || warn "torch env not ready -- run the deepln-setup skill after this"
else
    warn "--no-verify: writing config without checking the host"
fi

# ---------- write ----------
mkdir -p "$(dirname "$CONFIG")"; chmod 700 "$(dirname "$CONFIG")" 2>/dev/null
[ -f "$CONFIG" ] || : > "$CONFIG"
BACKUP="${CONFIG}.bak.$(date +%Y%m%d-%H%M%S)"
cp -p "$CONFIG" "$BACKUP" || die "could not back up $CONFIG" 3

TMP=$(mktemp) || die "mktemp failed" 3
trap 'rm -f "$TMP"' EXIT

if has_block; then
    # block exists -- rewrite only HostName/Port inside it
    awk -v a="$ALIAS" -v h="$HOST" -v p="$PORT" -v u="$USER_" '
        tolower($1)=="host" { inblk=0; for(i=2;i<=NF;i++) if($i==a) inblk=1 }
        inblk && tolower($1)=="hostname" { sub(/[^ \t].*/,""); print $0 "HostName " h; next }
        inblk && tolower($1)=="port"     { sub(/[^ \t].*/,""); print $0 "Port " p;     next }
        inblk && tolower($1)=="user"     { sub(/[^ \t].*/,""); print $0 "User " u;     next }
        { print }
    ' "$CONFIG" > "$TMP" || die "awk rewrite failed" 3
    ACTION="updated"
else
    # no block -- append a fresh one
    cat "$CONFIG" > "$TMP"
    [ -s "$TMP" ] && echo >> "$TMP"
    cat >> "$TMP" <<EOF
# DeepLN Tesla P4 instance.
# Rentals get a fresh domain + port each time. After verifying a new instance,
# update HostName and Port below -- do NOT add a *.deepln.com wildcard here:
# a wildcard rewrites HostName for every deepln host you type, silently sending
# you to whichever instance is hardcoded below. See the deepln-setup skill.
# Managed by scripts/set-deepln.sh
Host $ALIAS
    HostName $HOST
    Port $PORT
    User $USER_
    IdentityFile $IDENTITY
    KexAlgorithms $KEX
    ServerAliveInterval 60
    ServerAliveCountMax 3
EOF
    ACTION="created"
fi

cat "$TMP" > "$CONFIG" || die "could not write $CONFIG" 3
chmod 600 "$CONFIG"

echo "result:"
ok "$ACTION 'Host $ALIAS' in $CONFIG"
info "backup: $BACKUP"
info "ssh -G reports: $(current_field hostname):$(current_field port) as $(current_field user)"

if [ "$VERIFY" -eq 1 ]; then
    printf '  alias check: '
    if ssh -o BatchMode=yes -o ConnectTimeout=15 "$ALIAS" 'echo ALIAS_OK' 2>/dev/null | grep -q ALIAS_OK; then
        printf '\033[32mssh %s works\033[0m\n' "$ALIAS"
    else
        printf '\033[31mssh %s failed -- restore with: cp %s %s\033[0m\n' "$ALIAS" "$BACKUP" "$CONFIG"; exit 1
    fi
fi

# Warn about the wildcard footgun if someone reintroduced it.
if grep -qE '^[[:space:]]*Host[[:space:]].*\*\.deepln\.com' "$CONFIG"; then
    warn "a '*.deepln.com' wildcard is present in $CONFIG -- it will rewrite HostName"
    warn "for every deepln host you type. Remove it (see the deepln-setup skill)."
fi
