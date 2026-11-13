package dev.zx.paihuor;

import static org.junit.Assert.assertEquals;
import java.time.Instant;
import org.junit.Test;

public class VoiceDraftTest {
    @Test public void parsesEditableDraftAndShanghaiDeadlineIgnoringReasoning() throws Exception {
        VoiceDraft draft = VoiceDraft.parse("<think>{not the draft}</think>```json\n"
                + "{\"title\":\"买牛奶\",\"detail\":\"两盒\",\"hasDeadline\":true,"
                + "\"deadlineISO\":\"2026-11-14T09:00:00+08:00\"}\n```", "明早九点买两盒牛奶");
        assertEquals("买牛奶", draft.title);
        assertEquals("两盒", draft.detail);
        assertEquals(Instant.parse("2026-11-14T01:00:00Z").toEpochMilli(), draft.deadline);
    }

    @Test public void missingTitleUsesTranscriptAndInvalidDeadlineIsNotInvented() throws Exception {
        VoiceDraft draft = VoiceDraft.parse("{\"title\":\"\",\"hasDeadline\":true,\"deadlineISO\":\"明早\"}", "买牛奶");
        assertEquals("买牛奶", draft.title);
        assertEquals("", draft.detail);
        assertEquals(0, draft.deadline);
    }

    @Test public void explicitNoDeadlineIgnoresAnyDateInResponse() throws Exception {
        VoiceDraft draft = VoiceDraft.parse("{\"title\":\"买牛奶\",\"hasDeadline\":false,"
                + "\"deadlineISO\":\"2026-11-14T09:00:00+08:00\"}", "买牛奶");
        assertEquals(0, draft.deadline);
    }
}
