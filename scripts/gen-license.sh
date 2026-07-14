#!/bin/bash
# Generates ArxOne license keys (ARX1-XXXX-XXXX-CCCC) that Lumen and every
# other ARXNDEV app accept. Run after a customer subscribes, send them the key.
#   ./scripts/gen-license.sh        # one key
#   ./scripts/gen-license.sh 10     # ten keys
# KEEP THIS FILE PRIVATE if you ever change the salt — the salt here must
# match LicenseManager.salt in the apps.
set -e
SALT="arxone-2026-suite-salt-v1"
COUNT="${1:-1}"

for _ in $(seq 1 "$COUNT"); do
    RAND=$(LC_ALL=C tr -dc 'A-HJ-NP-Z2-9' </dev/urandom | head -c 8)
    BODY="ARX1-${RAND:0:4}-${RAND:4:4}"
    CHECK=$(printf "%s" "${BODY}${SALT}" | shasum -a 256 | tr 'a-f' 'A-F' | cut -c1-4)
    echo "${BODY}-${CHECK}"
done
