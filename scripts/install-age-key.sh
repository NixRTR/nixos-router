#!/usr/bin/env bash

set -euo pipefail

usage() {
  cat <<'EOF'
Usage: install-age-key.sh [AGE_KEY]

Writes the provided Age private key material to /root/.config/sops/age/keys.txt
and applies strict permissions.

Pass the key as an argument or via standard input (end with Ctrl-D).
EOF
}

if [[ "${1-}" == "-h" || "${1-}" == "--help" ]]; then
  usage
  exit 0
fi

if [[ $# -gt 1 ]]; then
  echo "error: too many arguments" >&2
  usage >&2
  exit 1
fi

if [[ $# -eq 1 ]]; then
  key_material=$1
else
  if [[ -t 0 ]]; then
    echo "Enter Age key material, followed by Ctrl-D:" >&2
  fi
  key_material=$(cat)
fi

if [[ -z "${key_material// }" ]]; then
  echo "error: no key material provided" >&2
  exit 1
fi

target_dir=/root/.config/sops/age
target_file="$target_dir/keys.txt"

install -d -m 0700 "$target_dir"
printf '%s\n' "$key_material" > "$target_file"
chmod 0400 "$target_file"

echo "Age key written to $target_file"

