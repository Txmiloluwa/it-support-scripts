#!/usr/bin/env bash
#
# bulk_create_users.sh - create Linux user accounts from a CSV file (e.g. new starters).
#
# CSV columns: username,full_name,group
# Every new user gets a random temporary password and must change it at first login.
#
# By default this is a DRY RUN that only shows what it would do. Use --apply
# (as root, on Linux) to actually create the accounts.
#
# Usage:
#   ./bulk_create_users.sh examples/new_starters.csv            dry run
#   sudo ./bulk_create_users.sh examples/new_starters.csv --apply

set -euo pipefail

CSV="${1:-}"
APPLY=false
[[ "${2:-}" == "--apply" ]] && APPLY=true

if [[ -z "$CSV" || "$CSV" == "-h" || "$CSV" == "--help" ]]; then
  sed -n '3,14p' "$0" | sed 's/^# \{0,1\}//'
  exit 0
fi
if [[ ! -f "$CSV" ]]; then
  echo "File not found: $CSV" >&2
  exit 1
fi
if [[ "$APPLY" == true ]]; then
  if [[ "$(uname -s)" != "Linux" ]]; then
    echo "--apply only works on Linux (it uses useradd)." >&2
    exit 1
  fi
  if [[ "$EUID" -ne 0 ]]; then
    echo "--apply must be run as root (use sudo)." >&2
    exit 1
  fi
fi

# Linux usernames: start with a lowercase letter, then lowercase letters, digits, dots, - or _, max 32 chars.
valid_username() { [[ "$1" =~ ^[a-z][a-z0-9._-]{0,31}$ ]]; }

random_password() {
  # 14 random characters from letters and digits.
  # Read a fixed 300 bytes first: piping endless /dev/urandom into `head` makes the
  # earlier command fail with SIGPIPE, which `set -o pipefail` treats as an error.
  head -c 300 /dev/urandom | LC_ALL=C tr -dc 'A-Za-z0-9' | cut -c 1-14
}

CREATED=0
SKIPPED=0
LINE=1

echo "Mode: $([[ "$APPLY" == true ]] && echo 'APPLY (accounts will be created)' || echo 'DRY RUN (nothing will change)')"
echo

# Skip the header row, then read each line.
while IFS=, read -r username full_name group || [[ -n "${username:-}" ]]; do
  LINE=$((LINE + 1))
  username="$(echo "$username" | tr -d '[:space:]')"
  group="$(echo "$group" | tr -d '[:space:]')"

  if [[ -z "$username" ]]; then
    continue
  fi
  if ! valid_username "$username"; then
    echo "  Line $LINE: SKIPPED '$username' (invalid username)"
    SKIPPED=$((SKIPPED + 1))
    continue
  fi
  if id "$username" > /dev/null 2>&1; then
    echo "  Line $LINE: SKIPPED '$username' (user already exists)"
    SKIPPED=$((SKIPPED + 1))
    continue
  fi

  if [[ "$APPLY" == true ]]; then
    getent group "$group" > /dev/null || groupadd "$group"
    useradd --create-home --comment "$full_name" --groups "$group" --shell /bin/bash "$username"
    password="$(random_password)"
    echo "$username:$password" | chpasswd
    chage -d 0 "$username"   # force a password change at first login
    echo "  Line $LINE: CREATED $username ($full_name) in group '$group', temporary password: $password"
  else
    echo "  Line $LINE: would create $username ($full_name) in group '$group'"
  fi
  CREATED=$((CREATED + 1))
done < <(tail -n +2 "$CSV")

echo
echo "Done: $CREATED $([[ "$APPLY" == true ]] && echo created || echo 'to create'), $SKIPPED skipped."
[[ "$APPLY" == true ]] && echo "Share each temporary password with its user securely, never by plain email."
exit 0
