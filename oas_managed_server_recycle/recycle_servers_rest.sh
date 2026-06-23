#!/bin/bash
# Uses WebLogic REST API via curl. No WLST or local OAS install required.

ADMIN_HOST="localhost"
ADMIN_PORT="9500"
ADMIN_USER="weblogic"
ADMIN_PASS="your_password"
STUCK_THRESHOLD=0
BASE_URL="http://${ADMIN_HOST}:${ADMIN_PORT}/management/weblogic/latest"

if ! command -v jq &>/dev/null; then
    echo "ERROR: jq is required. Install with: sudo apt-get install -y jq"
    exit 1
fi

recycle_server() {
    local name=$1
    echo "  -> Shutting down ${name}..."
    curl -s -X POST \
        -u "${ADMIN_USER}:${ADMIN_PASS}" \
        -H "Accept: application/json" \
        -H "X-Requested-By: recycle_servers" \
        "${BASE_URL}/domainRuntime/serverLifeCycleRuntimes/${name}/forceShutdown"

    echo "  -> Waiting for shutdown..."
    sleep 15

    echo "  -> Starting ${name}..."
    curl -s -X POST \
        -u "${ADMIN_USER}:${ADMIN_PASS}" \
        -H "Accept: application/json" \
        -H "X-Requested-By: recycle_servers" \
        "${BASE_URL}/domainRuntime/serverLifeCycleRuntimes/${name}/start"

    echo "  -> ${name} recycled."
}

echo "Connecting to Admin Server at ${ADMIN_HOST}:${ADMIN_PORT}..."

servers=$(curl -sf \
    -u "${ADMIN_USER}:${ADMIN_PASS}" \
    -H "Accept: application/json" \
    "${BASE_URL}/domainRuntime/serverLifeCycleRuntimes")

if [ $? -ne 0 ]; then
    echo "ERROR: Could not reach Admin Server at ${BASE_URL}"
    exit 1
fi

echo "$servers" | jq -r '.items[] | "\(.name) \(.state)"' | while read -r name state; do

    [[ "$name" == "AdminServer" ]] && continue

    stuck=0
    thread_info=$(curl -sf \
        -u "${ADMIN_USER}:${ADMIN_PASS}" \
        -H "Accept: application/json" \
        "${BASE_URL}/serverRuntimes/${name}/threadPoolRuntime" 2>/dev/null)

    if [ $? -eq 0 ] && [ -n "$thread_info" ]; then
        stuck=$(echo "$thread_info" | jq -r '.stuckThreadCount // 0')
    fi

    printf "%-25s  state=%-10s  stuck_threads=%d\n" "$name" "$state" "$stuck"

    if [ "$state" != "RUNNING" ] || [ "$stuck" -gt "$STUCK_THRESHOLD" ]; then
        recycle_server "$name"
    fi

done

echo ""
echo "Done."
