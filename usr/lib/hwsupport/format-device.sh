#!/bin/bash

set -e

. /usr/lib/hwsupport/common-functions

# If the script is not run from a tty then send a copy of stdout and
# stderr to the journal. In this case stderr is also redirected to stdout.
if ! tty -s; then
    exec 8>&1
    exec &> >(tee /dev/fd/8 | logger -t holo-format-device)
fi

RUN_VALIDATION=1
EXTENDED_OPTIONS="nodiscard"
# default owner for the new filesystem
OWNER="1000:1000"
EXTRA_MKFS_ARGS=()
# A 1 MiB partition start is offset from a 4 MiB SD allocation unit.
# Parted recommends 4 MiB alignment for some flash devices.
# Reported device alignment takes precedence over this fallback.
# https://www.gnu.org/software/parted/manual/html_node/mkpart.html
PARTITION_START="4MiB"
# Increase the version number every time a new option is added
VERSION_NUMBER=1

OPTS=$(getopt -l version,force,skip-validation,full,quick,owner:,device:,label: -n format-device.sh -- "" "$@")

eval set -- "$OPTS"

while true; do
    case "$1" in
        --version) echo $VERSION_NUMBER; exit 0 ;;
        --force) RUN_VALIDATION=0; shift ;;
        --skip-validation) RUN_VALIDATION=0; shift ;;
        --full) EXTENDED_OPTIONS="discard"; shift ;;
        --quick) EXTENDED_OPTIONS="nodiscard"; shift ;;
        --owner) OWNER="$2"; shift 2;;
        --label) EXTRA_MKFS_ARGS+=(-L "$2"); shift 2 ;;
        --device) STORAGE_DEVICE="$2"; shift 2 ;;
        --) shift; break ;;
    esac
done

if [[ "$#" -gt 0 ]]; then
    echo "Unknown option $1"; exit 22
fi

EXTENDED_OPTIONS="$EXTENDED_OPTIONS,root_owner=$OWNER"

function usb_needs_parted_alignment()
{
    local _sysfs="/sys/block/${1##*/}"
    local _offset _size _attribute

    # Let Parted account for reported or indeterminate alignment offsets.
    _offset="$(cat "$_sysfs/alignment_offset" 2>/dev/null)" || _offset=0
    if [[ "$_offset" == "-1" ]]; then
        return 0
    fi
    if [[ "$_offset" =~ ^[0-9]{1,10}$ ]]; then
        _offset=$((10#$_offset))
        if (( _offset > 0 && _offset <= 4294967295 && _offset % 512 == 0 )); then
            return 0
        fi
    fi

    # For example, an 8 MiB optimal I/O size needs Parted's normal alignment.
    for _attribute in physical_block_size minimum_io_size optimal_io_size; do
        _size="$(cat "$_sysfs/queue/$_attribute" 2>/dev/null)" || continue
        [[ "$_size" =~ ^[0-9]{1,10}$ ]] || continue
        _size=$((10#$_size))
        if (( _size >= 512 && _size <= 4294967295 &&
              _size % 512 == 0 && 4194304 % _size != 0 )); then
            return 0
        fi
    done

    return 1
}

# We only support SD/MMC and USB mass-storage devices
case "$STORAGE_DEVICE" in
    "")
        echo "Usage: $(basename $0) [--version] [--force] [--skip-validation] [--full] [--quick] [--owner <uid>:<gid>] [--label <label>] --device <device>"
        exit 19 #ENODEV
        ;;
    /dev/mmcblk[0-9])
        STORAGE_PARTITION="${STORAGE_DEVICE}p1"
        # Use the reported allocation unit when it is larger.
        SD_AU_SIZE="$(cat "/sys/block/${STORAGE_DEVICE##*/}/device/preferred_erase_size" 2>/dev/null)" || SD_AU_SIZE=0
        case "$SD_AU_SIZE" in
            8388608|12582912|16777216|25165824|33554432|67108864)
                PARTITION_START="${SD_AU_SIZE}B"
                ;;
        esac
        ;;
    /dev/sd[a-z])
        STORAGE_PARTITION="${STORAGE_DEVICE}1"
        if usb_needs_parted_alignment "$STORAGE_DEVICE"; then
            PARTITION_START="0%"
        fi
        ;;
    *)
        echo "Unknown or unsupported device: $STORAGE_DEVICE"
        exit 19 #ENODEV
esac

if [[ ! -e "$STORAGE_DEVICE" ]]; then
    exit 19 #ENODEV
fi

STORAGE_PARTBASE="${STORAGE_PARTITION#/dev/}"

# Shared between this and block-device-event.sh to ensure we're not
# double-triggering nor automounting while formatting or vice-versa.
if ! create_lock_file "$STORAGE_PARTBASE"; then
    exit 53
fi

/usr/lib/hwsupport/holo-automount.sh remove "${STORAGE_PARTBASE}"

# If any partitions on the device are mounted, unmount them before continuing
# to prevent problems later
lsblk -n "$STORAGE_DEVICE" -o MOUNTPOINTS | awk NF | sort -u | while read m; do
    if ! umount "$m"; then
        echo "Failed to unmount filesystem: $m"
        exit 32 # EPIPE
    fi
done

# Test the sdcard
# Some fake cards advertise a larger size than their actual capacity,
# which can result in data loss or other unexpected behaviour. It is
# best to try to detect these issues as early as possible.
if [[ "$RUN_VALIDATION" != "0" ]]; then
    echo "stage=testing"
    if ! f3probe --destructive "$STORAGE_DEVICE"; then
        # Fake sdcards tend to only behave correctly when formatted as exfat
        # The tricks they try to pull fall apart with any other filesystem and
        # it renders the card unusuable.
        #
        # Here we restore the card to exfat so that it can be used with other devices.
        # It won't be usable with the deck, and usage of the card will most likely
        # result in data loss. We return a special error code so we can surface
        # a specific error to the user.
        echo "stage=rescuing"
        echo "Bad sdcard - rescuing"
        for i in {1..3}; do # Give this a couple of tries since it fails sometimes
            echo "Create partition table: $i"
            dd if=/dev/zero of="$STORAGE_DEVICE" bs=512 count=1024 # see comment in similar statement below
            if ! parted --script "$STORAGE_DEVICE" mklabel msdos mkpart primary 0% 100% ; then
                echo "Failed to create partition table: $i"
                continue # try again
            fi

            echo "Create exfat filesystem: $i"
            sync
            if ! mkfs.exfat "$STORAGE_PARTITION"; then
                echo "Failed to exfat filesystem: $i"
                continue # try again
            fi

            echo "Successfully restored device"
            break
        done

        # Return a specific error code so the UI can warn the user about this bad device
        exit 14 # EFAULT
    fi
fi

# Clear out the garbage bits generated by f3probe from the partition table sectors
# Otherwise parted may think we have existing partitions in a bogus state
dd if=/dev/zero of="$STORAGE_DEVICE" bs=512 count=1024

# Format as EXT4 with casefolding for proton compatibility
echo "stage=formatting"
sync
parted --script "$STORAGE_DEVICE" mklabel gpt mkpart primary "$PARTITION_START" 100%
udevadm settle
mkfs.ext4 -m 0 -O casefold -E "$EXTENDED_OPTIONS" "${EXTRA_MKFS_ARGS[@]}" -F "$STORAGE_PARTITION"
udevadm settle

# Mount the device
if ! /usr/lib/hwsupport/holo-automount.sh add "$STORAGE_PARTBASE"; then
    echo "Failed to mount ${STORAGE_PARTBASE}"
    exit 5
fi

exit 0
