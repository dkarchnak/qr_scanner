package cz.bcx.qrscanner;

import android.annotation.TargetApi;
import android.os.Build;
import android.util.Size;

@TargetApi(Build.VERSION_CODES.LOLLIPOP)
public enum PreviewQuality {
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