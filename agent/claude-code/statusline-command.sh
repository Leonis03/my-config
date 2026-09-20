#!/usr/bin/env bash
# Claude Code statusLine command.
#
# Renders: user@host:cwd  model  ctx:NN%  in/out/last tokens  cache state
#          5h rate limit  session cost
#
# Wire it up with `"command": "bash ~/.claude/statusline-command.sh"` rather than
# a bare path -- that form needs no execute bit and no hardcoded /home/<user>,
# so the file survives being copied to another machine.
#
# Everything comes from the JSON payload Claude Code writes to stdin, except the
# cumulative output-token count, which has to be summed from the transcript (see
# the note below). One jq pass extracts all payload fields; adding fields here is
# free, adding jq invocations is not (each fork costs ~4 ms).
#
# Dependency: jq. Without it the prompt still renders, just without the metrics.

input=$(cat)

# ---------------------------------------------------------------------------
# Single jq pass -> newline-separated fields, read into shell vars below.
# Notes on the awkward bits:
#   * jq's `//` treats `false` as absent, so cache warm/cold needs if/elif.
#   * rate_limits is only present for Claude.ai Pro/Max subscribers (or behind a
#     gateway that sets a spend limit); everything here degrades to empty.
#   * expires_at / resets_at are unix epoch seconds -> converted to minutes left.
# ---------------------------------------------------------------------------
# IFS must be a literal tab: @tsv is tab-separated, and values like the model
# name ("Opus 5") contain spaces, which default word splitting would break on.
IFS=$'\t' read -r model ctx tin last_out cache hit ttl_min miss_cause lim5 lim5_min cost transcript <<EOF
$(printf '%s' "$input" | jq -r '
  def m($t): if $t == null then "-" else ((($t - now) / 60) | floor | if . < 0 then 0 else . end) end;
  def d($v): if $v == null or $v == "" then "-" else ($v|tostring) end;
  [ d(.model.display_name // null)
  , d(.context_window.used_percentage // null)
  , d(.context_window.total_input_tokens // null)
  , d(.context_window.total_output_tokens // null)
  , (if .prompt_cache.warm == true then "warm" elif .prompt_cache.warm == false then "cold" else "-" end)
  , (if .prompt_cache.hit_ratio != null then (.prompt_cache.hit_ratio * 100 | round | tostring) else "-" end)
  , (if .prompt_cache.warm == true then m(.prompt_cache.expires_at) else "-" end)
  , d(.prompt_cache.last_miss_cause.causes[0] // null)
  , (if .rate_limits.five_hour.used_percentage != null
       then (.rate_limits.five_hour.used_percentage | round | tostring) else "-" end)
  , (if .rate_limits.five_hour.resets_at != null then m(.rate_limits.five_hour.resets_at) else "-" end)
  , (if .cost.total_cost_usd != null then (.cost.total_cost_usd * 100 | round / 100 | tostring) else "-" end)
  , d(.transcript_path // null)
  ] | @tsv' 2>/dev/null)
EOF

# ---------------------------------------------------------------------------
# context_window.total_output_tokens is only the output of the *most recent* API
# response, not a session total (unlike total_input_tokens, which reflects the
# whole current context). Sum every assistant turn in the transcript instead,
# deduplicated by message id because streamed/updated entries repeat an id.
# Uses `-n` + `inputs` to stream the file rather than `-s`, which would slurp a
# multi-megabyte transcript into memory on every render.
# ---------------------------------------------------------------------------
# The same pass also totals cache_read_input_tokens. That number is invisible in
# the payload yet dominates the bill: the API is stateless, so every turn resends
# the whole history, and on a long session the cumulative cache reads reach two
# orders of magnitude more tokens than the context itself. Cheap per token
# (~0.1x input), but it is where the money actually goes.
tout="-"; tcr="-"
if [ "$transcript" != "-" ] && [ -f "$transcript" ]; then
    IFS=$'\t' read -r tout tcr <<INNER
$(jq -rn '
    reduce inputs as $l ({};
        if $l.type == "assistant" and $l.message.usage.output_tokens != null
        then .[$l.message.id] = { o: $l.message.usage.output_tokens,
                                  c: ($l.message.usage.cache_read_input_tokens // 0) }
        else . end)
    | [ ([ .[].o ] | add // 0), ([ .[].c ] | add // 0) ] | @tsv' "$transcript" 2>/dev/null)
INNER
    [ -z "$tout" ] || [ "$tout" = "0" ] && tout="$last_out"
    [ -z "$tcr" ] && tcr="-"
fi

# 1234567 -> 1.2M, 12345 -> 12k. Keeps the bar narrow on long sessions.
human() {
    case "$1" in ''|-|*[!0-9]*) printf '%s' "$1"; return ;; esac
    if   [ "$1" -ge 1000000 ]; then awk -v n="$1" 'BEGIN{printf "%.1fM", n/1000000}'
    elif [ "$1" -ge 1000 ];    then awk -v n="$1" 'BEGIN{printf "%.0fk", n/1000}'
    else printf '%s' "$1"; fi
}

# Collapse $HOME to ~ ourselves; the payload's .cwd is always absolute.
p=$(pwd)
case "$p" in
    "$HOME")   p='~' ;;
    "$HOME"/*) p="~${p#"$HOME"}" ;;
esac

# Cost/pressure gauges follow Claude Code's own docs example: green <70,
# yellow 70-89, red >=90. Used for anything where a HIGH number is bad.
cost_color() {
    if   [ "$1" -ge 90 ]; then printf '\033[31m'
    elif [ "$1" -ge 70 ]; then printf '\033[33m'
    else printf '\033[32m'; fi
}
# Same bands inverted, for gauges where a HIGH number is GOOD (cache hit rate).
# Applying the docs thresholds directly here would paint a 99% hit rate red.
bene_color() {
    if   [ "$1" -ge 90 ]; then printf '\033[32m'
    elif [ "$1" -ge 70 ]; then printf '\033[33m'
    else printf '\033[31m'; fi
}
DIM='\033[90m'
RST='\033[00m'

# Token counters are activity, not danger, so they get a brightness ramp instead
# of the green/yellow/red pressure scale -- reusing red here would imply a large
# response is a problem. Dim -> cyan -> bright cyan reads as "bigger" without
# competing with ctx/5h for alarm attention. Bands are token counts; override
# with SL_MAG_MID / SL_MAG_HIGH if your sessions run larger or smaller.
: "${SL_MAG_MID:=100000}"
: "${SL_MAG_HIGH:=500000}"
mag_color() {
    case "$1" in ''|-|*[!0-9]*) printf '%b' "$DIM"; return ;; esac
    if   [ "$1" -ge "$SL_MAG_HIGH" ]; then printf '\033[96m'
    elif [ "$1" -ge "$SL_MAG_MID"  ]; then printf '\033[36m'
    else printf '%b' "$DIM"; fi
}

printf '\033[01;32m%s@%s\033[00m:\033[01;34m%s\033[00m' "$(whoami)" "$(hostname -s)" "$p"
# Magenta, not cyan: the token counters below own the cyan ramp now.
[ "$model" != "-" ] && printf ' \033[00;35m%s\033[00m' "$model"

if [ "$ctx" != "-" ]; then
    ctx_pct=$(printf '%.0f' "$ctx" 2>/dev/null || echo 0)
    printf " $(cost_color "$ctx_pct")ctx:%s%%${RST}" "$ctx_pct"
fi

[ "$tin"      != "-" ] && printf " $(mag_color "$tin")in:%s${RST}"        "$(human "$tin")"
[ "$tout"     != "-" ] && printf " $(mag_color "$tout")out:%s${RST}"      "$(human "$tout")"
[ "$last_out" != "-" ] && printf " $(mag_color "$last_out")last:%s${RST}" "$(human "$last_out")"
# Cumulative cache reads -- the dominant cost line, an order of magnitude above
# the others, so it gets its own band via SL_CR_MID / SL_CR_HIGH.
[ "$tcr" != "-" ] && printf " $(SL_MAG_MID=${SL_CR_MID:-10000000} SL_MAG_HIGH=${SL_CR_HIGH:-50000000} mag_color "$tcr")cr:%s${RST}" "$(human "$tcr")"

case "$cache" in
    warm) if [ "$ttl_min" != "-" ]; then printf ' \033[32mcache:%sm\033[00m' "$ttl_min"
          else printf ' \033[32mcache:warm\033[00m'; fi ;;
    cold) if [ "$miss_cause" != "-" ]; then printf ' \033[31mcache:cold(%s)\033[00m' "$miss_cause"
          else printf ' \033[31mcache:cold\033[00m'; fi ;;
esac
# Inverted bands: a high cache hit rate is good, so 99% must read green.
[ "$hit" != "-" ] && printf " $(bene_color "$hit")hit:%s%%${RST}" "$hit"

# rate_limits is absent on plans that don't expose it -- stay silent rather than
# printing a placeholder.
if [ "$lim5" != "-" ]; then
    if [ "$lim5_min" != "-" ]; then
        printf " $(cost_color "$lim5")5h:%s%%${RST}${DIM}/%sm${RST}" "$lim5" "$lim5_min"
    else
        printf " $(cost_color "$lim5")5h:%s%%${RST}" "$lim5"
    fi
fi

[ "$cost" != "-" ] && printf " \033[00;33m\$%s${RST}" "$cost"
