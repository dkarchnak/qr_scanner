import 'package:flutter/material.dart';
import 'package:qr_scanner/qr_scanner.dart';

void main() => runApp(new MyApp());

class MyApp extends StatefulWidget {
  @override
  _MyAppState createState() => new _MyAppState();
}

class _MyAppState extends State<MyApp> {
  ScannerController controller;

  String codeScanned = 'None';

  _MyAppState() {
    this.controller = new ScannerController(
      previewQuality: PreviewQuality.high,
      onCodeScanned: (String code) {
        setState(() {
          this.codeScanned = code;
        });
      }
    );
  }

  @override
  initState() {
    super.initState();
    initController();
  }

  initController() async {
    try {
      controller.addListener(() {
        if(controller.value.error != null) {
          controller.stopPreview();
          codeScanned = controller.value.error;
        }

        setState(() {}); //Update state
      });

      await controller.initialize();
      controller.enableScanning();
      controller.startPreview();

    } on ScannerException catch(e) {
      print(e.message);
    }
  }

  _togglePreview() {
    if(controller.value.previewStarted)
      controller.stopPreview();
    else
      controller.startPreview();
  }

  @override
  Widget build(BuildContext context) {
    return new MaterialApp(
      home: new Scaffold(
        body: new Stack(
          children: <Widget>[
            new ScannerPreview(controller),
            new Container(
              alignment: Alignment.topCenter,
              padding: const EdgeInsets.only(top: 32.0),
              child: new Text(
                codeScanned,
                textAlign: TextAlign.center,
                style: new TextStyle(
                  color: Colors.white,
                  fontSize: 20.0,
                ),
              ),
            ), //Top scanned text
            new Container( //Bottom control
              width: double.infinity,
              height: double.infinity,
              alignment: Alignment.bottomCenter,
              padding: const EdgeInsets.only(bottom: 8.0),
              child: new GestureDetector(
                onTap: _togglePreview,
                child: new SizedBox.fromSize(
                  size: new Size(48.0, 48.0),
                  child: new Container(
                    decoration: new ShapeDecoration(
                      shadows: [
                        new BoxShadow(
                          color: const Color(0x66000000),
                          blurRadius: 8.0,
                          spreadRadius: 4.0
                        )
                      ],
                      shape: new CircleBorder(
                        side: new BorderSide(
                          color: Colors.white,
                          width: 2.0
                        )
                      )
                    ),
                    child: new Center(
                      child: new Icon(
                        this.controller.value.previewStarted ? Icons.stop : Icons.play_arrow,
                        color: Colors.white,
                      ),
                    ),
                  ),
                )
              ),
            ),
          ]
        )
      )
    );
  }
}