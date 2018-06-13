#import "QrScannerPlugin.h"
#import <AVFoundation/AVFoundation.h>

@interface QRCam : NSObject<AVCaptureMetadataOutputObjectsDelegate>
@property(readonly, nonatomic) AVCaptureSession *captureSession;
@property(readonly, nonatomic) AVCaptureDevice *captureDevice;
@property(readonly, nonatomic) AVCaptureDeviceInput *captureDeviceInput;
@property(readonly, nonatomic) AVCaptureMetadataOutput *captureMetdadaOutput;
@property(readonly, nonatomic) AVCaptureVideoPreviewLayer *captureVideoPreviewLayer;

@end

@interface QrScannerPlugin ()
@property(readonly, nonatomic) NSObject<FlutterTextureRegistry> *registry;
@property(readonly, nonatomic) NSObject<FlutterBinaryMessenger> *messenger;
@property(readonly, nonatomic) QRCam *camera;
@end

@implementation QrScannerPlugin
+ (void)registerWithRegistrar:(NSObject<FlutterPluginRegistrar>*)registrar {
    FlutterMethodChannel *channel = [FlutterMethodChannel
                                     methodChannelWithName: @"cz.bcx.qr_scanner"
                                     binaryMessenger: [registrar messenger]];
    
    QrScannerPlugin *instance = [[QrScannerPlugin alloc] initWithRegistry:[registrar textures] messenger:[registrar messenger]];
    [registrar addMethodCallDelegate:instance channel:channel];
}

- (instancetype)initWithRegistry:(NSObject<FlutterTextureRegistry> *)registry
                       messenger:(NSObject<FlutterBinaryMessenger> *)messenger {
    self = [super init];
    NSAssert(self, @"super init cannot be nil");
    _registry = registry;
    _messenger = messenger;
    return self;
}

- (void)handleMethodCall:(FlutterMethodCall *)call result:(FlutterResult)result {
    NSLog(@"Method call: %@", call.method);
    if([@"initialize" isEqualToString:call.method]){
        
        NSLog(@"init...");
        
    }else if([@"startPreview" isEqualToString:call.method]){
        
        NSLog(@"start...");
        
    }else if([@"stopPreview" isEqualToString:call.method]){
        
        NSLog(@"stop...");
        
    }else if([@"enableScanning" isEqualToString:call.method]){
        
        NSLog(@"enable...");
        
    }else if([@"disableScanning" isEqualToString:call.method]){
        
        NSLog(@"disable...");
        
    }else if([@"dispose" isEqualToString:call.method]){
        
        NSLog(@"dispose...");
        
    }
}
@end
