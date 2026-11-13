import { http } from '@kit.NetworkKit';
import { hilog } from '@kit.PerformanceAnalysisKit';
import { AppConfig } from '../config/AppConfig';
import { TaskItem, TaskImage } from '../models/TaskModels';
import { HouseholdCard, HouseholdDraft } from '../models/HouseholdCard';

const TAG = 'RelayService';

interface RelayHeader {
  'Content-Type': string;
  'x-paihuor-key': string;
}

// 取图只需带密钥；下载走 ARRAY_BUFFER
interface KeyHeader {
  'x-paihuor-key': string;
}

export interface SyncStatus {
  selfSyncedAt: number;
  peerSyncedAt: number;
  selfPushRegistered: boolean;
  peerPushRegistered: boolean;
}

interface SyncAcknowledgment {
  familyId: string;
  userId: string;
  deviceId: string;
  platform: string;
  objectIds: string[];
}

interface RepeatActionBody {
  familyId: string;
  userId: string;
  action: string;
}

interface HouseholdBatch {
  familyId: string;
  userId: string;
  list: string;
  items: HouseholdDraft[];
}

interface HouseholdAction {
  familyId: string;
  userId: string;
  action: string;
  revision: number;
  title?: string;
  detail?: string;
  list?: string;
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

  async list(familyId: string, since: number): Promise<TaskItem[] | null> {
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
        this.resetBase();
        return null;
      }
      return JSON.parse(resp.result as string) as TaskItem[];
    } catch (err) {
      hilog.error(0x0000, TAG, 'list: ' + JSON.stringify(err));
      this.resetBase();
      return null;
    } finally {
      c.destroy();
    }
  }

  async acknowledge(familyId: string, userId: string, deviceId: string, objectIds: string[]): Promise<boolean> {
    const base = await this.base();
    const client = http.createHttp();
    try {
      const body: SyncAcknowledgment = { familyId: familyId, userId: userId, deviceId: deviceId,
        platform: 'harmony', objectIds: objectIds };
      const response = await client.request(base + '/sync/ack', {
        method: http.RequestMethod.POST, header: this.header(), extraData: JSON.stringify(body),
        connectTimeout: 6000, readTimeout: 6000
      });
      return response.responseCode === 200;
    } catch (err) {
      this.resetBase();
      return false;
    } finally {
      client.destroy();
    }
  }

  async syncStatus(familyId: string, userId: string): Promise<SyncStatus | null> {
    const base = await this.base();
    const client = http.createHttp();
    try {
      const response = await client.request(base + '/sync/status?familyId=' + encodeURIComponent(familyId)
        + '&userId=' + encodeURIComponent(userId), {
        method: http.RequestMethod.GET, header: this.header(), connectTimeout: 6000, readTimeout: 6000
      });
      return response.responseCode === 200 ? JSON.parse(response.result as string) as SyncStatus : null;
    } catch (err) {
      this.resetBase();
      return null;
    } finally {
      client.destroy();
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

  async repeatAction(task: TaskItem, userId: string, action: string): Promise<TaskItem | null> {
    const base = await this.base();
    const client = http.createHttp();
    try {
      const data: RepeatActionBody = { familyId: task.familyId, userId: userId, action: action };
      const response = await client.request(base + '/tasks/' + encodeURIComponent(task.objectId) + '/repeat', {
        method: http.RequestMethod.POST, header: this.header(), extraData: JSON.stringify(data),
        connectTimeout: 8000, readTimeout: 8000
      });
      return response.responseCode === 200 ? JSON.parse(response.result as string) as TaskItem : null;
    } catch (err) {
      this.resetBase();
      return null;
    } finally {
      client.destroy();
    }
  }

  async household(family: string): Promise<HouseholdCard[] | null> {
    const base = await this.base();
    const client = http.createHttp();
    try {
      const response = await client.request(base + '/household/cards?familyId=' + encodeURIComponent(family), {
        method: http.RequestMethod.GET, header: this.header(), connectTimeout: 6000, readTimeout: 8000
      });
      return response.responseCode === 200 ? JSON.parse(response.result as string) as HouseholdCard[] : null;
    } catch (err) {
      this.resetBase();
      return null;
    } finally { client.destroy(); }
  }

  async addHousehold(family: string, user: string, list: string, items: HouseholdDraft[]): Promise<boolean> {
    const data: HouseholdBatch = { familyId: family, userId: user, list: list, items: items };
    return this.writeHousehold('/household/cards', JSON.stringify(data));
  }

  async householdAction(card: HouseholdCard, user: string, action: string): Promise<boolean> {
    const data: HouseholdAction = { familyId: card.familyId, userId: user, action: action, revision: card.revision };
    return this.writeHousehold('/household/cards/' + encodeURIComponent(card.id), JSON.stringify(data));
  }

  async editHousehold(card: HouseholdCard, user: string, title: string, detail: string, list: string): Promise<boolean> {
    const data: HouseholdAction = { familyId: card.familyId, userId: user, action: 'edit', revision: card.revision,
      title: title, detail: detail, list: list };
    return this.writeHousehold('/household/cards/' + encodeURIComponent(card.id), JSON.stringify(data));
  }

  private async writeHousehold(path: string, body: string): Promise<boolean> {
    const base = await this.base();
    const client = http.createHttp();
    try {
      const response = await client.request(base + path, {
        method: http.RequestMethod.POST, header: this.header(), extraData: body, connectTimeout: 6000, readTimeout: 8000
      });
      return response.responseCode === 200;
    } catch (err) {
      this.resetBase();
      return false;
    } finally { client.destroy(); }
  }

  // 上传一张图片（原始字节 body + Content-Type: image/*），返回中继分配的附件元数据
  async uploadImage(bytes: ArrayBuffer, mime: string, familyId: string, w: number, h: number): Promise<TaskImage | null> {
    const b = await this.base();
    const c = http.createHttp();
    try {
      const u = b + '/uploads?familyId=' + encodeURIComponent(familyId) + '&w=' + w + '&h=' + h;
      const header: RelayHeader = { 'Content-Type': mime, 'x-paihuor-key': AppConfig.RELAY_KEY };
      const resp = await c.request(u, {
        method: http.RequestMethod.POST, header: header,
        extraData: bytes, connectTimeout: 20000, readTimeout: 30000
      });
      if (resp.responseCode !== 200) {
        hilog.error(0x0000, TAG, 'uploadImage code=' + resp.responseCode);
        return null;
      }
      return JSON.parse(resp.result as string) as TaskImage;
    } catch (err) {
      hilog.error(0x0000, TAG, 'uploadImage: ' + JSON.stringify(err));
      this.resetBase();
      return null;
    } finally {
      c.destroy();
    }
  }

  // 下载一张图片的原始字节（供本地解码成 PixelMap 显示）
  async downloadImage(id: string): Promise<ArrayBuffer | null> {
    const b = await this.base();
    const c = http.createHttp();
    try {
      const header: KeyHeader = { 'x-paihuor-key': AppConfig.RELAY_KEY };
      const resp = await c.request(b + '/uploads/' + encodeURIComponent(id), {
        method: http.RequestMethod.GET, header: header,
        expectDataType: http.HttpDataType.ARRAY_BUFFER,
        connectTimeout: 15000, readTimeout: 30000
      });
      if (resp.responseCode !== 200) {
        return null;
      }
      return resp.result as ArrayBuffer;
    } catch (err) {
      hilog.error(0x0000, TAG, 'downloadImage: ' + JSON.stringify(err));
      this.resetBase();
      return null;
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
