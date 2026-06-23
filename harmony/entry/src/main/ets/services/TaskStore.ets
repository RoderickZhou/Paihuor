import { common } from '@kit.AbilityKit';
import { preferences } from '@kit.ArkData';
import { hilog } from '@kit.PerformanceAnalysisKit';
import { Constants } from '../constants/Constants';
import { TaskItem } from '../models/TaskModels';

const TAG = 'TaskStore';

// 本地任务存储（M1 用 Preferences 存 JSON；M3 再接 LeanCloud 作云端镜像）
export class TaskStore {
  private static instance: TaskStore;
  private store: preferences.Preferences | null = null;
  private tasks: TaskItem[] = [];
  private initPromise: Promise<void> | null = null;

  static getInstance(): TaskStore {
    if (!TaskStore.instance) {
      TaskStore.instance = new TaskStore();
    }
    return TaskStore.instance;
  }

  // 在 EntryAbility.onCreate 调用一次（幂等）
  init(context: common.Context): Promise<void> {
    if (!this.initPromise) {
      this.initPromise = this.doInit(context);
    }
    return this.initPromise;
  }

  // 页面等待存储就绪
  async whenReady(): Promise<void> {
    if (this.initPromise) {
      await this.initPromise;
    }
  }

  private async doInit(context: common.Context): Promise<void> {
    try {
      const opt: preferences.Options = { name: Constants.PREF_NAME };
      this.store = await preferences.getPreferences(context, opt);
      const raw = await this.store.get(Constants.PREF_TASKS_KEY, '[]') as string;
      this.tasks = JSON.parse(raw) as TaskItem[];
      hilog.info(0x0000, TAG, 'TaskStore ready, count=' + this.tasks.length);
    } catch (err) {
      hilog.error(0x0000, TAG, 'init failed: ' + JSON.stringify(err));
      this.tasks = [];
    }
  }

  getAll(): TaskItem[] {
    return this.tasks.slice().sort((a: TaskItem, b: TaskItem) => b.createdAt - a.createdAt);
  }

  getById(id: string): TaskItem | undefined {
    return this.tasks.find((t: TaskItem) => t.id === id);
  }

  async upsert(task: TaskItem): Promise<void> {
    const idx = this.tasks.findIndex((t: TaskItem) => t.id === task.id);
    if (idx >= 0) {
      this.tasks[idx] = task;
    } else {
      this.tasks.push(task);
    }
    await this.persist();
  }

  async remove(id: string): Promise<void> {
    this.tasks = this.tasks.filter((t: TaskItem) => t.id !== id);
    await this.persist();
  }

  // 用中继返回的任务合并进本地（按 objectId 去重；保留本地 id 与 reminderIds）
  async mergeRemote(remote: TaskItem[]): Promise<void> {
    for (let i = 0; i < remote.length; i++) {
      const s = remote[i];
      if (!s.objectId || s.objectId.length === 0) {
        continue;
      }
      const idx = this.tasks.findIndex((t: TaskItem) => t.objectId === s.objectId);
      if (idx >= 0) {
        const keepId = this.tasks[idx].id;
        const keepReminders = this.tasks[idx].reminderIds;
        this.tasks[idx] = s;
        this.tasks[idx].id = keepId.length > 0 ? keepId : s.objectId;
        this.tasks[idx].reminderIds = keepReminders;
      } else {
        if (!s.id || s.id.length === 0) {
          s.id = s.objectId;
        }
        this.tasks.push(s);
      }
    }
    await this.persist();
  }

  private async persist(): Promise<void> {
    if (!this.store) {
      return;
    }
    try {
      await this.store.put(Constants.PREF_TASKS_KEY, JSON.stringify(this.tasks));
      await this.store.flush();
    } catch (err) {
      hilog.error(0x0000, TAG, 'persist failed: ' + JSON.stringify(err));
    }
  }
}
