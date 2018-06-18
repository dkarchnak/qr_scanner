#import "QrScannerPlugin.h"
#import <AVFoundation/AVFoundation.h>

@interface NSError (FlutterError)
@property(readonly, nonatomic) FlutterError *flutterError;
@end

@implementation NSError (FlutterError)
- (FlutterError *)flutterError {
    return [FlutterError errorWithCode:[NSString stringWithFormat:@"Error %d", (int)self.code]
                               message:self.domain
                               details:self.localizedDescription];
}
@end

@interface QRCam : NSObject<AVCaptureMetadataOutputObjectsDelegate>
@property(readonly, nonatomic) AVCaptureSession *captureSession;
@property(readonly, nonatomic) AVCaptureDevice *captureDevice;
@property(readonly, nonatomic) AVCaptureDeviceInput *captureDeviceInput;
@property(readonly, nonatomic) AVCaptureMetadataOutput *captureMetadataOutput;
@property(readonly, nonatomic) AVCaptureVideoPreviewLayer *captureVideoPreviewLayer;
@property(readonly, nonatomic) dispatch_queue_t serialQueue;

@property(readonly, nonatomic) UIViewController *cameraViewController;
@property(readonly, nonatomic) UIView *cameraView;

@property(readonly, nonatomic) int64_t textureId;

- (instancetype)initWithCameraName:(NSString *)cameraName
                            viewController: (UIViewController *) viewController
                            resolutionPreset:(NSString *)resolutionPreset
                            error:(NSError **)error;
- (void)start;
- (void)stop;


@end

@implementation QRCam

-(instancetype)initWithCameraName:(NSString *)cameraName
                            viewController: (UIViewController *) viewController
                            resolutionPreset:(NSString *)resolutionPreset
                            error:(NSError **)error{
    self = [super init];
    
    _captureSession = [[AVCaptureSession alloc] init];
    AVCaptureSessionPreset preset;
    if ([resolutionPreset isEqualToString:@"high"]) {
        preset = AVCaptureSessionPresetHigh;
    } else if ([resolutionPreset isEqualToString:@"medium"]) {
        preset = AVCaptureSessionPresetMedium;
    } else {
        NSAssert([resolutionPreset isEqualToString:@"low"], @"Unknown resolution preset %@",
                 resolutionPreset);
        preset = AVCaptureSessionPresetLow;
    }
    
    _captureSession.sessionPreset = preset;
    _captureDevice = [AVCaptureDevice deviceWithUniqueID:cameraName];
    NSError *localError = nil;
    _captureDeviceInput =
    [AVCaptureDeviceInput deviceInputWithDevice:_captureDevice error:&localError];
    if (localError) {
        *error = localError; //TODO send flutter event error
        return nil;
    }
    
    [_captureSession addInput: _captureDeviceInput];
    
    _captureMetadataOutput = [[AVCaptureMetadataOutput alloc] init];
    [_captureSession addOutput: _captureMetadataOutput];
    
    _serialQueue = dispatch_queue_create("qrCodeQueue", NULL); //CANT FORGOT STOP QUEUE
    [_captureMetadataOutput setMetadataObjectsDelegate:self queue:_serialQueue];
    [_captureMetadataOutput setMetadataObjectTypes:[self barcodeTypes]];
    
    CGRect rc = viewController.view.bounds;
    
    [_captureMetadataOutput setRectOfInterest:rc];
    
    _cameraViewController = [[UIViewController alloc] init];
    _cameraView = [[UIView alloc] init];
    [_cameraView setBounds: rc];
    [_cameraView setCenter: viewController.view.center];
    
    _captureVideoPreviewLayer = [[AVCaptureVideoPreviewLayer alloc] initWithSession:_captureSession];
    [_captureVideoPreviewLayer setFrame: rc];
    [_cameraView.layer addSublayer: _captureVideoPreviewLayer];
    
    [viewController addChildViewController: _cameraViewController];
    [viewController.view addSubview: _cameraView];
    
    return self;
}

- (NSArray*)barcodeTypes {
    NSMutableArray *metadataObjectTypes = [NSMutableArray array];
    [metadataObjectTypes addObject:AVMetadataObjectTypeQRCode];
    [metadataObjectTypes addObject:AVMetadataObjectTypeAztecCode];
    [metadataObjectTypes addObject:AVMetadataObjectTypePDF417Code];
    [metadataObjectTypes addObject:AVMetadataObjectTypeDataMatrixCode];
    
    return [NSArray arrayWithArray:metadataObjectTypes];
    
}

- (void)captureOutput:(AVCaptureOutput *)captureOutput
didOutputMetadataObjects:(NSArray *)metadataObjects
       fromConnection:(AVCaptureConnection *)connection {
   

}
- (void)start {
    [_captureSession startRunning];
}

- (void)stop {
    [_captureSession stopRunning];
}

@end

@interface QrScannerPlugin ()
@property(readonly, nonatomic) NSObject<FlutterTextureRegistry> *registry;
@property(readonly, nonatomic) NSObject<FlutterBinaryMessenger> *messenger;
@property(readonly, nonatomic) UIViewController *viewController;
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
    _viewController = (UIViewController *)messenger;
    return self;
}

- (void)handleMethodCall:(FlutterMethodCall *)call result:(FlutterResult)result {
    NSLog(@"Method call: %@", call.method);
    if([@"initialize" isEqualToString:call.method]){
        
        if([call.arguments class] != [NSMutableDictionary class]){
            NSLog(@"Call's arguments is not instance of a Map.");
            return;
        }
        
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
