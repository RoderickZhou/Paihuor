package dev.zx.paihuor;

import android.content.Context;
import java.io.ByteArrayOutputStream;
import java.io.IOException;
import java.io.InputStream;
import java.io.OutputStream;
import java.net.HttpURLConnection;
import java.net.URLEncoder;
import java.net.URL;
import java.nio.charset.StandardCharsets;
import org.json.JSONArray;
import org.json.JSONObject;

public final class RelayClient {
    private final Config config;
    private String resolvedBase = "";
    private long resolvedAt;

    public RelayClient(Context context) {
        config = Config.load(context);
    }

    public boolean usable() {
        return config.usable();
    }

    public JSONArray fetch(String familyId, long since) throws Exception {
        String query = "/tasks?familyId=" + encode(familyId) + "&since=" + since + "&caps=v2";
        return new JSONArray(request("GET", query, null, null));
    }

    public TaskItem create(TaskItem item) throws Exception {
        return TaskJson.decode(new JSONObject(request("POST", "/tasks", TaskJson.encode(item), null)));
    }

    public void acknowledge(String family, String role, String device, JSONArray ids) throws Exception {
        JSONObject body = new JSONObject().put("familyId", family).put("userId", role)
                .put("deviceId", device).put("platform", "android").put("objectIds", ids);
        request("POST", "/sync/ack", body, null);
    }

    public JSONObject syncStatus(String family, String role) throws Exception {
        return new JSONObject(request("GET", "/sync/status?familyId=" + encode(family) + "&userId=" + encode(role), null, null));
    }

    public TaskItem patch(TaskItem item, JSONObject fields) throws Exception {
        String path = "/tasks/" + encode(item.objectId);
        return TaskJson.decode(new JSONObject(request("POST", path, fields, null)));
    }

    public void delete(TaskItem item, String userId) throws Exception {
        request("DELETE", "/tasks/" + encode(item.objectId) + "?by=" + encode(userId), null, null);
    }

    public TaskItem.TaskImage upload(byte[] bytes, String familyId, int width, int height) throws Exception {
        String path = "/uploads?familyId=" + encode(familyId) + "&w=" + width + "&h=" + height;
        JSONObject value = new JSONObject(request("POST", path, null, bytes));
        TaskItem.TaskImage image = new TaskItem.TaskImage();
        image.id = value.optString("id");
        image.mime = value.optString("mime", "image/jpeg");
        image.width = value.optInt("w", width);
        image.height = value.optInt("h", height);
        image.size = value.optInt("size", bytes.length);
        return image;
    }

    public byte[] download(String imageId) throws Exception {
        return requestBytes("GET", "/uploads/" + encode(imageId), null, null, "application/json");
    }

    private String request(String method, String path, JSONObject json, byte[] raw) throws Exception {
        byte[] response = requestBytes(method, path, json, raw,
                raw == null ? "application/json" : "image/jpeg");
        return new String(response, StandardCharsets.UTF_8);
    }

    private byte[] requestBytes(String method, String path, JSONObject json, byte[] raw,
                                String contentType) throws Exception {
        byte[] body = raw != null ? raw : json == null ? null
                : json.toString().getBytes(StandardCharsets.UTF_8);
        IOException first = null;
        for (String base : candidates()) {
            if (base.isEmpty()) continue;
            try {
                HttpURLConnection connection = (HttpURLConnection) new URL(trim(base) + path).openConnection();
                connection.setConnectTimeout(6000);
                connection.setReadTimeout(15000);
                connection.setRequestMethod(method);
                connection.setRequestProperty("x-paihuor-key", config.paihuorKey);
                if (body != null) {
                    connection.setDoOutput(true);
                    connection.setRequestProperty("Content-Type", contentType);
                    try (OutputStream output = connection.getOutputStream()) {
                        output.write(body);
                    }
                }
                int code = connection.getResponseCode();
                InputStream input = code >= 200 && code < 300
                        ? connection.getInputStream() : connection.getErrorStream();
                byte[] bytes = readAll(input);
                connection.disconnect();
                if (code < 200 || code >= 300) {
                    throw new IOException("中继返回 " + code + ": " + new String(bytes, StandardCharsets.UTF_8));
                }
                resolvedBase = base;
                resolvedAt = System.currentTimeMillis();
                return bytes;
            } catch (IOException error) {
                first = error;
            }
        }
        throw first == null ? new IOException("未配置中继地址") : first;
    }

    private String[] candidates() {
        if (!resolvedBase.isEmpty() && System.currentTimeMillis() - resolvedAt < 60_000) {
            return new String[]{resolvedBase, config.relayLanUrl, config.relayBaseUrl};
        }
        return new String[]{config.relayLanUrl, config.relayBaseUrl};
    }

    private static byte[] readAll(InputStream input) throws IOException {
        if (input == null) return new byte[0];
        try (InputStream source = input; ByteArrayOutputStream output = new ByteArrayOutputStream()) {
            byte[] buffer = new byte[8192];
            int count;
            while ((count = source.read(buffer)) >= 0) output.write(buffer, 0, count);
            return output.toByteArray();
        }
    }

    private static String trim(String value) {
        return value.endsWith("/") ? value.substring(0, value.length() - 1) : value;
    }

    private static String encode(String value) {
        try {
            return URLEncoder.encode(value, "UTF-8");
        } catch (Exception ignored) {
            return value;
        }
    }
}
