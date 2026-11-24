# Firmware scripts

Text part of the `firmware/` folder that BoxFlasher pushes to a box.
The full `firmware/` folder (APKs, extracted native libs, root certificates) is distributed
separately because it is large and contains third-party APKs.

Layout of `firmware/`:

```
apply.sh                  # run as root on the box; idempotent, checks the stock build fingerprint
etc/box_init.sh           # boot script: NTP, provisioning flags, first-boot defaults
etc/box_launcher.conf     # BoxLauncher tiles
cacerts/                  # extra root CAs (Android subject_hash_old names)
app/<Name>/<Name>.apk     # system apps; native libs extracted to app/<Name>/lib/arm
```
