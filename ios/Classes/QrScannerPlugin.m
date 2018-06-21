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
@property(readonly, nonatomic) int64_t textureId;
@property(readonly, nonatomic) AVCaptureSession *captureSession;
@property(readonly, nonatomic) AVCaptureDevice *captureDevice;
@property(readonly, nonatomic) AVCaptureDeviceInput *captureDeviceInput;
@property(readonly, nonatomic) AVCaptureMetadataOutput *captureMetadataOutput;
@property(readonly, nonatomic) AVCaptureVideoPreviewLayer *captureVideoPreviewLayer;
@property(readonly, nonatomic) AVCaptureVideoDataOutput *captureVideoOutput;
@property(readonly, nonatomic) AVCaptureConnection *connection;
@property(readonly, nonatomic) CGSize previewSize;
@property(readonly) CVPixelBufferRef volatile latestPixelBuffer;

@property(nonatomic, copy) void (^onFrameAvailable)();

@property(nonatomic) FlutterEventChannel *eventChannel;
@property(nonatomic) FlutterEventSink eventSink;
@property(nonatomic) BOOL enableScanning;


- (instancetype)initCamera: (NSString *)resolutionPreset
                            error:(NSError **)error;
- (void)start;
- (void)stop;


@end

@implementation QRCam

-(instancetype)initCamera:  (NSString *)resolutionPreset
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
    
    CMVideoDimensions dimensions =
    CMVideoFormatDescriptionGetDimensions([[_captureDevice activeFormat] formatDescription]);
    _previewSize = CGSizeMake(dimensions.width, dimensions.height);
    
    _captureVideoOutput = [AVCaptureVideoDataOutput new];
    _captureVideoOutput.videoSettings =
    @{(NSString *)kCVPixelBufferPixelFormatTypeKey : @(kCVPixelFormatType_32BGRA) };
    [_captureVideoOutput setAlwaysDiscardsLateVideoFrames:YES];
    [_captureVideoOutput setSampleBufferDelegate:self queue:dispatch_get_main_queue()];
    
    _connection =
    [AVCaptureConnection connectionWithInputPorts:_captureDeviceInput.ports
                                           output:_captureVideoOutput];
    if ([_captureDevice position] == AVCaptureDevicePositionFront) {
        _connection.videoMirrored = YES;
    }
    [_connection setVideoOrientation:[self interfaceOrientationToVideoOrientation]];
    [_captureSession addInputWithNoConnections:_captureDeviceInput];
    [_captureSession addOutputWithNoConnections:_captureVideoOutput];
    [_captureSession addConnection:_connection];
    
    _captureMetadataOutput = [[AVCaptureMetadataOutput alloc] init];
    [_captureSession addOutput: _captureMetadataOutput];
    [_captureMetadataOutput setMetadataObjectsDelegate:self queue:dispatch_get_main_queue()];
    
    [_captureMetadataOutput setMetadataObjectTypes:[self barcodeTypes]];
    
    [[UIDevice currentDevice] beginGeneratingDeviceOrientationNotifications];
    [[NSNotificationCenter defaultCenter]
     addObserver:self selector:@selector(orientationChanged)
     name:UIDeviceOrientationDidChangeNotification
     object:[UIDevice currentDevice]];
    
    return self;
}

-(AVCaptureVideoOrientation)interfaceOrientationToVideoOrientation {
    switch ([[UIApplication sharedApplication] statusBarOrientation]) {
        case UIInterfaceOrientationPortraitUpsideDown:
            return AVCaptureVideoOrientationPortraitUpsideDown;
        case UIInterfaceOrientationPortrait:
            return AVCaptureVideoOrientationPortrait;
        case UIInterfaceOrientationLandscapeLeft:
            return AVCaptureVideoOrientationLandscapeLeft;
        case UIInterfaceOrientationLandscapeRight:
            return AVCaptureVideoOrientationLandscapeRight;
        default:
           return AVCaptureVideoOrientationPortrait;
    }

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

- (void)dealloc {
    if (_latestPixelBuffer) {
        CFRelease(_latestPixelBuffer);
    }
}
#pragma mark Video data capture

- (void)captureOutput:(AVCaptureOutput *)output
didOutputSampleBuffer:(CMSampleBufferRef)sampleBuffer
       fromConnection:(AVCaptureConnection *)connection {
    if(output == _captureVideoOutput){
        CVPixelBufferRef newBuffer = CMSampleBufferGetImageBuffer(sampleBuffer);
        CFRetain(newBuffer);
        CVPixelBufferRef old = _latestPixelBuffer;
        while (!OSAtomicCompareAndSwapPtrBarrier(old, newBuffer, (void **)&_latestPixelBuffer)) {
            old = _latestPixelBuffer;
        }
        if (old != nil) {
            CFRelease(old);
        }
        if (_onFrameAvailable)
        {
            _onFrameAvailable();
        }
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
    

    if(_enableScanning == YES && metadataObjects != nil && [metadataObjects count] > 0){
        AVMetadataObject *data = metadataObjects[0];
        NSString *code = [(AVMetadataMachineReadableCodeObject *)data stringValue];
    
        _eventSink(@{
                     @"eventType" : @"codeScanned",
                     @"code" : code
                     });
    }
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

- (void) orientationChanged{
    NSLog(@"Orientation changed");
    [_connection setVideoOrientation:[self interfaceOrientationToVideoOrientation]];
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
    
    if (_latestPixelBuffer)
    {
        CFRelease(_latestPixelBuffer);
    }
    
    _captureDeviceInput = nil;
    _captureMetadataOutput = nil;
    _captureVideoOutput = nil;
    _connection = nil;
    _captureSession = nil;
}

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
                        messenger:(NSObject<FlutterBinaryMessenger> *)messenger
                        {
    self = [super init];
    NSAssert(self, @"super init cannot be nil");
    _registry = registry;
    _messenger = messenger;
    
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
        _camera = [[QRCam alloc] initCamera: quality
                                error: &error];
        
        if(error){
            result([error flutterError]);
            return;
        }
        
        int64_t textureId = [_registry registerTexture:_camera];
        _camera.onFrameAvailable = ^{
            [_registry textureFrameAvailable:textureId];
        };
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
