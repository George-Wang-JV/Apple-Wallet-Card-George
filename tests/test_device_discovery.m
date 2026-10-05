#import "../Sources/device_discovery.h"
#include <assert.h>

// The legacy AMDevice API only reaches devices through usbmuxd, so the
// subscription has to request that transport. Adding RemoteXPC back hides every
// USB device on macOS 27, which is what this test locks out.
static void TestRequestsUsbMuxOnly(void) {
    for (NSNumber *direct in @[@NO, @YES]) {
        NSDictionary *options = ScreenDeviceNotificationOptions(direct.boolValue);
        assert([options[@"NotificationOptionSearchForPairedDevices"] boolValue]);
        assert([options[@"NotificationOptionEnableUSBMux"] boolValue]);
        assert([options[@"NotificationOptionSearchForWiFiPairableDevices"] isEqual:@NO]);
        assert([options[@"NotificationOptionSearchForPairedDevicesViaDirectConnectionsOnly"]
            isEqual:direct]);
        for (NSString *key in options)
            assert([key rangeOfString:@"RemoteXPC"].location == NSNotFound);
    }
}

int main(void) {
    @autoreleasepool {
        TestRequestsUsbMuxOnly();
        puts("USB mux-only device discovery options passed.");
    }
    return 0;
}
