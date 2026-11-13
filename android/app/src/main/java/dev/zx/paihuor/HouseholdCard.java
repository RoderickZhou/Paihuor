package dev.zx.paihuor;

import org.json.JSONObject;
import org.json.JSONArray;
import java.util.ArrayList;
import java.util.List;

final class HouseholdCard {
    final TaskItem task;
    final String list;
    final String state;
    final String assignee;
    final int revision;
    final List<Step> checklist = new ArrayList<>();

    static final class Step {
        final String id, title;
        final boolean checked;
        Step(JSONObject json) { id = json.optString("id"); title = json.optString("title"); checked = json.optBoolean("checked"); }
    }

    HouseholdCard(JSONObject json) {
        task = TaskJson.decode(json);
        task.objectId = json.optString("id");
        task.fromUserId = json.optString("creator");
        list = json.optString("list", "日常");
        state = json.optString("status");
        assignee = json.optString("assignee");
        revision = json.optInt("revision");
        JSONArray steps = json.optJSONArray("checklist");
        if (steps != null) for (int i = 0; i < steps.length(); i++) {
            JSONObject step = steps.optJSONObject(i);
            if (step != null) checklist.add(new Step(step));
        }
        task.household = this;
        task.toUserId = assignee;
        task.status = "done".equals(state) ? "done" : "received";
    }

    String progress() {
        if (checklist.isEmpty()) return "";
        int checked = 0;
        for (Step step : checklist) if (step.checked) checked++;
        return "子清单 " + checked + "/" + checklist.size();
    }
}
