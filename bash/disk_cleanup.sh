#!/usr/bin/env bash
#
# disk_cleanup.sh - find what is filling up a folder, and optionally clear old temp files.
#
# By default this is a DRY RUN: it only reports. Nothing is deleted unless you
# pass --delete AND confirm at the prompt.
#
# Usage:
#   ./disk_cleanup.sh [folder]                    report on folder (default: your home folder)
#   ./disk_cleanup.sh [folder] --days 30          change what counts as "old" (default 30 days)
#   ./disk_cleanup.sh [folder] --delete           delete old .tmp/.log/.cache files after confirming

set -euo pipefail

FOLDER="$HOME"
DAYS=30
DELETE=false

while [[ $# -gt 0 ]]; do
  case "$1" in
    --days)   DAYS="${2:?--days needs a number}"; shift 2 ;;
    --delete) DELETE=true; shift ;;
    -h|--help) sed -n '3,12p' "$0" | sed 's/^# \{0,1\}//'; exit 0 ;;
    -*)       echo "Unknown option: $1 (try --help)" >&2; exit 2 ;;
    *)        FOLDER="$1"; shift ;;
  esac
done

if [[ ! -d "$FOLDER" ]]; then
  echo "Not a folder: $FOLDER" >&2
  exit 1
fi
if ! [[ "$DAYS" =~ ^[0-9]+$ ]]; then
  echo "--days must be a whole number" >&2
  exit 2
fi

echo "Disk report for: $FOLDER"
echo

echo "Largest items (top 10):"
du -sh "$FOLDER"/* 2>/dev/null | sort -rh | head -10 | sed 's/^/  /' || true
echo

echo "Largest files over 100 MB (top 10):"
find "$FOLDER" -type f -size +100M -exec du -h {} + 2>/dev/null | sort -rh | head -10 | sed 's/^/  /' || true
echo

# Old temporary files are usually safe to remove.
# (A while-read loop instead of `mapfile`, because macOS ships with bash 3.2, which has no mapfile.)
OLD_FILES=()
while IFS= read -r file; do
  OLD_FILES+=("$file")
done < <(find "$FOLDER" -type f \( -name '*.tmp' -o -name '*.log' -o -name '*.cache' \) -mtime +"$DAYS" 2>/dev/null)

echo "Temporary files (.tmp, .log, .cache) older than $DAYS days: ${#OLD_FILES[@]}"
if (( ${#OLD_FILES[@]} > 0 )); then
  TOTAL_KB="$(du -ck "${OLD_FILES[@]}" 2>/dev/null | tail -1 | cut -f1)"
  echo "  They take up about $(( TOTAL_KB / 1024 )) MB"
  printf '  %s\n' "${OLD_FILES[@]:0:10}"
  (( ${#OLD_FILES[@]} > 10 )) && echo "  ...and $(( ${#OLD_FILES[@]} - 10 )) more"
fi
echo

if [[ "$DELETE" != true ]]; then
  echo "Dry run: nothing was deleted. Re-run with --delete to remove the temporary files listed above."
  exit 0
fi

if (( ${#OLD_FILES[@]} == 0 )); then
  echo "Nothing to delete."
  exit 0
fi

read -r -p "Delete these ${#OLD_FILES[@]} file(s)? Type YES to confirm: " ANSWER
if [[ "$ANSWER" == "YES" ]]; then
  rm -f -- "${OLD_FILES[@]}"
  echo "Deleted ${#OLD_FILES[@]} file(s)."
else
  echo "Cancelled. Nothing was deleted."
fi
