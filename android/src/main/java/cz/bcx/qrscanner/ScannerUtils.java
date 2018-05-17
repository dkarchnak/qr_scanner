package cz.bcx.qrscanner;

import android.annotation.TargetApi;
import android.os.Build;
import android.util.Size;

@TargetApi(Build.VERSION_CODES.LOLLIPOP)
public class ScannerUtils {
    public static Size getOptimalSize(Size requestedSize, Size[] availableSizes) {
        Size size = null;
        long sizeResolution = 0;

        long requestedSizeResolution = requestedSize.getWidth() * requestedSize.getHeight();

        for (Size s : availableSizes) {
            long resolution = s.getWidth() * (long) s.getHeight();

            if ((size == null) || //Save first size
                resolution >= requestedSizeResolution && resolution < sizeResolution
            ) {
                size = s; // Save if s fits our needs better
                sizeResolution = resolution;
            }
        }

        return size;
    }
}
