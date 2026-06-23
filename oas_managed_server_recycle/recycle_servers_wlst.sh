#!/bin/bash
# Shell wrapper that connects to OAS via WLST using T3 protocol.

ADMIN_URL="t3://localhost:9500"
ADMIN_USER="weblogic"
ADMIN_PASS="your_password"
STUCK_THRESHOLD=0

# Auto-detect wlst.sh
if [ -n "$ORACLE_HOME" ] && [ -f "$ORACLE_HOME/oracle_common/common/bin/wlst.sh" ]; then
    WLST="$ORACLE_HOME/oracle_common/common/bin/wlst.sh"
elif [ -f "/u01/oracle/middleware/oracle_common/common/bin/wlst.sh" ]; then
    WLST="/u01/oracle/middleware/oracle_common/common/bin/wlst.sh"
else
    echo "ERROR: wlst.sh not found. Set ORACLE_HOME or update the WLST path."
    exit 1
fi

TMPFILE=$(mktemp /tmp/recycle_XXXX.py)
trap "rm -f $TMPFILE" EXIT

cat > "$TMPFILE" << JYTHON
import sys

ADMIN_URL       = '${ADMIN_URL}'
ADMIN_USER      = '${ADMIN_USER}'
ADMIN_PASS      = '${ADMIN_PASS}'
STUCK_THRESHOLD = ${STUCK_THRESHOLD}

def recycle(name):
    print('  -> Shutting down ' + name + '...')
    shutdown(name, 'Server', force='true', block='true')
    print('  -> Starting ' + name + '...')
    start(name, 'Server', block='true')
    print('  -> ' + name + ' recycled.')

try:
    connect(ADMIN_USER, ADMIN_PASS, ADMIN_URL)
except Exception as e:
    print('ERROR: Connection failed: ' + str(e))
    sys.exit(1)

domainRuntime()
servers = domainRuntimeService.getServerRuntimes()
to_recycle = []

for s in servers:
    name  = s.getName()
    state = s.getState()
    try:
        stuck = s.getThreadPoolRuntime().getStuckThreadCount()
    except:
        stuck = 0

    print('%-25s  state=%-10s  stuck_threads=%d' % (name, state, stuck))

    if name != 'AdminServer' and (state != 'RUNNING' or stuck > STUCK_THRESHOLD):
        to_recycle.append(name)

if not to_recycle:
    print('\nAll servers healthy -- nothing to recycle.')
else:
    print('\nServers to recycle: ' + str(to_recycle))
    for name in to_recycle:
        recycle(name)

disconnect()
JYTHON

echo "Connecting via WLST to ${ADMIN_URL}..."
"$WLST" "$TMPFILE"
