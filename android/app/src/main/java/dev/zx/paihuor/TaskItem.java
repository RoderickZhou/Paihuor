package dev.zx.paihuor;

import java.util.ArrayList;
import java.util.List;

public final class TaskItem {
    public String objectId = "";
    public long createdAt;
    public long updatedAt;
    public String familyId = "";
    public String fromUserId = "";
    public String toUserId = "";
    public String rawText = "";
    public String title = "";
    public String detail = "";
    public long deadline;
    public String status = "pending";
    public boolean archived;
    public boolean deleted;
    public long receivedAt;
    public long recipientSyncedAt;
    public String clientRequestId = "";
    public boolean queued;
    HouseholdCard household;
    public String repeatKind = "";
    public int repeatDays;
    public boolean repeatPaused;
    public boolean repeatCurrent;
    public boolean repeatGenerated;
    public long skippedAt;
    public long doneAt;
    public final List<Negotiation> negotiation = new ArrayList<>();
    public final List<TaskImage> images = new ArrayList<>();

    public static TaskItem fixture(String id, String familyId, String from, String to,
                                   String status, boolean archived) {
        TaskItem item = new TaskItem();
        item.objectId = id;
        item.familyId = familyId;
        item.fromUserId = from;
        item.toUserId = to;
        item.status = status;
        item.archived = archived;
        return item;
    }

    public boolean belongsTo(String familyId, String userId) {
        return this.familyId.equals(familyId)
                && (fromUserId.equals(userId) || toUserId.equals(userId));
    }

    public static final class Negotiation {
        public String id = "";
        public String fromUserId = "";
        public String text = "";
        public long proposedDeadline;
        public long createdAt;
    }

    public static final class TaskImage {
        public String id = "";
        public String mime = "image/jpeg";
        public int width;
        public int height;
        public int size;
    }
}
