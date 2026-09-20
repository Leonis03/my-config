---
name: download-bilibili
description: Download Bilibili videos or audio with BBDown and process downloaded audio with ffmpeg/ffprobe. Use when the user provides a Bilibili BV/AV/URL/playlist-style multi-P video and asks to download video, download audio, select pages, batch download BV lists, inspect multi-P metadata, convert Bilibili audio to MP3, split course audio into short MP3 segments, or troubleshoot BBDown/FFmpeg media handling for Bilibili sources.
---

# Download Bilibili

Use the project-local BBDown binary under `$HOME/code/audio/bbdown_bin/` first. Prefer `$HOME/code/audio/bbdown_bin/BBDown`; if the binary is present as lowercase `bbdown`, use `$HOME/code/audio/bbdown_bin/bbdown` instead. This avoids version drift.

Default project directories should be referenced with absolute paths under `$HOME/code/audio`. For example, use `$HOME/code/audio/audio` for raw downloaded audio, `$HOME/code/audio/mp3` for converted MP3 files when no course-specific directory is specified, and course-specific directories such as `$HOME/code/audio/CourseName/mp3` or `$HOME/code/audio/CourseName/md` when the user is working on a named course.

## Quick Checks

Run these before downloading:

```bash
bbdown=$HOME/code/audio/bbdown_bin/BBDown
[ -e "$bbdown" ] || bbdown=$HOME/code/audio/bbdown_bin/bbdown
[ -x "$bbdown" ] || chmod +x "$bbdown"
"$bbdown" --help | sed -n '1,8p'
command -v ffmpeg >/dev/null && ffmpeg -version | head -n 1
```

If Bilibili access fails because of the execution sandbox, request network escalation and rerun the same command. If the environment has broken local proxy variables, clear them for BBDown:

```bash
env -u HTTP_PROXY -u HTTPS_PROXY -u ALL_PROXY -u http_proxy -u https_proxy -u all_proxy \
  "$bbdown" "$bv" -info --show-all
```

## Inspect A Video

Always inspect unfamiliar multi-P videos before a large download:

```bash
"$bbdown" "$bv" -info --show-all
```

Use `-p` for page selection:

```bash
-p 1
-p 1,3,5
-p 3-8
-p ALL
-p LAST
```

## Download Audio

For one video or all selected pages, keep files directly in the target directory by setting `-M`:

```bash
"$bbdown" "$bv" --audio-only --skip-cover -p ALL \
  -M '<videoTitle>_[P<pageNumberWithZero>]<pageTitle>' \
  --work-dir "$out_dir" </dev/null
```

Notes:

- `--audio-only` usually produces `.m4a`; do not assume MP3 output.
- Keep `--skip-cover` unless the user asks for cover images.
- Use `--audio-ascending` only when the user asks for smaller/lower-bitrate audio.
- For a single page, replace `-p ALL` with the requested page, for example `-p 1`.

## Download Video

Use BBDown's default behavior for merged video output:

```bash
"$bbdown" "$bv" --skip-cover -p ALL \
  -M '<videoTitle>_[P<pageNumberWithZero>]<pageTitle>' \
  --work-dir "$out_dir" </dev/null
```

Use `--video-only` only when the user explicitly wants video without audio. Use `--skip-subtitle` if subtitle files are not desired.

## Batch BV Lists

BBDown reads from stdin. Never pipe a BV list directly into a loop that runs BBDown, because BBDown can consume later BV values.

Use fd 3 and connect BBDown to `/dev/null`:

```bash
grep -oP 'BV\S+' download.txt > /tmp/bv_list.txt

while IFS= read -r bv <&3; do
  "$bbdown" "$bv" --audio-only --skip-cover --work-dir $HOME/code/audio/audio </dev/null \
    || echo ">>> failed: $bv"
done 3< /tmp/bv_list.txt
```

## Process Audio

Use FFmpeg/ffprobe inside this skill for Bilibili audio conversion, duration checks, bitrate checks, and segmenting.

Defaults:

- Convert downloaded `.m4a` to MP3 at 64 kbps unless the user requests another bitrate or quality.
- When splitting audio into short segments, keep a 5 second buffer/overlap at cuts unless the user requests exact non-overlapping cuts.
- Name split MP3 outputs with ASCII only and no Chinese titles: `P<number>_part<number>.mp3`, for example `P1_part1.mp3` through `P11_part3.mp3`.
- Derive `P<number>` from the Bilibili page order or page number, not from the Chinese page title.
- Verify collisions before writing outputs; do not delete existing media unless the user explicitly asks.

### Convert Audio To MP3

For 64 kbps MP3 conversion, write only missing outputs:

```bash
mkdir -p "$mp3_dir"

for f in "$m4a_dir"/*.m4a; do
  base="$(basename "$f" .m4a)"
  out="$mp3_dir/$base.mp3"
  [ -f "$out" ] && continue
  ffmpeg -i "$f" -codec:a libmp3lame -b:a 64k -y "$out" -loglevel error
done
```

When the user requests numeric names, extract the intended number from the filename explicitly and verify collisions before converting.

### Split Audio To MP3 Segments

For a three-way split, compute the source duration `d` with `ffprobe` and use these default buffered ranges:

- Part 1: `[0, d/3 + 5]`
- Part 2: `[d/3, 2d/3 + 5]`
- Part 3: `[2d/3, d]`

Clamp segment ends to `d` if needed. Write the MP3 outputs at 64 kbps:

```bash
mkdir -p "$mp3_dir"
idx=0

find "$m4a_dir" -maxdepth 1 -type f -name '*.m4a' -print0 |
  sort -z -V |
  while IFS= read -r -d '' f; do
    idx=$((idx + 1))
    d="$(ffprobe -v error -show_entries format=duration \
      -of default=noprint_wrappers=1:nokey=1 "$f")"

    for part in 1 2 3; do
      vals="$(awk -v d="$d" -v p="$part" 'BEGIN {
        third = d / 3
        if (p == 1) { start = 0; end = third + 5 }
        else if (p == 2) { start = third; end = 2 * third + 5 }
        else { start = 2 * third; end = d }
        if (end > d) end = d
        len = end - start
        if (len < 0) len = 0
        printf "%.6f %.6f", start, len
      }')"
      start="${vals% *}"
      len="${vals#* }"
      out="$mp3_dir/P${idx}_part${part}.mp3"
      [ -f "$out" ] && continue
      ffmpeg -nostdin -i "$f" -ss "$start" -t "$len" -vn \
        -codec:a libmp3lame -b:a 64k -y "$out" -loglevel error
    done
  done
```

## Verification

After downloads:

```bash
find "$out_dir" -maxdepth 1 -type f | wc -l
find "$out_dir" -maxdepth 1 -type f -printf '%f\t%s bytes\n' | sort
du -sh "$out_dir"
```

After MP3 conversion:

```bash
find "$mp3_dir" -maxdepth 1 -type f -name '*.mp3' | wc -l
ffprobe -v error -show_entries format=duration,bit_rate,size \
  -of default=noprint_wrappers=1:nokey=0 "$mp3_file"
```

After splitting multi-P audio:

```bash
find "$mp3_dir" -maxdepth 1 -type f -name 'P*_part*.mp3' | sort -V
find "$mp3_dir" -maxdepth 1 -type f -printf '%f\n' |
  rg -v '^P([1-9][0-9]*)_part([1-9][0-9]*)\.mp3$'
```

Do not delete existing `$HOME/code/audio/audio/`, `$HOME/code/audio/mp3/`, `$HOME/code/audio/CourseName/`, or course-specific output files unless the user explicitly asks.
