import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:qr_scanner/qr_scanner.dart';

void main() => runApp(new MyApp());

class MyApp extends StatefulWidget {
  @override
  _MyAppState createState() => new _MyAppState(new ScannerController());
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
      await controller.initialize(previewQuality: PreviewQuality.high);
      await controller.startPreview();

      setState(() {
      });
    } on PlatformException {
      // TODO
    }
  }

  @override
  Widget build(BuildContext context) {
    return new MaterialApp(
      home: new Scaffold(
        appBar: new AppBar(
          title: new Text('Plugin example app'),
        ),
        body: new ScannerPreview(controller)
      ),
    );
  }
}