package dev.zx.paihuor;

import java.util.ArrayList;
import java.util.Comparator;
import java.util.List;

public final class TaskRepository {
    public enum Direction { ALL, INCOMING, OUTGOING }
    private TaskRepository() {}

    public static List<TaskItem> visible(List<TaskItem> all, String familyId,
                                         String userId, boolean archive) {
        return visible(all, familyId, userId, archive, Direction.ALL);
    }

    public static List<TaskItem> visible(List<TaskItem> all, String familyId,
                                         String userId, boolean archive, Direction direction) {
        List<TaskItem> result = new ArrayList<>();
        for (TaskItem item : all) {
            if (!item.deleted && item.belongsTo(familyId, userId) && item.archived == archive
                    && (direction != Direction.INCOMING || item.toUserId.equals(userId))
                    && (direction != Direction.OUTGOING || item.fromUserId.equals(userId))) {
                result.add(item);
            }
        }
        result.sort(Comparator.comparingLong((TaskItem item) -> item.createdAt).reversed());
        return result;
    }

    public static String receipt(TaskItem item) {
        if (item.queued) return "待发送";
        if (item.receivedAt > 0 || "received".equals(item.status)) return "对方已接下";
        return item.recipientSyncedAt > 0 ? "对方已同步" : "已发出";
    }

    public static void advance(TaskItem item, long now) {
        if ("received".equals(item.status)) {
            item.status = "done";
            item.doneAt = now;
            item.archived = true;
        } else {
            item.status = "received";
            item.receivedAt = now;
        }
    }
}
