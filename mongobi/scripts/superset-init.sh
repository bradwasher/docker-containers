#!/usr/bin/env bash
set -euo pipefail

echo "[init] Running DB migrations…"
superset db upgrade

echo "[init] Ensuring base roles/permissions…"
superset init

echo "[init] Deleting ALL users via CLI…"
# on initialization sometimes the admin user wasn't present, so this deletes any and readds one
# Parse usernames from the table printed by `superset fab list-users`
# - keep only table rows
# - drop header/separator lines
# - extract the "username" column (3rd column)
mapfile -t USERS < <(
  superset fab list-users \
  | awk -F"|" '/^\|/ {gsub(/^ +| +$/,"",$0); if ($0 !~ /^\+-/ && $0 !~ /username/i) print $0}' \
  | awk -F"|" '{gsub(/^ +| +$/,"",$3); if($3!="") print $3}'
)

for u in "${USERS[@]}"; do
  echo "[init] Deleting user: $u"
  superset fab delete-user --username "$u" || true
done

echo "[init] (Re)creating admin…"
superset fab create-admin \
  --username   "${ADMIN_USERNAME:-admin}" \
  --firstname  "${ADMIN_FIRSTNAME:-Admin}" \
  --lastname   "${ADMIN_LASTNAME:-User}" \
  --email      "${ADMIN_EMAIL:-admin@example.com}" \
  --password   "${ADMIN_PASSWORD:-admin}"

echo "[init] Done."

