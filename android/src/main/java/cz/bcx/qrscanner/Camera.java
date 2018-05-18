package cz.bcx.qrscanner;

import android.annotation.SuppressLint;
import android.annotation.TargetApi;
import android.graphics.ImageFormat;
import android.graphics.SurfaceTexture;
import android.hardware.camera2.CameraAccessException;
import android.hardware.camera2.CameraCaptureSession;
import android.hardware.camera2.CameraCharacteristics;
import android.hardware.camera2.CameraDevice;
import android.hardware.camera2.CameraManager;
import android.hardware.camera2.CaptureRequest;
import android.hardware.camera2.params.StreamConfigurationMap;
import android.media.Image;
import android.media.ImageReader;
import android.os.Build;
import android.os.Handler;
import android.os.HandlerThread;
import android.util.Log;
import android.util.Size;
import android.view.Surface;

import java.nio.ByteBuffer;
import java.util.ArrayList;
import java.util.Arrays;
import java.util.Map;
import java.util.HashMap;
import java.util.List;
import io.flutter.plugin.common.MethodChannel;
import io.flutter.view.FlutterView;

import com.google.zxing.BarcodeFormat;
import com.google.zxing.BinaryBitmap;
import com.google.zxing.DecodeHintType;
import com.google.zxing.LuminanceSource;
import com.google.zxing.MultiFormatReader;
import com.google.zxing.PlanarYUVLuminanceSource;
import com.google.zxing.ReaderException;
import com.google.zxing.Result;
import com.google.zxing.common.HybridBinarizer;


@TargetApi(Build.VERSION_CODES.LOLLIPOP)
public class Camera {
    public enum CameraStateError {
        CAMERA_UNKNOWN_ERROR(
            -1,
            "The camera has encountered an unknown error."
        ),
        CAMERA_IN_USE(
            CameraDevice.StateCallback.ERROR_CAMERA_IN_USE,
            "The camera device is already in use."
        ),
        CAMERA_MAX_IN_USE(
            CameraDevice.StateCallback.ERROR_MAX_CAMERAS_IN_USE,
            "Maximum number of cameras is in use."
        ),
        CAMERA_DISABLED(
            CameraDevice.StateCallback.ERROR_CAMERA_DISABLED,
            "The camera device couldn't be opened due to a device policy."
        ),
        CAMERA_DEVICE(
            CameraDevice.StateCallback.ERROR_CAMERA_DEVICE,
            "The camera device has encountered a fatal error."
        ),
        CAMERA_SERVICE(
            CameraDevice.StateCallback.ERROR_CAMERA_SERVICE,
            "The camera service has encountered a fatal error."
        );

        private int errorCode;
        private String message;

        CameraStateError(int errorCode, String message) {
            this.errorCode = errorCode;
            this.message = message;
        }

        public int getErrorCode() {
            return errorCode;
        }

        public String getMessage() {
            return message;
        }

        public static CameraStateError getByErrorCode(int error) {
            for(CameraStateError stateError : values()) {
                if(stateError.errorCode == error) return stateError;
            }

            return CAMERA_UNKNOWN_ERROR;
        }
    }

    public interface CameraStateListener {
        void onCameraDisconnected();
        void onCameraError(CameraStateError cameraStateError);
        void onCodeScanned(String code);
    }

    public interface ScannerCallback {
        void onCodeScanned(String data);
    }

    private static final int BETWEEN_SCANS_DELAY = 333; //ms

    private HandlerThread backgroundThread;
    private Handler backgroundHandler;

    private CameraStateListener stateListener;

    private final String cameraId;
    private final ImageReader imageReader;
    private final FlutterView.SurfaceTextureEntry textureEntry;

    private CameraDevice cameraDevice;
    private CameraCaptureSession cameraCaptureSession;

    private CaptureRequest captureRequest;

    private Surface previewSurface;
    private Size previewSize;

    private MultiFormatReader qrReader;

    private boolean scanningEnabled = false;
    private long lastTimeScanned = 0;

    protected Camera(String cameraId, FlutterView.SurfaceTextureEntry textureEntry, Size previewSize, Size captureSize) {
        this.cameraId = cameraId;
        this.textureEntry = textureEntry;
        this.previewSize = previewSize;

        this.imageReader = ImageReader.newInstance(
                captureSize.getWidth(),
                captureSize.getHeight(),
                ImageFormat.YUV_420_888,
                4
        );

        SurfaceTexture surfaceTexture = textureEntry.surfaceTexture();
        surfaceTexture.setDefaultBufferSize(previewSize.getWidth(), previewSize.getHeight()); //TODO);
        this.previewSurface = new Surface(surfaceTexture);

        this.qrReader = new MultiFormatReader();

        // Scan QR Codes only
        // Makes scanning much faster
        Map<DecodeHintType, Object> hints = new HashMap<>();
        hints.put(DecodeHintType.POSSIBLE_FORMATS, Arrays.asList(BarcodeFormat.QR_CODE));
        this.qrReader.setHints(hints);
    }

    public static Camera createCameraInstance(CameraManager cameraManager, FlutterView flutterView, PreviewQuality previewQuality) throws CameraAccessException {
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

        FlutterView.SurfaceTextureEntry surfaceTextureEntry = flutterView.createSurfaceTexture();

        CameraCharacteristics cameraCharacteristics = cameraManager.getCameraCharacteristics(cameraId);

        StreamConfigurationMap streamConfigurationMap =
                cameraCharacteristics.get(CameraCharacteristics.SCALER_STREAM_CONFIGURATION_MAP);

        Size[] availableTextureSizes = streamConfigurationMap.getOutputSizes(SurfaceTexture.class);
        Size previewSize = ScannerUtils.getOptimalSize(previewQuality.getSize(), availableTextureSizes);

        Size[] availableCaptureSizes = streamConfigurationMap.getOutputSizes(ImageFormat.YUV_420_888);
        Size captureSize = ScannerUtils.getOptimalSize(new Size(800, 600), availableCaptureSizes);

        return new Camera(cameraId, surfaceTextureEntry, previewSize, captureSize);
    }

    public long getTextureId() {
        return textureEntry.id();
    }

    public Size getPreviewResolution() {
        return previewSize;
    }

    private void startBackgroundThread() {
        if(backgroundThread != null) return;

        backgroundThread = new HandlerThread("cz.bcx.qr_scanner.background_thread");
        backgroundThread.start();
        backgroundHandler = new Handler(backgroundThread.getLooper());
    }

    private void stopBackgroundThread() {
        if(backgroundThread == null) return;

        backgroundThread.quitSafely();
        try {
            backgroundThread.join();
            backgroundThread = null;
            backgroundHandler = null;
        } catch (InterruptedException e) {
            e.printStackTrace();
        }
    }

    @SuppressLint("MissingPermission") //Put camera permission to your apps android manifest file.
    protected void openCamera(CameraManager cameraManager, final MethodChannel.Result result, final CameraStateListener cameraStateListener) throws CameraAccessException {
        this.stateListener = cameraStateListener;

        CameraDevice.StateCallback cameraDeviceStateCallback = new CameraDevice.StateCallback() {
            @Override
            public void onOpened(final CameraDevice cameraDevice) {
                Camera.this.cameraDevice = cameraDevice;

                List<Surface> surfaceList = new ArrayList<>();
                surfaceList.add(previewSurface);
                surfaceList.add(imageReader.getSurface());

                try {
                    cameraDevice.createCaptureSession(
                        surfaceList,
                        new CameraCaptureSession.StateCallback() {
                            @Override
                            public void onConfigured(CameraCaptureSession session) {
                                Camera.this.cameraCaptureSession = session;

                                HashMap<String, Object> response = new HashMap<>();
                                response.put("textureId", Camera.this.getTextureId());

                                Size res = Camera.this.getPreviewResolution();
                                response.put("previewWidth", res.getWidth());
                                response.put("previewHeight", res.getHeight());
                                result.success(response);
                            }

                            @Override
                            public void onConfigureFailed(CameraCaptureSession session) {
                                result.error("configureFailed", "Failed to configure camera session.", null);
                            }
                        },
                        null
                    );
                } catch (CameraAccessException e) {
                    result.error("CameraAccessException", "Failed to create capture session.", e);
                }
            }

            @Override
            public void onDisconnected(CameraDevice camera) {
                if(Camera.this.stateListener != null) {
                    Camera.this.stateListener.onCameraDisconnected();
                }
            }

            @Override
            public void onError(CameraDevice camera, int error) {
                if(Camera.this.stateListener != null) {
                    Camera.this.stateListener.onCameraError(CameraStateError.getByErrorCode(error));
                }
            }
        };

        cameraManager.openCamera(
            cameraId,
            cameraDeviceStateCallback,
            null
        );
    }

    protected void stopPreview() throws CameraAccessException {
        cameraCaptureSession.stopRepeating();
        captureRequest = null;

        stopBackgroundThread();
    }

    protected void startPreview() throws CameraAccessException {
        if(captureRequest == null) {
            startBackgroundThread();

            CaptureRequest.Builder captureRequestBuilder = cameraDevice.createCaptureRequest(CameraDevice.TEMPLATE_PREVIEW);

            captureRequestBuilder.set(CaptureRequest.CONTROL_AF_MODE, CaptureRequest.CONTROL_AF_MODE_CONTINUOUS_PICTURE);

            captureRequestBuilder.addTarget(previewSurface);
            captureRequestBuilder.addTarget(imageReader.getSurface());

            imageReader.setOnImageAvailableListener(new ImageReader.OnImageAvailableListener() {
                byte[] planeBufferArray;

                @Override
                public void onImageAvailable(ImageReader reader) {
                    Image image = reader.acquireLatestImage();

                    if (image == null) return;

                    if (!scanningEnabled || System.currentTimeMillis() - lastTimeScanned < BETWEEN_SCANS_DELAY) {
                        image.close();
                        return;
                    }

                    try {
                        ByteBuffer firstPlaneBuffer = image.getPlanes()[0].getBuffer();
                        if (planeBufferArray == null || planeBufferArray.length != firstPlaneBuffer.capacity()) {
                            planeBufferArray = new byte[firstPlaneBuffer.capacity()];
                        }

                        firstPlaneBuffer.get(planeBufferArray);

                        LuminanceSource source = new PlanarYUVLuminanceSource(
                                planeBufferArray,
                                image.getWidth(),
                                image.getHeight(),
                                0,
                                0,
                                image.getWidth(),
                                image.getHeight(),
                                false
                        );

                        BinaryBitmap bitmap = new BinaryBitmap(new HybridBinarizer(source));
                        Result rawResult = qrReader.decodeWithState(bitmap);

                        if(Camera.this.stateListener != null) {
                            Camera.this.stateListener.onCodeScanned(rawResult.toString());
                        }

                        lastTimeScanned = System.currentTimeMillis();
                    } catch (ReaderException e) {
                        e.printStackTrace();
                    } catch (NullPointerException e) {
                        e.printStackTrace();
                    } finally {
                        qrReader.reset();
                        image.close();
                    }
                }
            },
            backgroundHandler);

            captureRequest = captureRequestBuilder.build();
        }

        cameraCaptureSession.setRepeatingRequest(
            captureRequest,
            null,
            backgroundHandler
        );
    }

    protected void enableScanning() {
        scanningEnabled = true;
    }

    protected void disableScanning() {
        scanningEnabled = false;
    }

    protected void dispose() {
        if (cameraCaptureSession != null) {
            cameraCaptureSession.close();
            cameraCaptureSession = null;
        }

        if (this.cameraDevice != null) {
            cameraDevice.close();
            cameraDevice = null;
        }
    }
}