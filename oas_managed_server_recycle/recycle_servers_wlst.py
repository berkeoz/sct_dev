#!/usr/bin/env python
# Run with: $ORACLE_HOME/oracle_common/common/bin/wlst.sh recycle_servers_wlst.py

import sys

ADMIN_URL       = 't3://localhost:9500'
ADMIN_USER      = 'weblogic'
ADMIN_PASS      = 'your_password'
STUCK_THRESHOLD = 0

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
