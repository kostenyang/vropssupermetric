#!/usr/bin/env bash
# Apply this repo's super metrics to a vROps instance via REST API.
#
# Required env vars:
#   VROPS_HOST   - vROps FQDN or IP, e.g. 10.0.0.111
#   VROPS_USER   - admin user (default: admin)
#   VROPS_PASS   - admin password
#
# Optional:
#   SM_FILES     - space-separated list of JSON files (default: all snapshot-*.json)
#
# Usage:
#   VROPS_HOST=10.0.0.111 VROPS_USER=admin VROPS_PASS='VMware1!' bash apply.sh
#
# This script only CREATES the super metric definitions. It does NOT enable
# them in any policy — vROps public API does not expose that. Enable in UI:
#   Configure -> Policies -> edit active default policy
#   -> Collect Metrics and Properties -> Cluster Compute Resource
#   -> filter: Super Metric -> set State = Enabled -> Save

set -euo pipefail

: "${VROPS_HOST:?Set VROPS_HOST (e.g. 10.0.0.111)}"
: "${VROPS_PASS:?Set VROPS_PASS (admin password)}"
VROPS_USER="${VROPS_USER:-admin}"

cd "$(dirname "$0")"
SM_FILES="${SM_FILES:-$(ls snapshot-*.json 2>/dev/null || true)}"

if [[ -z "$SM_FILES" ]]; then
    echo "No snapshot-*.json files found in $(pwd)" >&2
    exit 1
fi

for f in $SM_FILES; do
    name=$(grep -oP '"name"\s*:\s*"\K[^"]+' "$f" | head -1)
    echo "==> POST $f  ($name)"
    http_code=$(curl -sk -o /tmp/sm_resp.json -w '%{http_code}' \
        -u "${VROPS_USER}:${VROPS_PASS}" \
        -X POST "https://${VROPS_HOST}/suite-api/api/supermetrics" \
        -H 'Content-Type: application/json' \
        -H 'Accept: application/json' \
        --data-binary "@$f")
    echo "    HTTP ${http_code}"
    case "$http_code" in
        201) echo "    OK — created";;
        400|409|500)
            echo "    Already exists or rejected — response:"
            cat /tmp/sm_resp.json | head -c 500
            echo
            echo "    To overwrite, find the existing id and DELETE it first:"
            echo "      curl -sk -u ${VROPS_USER}:\$VROPS_PASS \\"
            echo "          https://${VROPS_HOST}/suite-api/api/supermetrics | jq .superMetrics"
            ;;
        *)
            echo "    Unexpected response:"
            cat /tmp/sm_resp.json | head -c 500
            echo
            exit 2
            ;;
    esac
done

echo
echo "Done. Now go enable these in a policy via UI (see README)."
