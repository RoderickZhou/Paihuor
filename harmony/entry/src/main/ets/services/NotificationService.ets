import { notificationManager } from '@kit.NotificationKit';
import { common } from '@kit.AbilityKit';
import { hilog } from '@kit.PerformanceAnalysisKit';

const TAG = 'NotificationService';

// 本地通知 + 桌面图标角标。App 活着(前台/后台未被杀)时生效；
// 杀进程后的推送需 PushKit + AGC(见 EntryAbility.initPush)，本服务不负责。
export class NotificationService {
  private static instance: NotificationService;
  private seq: number = 1000;

  static getInstance(): NotificationService {
    if (!NotificationService.instance) {
      NotificationService.instance = new NotificationService();
    }
    return NotificationService.instance;
  }

  // 首次需用户允许通知，否则弹不出来
  async requestEnable(ctx: common.UIAbilityContext): Promise<void> {
    try {
      await notificationManager.requestEnableNotification(ctx);
    } catch (err) {
      hilog.warn(0x0000, TAG, 'requestEnable: ' + JSON.stringify(err));
    }
  }

  // 新活儿到达：弹一条社交类通知（带横幅/声音由系统槽位决定）
  async notifyNewTask(fromName: string, title: string): Promise<void> {
    try {
      const req: notificationManager.NotificationRequest = {
        id: this.seq++,
        notificationSlotType: notificationManager.SlotType.SOCIAL_COMMUNICATION,
        content: {
          notificationContentType: notificationManager.ContentType.NOTIFICATION_CONTENT_BASIC_TEXT,
          normal: {
            title: fromName + ' 派来一件活',
            text: title.length > 0 ? title : '你有一条新任务'
          }
        }
      };
      await notificationManager.publish(req);
    } catch (err) {
      hilog.error(0x0000, TAG, 'notifyNewTask: ' + JSON.stringify(err));
    }
  }

  // 设置桌面图标角标未读数（0 清除）
  setBadge(count: number): void {
    const n = count > 0 ? count : 0;
    notificationManager.setBadgeNumber(n).catch((err: Object) => {
      hilog.warn(0x0000, TAG, 'setBadge: ' + JSON.stringify(err));
    });
  }
}
