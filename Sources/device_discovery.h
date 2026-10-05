#ifndef AIRCARD_DEVICE_DISCOVERY_H
#define AIRCARD_DEVICE_DISCOVERY_H

#import <Foundation/Foundation.h>

// Notification options for AMDeviceNotificationSubscribeWithOptions.
//
// `NotificationOptionEnableRemoteXPC` is deliberately absent. Screen reaches
// devices over usbmuxd (AMDeviceConnect, AMDeviceSecureStartService), so the
// mux transport is the one that has to be requested. On macOS 27 (26A5388g)
// enabling RemoteXPC does not add to that transport, it replaces it: a
// cable-connected, paired iPhone fires no connected callback at all, only
// detach callbacks with a NULL device. Every enumeration then reported "No
// iPhone found" and the card scanner reported "iPhone not found", even though
// ioreg, usbmuxd and devicectl all listed the device. Removing the option
// returns the device immediately on the same machine.
//
// Wi-Fi paired devices stay covered: usbmuxd publishes those over the same mux
// transport, and `NotificationOptionSearchForWiFiPairableDevices` is off here
// because this helper never pairs a device over the network.
static NSDictionary *ScreenDeviceNotificationOptions(BOOL directConnectionsOnly) {
    return @{
        @"NotificationOptionSearchForPairedDevices": @YES,
        @"NotificationOptionSearchForPairedDevicesViaDirectConnectionsOnly":
            @(directConnectionsOnly),
        @"NotificationOptionSearchForWiFiPairableDevices": @NO,
        @"NotificationOptionEnableUSBMux": @YES,
    };
}

#endif
