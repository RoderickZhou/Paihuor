import { http } from '@kit.NetworkKit';
import { hilog } from '@kit.PerformanceAnalysisKit';
import { AppConfig } from '../config/AppConfig';
import { TaskItem } from '../models/TaskModels';

const TAG = 'RelayService';

interface RelayHeader {
  'Content-Type': string;
  'x-paihuor-key': string;
}

// 跨设备中继客户端（175 上的 Node 服务，cloudflared 公网）
export class RelayService {
  private static instance: RelayService;

  static getInstance(): RelayService {
    if (!RelayService.instance) {
      RelayService.instance = new RelayService();
    }
    return RelayService.instance;
  }

  enabled(): boolean {
    return AppConfig.RELAY_BASE_URL.length > 0;
  }

  private header(): RelayHeader {
    return { 'Content-Type': 'application/json', 'x-paihuor-key': AppConfig.RELAY_KEY };
  }

  // 建任务：服务端补 objectId/createdAt/updatedAt 后回传完整任务
  async create(task: TaskItem): Promise<TaskItem | null> {
    const c = http.createHttp();
    try {
      const resp = await c.request(AppConfig.RELAY_BASE_URL + '/tasks', {
        method: http.RequestMethod.POST,
        header: this.header(),
        extraData: JSON.stringify(task),
        connectTimeout: 15000,
        readTimeout: 15000
      });
      if (resp.responseCode !== 200) {
        hilog.error(0x0000, TAG, 'create http ' + resp.responseCode);
        return null;
      }
      return JSON.parse(resp.result as string) as TaskItem;
    } catch (err) {
      hilog.error(0x0000, TAG, 'create: ' + JSON.stringify(err));
      return null;
    } finally {
      c.destroy();
    }
  }

  // 轮询：拉取本家庭 updatedAt 在 since 之后的任务
  async list(familyId: string, since: number): Promise<TaskItem[]> {
    const c = http.createHttp();
    try {
      const u = AppConfig.RELAY_BASE_URL + '/tasks?familyId=' + encodeURIComponent(familyId) + '&since=' + since;
      const resp = await c.request(u, {
        method: http.RequestMethod.GET,
        header: this.header(),
        connectTimeout: 15000,
        readTimeout: 15000
      });
      if (resp.responseCode !== 200) {
        return [];
      }
      return JSON.parse(resp.result as string) as TaskItem[];
    } catch (err) {
      hilog.error(0x0000, TAG, 'list: ' + JSON.stringify(err));
      return [];
    } finally {
      c.destroy();
    }
  }

  // 改状态/加商量：POST /tasks/:objectId （ArkTS 不支持 PATCH，故用 POST）
  async update(objectId: string, patch: Record<string, Object>): Promise<boolean> {
    const c = http.createHttp();
    try {
      const resp = await c.request(AppConfig.RELAY_BASE_URL + '/tasks/' + objectId, {
        method: http.RequestMethod.POST,
        header: this.header(),
        extraData: JSON.stringify(patch),
        connectTimeout: 15000,
        readTimeout: 15000
      });
      return resp.responseCode === 200;
    } catch (err) {
      hilog.error(0x0000, TAG, 'update: ' + JSON.stringify(err));
      return false;
    } finally {
      c.destroy();
    }
  }
}
