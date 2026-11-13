package dev.zx.paihuor;

import static org.junit.Assert.assertEquals;

import java.util.Arrays;
import java.util.List;
import org.junit.Test;

public class TaskRepositoryTest {
    @Test public void prioritizesOverdueTodayAndUnacceptedIncomingWithoutReorderingArchive() {
        long now = 10_000, tomorrow = 30_000;
        TaskItem other = TaskItem.fixture("other", "home", "husband", "wife", "pending", false);
        other.createdAt = 9_000;
        TaskItem waiting = TaskItem.fixture("waiting", "home", "wife", "husband", "pending", false);
        waiting.deadline = tomorrow;
        TaskItem due = TaskItem.fixture("due", "home", "wife", "husband", "received", false);
        due.deadline = 20_000;
        TaskItem late = TaskItem.fixture("late", "home", "husband", "wife", "pending", false);
        late.deadline = 9_999;
        TaskItem done = TaskItem.fixture("done", "home", "wife", "husband", "done", false);
        done.deadline = 1;
        List<TaskItem> all = Arrays.asList(other, waiting, due, late, done);
        assertEquals(Arrays.asList(late, due, waiting, other, done), TaskRepository.visible(all, "home", "husband", false,
                TaskRepository.Direction.ALL, now, tomorrow));
        assertEquals(TaskRepository.Group.WAITING, TaskRepository.group(waiting, "husband", now, tomorrow));
        assertEquals(TaskRepository.Group.OTHER, TaskRepository.group(done, "husband", now, tomorrow));
        late.archived = true;
        due.archived = true;
        due.createdAt = 9_500;
        assertEquals(Arrays.asList(due, late), TaskRepository.visible(all, "home", "husband", true,
                TaskRepository.Direction.ALL, now, tomorrow));
    }
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

    @Test public void directionFiltersPreserveFamilyAndBoardBoundaries() {
        TaskItem sent = TaskItem.fixture("sent", "home", "husband", "wife", "pending", false);
        TaskItem incoming = TaskItem.fixture("incoming", "home", "wife", "husband", "pending", false);
        TaskItem archived = TaskItem.fixture("archived", "home", "wife", "husband", "done", true);
        TaskItem unrelated = TaskItem.fixture("unrelated", "other", "wife", "husband", "pending", false);
        List<TaskItem> all = Arrays.asList(sent, incoming, archived, unrelated);
        assertEquals(Arrays.asList(incoming), TaskRepository.visible(all, "home", "husband", false, TaskRepository.Direction.INCOMING));
        assertEquals(Arrays.asList(sent), TaskRepository.visible(all, "home", "husband", false, TaskRepository.Direction.OUTGOING));
        assertEquals(Arrays.asList(archived), TaskRepository.visible(all, "home", "husband", true, TaskRepository.Direction.INCOMING));
    }

    @Test public void receiptDistinguishesQueueServerRecipientSyncAndManualAccept() {
        TaskItem task = TaskItem.fixture("task", "home", "wife", "husband", "pending", false);
        task.queued = true;
        assertEquals("待发送", TaskRepository.receipt(TaskJson.decode(TaskJson.encode(task))));
        task.queued = false;
        assertEquals("已发出", TaskRepository.receipt(task));
        task.recipientSyncedAt = 100;
        assertEquals("对方已同步", TaskRepository.receipt(TaskJson.decode(TaskJson.encode(task))));
        TaskRepository.advance(task, 200);
        assertEquals("对方已接下", TaskRepository.receipt(task));
    }
}
