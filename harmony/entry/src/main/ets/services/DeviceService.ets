import { http } from '@kit.NetworkKit';
import { pushService } from '@kit.PushKit';
import { hilog } from '@kit.PerformanceAnalysisKit';
import { BusinessError } from '@kit.BasicServicesKit';
import { AppConfig } from '../config/AppConfig';
import { RelayService } from './RelayService';
import { ProfileService } from './ProfileService';

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
  private static readonly RETRY_GAP_MS: number = 30 * 1000;
  private static readonly REFRESH_GAP_MS: number = 6 * 60 * 60 * 1000;
  private inFlight: boolean = false;
  private lastAttemptAt: number = 0;
  private registeredToken: string = '';
  private registeredProfileKey: string = '';

  static getInstance(): DeviceService {
    if (!DeviceService.instance) {
      DeviceService.instance = new DeviceService();
    }
    return DeviceService.instance;
  }

  async ensureRegisteredToken(force: boolean = false): Promise<boolean> {
    const now = Date.now();
    if (this.inFlight) {
      return false;
    }
    if (!force) {
      if (this.registeredToken.length > 0 && now - this.lastAttemptAt < DeviceService.REFRESH_GAP_MS) {
        return true;
      }
      if (this.registeredToken.length === 0 && now - this.lastAttemptAt < DeviceService.RETRY_GAP_MS) {
        return false;
      }
    }

    this.inFlight = true;
    this.lastAttemptAt = now;
    try {
      const token: string = await pushService.getToken();
      if (!token || token.length === 0) {
        hilog.warn(0x0000, TAG, 'getToken returned empty token');
        return false;
      }
      hilog.info(0x0000, TAG, 'pushToken length=' + token.length);
      const profile = ProfileService.getInstance().getProfile();
      if (!profile) {
        return false;
      }
      const profileKey = profile.familyId + ':' + profile.userId;
      if (!force && token === this.registeredToken && profileKey === this.registeredProfileKey) {
        return true;
      }
      const ok = await this.registerToken(token, profile.familyId, profile.userId);
      if (ok) {
        this.registeredToken = token;
        this.registeredProfileKey = profileKey;
      }
      return ok;
    } catch (err) {
      const e = err as BusinessError;
      hilog.error(0x0000, TAG, 'getToken fail: ' + e.code + ' ' + e.message);
      return false;
    } finally {
      this.inFlight = false;
    }
  }

  async registerToken(pushToken: string, familyId: string, userId: string): Promise<boolean> {
    if (!pushToken || pushToken.length === 0) {
      return false;
    }
    const base = await RelayService.getInstance().resolveBase();
    const c = http.createHttp();
    try {
      const body: DeviceReg = {
        familyId: familyId,
        userId: userId,
        platform: 'harmony',
        pushToken: pushToken
      };
      const header: DeviceHeader = { 'Content-Type': 'application/json', 'x-paihuor-key': AppConfig.RELAY_KEY };
      const resp = await c.request(base + '/devices', {
        method: http.RequestMethod.POST, header: header,
        extraData: JSON.stringify(body), connectTimeout: 10000, readTimeout: 10000
      });
      hilog.info(0x0000, TAG, 'registerToken resp=' + resp.responseCode);
      if (resp.responseCode !== 200) {
        hilog.warn(0x0000, TAG, 'registerToken body=' + String(resp.result));
      }
      return resp.responseCode === 200;
    } catch (err) {
      hilog.error(0x0000, TAG, 'registerToken: ' + JSON.stringify(err));
      return false;
    } finally {
      c.destroy();
    }
  }
}
