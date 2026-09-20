#!/usr/bin/env bash
# privacy-gate.sh -- scan this repo for identifying information before publishing.
#
# Run from anywhere:  bash tools/privacy-gate.sh [name ...]
# Exit 0 = clean, exit 1 = findings.
#
# THE ACCOUNT NAMES ARE NOT IN THIS FILE, ON PURPOSE
#
# Every other check here is structural: it knows the SHAPE of a leak
# (`Users\<something>\`, `S-1-5-21-<digits>`) without knowing your account
# name. That is what lets this script be published. But a bare `whoami`
# output -- one short word alone on a line, inside a ```text block -- has no
# shape at all. Nothing but the literal name finds it.
#
# So the names are supplied at run time and never written down here:
#
#   bash tools/privacy-gate.sh NAME             # argv
#   PRIVACY_NAMES="NAME OTHER" bash tools/...   # environment
#   printf 'NAME\n' > tools/.privacy-names      # gitignored, set up once
#
# The file is the one to use in practice -- argv and env only protect the run
# you remember to type them on. Matching is case-insensitive, so one entry
# covers both the Linux and the Windows spelling of the same name; list a
# name once per distinct spelling, not once per casing.
#
# Note the examples above say NAME, not a real one. An example is still a
# value: writing the actual name here would undo the entire point.
#
# WHY THIS EXISTS, AND WHAT IT CANNOT DO
#
# Three rounds of pattern-based scrubbing each passed clean, and each time a
# human reading the files found more. Every miss had the same shape: the SAME
# information rendered a DIFFERENT way.
#
#   round 1  matched S-1-5-21-*            missed S-1-5-83-*        (VM SIDs)
#   round 2  matched Users/<name>          missed `NAME:(I)(F)`     (icacls bare form)
#   round 3  matched S-1-5-83-<digits>     missed `NT VIRTUAL MACHINE\<GUID>`
#                                                 (same VM, resolved to a name)
#
# So: a clean run here means "none of the known shapes are present". It does
# NOT mean the repo is safe to publish. Read the files. Especially anything
# under wsl/storage/, which is raw icacls / auditpol / Procmon output and is
# where all three misses lived.

set -uo pipefail
cd "$(dirname "$0")/.." || exit 2

# .privacy-names holds the names by design; scanning it would fail every run.
# It is gitignored, so it is never what gets published.
#
# tmp/ is the scratch area (gitignored, see README "约定"): raw command output,
# backups taken before an overwrite, half-finished edits. It is EXPECTED to
# hold real paths and account names -- that is the point of having somewhere to
# put them. Scanning it would fail the run over files that can never be
# committed and never reach `git archive`.
EXCLUDE=(--exclude-dir=.git --exclude-dir=node_modules --exclude-dir=tmp --exclude=.privacy-names)
fail=0

NAMES_FILE=tools/.privacy-names
NAMES=()
if [ "$#" -gt 0 ]; then
  NAMES=("$@")
elif [ -n "${PRIVACY_NAMES:-}" ]; then
  read -r -a NAMES <<< "$PRIVACY_NAMES"
elif [ -f "$NAMES_FILE" ]; then
  while IFS= read -r line || [ -n "$line" ]; do
    line=${line%%#*}
    line=$(printf '%s' "$line" | tr -d '[:space:]')
    [ -n "$line" ] && NAMES+=("$line")
  done < "$NAMES_FILE"
fi

# Turn a literal name into an ERE that matches it in any casing: each letter
# becomes [xX]. Regex metacharacters are escaped first -- a name is user input
# and `.` or `+` in one would otherwise silently widen the match.
name_to_ere() {
  printf '%s' "$1" \
    | sed -e 's/[][\.*^$(){}?+|\\/]/\\&/g' \
          -e 's/\([a-zA-Z]\)/[\l\1\u\1]/g'
}

# Lines that are already sanitised, or that are generic documentation examples,
# still match the patterns below. Drop them, or every run drowns in its own
# placeholders. Keep this list tight: each entry is a hole in the gate.
ALLOW='<[a-z][a-z0-9-]*>'          # any <placeholder>
ALLOW+='|XXXXXXXX|xxxxxxxx'        # redacted digit/char runs
ALLOW+='|Users[/\\]Public'         # standard Windows folder, not a person
ALLOW+='|/home/user\b'             # the literal word "user" in an example
ALLOW+='|/home/\.\.\.'             # elided example path

check() {
  local label="$1" pattern="$2" note="${3:-}"
  local hits
  hits=$(grep -rnIE "$pattern" "${EXCLUDE[@]}" . 2>/dev/null | grep -vE "$ALLOW")
  if [ -n "$hits" ]; then
    printf '\n[FAIL] %s\n' "$label"
    [ -n "$note" ] && printf '       %s\n' "$note"
    printf '%s\n' "$hits" | head -20 | sed 's/^/       /'
    local n; n=$(printf '%s\n' "$hits" | wc -l)
    [ "$n" -gt 20 ] && printf '       ... and %s more\n' "$((n - 20))"
    fail=1
  else
    printf '  ok   %s\n' "$label"
  fi
}

echo "=== identifiers ==="
# A personal-looking email. GitHub's noreply form is deliberate and excluded.
check "personal email address" \
      '[A-Za-z0-9._%+-]+@(gmail|outlook|hotmail|qq|163|126|foxmail|yahoo|icloud)\.[A-Za-z]{2,}'
check "absolute home path" '/home/[a-z][a-z0-9_-]*\b' \
      'use $HOME or ~ instead'
check "Windows user path" 'Users[/\\]+[A-Za-z][A-Za-z0-9_.-]*[/\\]' \
      'placeholder should be <your-windows-user> or <user>'

echo
echo "=== account names supplied at run time ==="
if [ "${#NAMES[@]}" -eq 0 ]; then
  echo "  SKIP no names given -- the literal-name check did NOT run."
  echo "       This is the only check that catches a bare \`whoami\` line."
  echo "       Enable it once:  printf 'name\\n' > $NAMES_FILE   (gitignored)"
  names_skipped=1
else
  names_skipped=0
  for name in "${NAMES[@]}"; do
    ere=$(name_to_ere "$name")
    if [ "${#name}" -le 2 ]; then
      # A 1-2 character name matches inside ordinary words, hex digits and
      # single-letter key bindings, so a bare \b match would bury the run in
      # noise. Restrict it to the shapes an account name actually appears in.
      pattern="(^|[[:space:]])$ere\$"      # alone on a line -- whoami output
      pattern+="|\`$ere\`"                 # quoted in prose
      pattern+="|$ere\\\\"                 # owner column in dir /q output
      pattern+="|$ere:\("                  # NAME:( -- icacls principal
      pattern+="|/home/$ere\b"             # Linux home
      pattern+="|Users[/\\\\]$ere\b"       # Windows profile
      pattern+="|$ere@|@$ere\b"            # prompt / address
      note="short name: checked in account-shaped contexts only, not every occurrence"
    else
      pattern="\b$ere\b"
      note="literal account name"
    fi
    check "account name \"$name\"" "$pattern" "$note"
  done
fi

echo
echo "=== Windows security identifiers ==="
# Round 1 missed the 83 authority; keep both, and any future authority too.
check "numeric SID (user/machine/VM)" 'S-1-5-(21|83)-[0-9]{4,}'
# Round 3 missed this: same VM, rendered as a resolved name instead of a SID.
check "VM SID resolved to a name" 'NT VIRTUAL MACHINE\\[0-9A-Fa-f]{8}-'
# Round 2 missed this: icacls prints a bare principal with no Users/ prefix.
check "icacls bare principal" '(^|[[:space:]])[A-Z][A-Za-z0-9_-]*\\:\(' \
      'e.g. `NAME\:(I)(F)` -- the account name with no path around it'
# Round 4, same shape as round 2: the check above only knows the icacls
# rendering (`NAME:(...)`). `dir /q` prints the SAME owner as a padded column
# (`NAME\` + spaces + filename), which sailed straight through it. Requiring
# 2+ trailing spaces is what distinguishes a column from a backslash-escaped
# space in a path (`/mnt/c/Program\ Files`), which has exactly one.
check "dir /q owner column" '[[:space:]][A-Za-z][A-Za-z0-9_.-]{0,30}\\[[:space:]]{2,}' \
      'e.g. `NAME\                  ext4.vhdx` -- owner column in dir /q output'
check "host\\user pair" '\b[A-Za-z][A-Za-z0-9_-]*\\[A-Za-z][A-Za-z0-9_-]*\b.*([Hh]ost user|owner)'
check "explicit owner line" 'owner[[:space:]]*:[[:space:]]*[A-Za-z][A-Za-z0-9_-]*$'

echo
echo "=== credentials ==="
check "GitHub token" '(github_pat_|ghp_|gho_|ghu_|ghs_|ghr_)[A-Za-z0-9_]{10,}'
check "Brave API key" 'BSA[A-Za-z0-9_-]{6,}' \
      'even a truncated key keeps its real prefix and suffix'
check "generic API key assignment" '(api[_-]?key|secret|passwd|password)[[:space:]]*[=:][[:space:]]*["'"'"']?[A-Za-z0-9_/+-]{16,}'
check "private key block" 'BEGIN (OPENSSH|RSA|EC|DSA|PGP) PRIVATE KEY'

echo
echo "=== machine and session fingerprints ==="
check "cloud instance hostname" '[a-z0-9]{16,}\.[a-z0-9-]+\.(com|net|io|cn)'
# The keyword-gated version of this check (sessionId|conversationId|/c/) read
# as precise and was in fact blind: the label next to the UUID was written in
# Chinese (`会话 ID:`), so two real ids passed. Anchoring on a *label* is the
# round-2 mistake again -- the id is the secret, not the word in front of it.
# So: flag every unbraced UUID. Braced ones are the distro-key / CLSID case,
# handled as a WARN below; `[^{...]` keeps them out of here.
check "bare UUID (session, conversation, instance)" \
      '(^|[^{0-9a-fA-F-])[0-9a-fA-F]{8}-[0-9a-fA-F]{4}-[0-9a-fA-F]{4}-[0-9a-fA-F]{4}-[0-9a-fA-F]{12}' \
      'no keyword required -- a label can be in any language, or absent'
check "AI chat share URL" 'https?://(chat\.openai|chatgpt|claude)\.(com|ai)/(c|share)/[0-9a-zA-Z-]{20,}'
check "shell prompt sample with host" '[a-z][a-z0-9_-]*@[A-Za-z][A-Za-z0-9_-]*:~' \
      'statusline/prompt examples leak both usernames at once'
check "real currency amount" '\$[0-9]+\.[0-9]{2}' \
      'billing figures from real sessions'

echo
echo "=== warnings (review manually, not auto-fail) ==="
# A braced GUID is usually a WSL distro registry key (machine-unique), but it
# can also be a vendor CLSID (e.g. AMD's shell extension), which is public.
if grep -rnIE '\{[0-9a-fA-F]{8}-[0-9a-fA-F]{4}-[0-9a-fA-F]{4}-[0-9a-fA-F]{4}-[0-9a-fA-F]{12}\}' "${EXCLUDE[@]}" . >/dev/null 2>&1; then
  echo "  WARN braced GUID present -- distro registry keys are machine-unique;"
  echo "       vendor CLSIDs are public. Check which kind each one is:"
  grep -rnIE '\{[0-9a-fA-F]{8}-' "${EXCLUDE[@]}" . 2>/dev/null | head -10 | sed 's/^/       /'
fi
# S-1-15-3-* capability SIDs are hashes of a capability name and are identical
# on every Windows install, so they are NOT flagged above. Noted here only so
# nobody "fixes" them later.
echo "  note S-1-15-3-* capability SIDs are intentionally allowed (same on every machine)"

echo
if [ "$fail" -eq 0 ]; then
  echo "RESULT: no known pattern matched."
  echo "        This is necessary, not sufficient. Read wsl/storage/ by hand."
  [ "$names_skipped" -eq 1 ] && \
    echo "        AND the literal-name check was skipped -- see SKIP above."
else
  echo "RESULT: findings above. Fix, then re-run."
fi
exit "$fail"
