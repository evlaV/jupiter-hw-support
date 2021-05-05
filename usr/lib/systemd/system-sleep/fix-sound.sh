#!/bin/bash

if [ "${1}" == "post" ]; then
	for i in /sys/kernel/debug/regmap/spi-VLV*; do
		/usr/lib/hwsupport/cirrus-fixup.sh $i
	done
fi
