import 'dart:async';

import 'package:flutter/services.dart';
import 'package:flutter/widgets.dart';

final MethodChannel _channel =
    const MethodChannel('cz.bcx.qr_scanner');

class ScannerPreview extends StatefulWidget {
  final ScannerController controller;

  const ScannerPreview(this.controller);

  @override
  State<StatefulWidget> createState() {
    return new ScannerPreviewState(controller);
  }
}

class ScannerPreviewState extends State<ScannerPreview> {
  final ScannerController controller;
  String text = "Nic";

  ScannerPreviewState(this.controller);

  @override
  Widget build(BuildContext context) {
    if(this.controller != null && this.controller._initialized)
      return new Container(
        child: new Texture(textureId: controller._textureId),
      );
    else
      return new Container(
        child: new Text("text")
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

class ScannerController {
  bool _initialized = false;
  bool _disposed = false;

  int _textureId;
  int _resWidth, _resHeight;

  int get textureId => _textureId;

  int get resWidth => _resWidth;

  int get resHeight => _resHeight;

  int get aspectRatio => _resWidth * _resHeight;

  Future<Null> initialize({PreviewQuality previewQuality : PreviewQuality.medium}) async {
    var completer = new Completer<Null>();
    if(_disposed) {
      throw new ScannerException(message: "Calling initialize method on already disposed ScannerController instance!");
    }

    try {
      final Map parameters = <String, dynamic>{
        'previewQuality': _serializePreviewQuality(previewQuality)
      };

      final Map<dynamic, dynamic> methodResult = await _channel.invokeMethod(
        'initialize',
        parameters
      );

      this._textureId = methodResult['textureId'];
      this._resWidth  = methodResult['resWidth'];
      this._resHeight  = methodResult['resHeight'];

      print('Initialzed ScannerController with textureId: ${this._textureId} and resolution: ${this._resWidth}x${this.resHeight}');

      this._initialized = true;

      completer.complete(null);
    } on PlatformException catch(e) {
      throw new ScannerException(
        message: 'PlatformException raised during initialize method!',
        cause: e
      );
    }

    return completer.future;
  }

  Future<Null> startPreview() async {
    var completer = new Completer<Null>();

    if(_disposed) {
      throw new ScannerException(message: "Calling startPreview method on already disposed ScannerController instance!");
    }

    if(!_initialized) {
      throw new ScannerException(message: "You need to initialize ScannerController before starting preview.");
    }

    try {
      await _channel.invokeMethod(
        'start'
      );

      completer.complete(null);
    } on PlatformException catch(e) {
      throw new ScannerException(
          message: 'PlatformException raised during startPreview method!',
          cause: e
      );
    }

    return completer.future;
  }
}

class ScannerException implements Exception {
  String message;
  Exception cause;

  ScannerException({this.message, this.cause});
}