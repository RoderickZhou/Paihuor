import { http } from '@kit.NetworkKit';
import { hilog } from '@kit.PerformanceAnalysisKit';
import { AppConfig } from '../config/AppConfig';
import { RelayService } from './RelayService';

const TAG = 'DeviceService';

interface DeviceHeader {
  'Content-Type': string;
  'x-paihuor-key': string;
}

interface DeviceReg {
  familyId: string;
  userId: string;
  platform: string;
  pushToken: string;
}

// 把本机的华为 Push Token 注册到中继，供对端有新任务时推送通知
export class DeviceService {
  private static instance: DeviceService;

  static getInstance(): DeviceService {
    if (!DeviceService.instance) {
      DeviceService.instance = new DeviceService();
    }
    return DeviceService.instance;
  }

  async registerToken(pushToken: string): Promise<boolean> {
    if (!pushToken || pushToken.length === 0) {
      return false;
    }
    const base = await RelayService.getInstance().resolveBase();
    const c = http.createHttp();
    try {
      const body: DeviceReg = {
        familyId: AppConfig.FAMILY_ID,
        userId: AppConfig.MY_USER_ID,
        platform: 'harmony',
        pushToken: pushToken
      };
      const header: DeviceHeader = { 'Content-Type': 'application/json', 'x-paihuor-key': AppConfig.RELAY_KEY };
      const resp = await c.request(base + '/devices', {
        method: http.RequestMethod.POST, header: header,
        extraData: JSON.stringify(body), connectTimeout: 10000, readTimeout: 10000
      });
      hilog.info(0x0000, TAG, 'registerToken resp=' + resp.responseCode);
      return resp.responseCode === 200;
    } catch (err) {
      hilog.error(0x0000, TAG, 'registerToken: ' + JSON.stringify(err));
      return false;
    } finally {
      c.destroy();
    }
  }
}
