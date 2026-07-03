import { RemoteNotificationExtensionAbility, pushCommon } from '@kit.PushKit';
import { hilog } from '@kit.PerformanceAnalysisKit';

const TAG = 'RemoteNotification';

interface RemoteTaskPayload {
  title?: string;
  text?: string;
  fromName?: string;
  badgeNumber?: number;
  setBadgeNumber?: number;
}

export default class RemoteNotificationAbility extends RemoteNotificationExtensionAbility {
  async onReceiveMessage(remoteNotificationInfo: pushCommon.RemoteNotificationInfo):
    Promise<pushCommon.RemoteNotificationContent> {
    hilog.info(0x0000, TAG, 'remoteNotificationInfo: %{public}s', JSON.stringify(remoteNotificationInfo));

    const payload = this.parsePayload(remoteNotificationInfo.data);
    const title = payload.fromName && payload.fromName.length > 0
      ? payload.fromName + ' 派来一件活'
      : '派活儿';
    const text = payload.title && payload.title.length > 0
      ? payload.title
      : (payload.text && payload.text.length > 0 ? payload.text : '你有一条新任务');
    const badge = payload.setBadgeNumber || payload.badgeNumber || 1;

    return {
      title: title,
      text: text,
      setBadgeNumber: badge,
      wantAgent: {
        abilityName: 'EntryAbility',
        parameters: {
          source: 'remoteNotification'
        }
      }
    };
  }

  private parsePayload(data: string): RemoteTaskPayload {
    if (!data || data.length === 0) {
      return {};
    }
    try {
      return JSON.parse(data) as RemoteTaskPayload;
    } catch (err) {
      hilog.warn(0x0000, TAG, 'parse payload failed: %{public}s', JSON.stringify(err));
      return { text: data };
    }
  }
}
