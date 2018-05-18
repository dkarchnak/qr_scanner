package cz.bcx.qrscanner;

import android.Manifest;
import android.annotation.TargetApi;
import android.app.Activity;
import android.app.Application;
import android.content.Context;
import android.content.pm.PackageManager;
import android.hardware.camera2.CameraAccessException;
import android.hardware.camera2.CameraManager;
import android.os.Build;
import android.os.Bundle;

import java.util.HashMap;
import java.util.Map;

import io.flutter.plugin.common.EventChannel;
import io.flutter.plugin.common.MethodChannel;
import io.flutter.plugin.common.MethodChannel.MethodCallHandler;
import io.flutter.plugin.common.MethodChannel.Result;
import io.flutter.plugin.common.MethodCall;
import io.flutter.plugin.common.PluginRegistry;
import io.flutter.plugin.common.PluginRegistry.Registrar;
import io.flutter.view.FlutterView;

@TargetApi(Build.VERSION_CODES.LOLLIPOP)
public class QrScannerPlugin implements MethodCallHandler, PluginRegistry.RequestPermissionsResultListener {
  private static final int CAMERA_REQUEST_ID = 77_1337_77;

  private Camera camera;

  private Registrar registrar;
  private FlutterView view;
  private Activity activity;

  private static MethodChannel methodChannel;
  private EventChannel eventChannel;
  private EventChannel.EventSink eventSink;

  private Runnable initializeTask = null;

  private QrScannerPlugin(Registrar registrar, FlutterView view, Activity activity) {
    this.registrar = registrar;
    this.view = view;
    this.activity = activity;

    this.registrar.addRequestPermissionsResultListener(this);

    this.activity.getApplication().registerActivityLifecycleCallbacks(new Application.ActivityLifecycleCallbacks() {
      @Override
      public void onActivityCreated(Activity activity, Bundle savedInstanceState) {}

      @Override
      public void onActivityStarted(Activity activity) {}

      @Override
      public void onActivityResumed(Activity activity) {
        // TODO
      }


      @Override
      public void onActivityPaused(Activity activity) {
        // TODO
      }

      @Override
      public void onActivityStopped(Activity activity) {
        // TODO - Dispose
      }

      @Override
      public void onActivitySaveInstanceState(Activity activity, Bundle outState) {}

      @Override
      public void onActivityDestroyed(Activity activity) {}
    });
  }

  public static void registerWith(Registrar registrar) {
    QrScannerPlugin.methodChannel = new MethodChannel(registrar.messenger(), "cz.bcx.qr_scanner");
    QrScannerPlugin.methodChannel.setMethodCallHandler(new QrScannerPlugin(registrar, registrar.view(), registrar.activity()));
  }

  /**
   * Available methods: ["initialize", "startPreview", "stopPreview", "enableScanning", "disableScanning", "dispose"]
   * @param call - Method call from Flutter
   * @param result - Object to let Flutter know result of the method call.
   */
  @Override
  public void onMethodCall(MethodCall call, Result result) {
    if(call.method.equals("initialize")) {
      if(!(call.arguments instanceof Map)) {
        throw new IllegalArgumentException("Call's arguments is not instance of a Map.");
      }

      Map<String, Object> arguments = (Map<String, Object>) call.arguments;

      String quality = (String) arguments.get("previewQuality");
      PreviewQuality previewQuality = PreviewQuality.getPreviewQualityForName(quality);

      onInitialize(previewQuality, result);
    }
    else if(call.method.equals("startPreview")) {
      onStartPreview();
      result.success(null);
    }
    else if(call.method.equals("stopPreview")) {
      onStopPreview();
      result.success(null);

    }
    else if(call.method.equals("enableScanning")) {
      onEnableScanning();
      result.success(null);
    }
    else if(call.method.equals("disableScanning")) {
      onDisableScanning();
      result.success(null);
    }
    else if(call.method.equals("dispose")) {
      onDispose();
      result.success(null);
    }
    else {
      result.notImplemented();
    }
  }

  private boolean hasCameraPermissions() {
    return Build.VERSION.SDK_INT < Build.VERSION_CODES.M ||
            activity.checkSelfPermission(Manifest.permission.CAMERA) == PackageManager.PERMISSION_GRANTED;
  }

  @Override
  public boolean onRequestPermissionsResult(int id, String[] strings, int[] ints) {
    if (id == CAMERA_REQUEST_ID) {
      initializeTask.run();
      return true;
    }
    return false;
  }

  private void onInitialize(final PreviewQuality previewQuality, final Result result) {
    if(initializeTask != null) {
      result.success(null); //TODO - We are waiting for permissions
      return;
    }

    initializeTask = new Runnable() {
      @Override
      public void run() {
        try {
          // Initialize eventChannel and eventSink.
          if(QrScannerPlugin.this.eventChannel == null) {
            QrScannerPlugin.this.eventChannel = new EventChannel(
                    registrar.messenger(),
                    "cz.bcx.qr_scanner/events"
            );

            QrScannerPlugin.this.eventChannel.setStreamHandler(
                new EventChannel.StreamHandler() {
                  @Override
                  public void onListen(Object o, EventChannel.EventSink eventSink) {
                    QrScannerPlugin.this.eventSink = eventSink;
                  }

                  @Override
                  public void onCancel(Object o) {
                    QrScannerPlugin.this.eventSink = null;
                  }
                }
            );
          }

          CameraManager cameraManager = (CameraManager) activity.getSystemService(Context.CAMERA_SERVICE);

          Camera camera =  Camera.createCameraInstance(cameraManager, view, previewQuality);
          camera.openCamera(cameraManager, result, new Camera.CameraStateListener() {
            @Override
            public void onCameraDisconnected() {
              if(eventSink != null) {
                Map<String, String> event = new HashMap<>();
                event.put("eventType", "error");
                event.put("errorMessage", "The camera has been disconnected.");
                eventSink.success(event);
              }
            }

            @Override
            public void onCameraError(Camera.CameraStateError cameraStateError) {
              Map<String, String> event = new HashMap<>();
              event.put("eventType", "error");
              event.put("errorMessage", cameraStateError.getMessage());
              eventSink.success(event);
            }

            @Override
            public void onCodeScanned(String code) {
              Map<String, String> event = new HashMap<>();
              event.put("eventType", "codeScanned");
              event.put("code", code);
              eventSink.success(event);
            }
          });

          QrScannerPlugin.this.camera = camera;

          initializeTask = null;
        } catch (CameraAccessException e) {
          result.error("CameraAccessException", "Exception raised when initializing qr scanner plugin.", e);
        }
      }
    };

    if(!hasCameraPermissions()) {
      activity.requestPermissions(new String[] {Manifest.permission.CAMERA}, CAMERA_REQUEST_ID);
    }
    else {
      initializeTask.run();
    }
  }

  private void onStartPreview() {
    // TODO - Error Handling
    try {
      camera.startPreview();
    } catch (CameraAccessException e) {
      e.printStackTrace();
    }
  }

  private void onStopPreview() {
    // TODO - Error Handling
    try {
      camera.stopPreview();
    } catch (CameraAccessException e) {
      e.printStackTrace();
    }
  }

  private void onEnableScanning() {
    // TODO - Error Handling
    camera.enableScanning();
  }

  private void onDisableScanning() {
    // TODO - Error Handling
    camera.disableScanning();
  }

  private void onDispose() {
    // TODO - Error handling
    camera.dispose();
  }
}