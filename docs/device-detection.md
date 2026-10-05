# Device detection validation

## Reproduction and cause

`device_helper` enumerates iPhones through
`AMDeviceNotificationSubscribeWithOptions`. Its option dictionary requested
`NotificationOptionEnableRemoteXPC` alongside `NotificationOptionEnableUSBMux`.

On macOS 27 (26A5388g) that option does not add the RemoteXPC transport to the
mux transport, it replaces it. A cable-connected iPhone that was already paired
produced no connected callback at all: the subscription delivered only detach
callbacks with a NULL device. `device_helper list` printed `[]`, so `cmd_device`
reported `{"connected": false, "error": "no_device"}` and the app showed
"No iPhone found. Please connect via USB." The scanner path (`FindTarget`)
failed the same way with "iPhone not found. Reconnect it via USB."

The device itself was healthy. `ioreg -p IOUSB` listed `iPhone@02100000` with
`SupportsIPhoneOS = Yes`, a direct `usbmuxd` `ListDevices` call over
`/var/run/usbmuxd` returned the device with `ConnectionType: USB`, and
`xcrun devicectl list devices` reported `Pairing State: paired`. Comparing
subscriptions on the same machine showed the option was the only difference:
`SearchForPairedDevices` alone, `...ViaDirectConnectionsOnly` alone and
`EnableUSBMux` alone each returned the device, `EnableRemoteXPC` alone returned
nothing, and adding it back to the full set hid the device again.

The option set now lives in `Sources/device_discovery.h` and requests the mux
transport only, which is the transport the legacy `AMDevice*` API actually uses.
Wi-Fi paired devices are unaffected because usbmuxd publishes those over the
same transport. `tests/test_device_discovery.py` fails if RemoteXPC is
requested again.

## Verified environment

| Component | Version |
| --- | --- |
| iPhone | iPhone 16 Pro (`iPhone17,1`), iOS 27.0 (24A5370h) |
| Mac | macOS 27.0 (26A5388g) |
| Source baseline | Screen 1.2.4, commit `c91d8f9` |

With the change `device_helper list` returned the device with a live lockdown
session (`product`, `version`, `name`, `language`, `bold_text`), and
`aircard_backend.py --device` reported `"connected": true` with
`"airlift_compatible": true`. `device_helper syslog <udid>` reached
`Connected to the unified device log stream`, so the scanner path is restored
too.

Only macOS 27 was tested. If detection fails elsewhere, or if a previously
working macOS version regresses after this change, report the macOS version,
iPhone model and iOS version alongside the Screen commit tested.

## Automated checks

```sh
python3 -m unittest discover -s tests -v
bash build.sh
```
