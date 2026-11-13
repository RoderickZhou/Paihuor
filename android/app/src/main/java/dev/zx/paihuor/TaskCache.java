package dev.zx.paihuor;

import android.content.Context;
import android.util.AtomicFile;
import java.io.ByteArrayOutputStream;
import java.io.File;
import java.io.FileInputStream;
import java.io.FileOutputStream;
import java.nio.charset.StandardCharsets;
import java.util.ArrayList;
import java.util.LinkedHashMap;
import java.util.List;
import java.util.Map;
import org.json.JSONArray;
import org.json.JSONObject;

public final class TaskCache {
    private static final String FILE_NAME = "tasks_cache.json";

    private TaskCache() {}

    public static synchronized List<TaskItem> load(Context context) {
        List<TaskItem> result = new ArrayList<>();
        File file = new File(context.getFilesDir(), FILE_NAME);
        if (!file.exists() && !new File(file.getPath() + ".bak").exists()) return result;
        try (FileInputStream input = new AtomicFile(file).openRead();
             ByteArrayOutputStream output = new ByteArrayOutputStream()) {
            byte[] buffer = new byte[4096];
            int count;
            while ((count = input.read(buffer)) >= 0) output.write(buffer, 0, count);
            JSONObject root = new JSONObject(output.toString(StandardCharsets.UTF_8.name()));
            JSONArray tasks = root.optJSONArray("tasks");
            if (tasks == null) tasks = new JSONArray();
            for (int index = 0; index < tasks.length(); index++) {
                JSONObject value = tasks.optJSONObject(index);
                if (value != null) result.add(TaskJson.decode(value));
            }
        } catch (Exception ignored) {
            // A damaged cache is replaceable from the relay on the next sync.
        }
        return result;
    }

    public static synchronized void merge(Context context, JSONArray remote) {
        Map<String, TaskItem> tasks = new LinkedHashMap<>();
        for (TaskItem item : load(context)) tasks.put(item.objectId, item);
        for (int index = 0; index < remote.length(); index++) {
            JSONObject value = remote.optJSONObject(index);
            if (value == null) continue;
            TaskItem item = TaskJson.decode(value);
            TaskItem existing = tasks.get(item.objectId);
            if (!item.objectId.isEmpty() && (existing == null || existing.updatedAt <= item.updatedAt)) tasks.put(item.objectId, item);
        }
        save(context, new ArrayList<>(tasks.values()));
    }

    public static synchronized void upsert(Context context, TaskItem item) {
        Map<String, TaskItem> tasks = new LinkedHashMap<>();
        for (TaskItem current : load(context)) tasks.put(current.objectId, current);
        tasks.put(item.objectId, item);
        save(context, new ArrayList<>(tasks.values()));
    }

    public static synchronized void finishSending(Context context, String pendingId, TaskItem sent) {
        List<TaskItem> tasks = load(context);
        TaskItem latest = sent;
        for (TaskItem item : tasks) {
            if (item.objectId.equals(sent.objectId) && item.updatedAt > latest.updatedAt) latest = item;
        }
        tasks.removeIf(item -> item.objectId.equals(pendingId) || item.objectId.equals(sent.objectId));
        tasks.add(latest);
        save(context, tasks);
    }

    public static long lastSync(Context context, String family) {
        long latest = 0;
        for (TaskItem item : load(context)) {
            if (!item.queued && item.familyId.equals(family)) latest = Math.max(latest, item.updatedAt);
        }
        return latest;
    }

    private static void save(Context context, List<TaskItem> items) {
        JSONArray tasks = new JSONArray();
        for (TaskItem item : items) tasks.put(TaskJson.encode(item));
        JSONObject root = new JSONObject();
        try {
            root.put("tasks", tasks);
        } catch (Exception ignored) {
            return;
        }
        AtomicFile file = new AtomicFile(new File(context.getFilesDir(), FILE_NAME));
        FileOutputStream output = null;
        try {
            output = file.startWrite();
            output.write(root.toString().getBytes(StandardCharsets.UTF_8));
            file.finishWrite(output);
        } catch (Exception error) {
            file.failWrite(output);
            throw new IllegalStateException("Cannot save task cache", error);
        }
    }
}
