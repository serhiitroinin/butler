#!/bin/bash
# Builds a realistic messy folder for development. Never point Butler at a real
# user folder: use this one.
set -euo pipefail

root="${1:-$(cd "$(dirname "$0")/.." && pwd)/.demo/Downloads}"
# A capture may have locked a file to make an apply fail.
[ -d "$root" ] && chflags -R nouchg "$root"
rm -rf "$root"
mkdir -p "$root"

write() {
  local path="$1" size="$2" stamp="$3"
  mkdir -p "$(dirname "$path")"
  head -c "$size" /dev/urandom | base64 > "$path"
  touch -t "$stamp" "$path"
}

text() {
  local path="$1" stamp="$2"
  shift 2
  printf '%s\n' "$@" > "$path"
  touch -t "$stamp" "$path"
}

for year in 2023 2024 2025; do
  short="${year:2:2}"
  for month in 01 03 05 07 09 11; do
    write "$root/invoice-$year-$month.pdf" 2000 "${short}${month}120930"
    write "$root/Screenshot $year-$month-14 at 09.41.22.png" 4000 "${short}${month}140941"
  done
  write "$root/statement-$year.pdf" 3000 "${short}1231110000"
  write "$root/photo-$year-holiday.jpg" 9000 "${short}0715140000"
done

write "$root/report (1).pdf" 2500 "2410021200"
write "$root/report.pdf" 2500 "2410011200"
write "$root/report (2).pdf" 2500 "2410031200"
write "$root/Slack.dmg" 12000 "2502111000"
write "$root/Docker.dmg" 14000 "2411051000"
write "$root/node-v22.tar.gz" 8000 "2501091000"
write "$root/dataset.zip" 16000 "2503231000"
write "$root/backup-old.zip" 7000 "2308191000"
write "$root/talk-recording.mp4" 20000 "2504171000"
write "$root/voice-memo.m4a" 6000 "2504181000"
write "$root/budget.xlsx" 5000 "2501151000"
write "$root/contacts.csv" 1500 "2412201000"
write "$root/presentation.key" 11000 "2502281000"

text "$root/notes.md" "2505011000" "# Notes" "" "- call the accountant" "- renew the domain"
text "$root/todo.txt" "2505021000" "buy coffee" "file the invoices"
text "$root/.hidden-config" "2501011000" "keep=me"

mkdir -p "$root/Old stuff"
write "$root/Old stuff/receipt-2019.pdf" 1200 "1906061200"
write "$root/Old stuff/scan.png" 3000 "1906071200"

mkdir -p "$root/Empty folder"

count=$(find "$root" -type f | wc -l | tr -d ' ')
echo "demo folder: $root ($count files)"
