#!/bin/bash

set -xeuo pipefail

# For reasons I cannot explain, piping lsmod to grep -q here randomly fails sometimes. Some kind of output buffering bug
# in lsmod?
lsmod=$(lsmod)

if grep -q snd_soc_acp5x_mach <<< "$lsmod"; then
  ## EV2 with acp5x driver
  if [[ ${1-} = "pre" ]]; then
    sudo -u '#1000' XDG_RUNTIME_DIR=/run/user/1000 pactl unload-module module-echo-cancel
    sudo -u '#1000' XDG_RUNTIME_DIR=/run/user/1000 pactl unload-module module-null-sink
    sudo -u '#1000' XDG_RUNTIME_DIR=/run/user/1000 pactl load-module module-null-sink
    sudo -u '#1000' XDG_RUNTIME_DIR=/run/user/1000 pactl set-default-sink null-sink
  elif [[ ${1-} = "post" ]]; then
    sleep 2
    sudo -u '#1000' XDG_RUNTIME_DIR=/run/user/1000 pactl unload-module module-null-sink
    sudo -u '#1000' XDG_RUNTIME_DIR=/run/user/1000 pactl load-module module-echo-cancel aec_method=webrtc aec_args="beamforming=1 mic_geometry=-0.0062,0,0,0.0062,0,0"
  fi
else
  ## EV1 or without acp5x driver, fixup registers manually
  if [ "${1-}" == "post" ]; then
    for i in /sys/kernel/debug/regmap/spi-VLV*; do
      /usr/lib/hwsupport/cirrus-fixup.sh $i
    done
  fi
fi
