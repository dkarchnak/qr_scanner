#import "QrScannerPlugin.h"
#import <qr_scanner/qr_scanner-Swift.h>

@implementation QrScannerPlugin
+ (void)registerWithRegistrar:(NSObject<FlutterPluginRegistrar>*)registrar {
  [SwiftQrScannerPlugin registerWithRegistrar:registrar];
}
@end
