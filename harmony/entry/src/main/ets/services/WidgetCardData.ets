// 桌面卡片数据：从 Preferences(与 TaskStore 同一库)同步读任务，构建卡片绑定数据；
// 维护已添加卡片的 formId 列表，供 App 端主动推送更新。
import { common } from '@kit.AbilityKit';
import { preferences } from '@kit.ArkData';
import { formProvider, formBindingData } from '@kit.FormKit';
import { hilog } from '@kit.PerformanceAnalysisKit';
import { TaskItem, TaskStatus } from '../models/TaskModels';

const TAG = 'WidgetCardData';
const PREF = 'paihuor_store';
const TASKS_KEY = 'tasks';
const FORMIDS_KEY = 'widget_form_ids';

export interface CardData {
  count: number;
  t1: string;
  t2: string;
  empty: boolean;
}

function titleOf(t: TaskItem): string {
  return t.title && t.title.length > 0 ? t.title : t.rawText;
}

function readActive(context: common.Context): TaskItem[] {
  try {
    const store = preferences.getPreferencesSync(context, { name: PREF });
    const raw = store.getSync(TASKS_KEY, '[]') as string;
    const all = JSON.parse(raw) as TaskItem[];
    const act = all.filter((t: TaskItem) => !t.archived && t.status !== TaskStatus.DONE && !t.deleted);
    act.sort((a: TaskItem, b: TaskItem) => b.createdAt - a.createdAt);
    return act;
  } catch (err) {
    hilog.warn(0x0000, TAG, 'readActive: ' + JSON.stringify(err));
    return [];
  }
}

export function buildCardData(context: common.Context): CardData {
  const act = readActive(context);
  if (act.length === 0) {
    return { count: 0, t1: '', t2: '', empty: true };
  }
  return {
    count: act.length,
    t1: titleOf(act[0]),
    t2: act.length > 1 ? titleOf(act[1]) : '',
    empty: false
  };
}

export function addFormId(context: common.Context, formId: string): void {
  if (!formId || formId.length === 0) {
    return;
  }
  try {
    const store = preferences.getPreferencesSync(context, { name: PREF });
    const ids = JSON.parse(store.getSync(FORMIDS_KEY, '[]') as string) as string[];
    if (ids.indexOf(formId) < 0) {
      ids.push(formId);
      store.putSync(FORMIDS_KEY, JSON.stringify(ids));
      store.flush();
    }
  } catch (err) {
    hilog.warn(0x0000, TAG, 'addFormId: ' + JSON.stringify(err));
  }
}

export function removeFormId(context: common.Context, formId: string): void {
  try {
    const store = preferences.getPreferencesSync(context, { name: PREF });
    const ids = (JSON.parse(store.getSync(FORMIDS_KEY, '[]') as string) as string[])
      .filter((x: string) => x !== formId);
    store.putSync(FORMIDS_KEY, JSON.stringify(ids));
    store.flush();
  } catch (err) {
    hilog.warn(0x0000, TAG, 'removeFormId: ' + JSON.stringify(err));
  }
}

// App 端：把最新数据推给所有已添加的卡片（无卡片则直接返回）
export async function updateAllCards(context: common.Context): Promise<void> {
  try {
    const store = preferences.getPreferencesSync(context, { name: PREF });
    const ids = JSON.parse(store.getSync(FORMIDS_KEY, '[]') as string) as string[];
    if (ids.length === 0) {
      return;
    }
    const binding = formBindingData.createFormBindingData(buildCardData(context));
    for (let i = 0; i < ids.length; i++) {
      try {
        await formProvider.updateForm(ids[i], binding);
      } catch (err) {
        hilog.warn(0x0000, TAG, 'updateForm ' + ids[i] + ': ' + JSON.stringify(err));
      }
    }
  } catch (err) {
    hilog.warn(0x0000, TAG, 'updateAllCards: ' + JSON.stringify(err));
  }
}
