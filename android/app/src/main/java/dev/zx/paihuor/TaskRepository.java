package dev.zx.paihuor;

import java.util.ArrayList;
import java.util.Comparator;
import java.util.List;

public final class TaskRepository {
    private TaskRepository() {}

    public static List<TaskItem> visible(List<TaskItem> all, String familyId,
                                         String userId, boolean archive) {
        List<TaskItem> result = new ArrayList<>();
        for (TaskItem item : all) {
            if (!item.deleted && item.belongsTo(familyId, userId) && item.archived == archive) {
                result.add(item);
            }
        }
        result.sort(Comparator.comparingLong((TaskItem item) -> item.createdAt).reversed());
        return result;
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
