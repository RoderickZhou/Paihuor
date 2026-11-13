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
        if (!Profile.isComplete(this) || !relay.usable()) return;
        new Thread(() -> {
            try {
                long previous = TaskCache.lastSync(this);
                JSONArray remote = relay.fetch(Profile.familyId(this), previous);
                TaskCache.merge(this, remote);
                List<TaskItem> tasks = TaskCache.load(this);
                long newest = previous;
                for (TaskItem item : tasks) {
                    newest = Math.max(newest, item.updatedAt);
                    if (item.updatedAt > previous && item.toUserId.equals(Profile.userId(this))
                            && "pending".equals(item.status) && !item.deleted) {
                        String title = item.title.isEmpty() ? item.rawText : item.title;
                        ((NotificationManager) getSystemService(NOTIFICATION_SERVICE))
                                .notify(item.objectId.hashCode(), notification(TASK_CHANNEL,
                                        "家人派来一件事", title, true));
                    }
                }
                if (newest > previous) sendBroadcast(new Intent("dev.zx.paihuor.SYNCED").setPackage(getPackageName()));
            } catch (Throwable ignored) {
            }
        }).start();
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

    @Override public int onStartCommand(Intent intent, int flags, int startId) { return START_STICKY; }
    @Override public void onDestroy() { handler.removeCallbacks(loop); super.onDestroy(); }
    @Override public IBinder onBind(Intent intent) { return null; }
}
