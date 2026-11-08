#!/bin/sh
# Prints one sha256 for a whole directory tree (file paths + contents).
# Identical output on Linux and macOS. Usage: tree-hash.sh <dir>
set -eu
cd "$1"
LC_ALL=C find . -type f ! -name '.DS_Store' -print | LC_ALL=C sort | while IFS= read -r f; do
  printf '%s  %s\n' "$(shasum -a 256 "$f" | cut -d' ' -f1)" "$f"
done | shasum -a 256 | cut -d' ' -f1
