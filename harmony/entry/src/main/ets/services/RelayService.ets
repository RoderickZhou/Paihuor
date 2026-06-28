import { http } from '@kit.NetworkKit';
import { hilog } from '@kit.PerformanceAnalysisKit';
import { AppConfig } from '../config/AppConfig';
import { TaskItem } from '../models/TaskModels';

const TAG = 'RelayService';

interface RelayHeader {
  'Content-Type': string;
  'x-paihuor-key': string;
}

// 跨设备中继客户端：优先局域网直连(快)，连不上回退 cloudflared 公网
export class RelayService {
  private static instance: RelayService;
  private activeBase: string = '';

  static getInstance(): RelayService {
    if (!RelayService.instance) {
      RelayService.instance = new RelayService();
    }
    return RelayService.instance;
  }

  enabled(): boolean {
    return AppConfig.RELAY_BASE_URL.length > 0 || AppConfig.RELAY_LAN_URL.length > 0;
  }

  private header(): RelayHeader {
    return { 'Content-Type': 'application/json', 'x-paihuor-key': AppConfig.RELAY_KEY };
  }

  // 供 DeviceService 复用基址选择(局域网优先，回退公网)
  async resolveBase(): Promise<string> {
    return this.base();
  }

  // 选定基址：先探局域网 /health，通就用局域网，否则用公网隧道（结果缓存）
  private async base(): Promise<string> {
    if (this.activeBase.length > 0) {
      return this.activeBase;
    }
    let useLan = false;
    if (AppConfig.RELAY_LAN_URL.length > 0) {
      useLan = await this.ping(AppConfig.RELAY_LAN_URL);
    }
    this.activeBase = useLan ? AppConfig.RELAY_LAN_URL : AppConfig.RELAY_BASE_URL;
    hilog.info(0x0000, TAG, 'activeBase=' + this.activeBase);
    return this.activeBase;
  }

  private async ping(b: string): Promise<boolean> {
    const c = http.createHttp();
    try {
      const r = await c.request(b + '/health', {
        method: http.RequestMethod.GET, header: this.header(),
        connectTimeout: 2500, readTimeout: 2500
      });
      return r.responseCode === 200;
    } catch (e) {
      return false;
    } finally {
      c.destroy();
    }
  }

  private resetBase(): void {
    this.activeBase = '';
  }

  async create(task: TaskItem): Promise<TaskItem | null> {
    const b = await this.base();
    const c = http.createHttp();
    try {
      const resp = await c.request(b + '/tasks', {
        method: http.RequestMethod.POST, header: this.header(),
        extraData: JSON.stringify(task), connectTimeout: 10000, readTimeout: 10000
      });
      if (resp.responseCode !== 200) {
        return null;
      }
      return JSON.parse(resp.result as string) as TaskItem;
    } catch (err) {
      hilog.error(0x0000, TAG, 'create: ' + JSON.stringify(err));
      this.resetBase();
      return null;
    } finally {
      c.destroy();
    }
  }

  async list(familyId: string, since: number): Promise<TaskItem[]> {
    const b = await this.base();
    const c = http.createHttp();
    try {
      // caps=v2 声明本端能处理 已归档/软删墓碑 行（老端不带，中继只给活跃未删行）
      const u = b + '/tasks?familyId=' + encodeURIComponent(familyId) + '&since=' + since + '&caps=v2';
      const resp = await c.request(u, {
        method: http.RequestMethod.GET, header: this.header(),
        connectTimeout: 8000, readTimeout: 8000
      });
      if (resp.responseCode !== 200) {
        return [];
      }
      return JSON.parse(resp.result as string) as TaskItem[];
    } catch (err) {
      hilog.error(0x0000, TAG, 'list: ' + JSON.stringify(err));
      this.resetBase();
      return [];
    } finally {
      c.destroy();
    }
  }

  async update(objectId: string, patch: Record<string, Object>): Promise<boolean> {
    const b = await this.base();
    const c = http.createHttp();
    try {
      const resp = await c.request(b + '/tasks/' + objectId, {
        method: http.RequestMethod.POST, header: this.header(),
        extraData: JSON.stringify(patch), connectTimeout: 10000, readTimeout: 10000
      });
      return resp.responseCode === 200;
    } catch (err) {
      hilog.error(0x0000, TAG, 'update: ' + JSON.stringify(err));
      this.resetBase();
      return false;
    } finally {
      c.destroy();
    }
  }

  // 删除任务：中继做软删（置 deleted=1 并刷新 updatedAt），对端轮询到墓碑后本地移除。by=发起人
  async remove(objectId: string, by: string): Promise<boolean> {
    const b = await this.base();
    const c = http.createHttp();
    try {
      const u = b + '/tasks/' + objectId + (by.length > 0 ? ('?by=' + encodeURIComponent(by)) : '');
      const resp = await c.request(u, {
        method: http.RequestMethod.DELETE, header: this.header(),
        connectTimeout: 10000, readTimeout: 10000
      });
      return resp.responseCode === 200;
    } catch (err) {
      hilog.error(0x0000, TAG, 'remove: ' + JSON.stringify(err));
      this.resetBase();
      return false;
    } finally {
      c.destroy();
    }
  }
}
