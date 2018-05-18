import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
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
      await controller.initialize();
      controller.startPreview();

      print(controller.value.previewSize);

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
              child: new Container(
                alignment: Alignment.bottomCenter,
                width: double.infinity,
                color: new Color.fromARGB(160, 60, 60, 60),
                child: new Padding(
                  padding: const EdgeInsets.symmetric(vertical: 8.0),
                  child: new Column(
                    mainAxisAlignment: MainAxisAlignment.end,
                    children: <Widget>[
                      new Text(
                        codeScanned,
                        textAlign: TextAlign.center,
                        style: new TextStyle(
                          color: Colors.white,
                          fontSize: 20.0
                        ),
                      ),
                      new Row(
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: <Widget>[
                          new Expanded(
                              child: new IconButton(
                                  icon: new Icon(this.controller.value.scanningEnabled ? Icons.favorite : Icons.favorite_border),
                                  iconSize: 42.0,
                                  color: this.controller.value.scanningEnabled ? Colors.white : Colors.red,
                                  onPressed: () {
                                    setState(() {
                                      if(this.controller.value.scanningEnabled)
                                        this.controller.disableScanning();
                                      else
                                        this.controller.enableScanning();
                                    });
                                  }
                              )
                          ),
                          new Expanded(
                              child: new IconButton(
                                  icon: new Icon(this.controller.value.previewStarted ? Icons.stop : Icons.play_arrow),
                                  iconSize: 42.0,
                                  color: Colors.white,
                                  onPressed: () {
                                    setState(() {
                                      if(this.controller.value.previewStarted) {
                                        this.controller.stopPreview();
                                      }
                                      else this.controller.startPreview();
                                    });
                                  }
                              )
                          ),
                        ],
                      )
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