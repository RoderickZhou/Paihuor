package dev.zx.paihuor;

import java.util.ArrayList;
import java.util.Calendar;
import java.util.Comparator;
import java.util.List;

public final class TaskRepository {
    public enum Direction { ALL, INCOMING, OUTGOING }
    public enum Group {
        OVERDUE("已超时"), TODAY("今天到期"), WAITING("待我接下"), OTHER("其他任务");
        final String label;
        Group(String label) { this.label = label; }
    }
    private TaskRepository() {}

    public static List<TaskItem> visible(List<TaskItem> all, String familyId,
                                         String userId, boolean archive) {
        return visible(all, familyId, userId, archive, Direction.ALL);
    }

    public static List<TaskItem> visible(List<TaskItem> all, String familyId,
                                         String userId, boolean archive, Direction direction) {
        long now = System.currentTimeMillis();
        return visible(all, familyId, userId, archive, direction, now, tomorrow(now));
    }

    static long tomorrow(long now) {
        Calendar date = Calendar.getInstance();
        date.setTimeInMillis(now);
        date.set(Calendar.HOUR_OF_DAY, 0);
        date.set(Calendar.MINUTE, 0);
        date.set(Calendar.SECOND, 0);
        date.set(Calendar.MILLISECOND, 0);
        date.add(Calendar.DAY_OF_MONTH, 1);
        return date.getTimeInMillis();
    }

    static List<TaskItem> visible(List<TaskItem> all, String familyId, String userId,
                                  boolean archive, Direction direction, long now, long tomorrow) {
        List<TaskItem> result = new ArrayList<>();
        for (TaskItem item : all) {
            if (!item.deleted && item.belongsTo(familyId, userId) && item.archived == archive
                    && (direction != Direction.INCOMING || item.toUserId.equals(userId))
                    && (direction != Direction.OUTGOING || (item.household == null && item.fromUserId.equals(userId)))) {
                result.add(item);
            }
        }
        Comparator<TaskItem> newestFirst = Comparator.comparingLong((TaskItem item) -> item.createdAt).reversed();
        if (archive) result.sort(newestFirst);
        else result.sort(Comparator.comparing((TaskItem item) -> group(item, userId, now, tomorrow))
                .thenComparingLong(item -> isDueGroup(group(item, userId, now, tomorrow)) ? item.deadline : 0)
                .thenComparing(newestFirst));
        return result;
    }

    private static boolean isDueGroup(Group group) { return group == Group.OVERDUE || group == Group.TODAY; }

    static Group group(TaskItem item, String userId, long now, long tomorrow) {
        if (item.archived || item.deleted || "done".equals(item.status)) return Group.OTHER;
        if (item.deadline > 0 && item.deadline <= now) return Group.OVERDUE;
        if (item.deadline > 0 && item.deadline < tomorrow) return Group.TODAY;
        if (item.toUserId.equals(userId) && "pending".equals(item.status)) return Group.WAITING;
        return Group.OTHER;
    }

    public static String receipt(TaskItem item) {
        if (item.queued) return "待发送";
        if (item.receivedAt > 0 || "received".equals(item.status)) return "对方已接下";
        return item.recipientSyncedAt > 0 ? "对方已同步" : "已发出";
    }

    public static String repeatLabel(String kind, int days) {
        switch (kind) {
            case "weekly": return "每周";
            case "monthly": return "每月";
            case "afterDone": return "完成后隔 " + days + " 天";
            default: return "不重复";
        }
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
