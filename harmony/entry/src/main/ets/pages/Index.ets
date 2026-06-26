import { abilityAccessCtrl, common, Permissions } from '@kit.AbilityKit';
import { Constants } from '../constants/Constants';
import { TaskItem, TaskStatus, ReminderConfig, NegotiationMsg } from '../models/TaskModels';
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
  // 商量弹窗状态
  @State showNegotiate: boolean = false;
  @State negTaskId: string = '';
  @State negTaskTitle: string = '';
  @State negMsgs: NegotiationMsg[] = [];
  @State negDeadlineShown: number = 0;
  @State negText: string = '';
  @State negProposedDeadline: number = 0;
  @State negProposedCode: number = 0;
  private lastSync: number = 0;
  private pollTimer: number = -1;

  async aboutToAppear(): Promise<void> {
    await TaskStore.getInstance().whenReady();
    this.refresh();
    this.startPolling();
    AsrService.getInstance().prewarm();
  }

  aboutToDisappear(): void {
    this.stopPolling();
  }

  refresh(): void {
    this.tasks = TaskStore.getInstance().getAll();
  }

  startPolling(): void {
    this.poll();
    // 8s 轮询：待办不需要秒级实时，省流量(免费穿透档)并降中继压力
    this.pollTimer = setInterval(() => { this.poll(); }, 8000);
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
    // 商量弹窗开着时，把对方刚发来的商量记录也同步进来
    if (this.showNegotiate) {
      this.reloadNeg();
    }
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
            }, (item: TaskItem) => item.id + '-' + item.status + '-' + item.deadline + '-' + item.updatedAt + '-' + item.receivedAt + '-' + item.doneAt + '-' + item.negotiation.length)
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

      if (this.showNegotiate) {
        this.NegotiationSheet()
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

      if (item.negotiation.length > 0) {
        this.NegPreview(item)
      }

      Row() {
        if (item.status === TaskStatus.PENDING) {
          Button('收到')
            .type(ButtonType.Normal).fontSize(14).fontColor(Color.White)
            .backgroundColor(Constants.COLOR_PRIMARY).height(36).borderRadius(10)
            .padding({ left: 16, right: 16 }).margin({ right: 10 })
            .onClick(() => { this.onReceive(item); })
          this.NegBtn(item)
        } else if (item.status === TaskStatus.RECEIVED) {
          Button('勾掉完成')
            .type(ButtonType.Normal).fontSize(14).fontColor(Color.White)
            .backgroundColor(Constants.COLOR_PRIMARY).height(36).borderRadius(10)
            .padding({ left: 16, right: 16 }).margin({ right: 10 })
            .onClick(() => { this.onDone(item); })
          this.NegBtn(item)
        } else if (item.status === TaskStatus.NEGOTIATING) {
          Button('改为收到')
            .type(ButtonType.Normal).fontSize(14).fontColor(Color.White)
            .backgroundColor(Constants.COLOR_PRIMARY).height(36).borderRadius(10)
            .padding({ left: 16, right: 16 }).margin({ right: 10 })
            .onClick(() => { this.onReceive(item); })
          this.NegBtn(item)
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
  NegBtn(item: TaskItem) {
    Button('商量')
      .type(ButtonType.Normal).fontSize(14).fontColor(Constants.COLOR_WARNING)
      .backgroundColor(Constants.COLOR_BG).height(36).borderRadius(10)
      .borderWidth(1).borderColor(Constants.COLOR_WARNING)
      .padding({ left: 16, right: 16 })
      .onClick(() => { this.openNegotiate(item); })
  }

  @Builder
  NegPreview(item: TaskItem) {
    Column() {
      Text('商量记录 · ' + item.negotiation.length + ' 条')
        .fontSize(12).fontColor(Constants.COLOR_TEXT_SECONDARY).width('100%')
      Text(this.displayName(item.negotiation[item.negotiation.length - 1].fromUserId) + '：'
        + item.negotiation[item.negotiation.length - 1].text)
        .fontSize(13).fontColor(Constants.COLOR_TEXT_PRIMARY).width('100%').margin({ top: 2 })
      if (item.negotiation[item.negotiation.length - 1].proposedDeadline > 0) {
        Text('建议改到 ' + Constants.formatDeadline(item.negotiation[item.negotiation.length - 1].proposedDeadline))
          .fontSize(12).fontColor(Constants.COLOR_PRIMARY).width('100%').margin({ top: 2 })
      }
    }
    .width('100%').padding(10).margin({ top: 10 })
    .backgroundColor(Constants.COLOR_BG).borderRadius(10)
    .alignItems(HorizontalAlign.Start)
  }

  @Builder
  NegotiationSheet() {
    Column() {
      Column().layoutWeight(1).width('100%')

      Column() {
        Row() {
          Text('商量一下')
            .fontSize(18).fontWeight(FontWeight.Bold)
            .fontColor(Constants.COLOR_TEXT_PRIMARY)
          Blank()
          Text('关闭')
            .fontSize(14).fontColor(Constants.COLOR_TEXT_SECONDARY).padding(4)
            .onClick(() => { this.closeNegotiate(); })
        }
        .width('100%').margin({ bottom: 12 })

        Text(this.negTaskTitle)
          .fontSize(16).fontWeight(FontWeight.Medium)
          .fontColor(Constants.COLOR_TEXT_PRIMARY).width('100%')
        Text('当前截止：' + Constants.formatDeadline(this.negDeadlineShown))
          .fontSize(13).fontColor(Constants.COLOR_TEXT_SECONDARY)
          .width('100%').margin({ top: 4 })

        if (this.negMsgs.length > 0) {
          List({ space: 8 }) {
            ForEach(this.negMsgs, (m: NegotiationMsg) => {
              ListItem() {
                this.NegMsgItem(m)
              }
            }, (m: NegotiationMsg) => m.at + '-' + m.fromUserId + '-' + m.proposedDeadline)
          }
          .width('100%')
          .constraintSize({ maxHeight: 200 })
          .margin({ top: 12 })
          .scrollBar(BarState.Off)
        } else {
          Text('还没有商量记录，先说一句吧')
            .fontSize(13).fontColor(Constants.COLOR_TEXT_SECONDARY)
            .width('100%').margin({ top: 12 })
        }

        TextInput({ text: this.negText, placeholder: '比如：能不能改到明早九点？' })
          .height(48).backgroundColor(Constants.COLOR_BG).borderRadius(10)
          .margin({ top: 12 })
          .onChange((v: string) => { this.negText = v; })

        Text('想改时间？')
          .fontSize(14).fontColor(Constants.COLOR_TEXT_SECONDARY)
          .width('100%').margin({ top: 14, bottom: 8 })
        Row() {
          this.NegTimeChip('1小时后', 60)
          this.NegTimeChip('今晚20点', -1)
          this.NegTimeChip('明早9点', -2)
          this.NegTimeChip('不改', 0)
        }
        .width('100%').justifyContent(FlexAlign.SpaceBetween)

        if (this.negProposedDeadline > 0) {
          Text('建议改到：' + Constants.formatDeadline(this.negProposedDeadline))
            .fontSize(13).fontColor(Constants.COLOR_PRIMARY)
            .width('100%').margin({ top: 10 })
        }

        Row() {
          Button('取消')
            .type(ButtonType.Normal).fontColor(Constants.COLOR_TEXT_SECONDARY)
            .backgroundColor(Constants.COLOR_BG).layoutWeight(1).height(46)
            .borderRadius(10).margin({ right: 10 })
            .onClick(() => { this.closeNegotiate(); })
          Button('发送')
            .type(ButtonType.Normal).fontColor(Color.White)
            .backgroundColor(this.negText.trim().length > 0 ? Constants.COLOR_PRIMARY : Constants.COLOR_PRIMARY_LIGHT)
            .layoutWeight(1).height(46).borderRadius(10)
            .enabled(this.negText.trim().length > 0)
            .onClick(() => { this.onSendNeg(); })
        }
        .width('100%').margin({ top: 20 })
      }
      .width('100%').padding(20)
      .backgroundColor(Constants.COLOR_CARD_BG)
      .borderRadius({ topLeft: 18, topRight: 18 })
    }
    .width('100%').height('100%')
    .backgroundColor('#66000000')
  }

  @Builder
  NegMsgItem(m: NegotiationMsg) {
    Column() {
      Row() {
        Text(this.displayName(m.fromUserId))
          .fontSize(13).fontWeight(FontWeight.Medium)
          .fontColor(m.fromUserId === AppConfig.MY_USER_ID ? Constants.COLOR_PRIMARY_DARK : Constants.COLOR_TEXT_PRIMARY)
        Blank()
        Text(Constants.formatDeadline(m.at))
          .fontSize(11).fontColor(Constants.COLOR_TEXT_SECONDARY)
      }
      .width('100%')
      Text(m.text)
        .fontSize(14).fontColor(Constants.COLOR_TEXT_PRIMARY)
        .width('100%').margin({ top: 4 })
      if (m.proposedDeadline > 0) {
        Row() {
          Text('建议改到 ' + Constants.formatDeadline(m.proposedDeadline))
            .fontSize(12).fontColor(Constants.COLOR_PRIMARY).layoutWeight(1)
          if (m.fromUserId !== AppConfig.MY_USER_ID && m.proposedDeadline !== this.negDeadlineShown) {
            Button('采纳')
              .type(ButtonType.Normal).fontSize(12).fontColor(Color.White)
              .backgroundColor(Constants.COLOR_PRIMARY).height(30).borderRadius(8)
              .padding({ left: 12, right: 12 })
              .onClick(() => { this.onAcceptProposed(m); })
          }
        }
        .width('100%').margin({ top: 6 })
      }
    }
    .width('100%').padding(10)
    .backgroundColor(Constants.COLOR_CARD_BG).borderRadius(10)
    .border({ width: 1, color: Constants.COLOR_BG })
    .alignItems(HorizontalAlign.Start)
  }

  @Builder
  NegTimeChip(label: string, code: number) {
    Button(label)
      .type(ButtonType.Normal).fontSize(12)
      .fontColor(this.negProposedCode === code ? Color.White : Constants.COLOR_TEXT_PRIMARY)
      .backgroundColor(this.negProposedCode === code ? Constants.COLOR_PRIMARY : Constants.COLOR_BG)
      .height(38).borderRadius(10).layoutWeight(1)
      .margin({ right: code === 0 ? 0 : 6 })
      .onClick(() => { this.setProposed(code); })
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
    // 收到要立即生效并同步，不被提醒排期拖累
    await TaskStore.getInstance().upsert(item);
    await this.pushStatus(item);
    this.refresh();
    this.toast('已收到');
    // 排提醒：能排就排，排不上(配额/权限)也静默，不影响"收到"
    if (item.deadline > Date.now()) {
      try {
        const ctx = this.getUIContext().getHostContext() as common.UIAbilityContext;
        await ReminderService.getInstance().requestNotify(ctx);
        const titleForRing = item.title.length > 0 ? item.title : item.rawText;
        const ids = await ReminderService.getInstance().scheduleForTask(
          titleForRing, item.deadline, item.reminder.intervalMinutes, item.reminder.rampUpLastMinutes, item.id);
        if (ids.length > 0) {
          item.reminderIds = ids;
          await TaskStore.getInstance().upsert(item);
        }
      } catch (err) {
        // 提醒排期失败(配额/权限)不影响收到，静默
      }
    }
  }

  openNegotiate(item: TaskItem): void {
    this.negTaskId = item.id;
    this.negTaskTitle = item.title.length > 0 ? item.title : item.rawText;
    this.negMsgs = item.negotiation.slice();
    this.negDeadlineShown = item.deadline;
    this.negText = '';
    this.negProposedDeadline = 0;
    this.negProposedCode = 0;
    this.showNegotiate = true;
  }

  closeNegotiate(): void {
    this.showNegotiate = false;
  }

  // 从本地存储重新载入当前商量任务（本机追加或对方轮询同步后刷新弹窗）
  private reloadNeg(): void {
    const item = TaskStore.getInstance().getById(this.negTaskId);
    if (!item) {
      return;
    }
    this.negMsgs = item.negotiation.slice();
    this.negDeadlineShown = item.deadline;
  }

  setProposed(code: number): void {
    this.negProposedCode = code;
    this.negProposedDeadline = code === 0 ? 0 : Constants.quickDeadline(code);
  }

  // 发一条商量：追加到 negotiation、置为商量中、撤掉旧提醒、同步中继
  async onSendNeg(): Promise<void> {
    const text = this.negText.trim();
    if (text.length === 0) {
      this.toast('说点什么吧');
      return;
    }
    const item = TaskStore.getInstance().getById(this.negTaskId);
    if (!item) {
      return;
    }
    const msg = new NegotiationMsg();
    msg.fromUserId = AppConfig.MY_USER_ID;
    msg.text = text;
    msg.proposedDeadline = this.negProposedDeadline;
    msg.at = Date.now();
    item.negotiation.push(msg);
    // 进入商量态：原有提醒可能因时间要变而过期，先撤掉，待重新「收到」再排
    if (item.status === TaskStatus.RECEIVED && item.reminderIds.length > 0) {
      await ReminderService.getInstance().cancelForTask(item.reminderIds);
      item.reminderIds = [];
    }
    item.status = TaskStatus.NEGOTIATING;
    await TaskStore.getInstance().upsert(item);
    this.negText = '';
    this.negProposedDeadline = 0;
    this.negProposedCode = 0;
    this.reloadNeg();
    this.refresh();
    await this.pushNegotiation(item);
  }

  // 采纳对方建议的新截止时间
  async onAcceptProposed(m: NegotiationMsg): Promise<void> {
    const item = TaskStore.getInstance().getById(this.negTaskId);
    if (!item || m.proposedDeadline <= 0) {
      return;
    }
    item.deadline = m.proposedDeadline;
    await TaskStore.getInstance().upsert(item);
    this.reloadNeg();
    this.refresh();
    await this.pushNegotiation(item);
    this.toast('已采纳新时间');
  }

  // 把商量记录/状态/截止时间整体推到中继（数组整段覆盖，两人量级足够）
  private async pushNegotiation(item: TaskItem): Promise<void> {
    if (item.objectId.length === 0) {
      return;
    }
    const patch: Record<string, Object> = {
      'status': item.status,
      'deadline': item.deadline,
      'negotiation': item.negotiation
    };
    await RelayService.getInstance().update(item.objectId, patch);
  }

  private displayName(userId: string): string {
    if (userId === 'wife') {
      return '老婆';
    }
    if (userId === 'husband') {
      return '老公';
    }
    return userId;
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
