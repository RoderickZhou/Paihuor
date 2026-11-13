package dev.zx.paihuor;

import org.json.JSONArray;
import org.json.JSONObject;

public final class TaskJson {
    private TaskJson() {}

    public static TaskItem decode(JSONObject value) {
        TaskItem item = new TaskItem();
        item.objectId = value.optString("objectId");
        item.createdAt = value.optLong("createdAt");
        item.updatedAt = value.optLong("updatedAt");
        item.familyId = value.optString("familyId");
        item.fromUserId = value.optString("fromUserId");
        item.toUserId = value.optString("toUserId");
        item.rawText = value.optString("rawText");
        item.title = value.optString("title", item.rawText);
        item.detail = value.optString("detail");
        item.deadline = value.optLong("deadline");
        item.status = value.optString("status", "pending");
        item.archived = value.optBoolean("archived");
        item.deleted = value.optBoolean("deleted");
        item.receivedAt = value.optLong("receivedAt");
        item.recipientSyncedAt = value.optLong("recipientSyncedAt");
        item.clientRequestId = value.optString("clientRequestId");
        item.queued = value.optBoolean("queued");
        JSONObject repeat = value.optJSONObject("repeat");
        if (repeat != null) {
            item.repeatKind = repeat.optString("kind");
            item.repeatDays = repeat.optInt("days");
            item.repeatPaused = repeat.optBoolean("paused");
            item.repeatCurrent = repeat.optBoolean("current");
            item.repeatGenerated = repeat.optBoolean("generated");
            item.skippedAt = repeat.optLong("skippedAt");
        }
        item.doneAt = value.optLong("doneAt");

        JSONArray messages = value.optJSONArray("negotiation");
        if (messages != null) {
            for (int index = 0; index < messages.length(); index++) {
                JSONObject source = messages.optJSONObject(index);
                if (source == null) continue;
                TaskItem.Negotiation message = new TaskItem.Negotiation();
                message.id = source.optString("id");
                message.fromUserId = source.optString("fromUserId");
                message.text = source.optString("text");
                message.proposedDeadline = source.optLong("proposedDeadline");
                message.createdAt = source.optLong("at", source.optLong("createdAt"));
                item.negotiation.add(message);
            }
        }

        JSONArray images = value.optJSONArray("images");
        if (images != null) {
            for (int index = 0; index < images.length(); index++) {
                JSONObject source = images.optJSONObject(index);
                if (source == null || source.optString("id").isEmpty()) continue;
                TaskItem.TaskImage image = new TaskItem.TaskImage();
                image.id = source.optString("id");
                image.mime = source.optString("mime", "image/jpeg");
                image.width = source.optInt("w");
                image.height = source.optInt("h");
                image.size = source.optInt("size");
                item.images.add(image);
            }
        }
        return item;
    }

    public static JSONObject encode(TaskItem item) {
        JSONObject value = new JSONObject();
        try {
        value.put("objectId", item.objectId);
        value.put("createdAt", item.createdAt);
        value.put("updatedAt", item.updatedAt);
        value.put("familyId", item.familyId);
        value.put("fromUserId", item.fromUserId);
        value.put("toUserId", item.toUserId);
        value.put("rawText", item.rawText);
        value.put("title", item.title);
        value.put("detail", item.detail);
        value.put("deadline", item.deadline);
        value.put("status", item.status);
        value.put("archived", item.archived);
        value.put("deleted", item.deleted);
        value.put("receivedAt", item.receivedAt);
        value.put("recipientSyncedAt", item.recipientSyncedAt);
        if (!item.clientRequestId.isEmpty()) value.put("clientRequestId", item.clientRequestId);
        if (item.queued) value.put("queued", true);
        if (!item.repeatKind.isEmpty()) value.put("repeat", new JSONObject().put("kind", item.repeatKind)
                .put("days", item.repeatDays).put("paused", item.repeatPaused).put("current", item.repeatCurrent)
                .put("generated", item.repeatGenerated).put("skippedAt", item.skippedAt));
        value.put("doneAt", item.doneAt);

        JSONArray messages = new JSONArray();
        for (TaskItem.Negotiation message : item.negotiation) {
            messages.put(new JSONObject()
                    .put("fromUserId", message.fromUserId)
                    .put("text", message.text)
                    .put("proposedDeadline", message.proposedDeadline)
                    .put("at", message.createdAt));
        }
        value.put("negotiation", messages);

        JSONArray images = new JSONArray();
        for (TaskItem.TaskImage image : item.images) {
            images.put(new JSONObject()
                    .put("id", image.id)
                    .put("mime", image.mime)
                    .put("w", image.width)
                    .put("h", image.height)
                    .put("size", image.size));
        }
        value.put("images", images);
        } catch (Exception ignored) {
            // All values written here are JSON-compatible primitives or arrays.
        }
        return value;
    }
}
