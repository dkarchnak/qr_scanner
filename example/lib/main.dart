import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:qr_scanner/qr_scanner.dart';

void main() => runApp(new MyApp());

class MyApp extends StatefulWidget {
  @override
  _MyAppState createState() => new _MyAppState(new ScannerController(previewQuality: PreviewQuality.high));
}

class _MyAppState extends State<MyApp> {
  ScannerController controller;

  _MyAppState(this.controller);

  @override
  initState() {
    super.initState();
    initController();
  }

  initController() async {
    try {
      await controller.initialize();
      controller.startPreview();

      setState(() {});
    } on PlatformException {
      // TODO
    }
  }

  @override
  Widget build(BuildContext context) {
    return new MaterialApp(
      home: new Scaffold(
        body: new Stack(
          children: <Widget>[
            new ScannerPreview(controller),
            new Container(
              alignment: Alignment.bottomCenter,
              child: new Container(
                width: double.infinity,
                color: new Color.fromARGB(160, 60, 60, 60),
                child: new Padding(
                  padding: const EdgeInsets.symmetric(vertical: 8.0),
                  child: new Row(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: <Widget>[
                      new Expanded(
                        child: new IconButton(
                            icon: new Icon(Icons.photo_camera),
                            iconSize: 42.0,
                            color: Colors.white,
                            onPressed: () {
                              this.controller.enableScanning();
                            }
                        )
                      ),
                      new Expanded(
                          child: new IconButton(
                              icon: new Icon(Icons.stop),
                              iconSize: 42.0,
                              color: Colors.white,
                              onPressed: () {
                                this.controller.stopPreview();
                              }
                          )
                      ),
                      new Expanded(
                          child: new IconButton(
                              icon: new Icon(Icons.play_arrow),
                              iconSize: 42.0,
                              color: Colors.white,
                              onPressed: () {
                                this.controller.startPreview();
                              }
                          )
                      ),
                    ],
                  )
                ),
              )
            ),
            new Center(
              child: new SizedBox.fromSize(
                size: new Size(200.0, 200.0),
                child: new Container(
                  decoration: new BoxDecoration(
                    border: new Border.all(
                      color: Colors.redAccent
                    ),
                  ),
                ),
              ),
            )
            ]
        )
      )
    );
  }
}