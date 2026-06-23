import { AbilityConstant, ConfigurationConstant, UIAbility, Want } from '@kit.AbilityKit';
import { hilog } from '@kit.PerformanceAnalysisKit';
import { window } from '@kit.ArkUI';
import { reminderAgentManager } from '@kit.BackgroundTasksKit';
import { notificationManager } from '@kit.NotificationKit';
import { TaskStore } from '../services/TaskStore';

const DOMAIN = 0x0000;

export default class EntryAbility extends UIAbility {
  onCreate(want: Want, launchParam: AbilityConstant.LaunchParam): void {
    try {
      this.context.getApplicationContext().setColorMode(ConfigurationConstant.ColorMode.COLOR_MODE_NOT_SET);
    } catch (err) {
      hilog.error(DOMAIN, 'testTag', 'Failed to set colorMode. Cause: %{public}s', JSON.stringify(err));
    }
    // 启动即初始化本地任务存储
    TaskStore.getInstance().init(this.context);
    this.debugReminders();
    hilog.info(DOMAIN, 'testTag', '%{public}s', 'Ability onCreate');
  }

  // 诊断：打印有效提醒数量，并尝试清空
  private async debugReminders(): Promise<void> {
    try {
      const before = await reminderAgentManager.getValidReminders();
      hilog.info(DOMAIN, 'RemDbg', 'validBefore=' + before.length);
      const notifEnabled = await notificationManager.isNotificationEnabled();
      hilog.info(DOMAIN, 'RemDbg', 'notifEnabled=' + notifEnabled);
      try {
        const all = await reminderAgentManager.getAllValidReminders();
        hilog.info(DOMAIN, 'RemDbg', 'allValid=' + all.length);
      } catch (e1) {
        hilog.error(DOMAIN, 'RemDbg', 'getAll err ' + JSON.stringify(e1));
      }
      await reminderAgentManager.cancelAllReminders();
      const after = await reminderAgentManager.getValidReminders();
      hilog.info(DOMAIN, 'RemDbg', 'validAfter=' + after.length);
      const d = new Date(Date.now() + 90000);
      const req: reminderAgentManager.ReminderRequestCalendar = {
        reminderType: reminderAgentManager.ReminderType.REMINDER_TYPE_CALENDAR,
        dateTime: { year: d.getFullYear(), month: d.getMonth() + 1, day: d.getDate(), hour: d.getHours(), minute: d.getMinutes(), second: d.getSeconds() },
        title: '测试', content: '测试',
        notificationId: 12321,
        slotType: notificationManager.SlotType.SOCIAL_COMMUNICATION
      };
      try {
        const id = await reminderAgentManager.publishReminder(req);
        hilog.info(DOMAIN, 'RemDbg', 'pubOK id=' + id);
      } catch (e2) {
        hilog.error(DOMAIN, 'RemDbg', 'pubFAIL ' + JSON.stringify(e2));
      }
    } catch (err) {
      hilog.error(DOMAIN, 'RemDbg', 'err ' + JSON.stringify(err));
    }
  }

  onDestroy(): void {
    hilog.info(DOMAIN, 'testTag', '%{public}s', 'Ability onDestroy');
  }

  onWindowStageCreate(windowStage: window.WindowStage): void {
    // Main window is created, set main page for this ability
    hilog.info(DOMAIN, 'testTag', '%{public}s', 'Ability onWindowStageCreate');

    windowStage.loadContent('pages/Index', (err) => {
      if (err.code) {
        hilog.error(DOMAIN, 'testTag', 'Failed to load the content. Cause: %{public}s', JSON.stringify(err));
        return;
      }
      hilog.info(DOMAIN, 'testTag', 'Succeeded in loading the content.');
    });
  }

  onWindowStageDestroy(): void {
    // Main window is destroyed, release UI related resources
    hilog.info(DOMAIN, 'testTag', '%{public}s', 'Ability onWindowStageDestroy');
  }

  onForeground(): void {
    // Ability has brought to foreground
    hilog.info(DOMAIN, 'testTag', '%{public}s', 'Ability onForeground');
  }

  onBackground(): void {
    // Ability has back to background
    hilog.info(DOMAIN, 'testTag', '%{public}s', 'Ability onBackground');
  }
}