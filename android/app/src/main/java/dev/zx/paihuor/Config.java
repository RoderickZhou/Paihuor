package dev.zx.paihuor;

import android.content.Context;
import java.io.ByteArrayOutputStream;
import java.io.InputStream;
import java.nio.charset.StandardCharsets;
import org.json.JSONObject;

public final class Config {
    public final String relayBaseUrl;
    public final String relayLanUrl;
    public final String paihuorKey;
    public final String minimaxKey;
    public final String minimaxModel;
    public final int pollIntervalSec;

    private Config(JSONObject value) {
        relayBaseUrl = value.optString("relayBaseUrl");
        relayLanUrl = value.optString("relayLanUrl");
        paihuorKey = value.optString("paihuorKey");
        minimaxKey = value.optString("minimaxKey");
        minimaxModel = value.optString("minimaxModel", "MiniMax-M3");
        pollIntervalSec = Math.max(5, value.optInt("pollIntervalSec", 8));
    }

    public boolean usable() {
        return !paihuorKey.isEmpty() && (!relayBaseUrl.isEmpty() || !relayLanUrl.isEmpty());
    }

    public static Config load(Context context) {
        try (InputStream input = context.getAssets().open("paihuor_config.json");
             ByteArrayOutputStream output = new ByteArrayOutputStream()) {
            byte[] buffer = new byte[4096];
            int count;
            while ((count = input.read(buffer)) >= 0) output.write(buffer, 0, count);
            return new Config(new JSONObject(output.toString(StandardCharsets.UTF_8.name())));
        } catch (Exception error) {
            return new Config(new JSONObject());
        }
    }
}
