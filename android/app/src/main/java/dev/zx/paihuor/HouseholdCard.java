package dev.zx.paihuor;

import org.json.JSONObject;

final class HouseholdCard {
    final TaskItem task;
    final String list;
    final String state;
    final String assignee;
    final int revision;

    HouseholdCard(JSONObject json) {
        task = TaskJson.decode(json);
        task.objectId = json.optString("id");
        task.fromUserId = json.optString("creator");
        list = json.optString("list", "日常");
        state = json.optString("status");
        assignee = json.optString("assignee");
        revision = json.optInt("revision");
        task.household = this;
        task.toUserId = assignee;
        task.status = "done".equals(state) ? "done" : "received";
    }
}
