package dev.zx.paihuor;

import android.app.Notification;
import android.app.NotificationChannel;
import android.app.NotificationManager;
import android.app.PendingIntent;
import android.app.Service;
import android.content.Intent;
import android.os.Handler;
import android.os.IBinder;
import android.os.Looper;
import java.util.List;
import org.json.JSONArray;

public final class PollService extends Service {
    private static final String SYNC_CHANNEL = "paihuor_sync";
    private static final String TASK_CHANNEL = "paihuor_tasks";
    private final Handler handler = new Handler(Looper.getMainLooper());
    private RelayClient relay;
    private int intervalMs = 8000;
    private boolean syncing;
    private final Runnable loop = new Runnable() {
        @Override public void run() {
            poll();
            handler.postDelayed(this, intervalMs);
        }
    };

    @Override
    public void onCreate() {
        super.onCreate();
        Config config = Config.load(this);
        relay = new RelayClient(this);
        intervalMs = config.pollIntervalSec * 1000;
        createChannels();
        startForeground(1, notification(SYNC_CHANNEL, "派活儿", "正在同步家庭任务", false));
        handler.post(loop);
    }

    private void poll() {
        if (syncing || !Profile.isComplete(this) || !relay.usable()) return;
        final String family = Profile.familyId(this);
        final String role = Profile.userId(this);
        syncing = true;
        new Thread(() -> {
            try {
                long previous = TaskCache.lastSync(this, family);
                for (TaskItem item : TaskCache.load(this)) {
                    if (!current(family, role)) return;
                    if (!item.queued || !item.familyId.equals(family) || !item.fromUserId.equals(role)) continue;
                    try {
                        TaskItem sent = TaskOutbox.send(this, relay, item);
                        TaskCache.finishSending(this, item.objectId, sent);
                        TaskOutbox.cleanup(this, item);
                        changed();
                    } catch (Exception ignored) { break; }
                }
                JSONArray remote = relay.fetch(family, previous);
                if (!current(family, role)) return;
                TaskCache.merge(this, remote);
                List<TaskItem> tasks = TaskCache.load(this);
                JSONArray acks = new JSONArray();
                for (TaskItem item : tasks) {
                    if (!item.familyId.equals(family) || !item.toUserId.equals(role) || item.queued || item.deleted) continue;
                    if (item.recipientSyncedAt == 0 && acks.length() < 100
                            && item.objectId.matches("(?i)[0-9a-f]{8}(-[0-9a-f]{4}){3}-[0-9a-f]{12}")) acks.put(item.objectId);
                    if (item.updatedAt > previous && item.recipientSyncedAt == 0
                            && "pending".equals(item.status) && !item.archived) {
                        String title = item.title.isEmpty() ? item.rawText : item.title;
                        ((NotificationManager) getSystemService(NOTIFICATION_SERVICE))
                                .notify(item.objectId.hashCode(), notification(TASK_CHANNEL,
                                        "家人派来一件事", title, true));
                    }
                }
                if (remote.length() > 0) changed();
                if (current(family, role)) relay.acknowledge(family, role, Profile.deviceId(this), acks);
            } catch (Exception ignored) {
            } finally {
                handler.post(() -> syncing = false);
            }
        }).start();
    }

    private boolean current(String family, String role) {
        return family.equals(Profile.familyId(this)) && role.equals(Profile.userId(this));
    }

    private void changed() {
        sendBroadcast(new Intent("dev.zx.paihuor.SYNCED").setPackage(getPackageName()));
    }

    private void createChannels() {
        NotificationManager manager = getSystemService(NotificationManager.class);
        manager.createNotificationChannel(new NotificationChannel(SYNC_CHANNEL, "任务同步",
                NotificationManager.IMPORTANCE_LOW));
        manager.createNotificationChannel(new NotificationChannel(TASK_CHANNEL, "新任务提醒",
                NotificationManager.IMPORTANCE_HIGH));
    }

    private Notification notification(String channel, String title, String text, boolean autoCancel) {
        PendingIntent open = PendingIntent.getActivity(this, 0, new Intent(this, MainActivity.class),
                PendingIntent.FLAG_UPDATE_CURRENT | PendingIntent.FLAG_IMMUTABLE);
        return new Notification.Builder(this, channel)
                .setSmallIcon(android.R.drawable.ic_menu_agenda)
                .setContentTitle(title)
                .setContentText(text)
                .setContentIntent(open)
                .setAutoCancel(autoCancel)
                .setOngoing(!autoCancel)
                .build();
    }

    @Override public int onStartCommand(Intent intent, int flags, int startId) { poll(); return START_STICKY; }
    @Override public void onDestroy() { handler.removeCallbacks(loop); super.onDestroy(); }
    @Override public IBinder onBind(Intent intent) { return null; }
}
