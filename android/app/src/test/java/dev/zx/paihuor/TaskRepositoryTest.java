package dev.zx.paihuor;

import static org.junit.Assert.assertEquals;

import java.util.Arrays;
import java.util.List;
import org.junit.Test;

public class TaskRepositoryTest {
    @Test
    public void separatesInboxAndArchiveForCurrentFamily() {
        TaskItem sent = TaskItem.fixture("sent", "fam-home", "husband", "wife", "pending", false);
        TaskItem received = TaskItem.fixture("received", "fam-home", "wife", "husband", "received", false);
        TaskItem archived = TaskItem.fixture("archived", "fam-home", "husband", "wife", "done", true);
        TaskItem otherFamily = TaskItem.fixture("other", "fam-other", "wife", "husband", "pending", false);
        List<TaskItem> tasks = Arrays.asList(sent, received, archived, otherFamily);

        assertEquals(Arrays.asList(sent, received), TaskRepository.visible(tasks, "fam-home", "husband", false));
        assertEquals(Arrays.asList(archived), TaskRepository.visible(tasks, "fam-home", "husband", true));
    }

    @Test
    public void receiverAdvancesTaskToReceivedThenDoneAndArchived() {
        TaskItem task = TaskItem.fixture("task", "fam-home", "wife", "husband", "pending", false);

        TaskRepository.advance(task, 1000L);
        assertEquals("received", task.status);
        assertEquals(1000L, task.receivedAt);

        TaskRepository.advance(task, 2000L);
        assertEquals("done", task.status);
        assertEquals(2000L, task.doneAt);
        assertEquals(true, task.archived);
    }
}
