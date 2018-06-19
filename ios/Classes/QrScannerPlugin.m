#import "QrScannerPlugin.h"
#import <AVFoundation/AVFoundation.h>
#import <libkern/OSAtomic.h>

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

@interface QRCam : NSObject<FlutterTexture, AVCaptureMetadataOutputObjectsDelegate, AVCaptureVideoDataOutputSampleBufferDelegate, FlutterStreamHandler>
@property(readonly, nonatomic) AVCaptureSession *captureSession;
@property(readonly, nonatomic) AVCaptureDevice *captureDevice;
@property(readonly, nonatomic) AVCaptureDeviceInput *captureDeviceInput;
@property(readonly, nonatomic) AVCaptureMetadataOutput *captureMetadataOutput;
@property(readonly, nonatomic) AVCaptureVideoPreviewLayer *captureVideoPreviewLayer;
@property(readonly, nonatomic) AVCaptureVideoDataOutput *captureVideoOutput;
@property(readonly, nonatomic) UIView *highlightView;
@property(readonly, nonatomic) CGSize previewSize;
@property(readonly, nonatomic) dispatch_queue_t serialQueue;
@property(readonly) CVPixelBufferRef volatile latestPixelBuffer;
@property(readonly, nonatomic) UIViewController *cameraViewController;
@property(readonly, nonatomic) UIView *cameraView;

@property(nonatomic) FlutterEventChannel *eventChannel;
@property(nonatomic) FlutterEventSink eventSink;
@property(nonatomic) BOOL enableScanning;


@property(readonly, nonatomic) int64_t textureId;

- (instancetype)initCamera: (UIViewController *) viewController
                            resolutionPreset:(NSString *)resolutionPreset
                            error:(NSError **)error;
- (void)start;
- (void)stop;


@end

@implementation QRCam

-(instancetype)initCamera:  (UIViewController *) viewController
                            resolutionPreset:(NSString *)resolutionPreset
                            error:(NSError **)error{
    self = [super init];
    _enableScanning = NO;
    
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
    _captureDevice = [AVCaptureDevice defaultDeviceWithMediaType: AVMediaTypeVideo];
    NSError *localError = nil;
    _captureDeviceInput =
    [AVCaptureDeviceInput deviceInputWithDevice:_captureDevice error:&localError];
    if (localError) {
        *error = localError;
        return nil;
    }
    
    [_captureSession addInput: _captureDeviceInput];
    
    _captureMetadataOutput = [[AVCaptureMetadataOutput alloc] init];
    [_captureSession addOutput: _captureMetadataOutput];
    //TODO use main queue for highlighView
    //_serialQueue = dispatch_queue_create("qrCodeQueue", NULL);
    [_captureMetadataOutput setMetadataObjectsDelegate:self queue:dispatch_get_main_queue()];
    [_captureMetadataOutput setMetadataObjectTypes:[self barcodeTypes]];
    
    CGRect rc = viewController.view.bounds;
    rc.size.width = 500;
    rc.size.height = 500;
    _previewSize = rc.size;

    [_captureMetadataOutput setRectOfInterest:rc];
    
    _cameraViewController = [[UIViewController alloc] init];
    _cameraView = [[UIView alloc] init];
    [_cameraView setBounds: rc];
    [_cameraView setCenter: viewController.view.center];
    
    _captureVideoPreviewLayer = [[AVCaptureVideoPreviewLayer alloc] initWithSession:_captureSession];
    [_captureVideoPreviewLayer setFrame: rc];
    [_cameraView.layer addSublayer: _captureVideoPreviewLayer];
    
    [viewController addChildViewController: _cameraViewController];
    
    _highlightView = [[UIView alloc] init];
    _highlightView.autoresizingMask = UIViewAutoresizingFlexibleTopMargin|UIViewAutoresizingFlexibleLeftMargin|UIViewAutoresizingFlexibleRightMargin|UIViewAutoresizingFlexibleBottomMargin;
    _highlightView.layer.borderColor = [UIColor greenColor].CGColor;
    _highlightView.layer.borderWidth = 2;
    
    [viewController.view addSubview: _cameraView];
    [_cameraView addSubview: _highlightView];
    
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

- (CVPixelBufferRef)copyPixelBuffer {
    CVPixelBufferRef pixelBuffer = _latestPixelBuffer;
    while (!OSAtomicCompareAndSwapPtrBarrier(pixelBuffer, nil, (void **)&_latestPixelBuffer)) {
        pixelBuffer = _latestPixelBuffer;
    }
    return pixelBuffer;
}

#pragma mark Video data capture

- (void)captureOutput:(AVCaptureOutput *)output
didOutputSampleBuffer:(CMSampleBufferRef)sampleBuffer
       fromConnection:(AVCaptureConnection *)connection {
   
    CVPixelBufferRef newBuffer = CMSampleBufferGetImageBuffer(sampleBuffer);
    CFRetain(newBuffer);
    CVPixelBufferRef old = _latestPixelBuffer;
    while (!OSAtomicCompareAndSwapPtrBarrier(old, newBuffer, (void **)&_latestPixelBuffer)) {
        old = _latestPixelBuffer;
    }
    if (old != nil) {
        CFRelease(old);
    }
    
    if (!CMSampleBufferDataIsReady(sampleBuffer)) {
        _eventSink(@{
                     @"eventType" : @"error",
                     @"errorMessage" : @"sample buffer is not ready. Skipping sample"
                     });
        return;
    }
    
}

#pragma mark Metadata capture

- (void)captureOutput:(AVCaptureOutput *)captureOutput
didOutputMetadataObjects:(NSArray *)metadataObjects
       fromConnection:(AVCaptureConnection *)connection {
    
    CGRect highlightViewRect = CGRectZero;
    AVMetadataMachineReadableCodeObject *barCodeObject;

    if(_enableScanning == YES && metadataObjects != nil && [metadataObjects count] > 0){
        AVMetadataObject *data = metadataObjects[0];
        barCodeObject = (AVMetadataMachineReadableCodeObject *)[_captureVideoPreviewLayer transformedMetadataObjectForMetadataObject:(AVMetadataMachineReadableCodeObject *)data];
        highlightViewRect = barCodeObject.bounds;

        NSString *code = [(AVMetadataMachineReadableCodeObject *)data stringValue];
    
        _eventSink(@{
                     @"eventType" : @"codeScanned",
                     @"code" : code
                     });
    }
    
    [_highlightView setFrame: highlightViewRect];

}

- (FlutterError *_Nullable)onCancelWithArguments:(id _Nullable)arguments {
    _eventSink = nil;
    return nil;
}

- (FlutterError *_Nullable)onListenWithArguments:(id _Nullable)arguments
                                       eventSink:(nonnull FlutterEventSink)events {
    _eventSink = events;
    return nil;
}

- (void)start {
    [_captureSession startRunning];
}

- (void)stop {
    [_captureSession stopRunning];
}

- (void)enable{
    _enableScanning = YES;
}

- (void)disable{
    _enableScanning = NO;
}

- (void)dispose{
    for (AVCaptureInput *input in [_captureSession inputs]) {
        [_captureSession removeInput:input];
    }
    for (AVCaptureOutput *output in [_captureSession outputs]) {
        [_captureSession removeOutput:output];
    }
    
    
    if (_latestPixelBuffer) {
        CFRelease(_latestPixelBuffer);
    }
    
    _captureDeviceInput = nil;
    _captureMetadataOutput = nil;
    
    [_captureVideoPreviewLayer removeFromSuperlayer];
    _captureVideoPreviewLayer = nil;
    
    [_cameraViewController removeFromParentViewController];
    _cameraViewController = nil;
    
    [_cameraView removeFromSuperview];
    _cameraView = nil;
    
    [_highlightView removeFromSuperview];
    _highlightView = nil;
    
    _captureSession = nil;
    
    //TODO main
    //_serialQueue = nil;
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
    
    
    QrScannerPlugin *instance = [[QrScannerPlugin alloc] initWithRegistry:[registrar textures] messenger:[registrar messenger] viewController: (UIViewController *)[registrar messenger]];
    [registrar addMethodCallDelegate:instance channel:channel];
}

- (instancetype)initWithRegistry:(NSObject<FlutterTextureRegistry> *)registry
                        messenger:(NSObject<FlutterBinaryMessenger> *)messenger
                        viewController: (UIViewController *) viewController{
    self = [super init];
    NSAssert(self, @"super init cannot be nil");
    _registry = registry;
    _messenger = messenger;
    _viewController = viewController;
    
    CGRect rc = _viewController.view.bounds;
    NSLog(@"VIEW w: %f h: %f", rc.size.width, rc.size.height);
    
    
    return self;
}

- (void)handleMethodCall:(FlutterMethodCall *)call result:(FlutterResult)result {
    if([@"initialize" isEqualToString:call.method]){
        if(![[call.arguments class] isSubclassOfClass:[NSMutableDictionary class]]){
            NSLog(@"Call's arguments is not instance of a Map.");
            return;
        }
        
        NSMutableDictionary *arg = (NSMutableDictionary *)call.arguments;
        NSString *quality = [arg objectForKey:@"previewQuality"];
      
        NSLog(@"init...");
        
        NSError *error;
        _camera = [[QRCam alloc] initCamera: _viewController
                           resolutionPreset: quality
                                      error: &error];
        
        if(error){
            result([error flutterError]);
            return;
        }
        
        int64_t textureId = [_registry registerTexture:_camera];
        
        FlutterEventChannel *eventChannel = [FlutterEventChannel
                                             eventChannelWithName:[NSString
                                                                   stringWithFormat:@"cz.bcx.qr_scanner/events",
                                                                   textureId]
                                             binaryMessenger:_messenger];
        [eventChannel setStreamHandler:_camera];
        _camera.eventChannel = eventChannel;
        
        result(@{
                 @"textureId" : @(textureId),
                 @"previewWidth" : @(_camera.previewSize.width),
                 @"previewHeight" : @(_camera.previewSize.height),
                 });
        
        
    }else if([@"startPreview" isEqualToString:call.method]){
        
        NSLog(@"start...");
        [_camera start];
        result(nil);
        
    }else if([@"stopPreview" isEqualToString:call.method]){
        
        NSLog(@"stop...");
        [_camera stop];
        result(nil);
        
    }else if([@"enableScanning" isEqualToString:call.method]){
        
        NSLog(@"enable...");
        [_camera enable];
        result(nil);
        
    }else if([@"disableScanning" isEqualToString:call.method]){
        
        NSLog(@"disable...");
        [_camera disable];
        result(nil);
        
    }else if([@"dispose" isEqualToString:call.method]){
        
        NSLog(@"dispose...");
        [_camera dispose];
        result(nil);
        
    }else {
        result(FlutterMethodNotImplemented);
    }
}
@end
