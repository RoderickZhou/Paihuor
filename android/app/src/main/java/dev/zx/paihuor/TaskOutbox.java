package dev.zx.paihuor;

import android.content.Context;
import java.io.File;
import java.io.IOException;
import java.nio.file.Files;

final class TaskOutbox {
    static File attachment(Context context, TaskItem task, int index) {
        return new File(context.getFilesDir(), "outbox-" + task.clientRequestId + "-" + index + ".jpg");
    }

    static TaskItem send(Context context, RelayClient relay, TaskItem queued) throws Exception {
        TaskItem payload = TaskJson.decode(TaskJson.encode(queued));
        payload.queued = false;
        for (int i = 0; i < queued.images.size(); i++) {
            TaskItem.TaskImage image = queued.images.get(i);
            if (image.id.startsWith("local-")) {
                File file = attachment(context, queued, i);
                if (!file.isFile()) throw new IOException("Draft attachment missing");
                TaskItem.TaskImage uploaded = relay.upload(Files.readAllBytes(file.toPath()), queued.familyId, image.width, image.height);
                queued.images.set(i, uploaded);
                TaskCache.upsert(context, queued);
            }
            payload.images.set(i, queued.images.get(i));
        }
        return relay.create(payload);
    }

    static void cleanup(Context context, TaskItem queued) {
        for (int i = 0; i < queued.images.size(); i++) attachment(context, queued, i).delete();
    }
}
