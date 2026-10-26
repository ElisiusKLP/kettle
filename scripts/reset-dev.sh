#!/usr/bin/env bash
# Deletes the Kettle Dev data folder, and nothing else. Asks for confirmation first.
set -euo pipefail

dev_dir="$HOME/Library/Application Support/Kettle-Dev"

if [[ ! -d "$dev_dir" ]]; then
    echo "No dev data at $dev_dir"
    exit 0
fi

read -r -p "Delete all Kettle Dev data in \"$dev_dir\"? [y/N] " answer
if [[ "$answer" == [yY] || "$answer" == [yY][eE][sS] ]]; then
    rm -rf "$dev_dir"
    echo "Deleted $dev_dir"
else
    echo "Cancelled."
fi
