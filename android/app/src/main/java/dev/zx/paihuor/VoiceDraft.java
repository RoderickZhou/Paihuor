package dev.zx.paihuor;

import java.time.OffsetDateTime;
import java.time.format.DateTimeParseException;
import org.json.JSONException;
import org.json.JSONObject;

final class VoiceDraft {
    final String title;
    final String detail;
    final long deadline;

    private VoiceDraft(String title, String detail, long deadline) {
        this.title = title;
        this.detail = detail;
        this.deadline = deadline;
    }

    static VoiceDraft parse(String content, String transcript) throws JSONException {
        String text = content.replaceAll("(?s)<think>.*?</think>", "");
        int start = text.indexOf('{');
        int end = text.lastIndexOf('}');
        if (start < 0 || end < start) throw new JSONException("No draft object");
        JSONObject json = new JSONObject(text.substring(start, end + 1));
        String title = json.optString("title").trim();
        long deadline = 0;
        if (json.optBoolean("hasDeadline")) {
            try {
                deadline = OffsetDateTime.parse(json.optString("deadlineISO")).toInstant().toEpochMilli();
            } catch (DateTimeParseException ignored) { }
        }
        return new VoiceDraft(title.isEmpty() ? transcript : title, json.optString("detail"), deadline);
    }
}
