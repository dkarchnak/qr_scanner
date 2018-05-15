package cz.bcx.qrscanner;

import android.Manifest;
import android.annotation.SuppressLint;
import android.annotation.TargetApi;
import android.app.Activity;
import android.content.Context;
import android.content.pm.PackageManager;
import android.graphics.SurfaceTexture;
import android.hardware.camera2.CameraAccessException;
import android.hardware.camera2.CameraCaptureSession;
import android.hardware.camera2.CameraCharacteristics;
import android.hardware.camera2.CameraDevice;
import android.hardware.camera2.CameraManager;
import android.hardware.camera2.CaptureRequest;
import android.hardware.camera2.params.StreamConfigurationMap;
import android.os.Build;
import android.util.Log;
import android.util.Size;
import android.view.Surface;

import java.util.ArrayList;
import java.util.HashMap;
import java.util.List;
import java.util.Map;

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

  private static CameraManager cameraManager;

  private Runnable initializeTask = null;

  private QrScannerPlugin(Registrar registrar, FlutterView view, Activity activity) {
    this.registrar = registrar;
    this.view = view;
    this.activity = activity;
  }

  public static void registerWith(Registrar registrar) {
    final MethodChannel channel = new MethodChannel(registrar.messenger(), "cz.bcx.qr_scanner");
    cameraManager = (CameraManager) registrar.activity().getSystemService(Context.CAMERA_SERVICE);
    channel.setMethodCallHandler(new QrScannerPlugin(registrar, registrar.view(), registrar.activity()));
  }

  @Override
  public void onMethodCall(MethodCall call, Result result) {
    if(call.method.equals("initialize")) {
      if(!(call.arguments instanceof Map)) {
        throw new IllegalArgumentException("Call's arguments is not instance of a Map.");
      }

      Map<String, Object> arguments = (Map<String, Object>) call.arguments;

      String quality = (String) arguments.get("previewQuality");
      PreviewQuality previewQuality = PreviewQuality.getPreviewQualityForName(quality);

      onInitializeMethod(previewQuality, result);
    }
    else if(call.method.equals("start")) {
      onStartMethod(result);
    }
    else {
      result.notImplemented();
    }
  }

  private void onInitializeMethod(final PreviewQuality previewQuality, final Result result) {
    if(initializeTask != null) {
      result.success(null); //TODO - We are waiting for permissions
      return;
    }

    initializeTask = new Runnable() {
      @Override
      public void run() {
        try {
          QrScannerPlugin.this.camera = createCameraInstance(previewQuality);

          HashMap<String, Object> response = new HashMap<>();
          response.put("textureId", camera.getTextureId());

          Size res = camera.getPreviewResolution();
          response.put("resWidth", res.getWidth());
          response.put("resHeight", res.getHeight());
          result.success(response);
        } catch (CameraAccessException e) {
          result.error("CameraAccessException", "Exception raised when creating Camera instance!", e);
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

  private enum PreviewQuality {
    LOW("low", 480, 320),
    MEDIUM("medium", 640, 480),
    HIGH("high", 1024, 768);

    private static final PreviewQuality FALLBACK_VALUE = PreviewQuality.MEDIUM;

    private final String serializedName;
    private final Size size;

    PreviewQuality(String serializedName, int width, int height) {
      this.serializedName =serializedName;
      this.size = new Size(width, height);
    }

    protected static PreviewQuality getPreviewQualityForName(String serializedName) {
      for(PreviewQuality quality : values()) {
        if(quality.serializedName.equals(serializedName)) return quality;
      }

      return FALLBACK_VALUE;
    }

    public Size getSize() {
      return size;
    }
  }

  private Camera createCameraInstance(PreviewQuality previewQuality) throws CameraAccessException {
    String   cameraId    = null;
    String[] availableCameras = cameraManager.getCameraIdList();

    for (String camera : availableCameras) {
      CameraCharacteristics camCharacteristics = cameraManager.getCameraCharacteristics(camera);

      @SuppressWarnings("ConstantConditions")
      int lensDirection = camCharacteristics.get(CameraCharacteristics.LENS_FACING);

      if (lensDirection == CameraCharacteristics.LENS_FACING_BACK) {
        cameraId = camera;
        break;
      }
    }

    if(cameraId == null) {
      throw new CameraAccessException(CameraAccessException.CAMERA_ERROR, "Couldn't find any useable back-facing camera.");
    }
    // TODO - No camera?

    FlutterView.SurfaceTextureEntry surfaceTextureEntry = this.view.createSurfaceTexture();

    CameraCharacteristics cameraCharacteristics = cameraManager.getCameraCharacteristics(cameraId);

    StreamConfigurationMap streamConfigurationMap =
        cameraCharacteristics.get(CameraCharacteristics.SCALER_STREAM_CONFIGURATION_MAP);

    Size[] availableSizes = streamConfigurationMap.getOutputSizes(SurfaceTexture.class);

    Size previewSize = getOptimalPreviewSize(availableSizes, previewQuality);

    return new Camera(cameraId, surfaceTextureEntry, previewSize);
  }

  private Size getOptimalPreviewSize(Size[] availableSizes, PreviewQuality previewQuality) {
    Log.i("BCX", "Getting optimal size for preview quality: " + previewQuality);

    Size size = null;
    long sizeResolution = 0;

    long requestedSizeResolution = previewQuality.getSize().getWidth() * previewQuality.getSize().getHeight();

    for (Size s : availableSizes) {
      long resolution = s.getWidth() * (long) s.getHeight();

      if (
        (size == null) || //Save first size
        resolution > requestedSizeResolution && resolution < sizeResolution //Compare sizes
      ) {
        size = s; // Save if s first our needs better
        sizeResolution = resolution;
      }

    }

    return size;
  }

  private class Camera {
    private final FlutterView.SurfaceTextureEntry textureEntry;
    private final String cameraId;

    private CameraCaptureSession cameraCaptureSession;
    private CameraDevice cameraDevice;
    private Surface previewSurface;
    private Size previewSize;

    private Camera(String cameraId, FlutterView.SurfaceTextureEntry textureEntry, Size previewSize) {
      this.cameraId = cameraId;
      this.textureEntry = textureEntry;
      this.previewSize = previewSize;

      SurfaceTexture surfaceTexture = textureEntry.surfaceTexture();
      surfaceTexture.setDefaultBufferSize(previewSize.getWidth(), previewSize.getHeight()); //TODO);
      this.previewSurface = new Surface(surfaceTexture);
    }

    public long getTextureId() {
      return textureEntry.id();
    }

    public Size getPreviewResolution() {
      return previewSize;
    }

    @SuppressLint("MissingPermission") //Put camera permission to your apps android manifest file.
    private void start(final Result result) {
      try {
        cameraManager.openCamera(
          cameraId,
          new CameraDevice.StateCallback() {
            @Override
            public void onOpened(CameraDevice camera) {
              Camera.this.cameraDevice = camera;

              List<Surface> surfaceList = new ArrayList<>();
              surfaceList.add(previewSurface);
              try {
                cameraDevice.createCaptureSession(
                  surfaceList,
                  new CameraCaptureSession.StateCallback() {
                    @Override
                    public void onConfigured(CameraCaptureSession session) {
                      Camera.this.cameraCaptureSession = session;

                      try {
                        CaptureRequest.Builder previewRequestbuilder = cameraDevice.createCaptureRequest(CameraDevice.TEMPLATE_PREVIEW);
                        previewRequestbuilder.set(CaptureRequest.CONTROL_AF_MODE, CaptureRequest.CONTROL_AF_MODE_CONTINUOUS_PICTURE);
                        previewRequestbuilder.addTarget(previewSurface);
                        CaptureRequest previewRequest = previewRequestbuilder.build();
                        cameraCaptureSession.setRepeatingRequest(
                                previewRequest,
                                null,
                                null
                        );
                      } catch (CameraAccessException e) {
                        result.error("CameraAccessException", "Failed while building a preview request.", e);
                      }
                    }

                    @Override
                    public void onReady(CameraCaptureSession session) {
                      Map<String, Object> resultData = new HashMap<>();
                      resultData.put("textureId", textureEntry.id());
                      resultData.put("resWidth", previewSize.getWidth());
                      resultData.put("resHeight", previewSize.getHeight());
                      result.success(resultData);
                    }

                    @Override
                    public void onConfigureFailed(CameraCaptureSession session) {
                      CameraAccessException e = new CameraAccessException(
                        CameraAccessException.CAMERA_ERROR,
                        "Failed while configuring capture session."
                      );
                      result.error("CameraAccessExpcetion", "Failed while configuring capture session.", e);
                    }
                  },
                  null
                );
              } catch (CameraAccessException e) {
                result.error("CameraAccessException", "Failed while trying to open the camera.", e);
              }
            }

            @Override
            public void onDisconnected(CameraDevice camera) {
              CameraAccessException e = new CameraAccessException(
                CameraAccessException.CAMERA_DISCONNECTED,
                "Camera has been disconnected"
              );
              result.error("CameraAccessException", "Camera has been disconnected.", e);
            }

            @Override
            public void onError(CameraDevice camera, int error) {
              CameraAccessException e = new CameraAccessException(
                      CameraAccessException.CAMERA_ERROR,
                      "Opening camera has resulted with error: " + error
              );
              result.error("CameraAccessException", "Opening camera has resulted with error.", e);
            }
          },
          null
        );
      } catch (CameraAccessException e) {
        result.error("CameraAccessException", "Failed while trying to open the camera.", e);
      }
    }
  }

  private void onStartMethod(Result result) {
    camera.start(result);
  }
}
