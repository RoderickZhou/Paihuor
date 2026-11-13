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
        return parse(content, transcript, System.currentTimeMillis());
    }

    static VoiceDraft parse(String content, String transcript, long now) throws JSONException {
        String text = content.replaceAll("(?s)<think>.*?</think>", "");
        int start = text.indexOf('{');
        int end = text.lastIndexOf('}');
        if (start < 0 || end < start) throw new JSONException("No draft object");
        JSONObject json = new JSONObject(text.substring(start, end + 1));
        String title = json.optString("title").trim();
        long deadline = 0;
        if (Boolean.TRUE.equals(json.opt("hasDeadline")) && supportsDeadline(transcript, json.optString("deadlineText"))) {
            try {
                long parsed = OffsetDateTime.parse(json.optString("deadlineISO")).toInstant().toEpochMilli();
                if (parsed > now) deadline = parsed;
            } catch (DateTimeParseException ignored) { }
        }
        return new VoiceDraft(title.isEmpty() ? transcript : title, json.optString("detail"), deadline);
    }

    private static boolean supportsDeadline(String transcript, String excerpt) {
        String words = transcript.replaceAll("\\s+", "");
        String source = excerpt.replaceAll("\\s+", "");
        // Require a concrete time quoted from the transcript, not only a model-supplied date.
        String precise = "[0-9]{1,2}[:：][0-9]{2}|[0-9零一二两三四五六七八九十百半]+(?:点|小时|分钟|秒)|正午|午夜";
        return !source.isEmpty() && words.contains(source) && java.util.regex.Pattern.compile(precise).matcher(source).find()
                && !java.util.regex.Pattern.compile("大概|左右|差不多|有空|找个时间|看情况|不确定|待定|几点").matcher(words).find();
    }
}
