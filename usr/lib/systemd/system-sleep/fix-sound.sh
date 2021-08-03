#!/bin/bash

if lsmod | grep -q snd_soc_acp5x_mach; then
  ## EV2 with acp5x driver
  if [[ ${1-} = "pre" ]]; then
    modprobe -r snd_pci_acp5x
  elif [[ ${1-} = "post" ]]; then
    modprobe snd_pci_acp5x
    sleep 2
    amixer -c 1 set "Left AMP Enable" unmute
    amixer -c 1 set "Right AMP Enable" unmute

    amixer -c 1 set "Left AMP PCM Gain" 70%
    amixer -c 1 set "Right AMP PCM Gain" 70%

    amixer -c 1 set "Left Digital PCM" 817
    amixer -c 1 set "Right Digital PCM" 817
  fi
else
  ## EV1 or without acp5x driver, fixup registers manually
  if [ "${1}" == "post" ]; then
    for i in /sys/kernel/debug/regmap/spi-VLV*; do
      /usr/lib/hwsupport/cirrus-fixup.sh $i
    done
  fi
fi
