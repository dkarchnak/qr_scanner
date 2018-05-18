import 'dart:async';


import 'package:flutter/services.dart';
import 'package:flutter/material.dart';

final MethodChannel _channel =
    const MethodChannel('cz.bcx.qr_scanner');

class ScannerPreview extends StatelessWidget {
  final ScannerController controller;

  const ScannerPreview(this.controller);


  @override
  Widget build(BuildContext context) {
    if(this.controller != null && this.controller.value.initialized)
      return new Container(
        child: new Texture(textureId: controller._textureId),
      );
    else
      return new Container(
        child: new Text("Controller is not initialized!"),
      );
  }
}

enum PreviewQuality {
  low,    // 320x240
  medium, // 640x480
  high    // 1024x768
}

String _serializePreviewQuality(PreviewQuality previewQuality) {
  switch(previewQuality) {
    case PreviewQuality.low:
      return 'low';
    case PreviewQuality.medium:
      return 'medium';
    case PreviewQuality.high:
      return 'high';

    // Fallback to medium quality
    default:
      return 'medium';
  }
}

class ScannerValue {
  final bool initialized;

  final bool previewStarted;
  final Size previewSize;
  final bool scanningEnabled;

  final String error;

  const ScannerValue({
    this.initialized,
    this.previewStarted,
    this.previewSize,
    this.scanningEnabled,
    this.error
  });

  const ScannerValue.uninitialized() : this(initialized: false, previewStarted: false, scanningEnabled: false);

  ScannerValue copyWith({
    bool initialized,
    bool previewStarted,
    Size previewSize,
    bool scanningEnabled,
    String error
  }) {
    return new ScannerValue(
      initialized: initialized ?? this.initialized,
      previewStarted: previewStarted ?? this.previewStarted,
      previewSize: previewSize ?? this.previewSize,
      scanningEnabled: scanningEnabled ?? this.scanningEnabled,
      error: error ?? this.error
    );
  }

  @override
  String toString() {
    return  '$runtimeType('
            'initialized: $initialized, '
            'previewStarted: $previewStarted, '
            'previewSize: $previewSize, '
            'scanningEnabled: $scanningEnabled)';
  }
}

class ScannerController extends ValueNotifier<ScannerValue> {
  Completer<Null> _initializeCompleter;

  PreviewQuality previewQuality;
  int _textureId;

  bool _disposed = false;

  StreamSubscription<dynamic> _eventChannelSubscription;

  ScannerController({this.previewQuality : PreviewQuality.medium}) : super(new ScannerValue.uninitialized());

  Future<Null> initialize() async {
    if(_disposed) {
      //TODO - Throw an error?
//      return Future<Null>.;
    }

    try {
      _initializeCompleter = new Completer<Null>();
      
      final Map<dynamic, dynamic> methodResult = await _channel.invokeMethod(
        'initialize',
        <String, dynamic> {
          'previewQuality' : _serializePreviewQuality(previewQuality)
        }
      );

      _textureId = methodResult['textureId'];
      value = value.copyWith(
        previewSize: new Size(
          methodResult['previewWidth'].toDouble(),
          methodResult['previewHeight'].toDouble()
        )
      );

      // Subscription to receive state and error events from native platform
      _eventChannelSubscription = new EventChannel('cz.bcx.qr_scanner/events')
          .receiveBroadcastStream()
          .listen(_onEventReceived);


      value = value.copyWith(
        initialized: true
      );

      _initializeCompleter.complete(null);
      return _initializeCompleter.future;
    } on PlatformException catch(e) {
      print(e.code);
      print(e.message);
      throw new ScannerException(message: "Failed while initializing ScannerController.", cause: e);
    }
  }

  void _onEventReceived(dynamic event) {
    if(_disposed) return;

    print(event); //TODO
  }

  void startPreview() async {
    if(value.initialized && !_disposed) { //Error if not initialized or disposed
      await _channel.invokeMethod(
        'startPreview',
      );

      value = value.copyWith(previewStarted: true);
    }
  }

  void stopPreview() async {
    if(value.initialized && !_disposed) { //Error if not initialized or disposed
      await _channel.invokeMethod(
        'stopPreview'
      );

      value = value.copyWith(previewStarted: false);
    }
  }

  void enableScanning() async {
    if(value.initialized && !_disposed) { //Error if not initialized or disposed
      await _channel.invokeMethod(
          'enableScanning'
      );

      value = value.copyWith(scanningEnabled: true);
    }
  }

  void disableScanning() async {
    if(value.initialized && !_disposed) { //Error if not initialized or disposed
      await _channel.invokeMethod(
          'disableScanning'
      );

      value = value.copyWith(scanningEnabled: false);
    }
  }

  @override
  Future<Null> dispose() {
    if(_disposed) {
      return new Future<Null>.value(null);
    }

    _disposed = true;

    super.dispose();

    if(_initializeCompleter != null) {
      return _initializeCompleter.future.then((param) async {
        await _channel.invokeMethod(
          'dispose'
        );
        await _eventChannelSubscription?.cancel();
      });
    }
    else {
      return new Future<Null>.value(null);
    }
  }
}

class ScannerException implements Exception {
  String message;
  Exception cause;

  ScannerException({this.message, this.cause});
}