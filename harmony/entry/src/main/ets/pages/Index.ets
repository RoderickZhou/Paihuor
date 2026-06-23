import { abilityAccessCtrl, common, Permissions } from '@kit.AbilityKit';
import { Constants } from '../constants/Constants';
import { TaskItem, TaskStatus, ReminderConfig } from '../models/TaskModels';
import { TaskStore } from '../services/TaskStore';
import { AsrService } from '../services/AsrService';
import { AIService } from '../services/AIService';
import { ReminderService } from '../services/ReminderService';
import { RelayService } from '../services/RelayService';
import { AppConfig } from '../config/AppConfig';

@Entry
@Component
struct Index {
  @State tasks: TaskItem[] = [];
  @State showCreate: boolean = false;
  @State draftTitle: string = '';
  @State draftDeadline: number = 0;
  @State draftDetail: string = '';
  @State recording: boolean = false;
  @State asrText: string = '';
  @State extracting: boolean = false;
  @State recordError: string = '';
  private lastSync: number = 0;
  private pollTimer: number = -1;

  async aboutToAppear(): Promise<void> {
    await TaskStore.getInstance().whenReady();
    this.refresh();
    this.startPolling();
  }

  aboutToDisappear(): void {
    this.stopPolling();
  }

  refresh(): void {
    this.tasks = TaskStore.getInstance().getAll();
  }

  startPolling(): void {
    this.poll();
    this.pollTimer = setInterval(() => { this.poll(); }, 4000);
  }

  stopPolling(): void {
    if (this.pollTimer >= 0) {
      clearInterval(this.pollTimer);
      this.pollTimer = -1;
    }
  }

  // 轮询中继，把对方建/改的任务合并到本地
  async poll(): Promise<void> {
    if (!RelayService.getInstance().enabled()) {
      return;
    }
    const remote = await RelayService.getInstance().list(AppConfig.FAMILY_ID, this.lastSync);
    if (remote.length === 0) {
      return;
    }
    let mx = this.lastSync;
    for (let i = 0; i < remote.length; i++) {
      if (remote[i].updatedAt > mx) {
        mx = remote[i].updatedAt;
      }
    }
    this.lastSync = mx;
    await TaskStore.getInstance().mergeRemote(remote);
    this.refresh();
  }

  // 把本机的状态变更推到中继（供对方同步）
  private async pushStatus(item: TaskItem): Promise<void> {
    if (item.objectId.length === 0) {
      return;
    }
    const patch: Record<string, Object> = {
      'status': item.status,
      'receivedAt': item.receivedAt,
      'doneAt': item.doneAt
    };
    await RelayService.getInstance().update(item.objectId, patch);
  }

  build() {
    Stack({ alignContent: Alignment.BottomEnd }) {
      Column() {
        // 顶部标题
        Row() {
          Text('派活儿')
            .fontSize(24)
            .fontWeight(FontWeight.Bold)
            .fontColor(Constants.COLOR_TEXT_PRIMARY)
          Blank()
        }
        .width('100%')
        .padding({ left: 20, right: 20, top: 16, bottom: 8 })

        if (this.tasks.length === 0) {
          Column() {
            Text('🌱').fontSize(48).margin({ bottom: 12 })
            Text('还没有事项').fontSize(16).fontColor(Constants.COLOR_TEXT_SECONDARY)
            Text('点右下角 ＋ 派一件活').fontSize(13).fontColor(Constants.COLOR_TEXT_SECONDARY).margin({ top: 6 })
          }
          .width('100%')
          .layoutWeight(1)
          .justifyContent(FlexAlign.Center)
        } else {
          List({ space: 12 }) {
            ForEach(this.tasks, (item: TaskItem) => {
              ListItem() {
                this.TaskCard(item)
              }
            }, (item: TaskItem) => item.id)
          }
          .width('100%')
          .layoutWeight(1)
          .padding({ left: 16, right: 16, top: 4, bottom: 100 })
          .scrollBar(BarState.Off)
        }
      }
      .width('100%')
      .height('100%')
      .backgroundColor(Constants.COLOR_BG)

      // 右下角悬浮「＋」
      Button() {
        Text('＋').fontSize(30).fontColor(Color.White)
      }
      .width(60)
      .height(60)
      .borderRadius(30)
      .backgroundColor(Constants.COLOR_PRIMARY)
      .margin({ right: 24, bottom: 32 })
      .shadow({ radius: 12, color: '#33000000', offsetY: 4 })
      .onClick(() => {
        this.openCreate();
      })

      if (this.showCreate) {
        this.CreateSheet()
      }
    }
    .width('100%')
    .height('100%')
  }

  @Builder
  TaskCard(item: TaskItem) {
    Column() {
      Row() {
        Text(item.title.length > 0 ? item.title : item.rawText)
          .fontSize(17)
          .fontWeight(FontWeight.Medium)
          .fontColor(Constants.COLOR_TEXT_PRIMARY)
          .layoutWeight(1)
        Text(this.statusLabel(item.status))
          .fontSize(12)
          .fontColor(Color.White)
          .backgroundColor(this.statusColor(item.status))
          .borderRadius(8)
          .padding({ left: 8, right: 8, top: 2, bottom: 2 })
      }
      .width('100%')

      Text(Constants.formatDeadline(item.deadline))
        .fontSize(13)
        .fontColor(Constants.COLOR_TEXT_SECONDARY)
        .margin({ top: 6 })
        .width('100%')

      if (item.status === TaskStatus.RECEIVED) {
        Text(Constants.formatRemaining(item.deadline))
          .fontSize(13)
          .fontColor(Constants.COLOR_WARNING)
          .margin({ top: 2 })
          .width('100%')
      }

      Row() {
        if (item.status === TaskStatus.PENDING) {
          Button('收到')
            .type(ButtonType.Normal).fontSize(14).fontColor(Color.White)
            .backgroundColor(Constants.COLOR_PRIMARY).height(36).borderRadius(10)
            .padding({ left: 16, right: 16 }).margin({ right: 10 })
            .onClick(() => { this.onReceive(item); })
          Button('商量')
            .type(ButtonType.Normal).fontSize(14).fontColor(Color.White)
            .backgroundColor(Constants.COLOR_WARNING).height(36).borderRadius(10)
            .padding({ left: 16, right: 16 })
            .onClick(() => { this.onNegotiate(item); })
        } else if (item.status === TaskStatus.RECEIVED) {
          Button('勾掉完成')
            .type(ButtonType.Normal).fontSize(14).fontColor(Color.White)
            .backgroundColor(Constants.COLOR_PRIMARY).height(36).borderRadius(10)
            .padding({ left: 16, right: 16 })
            .onClick(() => { this.onDone(item); })
        } else if (item.status === TaskStatus.NEGOTIATING) {
          Button('改为收到')
            .type(ButtonType.Normal).fontSize(14).fontColor(Color.White)
            .backgroundColor(Constants.COLOR_PRIMARY).height(36).borderRadius(10)
            .padding({ left: 16, right: 16 })
            .onClick(() => { this.onReceive(item); })
        }
        Blank()
        Text('删除')
          .fontSize(13)
          .fontColor(Constants.COLOR_TEXT_SECONDARY)
          .padding(6)
          .onClick(() => { this.onDelete(item); })
      }
      .width('100%')
      .margin({ top: 12 })
    }
    .width('100%')
    .padding(16)
    .backgroundColor(Constants.COLOR_CARD_BG)
    .borderRadius(14)
    .opacity(item.status === TaskStatus.DONE ? 0.5 : 1)
  }

  @Builder
  CreateSheet() {
    Column() {
      // 半透明遮罩占位（点遮罩不关闭，避免误触；用取消按钮关闭）
      Column().layoutWeight(1).width('100%')

      Column() {
        Text('派一件活')
          .fontSize(18).fontWeight(FontWeight.Bold)
          .fontColor(Constants.COLOR_TEXT_PRIMARY).margin({ bottom: 16 })

        // 第二步：按住说话
        Button(this.recording ? '🎤 松开结束' : '🎤 按住说话')
          .type(ButtonType.Capsule)
          .fontSize(16).fontColor(Color.White)
          .backgroundColor(this.recording ? Constants.COLOR_DANGER : Constants.COLOR_PRIMARY)
          .width('100%').height(64)
          .gesture(
            LongPressGesture({ repeat: false, duration: 150 })
              .onAction(() => { this.startRecord(); })
              .onActionEnd(() => { this.stopRecord(); })
              .onActionCancel(() => { this.stopRecord(); })
          )

        if (this.recording || this.asrText.length > 0) {
          Text(this.asrText.length > 0 ? this.asrText : '请说话…')
            .fontSize(14).fontColor(Constants.COLOR_TEXT_SECONDARY)
            .width('100%').margin({ top: 12 })
        }

        if (this.extracting) {
          Row() {
            LoadingProgress().width(20).height(20).color(Constants.COLOR_PRIMARY)
            Text(' AI 识别中…').fontSize(13).fontColor(Constants.COLOR_TEXT_SECONDARY)
          }
          .margin({ top: 12 })
        }

        if (this.recordError.length > 0) {
          Text(this.recordError)
            .fontSize(12).fontColor(Constants.COLOR_DANGER)
            .width('100%').margin({ top: 8 })
        }

        // 第三步：审核（标题可编辑）
        Text('事项')
          .fontSize(14).fontColor(Constants.COLOR_TEXT_SECONDARY)
          .width('100%').margin({ top: 16, bottom: 8 })
        TextInput({ text: this.draftTitle, placeholder: '说完自动填，也可手动改' })
          .height(48)
          .backgroundColor(Constants.COLOR_BG)
          .borderRadius(10)
          .onChange((v: string) => { this.draftTitle = v; })

        Text('截止时间')
          .fontSize(14).fontColor(Constants.COLOR_TEXT_SECONDARY)
          .width('100%').margin({ top: 16, bottom: 8 })

        Row() {
          this.QuickTime('2分钟后', 2)
          this.QuickTime('1小时后', 60)
          this.QuickTime('今晚20点', -1)
          this.QuickTime('明早9点', -2)
        }
        .width('100%')
        .justifyContent(FlexAlign.SpaceBetween)

        Text(this.draftDeadline > 0 ? ('截止：' + Constants.formatDeadline(this.draftDeadline)) : '未设时间')
          .fontSize(13)
          .fontColor(this.draftDeadline > 0 ? Constants.COLOR_PRIMARY : Constants.COLOR_TEXT_SECONDARY)
          .width('100%').margin({ top: 10 })

        // 第四步：发送
        Row() {
          Button('取消')
            .type(ButtonType.Normal).fontColor(Constants.COLOR_TEXT_SECONDARY)
            .backgroundColor(Constants.COLOR_BG).layoutWeight(1).height(46)
            .borderRadius(10).margin({ right: 10 })
            .onClick(() => { this.showCreate = false; })
          Button('发送')
            .type(ButtonType.Normal).fontColor(Color.White)
            .backgroundColor(Constants.COLOR_PRIMARY).layoutWeight(1).height(46)
            .borderRadius(10)
            .onClick(() => { this.onSend(); })
        }
        .width('100%')
        .margin({ top: 20 })
      }
      .width('100%')
      .padding(20)
      .backgroundColor(Constants.COLOR_CARD_BG)
      .borderRadius({ topLeft: 18, topRight: 18 })
    }
    .width('100%')
    .height('100%')
    .backgroundColor('#66000000')
  }

  @Builder
  QuickTime(label: string, code: number) {
    Button(label)
      .type(ButtonType.Normal)
      .fontSize(12)
      .fontColor(Constants.COLOR_TEXT_PRIMARY)
      .backgroundColor(Constants.COLOR_BG)
      .height(38)
      .borderRadius(10)
      .layoutWeight(1)
      .margin({ right: code === -2 ? 0 : 6 })
      .onClick(() => { this.draftDeadline = Constants.quickDeadline(code); })
  }

  openCreate(): void {
    this.draftTitle = '';
    this.draftDeadline = 0;
    this.draftDetail = '';
    this.asrText = '';
    this.recording = false;
    this.extracting = false;
    this.recordError = '';
    this.showCreate = true;
  }

  async onSend(): Promise<void> {
    if (this.draftTitle.trim().length === 0) {
      this.toast('说点什么吧');
      return;
    }
    const t = new TaskItem();
    t.id = '' + Date.now() + '_' + Math.floor(Math.random() * 100000);
    t.familyId = AppConfig.FAMILY_ID;
    t.fromUserId = AppConfig.MY_USER_ID;
    t.toUserId = AppConfig.OTHER_USER_ID;
    t.rawText = this.asrText.trim().length > 0 ? this.asrText.trim() : this.draftTitle.trim();
    t.title = this.draftTitle.trim();
    t.detail = this.draftDetail;
    t.deadline = this.draftDeadline;
    t.status = TaskStatus.PENDING;
    t.reminder = new ReminderConfig();
    t.createdAt = Date.now();
    // 先存本地（离线也能用）
    await TaskStore.getInstance().upsert(t);
    this.showCreate = false;
    this.refresh();
    // 推送到中继做跨设备投递
    const saved = await RelayService.getInstance().create(t);
    if (saved !== null && saved.objectId.length > 0) {
      t.objectId = saved.objectId;
      await TaskStore.getInstance().upsert(t);
      this.refresh();
      this.toast('已发出');
    } else {
      this.toast('已存本地（中继未连上）');
    }
  }

  async onReceive(item: TaskItem): Promise<void> {
    item.status = TaskStatus.RECEIVED;
    item.receivedAt = Date.now();
    if (item.deadline > Date.now()) {
      try {
        const ctx = this.getUIContext().getHostContext() as common.UIAbilityContext;
        await ReminderService.getInstance().requestNotify(ctx);
        const titleForRing = item.title.length > 0 ? item.title : item.rawText;
        item.reminderIds = await ReminderService.getInstance().scheduleForTask(
          titleForRing, item.deadline, item.reminder.intervalMinutes, item.reminder.rampUpLastMinutes, item.id);
        this.toast('已收到，提醒已排 ' + item.reminderIds.length + ' 次');
      } catch (err) {
        const m = err instanceof Error ? err.message : JSON.stringify(err);
        this.recordError = '排提醒失败：' + m;
        this.toast('排提醒失败：' + m);
      }
    }
    await TaskStore.getInstance().upsert(item);
    await this.pushStatus(item);
    this.refresh();
  }

  async onNegotiate(item: TaskItem): Promise<void> {
    item.status = TaskStatus.NEGOTIATING;
    await TaskStore.getInstance().upsert(item);
    await this.pushStatus(item);
    this.refresh();
    this.toast('商量流程在 M5 接入');
  }

  async onDone(item: TaskItem): Promise<void> {
    await ReminderService.getInstance().cancelForTask(item.reminderIds);
    item.reminderIds = [];
    item.status = TaskStatus.DONE;
    item.doneAt = Date.now();
    await TaskStore.getInstance().upsert(item);
    await this.pushStatus(item);
    this.refresh();
  }

  async onDelete(item: TaskItem): Promise<void> {
    await ReminderService.getInstance().cancelForTask(item.reminderIds);
    await TaskStore.getInstance().remove(item.id);
    this.refresh();
  }

  async startRecord(): Promise<void> {
    const ok = await this.ensureMicPermission();
    if (!ok) {
      this.toast('需要麦克风权限');
      return;
    }
    this.asrText = '';
    this.recordError = '';
    this.recording = true;
    await AsrService.getInstance().start(
      (t: string) => { this.asrText = t; },
      (t: string) => { this.onAsrFinal(t); },
      (m: string) => { this.recording = false; this.recordError = m; }
    );
  }

  async stopRecord(): Promise<void> {
    if (!this.recording) {
      return;
    }
    this.recording = false;
    await AsrService.getInstance().stop();
  }

  async onAsrFinal(text: string): Promise<void> {
    this.asrText = text;
    const trimmed = text.trim();
    if (trimmed.length === 0) {
      return;
    }
    this.extracting = true;
    this.recordError = '';
    try {
      const r = await AIService.getInstance().extractTask(trimmed);
      this.draftTitle = r.title;
      this.draftDetail = r.detail;
      this.draftDeadline = r.deadline;
    } catch (err) {
      let msg: string = '';
      if (err instanceof Error) {
        msg = err.message;
      } else {
        msg = JSON.stringify(err);
      }
      this.recordError = 'AI 识别失败：' + msg;
      this.draftTitle = trimmed;
    } finally {
      this.extracting = false;
    }
  }

  private async ensureMicPermission(): Promise<boolean> {
    try {
      const atManager = abilityAccessCtrl.createAtManager();
      const ctx = this.getUIContext().getHostContext() as common.UIAbilityContext;
      const perms: Array<Permissions> = ['ohos.permission.MICROPHONE'];
      const res = await atManager.requestPermissionsFromUser(ctx, perms);
      return res.authResults.length > 0 && res.authResults[0] === 0;
    } catch (err) {
      return false;
    }
  }

  private toast(msg: string): void {
    try {
      this.getUIContext().getPromptAction().showToast({ message: msg });
    } catch (err) {
      // 忽略提示失败
    }
  }

  statusLabel(s: string): string {
    if (s === TaskStatus.PENDING) {
      return '待收到';
    }
    if (s === TaskStatus.RECEIVED) {
      return '进行中';
    }
    if (s === TaskStatus.NEGOTIATING) {
      return '商量中';
    }
    if (s === TaskStatus.DONE) {
      return '已完成';
    }
    return s;
  }

  statusColor(s: string): string {
    if (s === TaskStatus.RECEIVED) {
      return Constants.COLOR_PRIMARY;
    }
    if (s === TaskStatus.NEGOTIATING) {
      return Constants.COLOR_WARNING;
    }
    if (s === TaskStatus.DONE) {
      return Constants.COLOR_TEXT_SECONDARY;
    }
    return Constants.COLOR_PRIMARY_LIGHT;
  }
}
