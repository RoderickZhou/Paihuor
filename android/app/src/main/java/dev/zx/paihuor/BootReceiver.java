package dev.zx.paihuor;

import android.content.BroadcastReceiver;
import android.content.Context;
import android.content.Intent;

public final class BootReceiver extends BroadcastReceiver {
    @Override
    public void onReceive(Context context, Intent intent) {
        if (Profile.isComplete(context)) {
            context.startForegroundService(new Intent(context, PollService.class));
        }
    }
}
