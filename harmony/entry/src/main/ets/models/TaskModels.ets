// 待办任务数据模型（纯数据类，便于 JSON 序列化与日后 LeanCloud 同步）

export class TaskStatus {
  static readonly PENDING: string = 'pending';       // 已发、对方未读
  static readonly RECEIVED: string = 'received';      // 已收到、倒计时中
  static readonly NEGOTIATING: string = 'negotiating';// 商量中
  static readonly DONE: string = 'done';              // 已完成
}

// 提醒配置
export class ReminderConfig {
  intervalMinutes: number = 30;     // 固定间隔反复响（分钟）
  rampUpLastMinutes: number = 5;    // 最后 N 分钟每分钟提醒
  ringtone: string = 'default';
}

// 一条商量记录
export class NegotiationMsg {
  fromUserId: string = '';
  text: string = '';
  proposedDeadline: number = 0;     // 0 表示没有提出新时间；否则为时间戳(ms)
  at: number = 0;
}

// 一条待办
export class TaskItem {
  id: string = '';
  objectId: string = '';            // 中继分配的服务端主键（跨设备唯一）
  familyId: string = '';            // 家庭配对码
  fromUserId: string = '';
  toUserId: string = '';
  rawText: string = '';             // 语音/输入原文
  title: string = '';               // AI 抽取的标题
  detail: string = '';              // AI 抽取的细节
  deadline: number = 0;             // 截止时间(ms)，0 表示未设
  status: string = TaskStatus.PENDING;
  reminder: ReminderConfig = new ReminderConfig();
  negotiation: NegotiationMsg[] = [];
  reminderIds: number[] = [];       // 本地排定的提醒 id（仅本机，不参与云端同步）
  createdAt: number = 0;
  updatedAt: number = 0;            // 中继维护，用于增量轮询
  receivedAt: number = 0;
  doneAt: number = 0;
}
