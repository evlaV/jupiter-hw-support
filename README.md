To update the BIOS on the board, please clone this repository.

Because the original BIOS you have is incompatible with newer ones, you need to flash two test images to the device before it'll let you get to the good stuff.

First hop:

```
$ sudo ./usr/share/jupiter_bios_updater/h2offt ./usr/share/jupiter_bios/Test1_sign.fd -all
```

Second hop:

```
$ sudo ./usr/share/jupiter_bios_updater/h2offt ./usr/share/jupiter_bios/Test2_sign.fd -all
```

Third hop:

```
$ sudo ./usr/share/jupiter_bios_updater/h2offt ./usr/share/jupiter_bios/F7A0010_sign.fd -all
```

That's our most recent image for now and it should greatly improve boot time, as well as plenty of other fixes/changes/regressions.

The flash process after running that command above looks like a reboot into their updater, then a reboot into the OS again. It needs to be on AC the whole time. If it seems like either reboot gets stuck on a black screen for more than 5 minutes, long-press power and try rebooting it. It should remember the fact it's doing a BIOS update and still do it.

There's a chance some of your boards won't come back from this process, but we should still apply these updates. Let me know if one seems completely stuck, with no amount of long-press cycling and waiting doing anything. Don't long-press if you see the update screen or if it's not been on a black screen for a while, obviously, as it could be a good boot.
