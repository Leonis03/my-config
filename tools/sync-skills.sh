#!/usr/bin/env bash
# sync-skills.sh -- deploy agent/skills/ to the live harnesses, or verify they match.
#
#   bash tools/sync-skills.sh                 # check (default): report per skill, per target
#   bash tools/sync-skills.sh deploy          # render and write to the live copies
#   bash tools/sync-skills.sh deploy <name>   # just one skill
#   bash tools/sync-skills.sh check  <name>
#
# Exit 0 = every checked skill matches, exit 1 = drift, exit 2 = setup error.
#
# WHY RENDERING, AND NOT A PLAIN cp
#
# This repo is redacted. It says `<your-home>`, `<your-windows-user>`,
# `CourseName` exactly where the live copies say the real home, the real
# Windows account, the real course name. A plain cp is a bug in BOTH
# directions:
#
#   repo -> live   wsl-cjk-font starts probing
#                  /mnt/c/Users/<your-windows-user>/.../SarasaTermSC-Regular.ttf
#                  No such file. matplotlib falls back to DejaVu Sans and emits
#                  tofu squares WITHOUT raising -- the exact failure that skill
#                  exists to prevent.
#
#   live -> repo   the account name lands in a public repo, and
#                  privacy-gate.sh stops it -- after you already committed.
#
# NOTE a literal `$HOME` in the repo is NOT a placeholder and is never
# substituted -- it is a runtime shell variable that ships as-is, which is what
# keeps set-deepln.sh working on a RENTED box whose home is not yours. The
# placeholder `<your-home>` is only for spots a shell never expands (JSON,
# Python string literals); see agent/skills/README.md.
#
# So: substitute on the way out, and compare the SUBSTITUTED bytes on the way
# back. Hash equality then means what you actually want it to mean -- "the repo
# is the live copy, modulo redaction".
#
# THE MAP IS NOT IN THIS FILE, ON PURPOSE
#
# Same reasoning as privacy-gate.sh: the real values are supplied at run time so
# that this script itself can be published. tools/.sync-map is gitignored, one
# `PLACEHOLDER=VALUE` per line, `#` comments and blank lines ignored:
#
#   <your-home>=/home/<your-linux-user>
#   <your-windows-user>=<the Windows account name>
#
# Matching is LITERAL, not regex -- no escaping, no anchors, no word
# boundaries. Longest placeholder is applied first, so one placeholder may
# contain another.
#
# WHAT IT DELIBERATELY DOES NOT DO
#
# Only skills that ALREADY exist under a target root are touched. Installing a
# new skill is a deliberate act (and the two harnesses do not carry the same
# set); do it by hand once, and this script keeps it in sync afterwards.
#
# `deploy` mirrors: files in the live copy that the repo does not have are
# DELETED, because otherwise the hashes can never converge. Every deletion is
# printed. Run `check` first -- it lists them as `live-only` without touching
# anything.

set -uo pipefail
cd "$(dirname "$0")/.." || exit 2

REPO_SKILLS=agent/skills
TARGET_ROOTS=("$HOME/.claude/skills" "$HOME/.gemini/config/skills")
MAP_FILE=tools/.sync-map

mode=${1:-check}
only=${2:-}
case "$mode" in
  check|deploy) ;;
  *) echo "usage: bash tools/sync-skills.sh [check|deploy] [skill-name]" >&2; exit 2 ;;
esac

# ---- load the substitution map -------------------------------------------
declare -A MAP=()
if [ ! -f "$MAP_FILE" ]; then
  cat >&2 <<EOF
error: $MAP_FILE not found.

Create it (it is gitignored) with one PLACEHOLDER=VALUE per line, e.g.

  printf '%s\n' '<your-home>=/home/YOURNAME' > $MAP_FILE

Placeholders currently used in $REPO_SKILLS (a literal \$HOME is NOT one):
EOF
  grep -rhoE '<your-[a-z-]+>|<[a-z-]+-user>' "$REPO_SKILLS" | sort | uniq -c | sort -rn >&2
  exit 2
fi
while IFS= read -r line || [ -n "$line" ]; do
  [ -z "${line// }" ] && continue
  case "$line" in \#*) continue ;; esac
  [ "${line%%=*}" = "$line" ] && { echo "warn: no '=' in map line: $line" >&2; continue; }
  MAP["${line%%=*}"]="${line#*=}"
done < "$MAP_FILE"
[ "${#MAP[@]}" -gt 0 ] || { echo "error: $MAP_FILE has no entries" >&2; exit 2; }

# Longest placeholder first, so a placeholder that contains another still wins.
mapfile -t KEYS < <(for k in "${!MAP[@]}"; do printf '%s\t%s\n' "${#k}" "$k"; done \
  | sort -rn | cut -f2-)

# ---- render one file ------------------------------------------------------
# Pure bash ${var//pat/rep} with a QUOTED pattern: literal replacement, no
# regex, so `$HOME` and `<...>` need no escaping.
render() {
  local src=$1 dst=$2 content ph
  content=$(cat -- "$src"; printf x)   # printf x guards trailing newlines
  content=${content%x}
  for ph in "${KEYS[@]}"; do content=${content//"$ph"/${MAP[$ph]}}; done
  printf '%s' "$content" > "$dst"
  chmod --reference="$src" "$dst" 2>/dev/null || true
}

render_tree() {
  local src=$1 dst=$2 rel
  while IFS= read -r -d '' f; do
    rel=${f#"$src"/}
    mkdir -p "$dst/$(dirname -- "$rel")"
    if grep -Iq . -- "$f"; then render "$f" "$dst/$rel"; else cp -p -- "$f" "$dst/$rel"; fi
  done < <(find "$src" -type f -print0)
}

# ---- walk -----------------------------------------------------------------
tmp=$(mktemp -d) || exit 2
trap 'rm -rf "$tmp"' EXIT
drift=0 checked=0 deployed=0

for d in "$REPO_SKILLS"/*/; do
  d=${d%/}                        # the glob's trailing slash breaks ${f#"$src"/}
  skill=$(basename "$d")
  [ -n "$only" ] && [ "$only" != "$skill" ] && continue
  for root in "${TARGET_ROOTS[@]}"; do
    target=$root/$skill
    [ -d "$target" ] || continue
    checked=$((checked + 1))
    label="$skill -> ${root/#$HOME/\~}"

    staged=$tmp/$skill-$(echo "$root" | tr -c 'a-zA-Z0-9' '_')
    mkdir -p "$staged"
    render_tree "$d" "$staged"

    if diff -rq "$staged" "$target" >/dev/null 2>&1; then
      printf '  ok      %s\n' "$label"
      continue
    fi

    drift=1
    printf '  DRIFT   %s\n' "$label"
    diff -rq "$staged" "$target" 2>/dev/null | sed \
      -e "s|^Files $staged/|          differs: |" \
      -e "s| and $target/[^ ]*||" \
      -e "s|^Only in $staged\(.*\): |          repo-only: |" \
      -e "s|^Only in $target\(.*\): |          live-only: |"

    if [ "$mode" = deploy ]; then
      # mirror: --delete is what makes the hashes converge
      rsync -a --delete "$staged/" "$target/" && {
        printf '          deployed\n'; deployed=$((deployed + 1)); }
    fi
  done
done

echo
if [ "$checked" -eq 0 ]; then
  echo "nothing to do: no repo skill is deployed under any target root"
  exit 0
fi
if [ "$mode" = deploy ]; then
  echo "checked $checked, deployed $deployed"
  exit 0
fi
[ "$drift" -eq 0 ] && { echo "checked $checked, all match (modulo redaction)"; exit 0; }
echo "checked $checked, drift found -- review above, then: bash tools/sync-skills.sh deploy"
exit 1
