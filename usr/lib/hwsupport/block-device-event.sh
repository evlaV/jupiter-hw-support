#!/bin/bash

set -euo pipefail

. /usr/lib/hwsupport/common-functions

usage()
{
    echo "Usage: $0 {add|remove} device_name (e.g. sdb1)"
    exit 1
}

if [[ $# -ne 2 ]]; then
    usage
fi

ACTION=$1
DEVBASE=$2

# Shared between this and format-device.sh to ensure we're not
# double-triggering nor automounting while formatting or vice-versa.
if ! create_lock_file "$DEVBASE"; then
    exit 0
fi

do_add()
{
    # Prior to talking to udisks, we need all udev hooks (we were started by one) to finish, so we know it has knowledge
    # of the drive.  Our own rule starts us as a service with --no-block, so we can wait for rules to settle here
    # safely.
    if ! udevadm settle; then
        echo "Failed to wait for \`udevadm settle\`" 2>&1
        exit 1
    fi

    systemctl start "steamos-automount@${DEVBASE}.service"
}

do_remove()
{
    systemctl stop "steamos-automount@${DEVBASE}.service"
}

case "${ACTION}" in
    add)
        do_add
        ;;
    remove)
        do_remove
        ;;
    *)
        usage
        ;;
esac
