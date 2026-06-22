import { reminderAgentManager } from '@kit.BackgroundTasksKit';
import { notificationManager } from '@kit.NotificationKit';
import { common } from '@kit.AbilityKit';
import { hilog } from '@kit.PerformanceAnalysisKit';

const TAG = 'ReminderService';
const MAX_REMINDERS = 8;        // 单个任务最多排这么多条（系统每应用约 30 条上限）
const PKG = 'com.example.paihuor';

// 到点反复响铃 + 最后 N 分钟每分钟提醒（系统代理提醒，App 关闭/被杀也响）
export class ReminderService {
  private static instance: ReminderService;
  private notifSeq: number = Date.now() % 100000;

  static getInstance(): ReminderService {
    if (!ReminderService.instance) {
      ReminderService.instance = new ReminderService();
    }
    return ReminderService.instance;
  }

  // 首次需要用户允许通知，否则提醒发不出来
  async requestNotify(ctx: common.UIAbilityContext): Promise<void> {
    try {
      await notificationManager.requestEnableNotification(ctx);
    } catch (err) {
      hilog.warn(0x0000, TAG, 'requestEnableNotification: ' + JSON.stringify(err));
    }
  }

  // 计算所有要响的时间点：固定间隔 + 最后 N 分钟每分钟 + 截止点
  computeFireTimes(now: number, deadline: number, intervalMin: number, rampUpMin: number): number[] {
    const set = new Set<number>();
    const interval = intervalMin * 60000;
    const rampWindow = rampUpMin * 60000;

    if (interval > 0) {
      let t = now + interval;
      while (t < deadline - rampWindow) {
        set.add(t);
        t += interval;
      }
    }
    for (let k = rampUpMin; k >= 1; k--) {
      const tt = deadline - k * 60000;
      if (tt > now) {
        set.add(tt);
      }
    }
    if (deadline > now) {
      set.add(deadline);
    }

    let arr = Array.from(set).sort((a: number, b: number) => a - b);
    if (arr.length > MAX_REMINDERS) {
      arr = arr.slice(arr.length - MAX_REMINDERS);
    }
    return arr;
  }

  async scheduleForTask(title: string, deadline: number, intervalMin: number, rampUpMin: number, taskId: string): Promise<number[]> {
    const ids: number[] = [];
    let firstErr: string = '';
    let clearedOnce: boolean = false;
    if (!deadline || deadline <= Date.now()) {
      return ids;
    }
    const fires = this.computeFireTimes(Date.now(), deadline, intervalMin, rampUpMin);
    for (let i = 0; i < fires.length; i++) {
      const fireMs = fires[i];
      const dt = new Date(fireMs);
      const isDeadline = fireMs === deadline;
      const req: reminderAgentManager.ReminderRequestCalendar = {
        reminderType: reminderAgentManager.ReminderType.REMINDER_TYPE_CALENDAR,
        dateTime: {
          year: dt.getFullYear(),
          month: dt.getMonth() + 1,
          day: dt.getDate(),
          hour: dt.getHours(),
          minute: dt.getMinutes(),
          second: dt.getSeconds()
        },
        title: '派活儿：' + title,
        content: isDeadline ? '到截止时间了！' : ('快到点了：' + title),
        ringDuration: 30,
        ringChannel: reminderAgentManager.RingChannel.RING_CHANNEL_ALARM,
        slotType: notificationManager.SlotType.SOCIAL_COMMUNICATION,
        notificationId: this.notifSeq++,
        groupId: taskId,
        tapDismissed: false,
        wantAgent: { pkgName: PKG, abilityName: 'EntryAbility' }
      };
      try {
        const id = await reminderAgentManager.publishReminder(req);
        ids.push(id);
      } catch (err) {
        const es = JSON.stringify(err);
        hilog.error(0x0000, TAG, 'publishReminder failed: ' + es);
        if (!clearedOnce && es.indexOf('1700002') >= 0) {
          // 超出系统上限：清空旧提醒后重试本条（自愈，清掉历史堆积）
          clearedOnce = true;
          try {
            await reminderAgentManager.cancelAllReminders();
            const retryId = await reminderAgentManager.publishReminder(req);
            ids.push(retryId);
          } catch (err2) {
            if (firstErr.length === 0) {
              firstErr = JSON.stringify(err2);
            }
          }
        } else if (firstErr.length === 0) {
          firstErr = es;
        }
      }
    }
    hilog.info(0x0000, TAG, 'scheduled ' + ids.length + ' reminders for ' + taskId);
    if (ids.length === 0 && firstErr.length > 0) {
      throw new Error(firstErr);
    }
    return ids;
  }

  async cancelForTask(ids: number[]): Promise<void> {
    for (let i = 0; i < ids.length; i++) {
      try {
        await reminderAgentManager.cancelReminder(ids[i]);
      } catch (err) {
        hilog.warn(0x0000, TAG, 'cancelReminder ' + ids[i] + ': ' + JSON.stringify(err));
      }
    }
  }
}
