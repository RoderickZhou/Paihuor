import { abilityAccessCtrl, common, Permissions } from '@kit.AbilityKit';
import { Constants } from '../constants/Constants';
import { TaskItem, TaskStatus, ReminderConfig, NegotiationMsg } from '../models/TaskModels';
import { TaskStore } from '../services/TaskStore';
import { AsrService } from '../services/AsrService';
import { AIService } from '../services/AIService';
import { ReminderService } from '../services/ReminderService';
import { RelayService } from '../services/RelayService';
import { NotificationService } from '../services/NotificationService';
import { updateAllCards } from '../services/WidgetCardData';
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
  // 归档区
  @State showArchive: boolean = false;
  @State archivedTasks: TaskItem[] = [];
  @State archivedCount: number = 0;
  @State doneUnarchivedCount: number = 0;
  // 编辑弹窗（仅新建方）
  @State showEdit: boolean = false;
  @State editTaskId: string = '';
  @State editTitle: string = '';
  @State editDetail: string = '';
  @State editDeadline: number = 0;
  private lastSync: number = 0;
  private pollTimer: number = -1;
  private firstPollDone: boolean = false; // 首轮只建立基线，不弹通知，避免启动刷屏

  async aboutToAppear(): Promise<void> {
    await TaskStore.getInstance().whenReady();
    this.refresh();
    this.startPolling();
    AsrService.getInstance().prewarm();
    // 申请通知权限（角标/横幅需要）
    try {
      const ctx = this.getUIContext().getHostContext() as common.UIAbilityContext;
      await NotificationService.getInstance().requestEnable(ctx);
    } catch (err) {
      // 忽略
    }
  }

  aboutToDisappear(): void {
    this.stopPolling();
  }

  refresh(): void {
    const store = TaskStore.getInstance();
    this.tasks = store.getActive();
    const arch = store.getArchived();
    this.archivedCount = arch.length;
    let doneU = 0;
    let unread = 0;
    for (let i = 0; i < this.tasks.length; i++) {
      const t = this.tasks[i];
      if (t.status === TaskStatus.DONE && !t.archived) {
        doneU++;
      }
      // 未读 = 派给我、还没点「收到」的活
      if (t.toUserId === AppConfig.MY_USER_ID && t.status === TaskStatus.PENDING) {
        unread++;
      }
    }
    this.doneUnarchivedCount = doneU;
    NotificationService.getInstance().setBadge(unread); // 桌面图标角标未读数
    // 推送桌面服务卡片更新（App 活着时近实时；无卡片则内部直接返回）
    try {
      const ctx = this.getUIContext().getHostContext() as common.Context;
      updateAllCards(ctx);
    } catch (err) {
      // 忽略
    }
    if (this.showArchive) {
      this.archivedTasks = arch;
    }
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
      this.firstPollDone = true;
      return;
    }
    let mx = this.lastSync;
    for (let i = 0; i < remote.length; i++) {
      if (remote[i].updatedAt > mx) {
        mx = remote[i].updatedAt;
      }
    }
    this.lastSync = mx;
    // 合并前记录已知 objectId，用来识别"新到的活"
    const beforeIds: string[] = [];
    const known = TaskStore.getInstance().getAll();
    for (let i = 0; i < known.length; i++) {
      beforeIds.push(known[i].objectId);
    }
    const orphan = await TaskStore.getInstance().mergeRemote(remote);
    // 远端删除的任务，撤掉本机为它排的提醒
    if (orphan.length > 0) {
      await ReminderService.getInstance().cancelForTask(orphan);
    }
    this.refresh();
    // 新到的、派给我的、未读(pending)活 → 弹本地通知（首轮只建基线、不弹，避免启动刷屏）
    if (this.firstPollDone) {
      const after = TaskStore.getInstance().getAll();
      for (let i = 0; i < after.length; i++) {
        const t = after[i];
        if (beforeIds.indexOf(t.objectId) < 0
          && t.toUserId === AppConfig.MY_USER_ID
          && t.status === TaskStatus.PENDING
          && !t.archived && !t.deleted) {
          await NotificationService.getInstance().notifyNewTask(this.displayName(t.fromUserId), t.title);
        }
      }
    }
    this.firstPollDone = true;
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
        // 顶部标题 + 归档入口
        Row() {
          Text('派活儿')
            .fontSize(24)
            .fontWeight(FontWeight.Bold)
            .fontColor(Constants.COLOR_TEXT_PRIMARY)
          Blank()
          if (this.doneUnarchivedCount > 0) {
            Text('归档已完成')
              .fontSize(13).fontColor(Constants.COLOR_PRIMARY)
              .padding({ left: 8, right: 8, top: 4, bottom: 4 })
              .margin({ right: 8 })
              .onClick(() => { this.onArchiveAllDone(); })
          }
          Text('归档 ' + this.archivedCount)
            .fontSize(13).fontColor(Constants.COLOR_TEXT_SECONDARY)
            .padding({ left: 10, right: 10, top: 5, bottom: 5 })
            .backgroundColor(Constants.COLOR_CARD_BG).borderRadius(8)
            .onClick(() => { this.openArchive(); })
        }
        .width('100%')
        .padding({ left: 20, right: 16, top: 16, bottom: 8 })

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
            }, (item: TaskItem) => item.id + '-' + item.status + '-' + item.deadline + '-' + item.updatedAt + '-' + item.receivedAt + '-' + item.doneAt + '-' + item.negotiation.length + '-' + item.archived + '-' + item.title)
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

      if (this.showEdit) {
        this.EditSheet()
      }

      if (this.showArchive) {
        this.ArchiveSheet()
      }
    }
    .width('100%')
    .height('100%')
  }

  // 滴答清单风格卡片：左侧勾选圈 + 标题(完成划线) + 截止(按紧急度变色)
  @Builder
  TaskCard(item: TaskItem) {
    Row() {
      this.CheckCircle(item)
      Column() {
        Row() {
          Text(item.title.length > 0 ? item.title : item.rawText)
            .fontSize(16)
            .fontWeight(FontWeight.Medium)
            .fontColor((item.status === TaskStatus.DONE || item.archived) ? Constants.COLOR_TEXT_SECONDARY : Constants.COLOR_TEXT_PRIMARY)
            .decoration({ type: (item.status === TaskStatus.DONE || item.archived) ? TextDecorationType.LineThrough : TextDecorationType.None })
            .maxLines(2).textOverflow({ overflow: TextOverflow.Ellipsis })
            .layoutWeight(1)
          Text(this.statusLabel(item.status))
            .fontSize(11)
            .fontColor(Color.White)
            .backgroundColor(this.statusColor(item.status))
            .borderRadius(6)
            .padding({ left: 7, right: 7, top: 2, bottom: 2 })
            .margin({ left: 8 })
        }
        .width('100%')

        if (item.detail.length > 0) {
          Text(item.detail)
            .fontSize(13).fontColor(Constants.COLOR_TEXT_SECONDARY)
            .maxLines(1).textOverflow({ overflow: TextOverflow.Ellipsis })
            .width('100%').margin({ top: 4 })
        }

        Row() {
          Text('🕑 ' + Constants.formatDeadline(item.deadline)
            + (item.status === TaskStatus.RECEIVED && item.deadline > 0 ? ('  ' + Constants.formatRemaining(item.deadline)) : ''))
            .fontSize(12).fontColor(this.deadlineColor(item))
        }
        .width('100%').margin({ top: 6 })

        if (item.negotiation.length > 0) {
          this.NegPreview(item)
        }

        this.ActionRow(item)
      }
      .layoutWeight(1)
      .alignItems(HorizontalAlign.Start)
    }
    .width('100%')
    .padding(14)
    .backgroundColor(Constants.COLOR_CARD_BG)
    .borderRadius(14)
    .shadow({ radius: 6, color: '#11000000', offsetY: 2 })
    .alignItems(VerticalAlign.Top)
    .opacity(item.archived ? 0.7 : 1)
  }

  // 左侧勾选圈：收到的活点圈即完成；已完成/归档显示绿色对勾
  @Builder
  CheckCircle(item: TaskItem) {
    Stack() {
      Column()
        .width(22).height(22).borderRadius(11)
        .border({ width: 2, color: this.circleColor(item) })
        .backgroundColor((item.status === TaskStatus.DONE || item.archived) ? Constants.COLOR_PRIMARY : Color.Transparent)
      if (item.status === TaskStatus.DONE || item.archived) {
        Text('✓').fontSize(13).fontColor(Color.White)
      }
    }
    .width(22).height(22).margin({ right: 12, top: 2 })
    .onClick(() => {
      if (item.status === TaskStatus.RECEIVED && this.isReceiver(item)) {
        this.onDone(item);
      }
    })
  }

  private circleColor(item: TaskItem): string {
    if (item.status === TaskStatus.DONE || item.archived || item.status === TaskStatus.RECEIVED) {
      return Constants.COLOR_PRIMARY;
    }
    if (item.status === TaskStatus.NEGOTIATING) {
      return Constants.COLOR_WARNING;
    }
    return Constants.COLOR_TEXT_SECONDARY;
  }

  private deadlineColor(item: TaskItem): string {
    if (!item.deadline || item.deadline <= 0 || item.status === TaskStatus.DONE || item.archived) {
      return Constants.COLOR_TEXT_SECONDARY;
    }
    const diff = item.deadline - Date.now();
    if (diff <= 0) {
      return Constants.COLOR_DANGER;
    }
    if (diff < 3600000) {
      return Constants.COLOR_WARNING;
    }
    return Constants.COLOR_TEXT_SECONDARY;
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

  // 卡片动作区：按 归档/状态/角色(新建方 vs 接收方) 决定显示哪些按钮
  @Builder
  ActionRow(item: TaskItem) {
    Row() {
      if (item.archived) {
        Button('取消归档')
          .type(ButtonType.Normal).fontSize(14).fontColor(Constants.COLOR_TEXT_PRIMARY)
          .backgroundColor(Constants.COLOR_BG).height(36).borderRadius(10)
          .padding({ left: 16, right: 16 }).margin({ right: 10 })
          .onClick(() => { this.onUnarchive(item); })
      } else if (item.status === TaskStatus.DONE) {
        Button('归档')
          .type(ButtonType.Normal).fontSize(14).fontColor(Color.White)
          .backgroundColor(Constants.COLOR_PRIMARY).height(36).borderRadius(10)
          .padding({ left: 16, right: 16 }).margin({ right: 10 })
          .onClick(() => { this.onArchive(item); })
      } else if (this.isReceiver(item)) {
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
      } else if (this.isCreator(item)) {
        // 新建方（fromUserId==我）：编辑 + 商量
        Button('编辑')
          .type(ButtonType.Normal).fontSize(14).fontColor(Constants.COLOR_PRIMARY)
          .backgroundColor(Constants.COLOR_BG).height(36).borderRadius(10)
          .borderWidth(1).borderColor(Constants.COLOR_PRIMARY)
          .padding({ left: 16, right: 16 }).margin({ right: 10 })
          .onClick(() => { this.openEdit(item); })
        this.NegBtn(item)
      }
      Blank()
      // 删除：仅新建方可删（软删，会同步移除对端）
      if (this.isCreator(item)) {
        this.DeleteBtn(item)
      }
    }
    .width('100%')
    .margin({ top: 12 })
  }

  @Builder
  DeleteBtn(item: TaskItem) {
    Text('删除')
      .fontSize(13)
      .fontColor(Constants.COLOR_DANGER)
      .padding(6)
      .onClick(() => { this.onDelete(item); })
  }

  @Builder
  EditSheet() {
    Column() {
      Column().layoutWeight(1).width('100%')

      Column() {
        Text('编辑任务')
          .fontSize(18).fontWeight(FontWeight.Bold)
          .fontColor(Constants.COLOR_TEXT_PRIMARY).margin({ bottom: 16 })

        Text('事项').fontSize(14).fontColor(Constants.COLOR_TEXT_SECONDARY)
          .width('100%').margin({ bottom: 8 })
        TextInput({ text: this.editTitle, placeholder: '任务标题' })
          .height(48).backgroundColor(Constants.COLOR_BG).borderRadius(10)
          .onChange((v: string) => { this.editTitle = v; })

        Text('细节').fontSize(14).fontColor(Constants.COLOR_TEXT_SECONDARY)
          .width('100%').margin({ top: 14, bottom: 8 })
        TextInput({ text: this.editDetail, placeholder: '补充细节（可空）' })
          .height(48).backgroundColor(Constants.COLOR_BG).borderRadius(10)
          .onChange((v: string) => { this.editDetail = v; })

        Text('截止时间').fontSize(14).fontColor(Constants.COLOR_TEXT_SECONDARY)
          .width('100%').margin({ top: 14, bottom: 8 })
        Row() {
          this.EditTimeChip('2分钟后', 2)
          this.EditTimeChip('1小时后', 60)
          this.EditTimeChip('今晚20点', -1)
          this.EditTimeChip('清除', 0)
        }
        .width('100%').justifyContent(FlexAlign.SpaceBetween)
        Text(this.editDeadline > 0 ? ('截止：' + Constants.formatDeadline(this.editDeadline)) : '未设时间')
          .fontSize(13)
          .fontColor(this.editDeadline > 0 ? Constants.COLOR_PRIMARY : Constants.COLOR_TEXT_SECONDARY)
          .width('100%').margin({ top: 10 })

        Row() {
          Button('取消')
            .type(ButtonType.Normal).fontColor(Constants.COLOR_TEXT_SECONDARY)
            .backgroundColor(Constants.COLOR_BG).layoutWeight(1).height(46)
            .borderRadius(10).margin({ right: 10 })
            .onClick(() => { this.closeEdit(); })
          Button('保存')
            .type(ButtonType.Normal).fontColor(Color.White)
            .backgroundColor(Constants.COLOR_PRIMARY).layoutWeight(1).height(46)
            .borderRadius(10)
            .onClick(() => { this.onSaveEdit(); })
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
  EditTimeChip(label: string, code: number) {
    Button(label)
      .type(ButtonType.Normal).fontSize(12).fontColor(Constants.COLOR_TEXT_PRIMARY)
      .backgroundColor(Constants.COLOR_BG).height(38).borderRadius(10).layoutWeight(1)
      .margin({ right: code === 0 ? 0 : 6 })
      .onClick(() => { this.setEditDeadline(code); })
  }

  @Builder
  ArchiveSheet() {
    Column() {
      Row() {
        Text('已归档')
          .fontSize(20).fontWeight(FontWeight.Bold).fontColor(Constants.COLOR_TEXT_PRIMARY)
        Blank()
        Text('关闭').fontSize(15).fontColor(Constants.COLOR_PRIMARY).padding(6)
          .onClick(() => { this.closeArchive(); })
      }
      .width('100%').padding({ left: 20, right: 16, top: 16, bottom: 8 })

      if (this.archivedTasks.length === 0) {
        Column() {
          Text('📦').fontSize(44).margin({ bottom: 10 })
          Text('还没有归档任务').fontSize(15).fontColor(Constants.COLOR_TEXT_SECONDARY)
        }
        .width('100%').layoutWeight(1).justifyContent(FlexAlign.Center)
      } else {
        List({ space: 12 }) {
          ForEach(this.archivedTasks, (item: TaskItem) => {
            ListItem() {
              this.TaskCard(item)
            }
          }, (item: TaskItem) => 'arc-' + item.id + '-' + item.archived + '-' + item.updatedAt + '-' + item.deadline + '-' + item.title)
        }
        .width('100%').layoutWeight(1)
        .padding({ left: 16, right: 16, top: 4, bottom: 40 })
        .scrollBar(BarState.Off)
      }
    }
    .width('100%').height('100%')
    .backgroundColor(Constants.COLOR_BG)
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
    // 采纳只改时间，不动状态机：patch 只发 deadline + negotiation，避免把对端 status 盖回
    if (item.objectId.length > 0) {
      const patch: Record<string, Object> = {
        'deadline': item.deadline,
        'negotiation': item.negotiation
      };
      await RelayService.getInstance().update(item.objectId, patch);
    }
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
    item.archived = true;            // 完成即自动归档，主列表保持清爽
    await TaskStore.getInstance().upsert(item);
    if (item.objectId.length > 0) {
      const patch: Record<string, Object> = {
        'status': item.status, 'doneAt': item.doneAt, 'archived': true
      };
      await RelayService.getInstance().update(item.objectId, patch);
    }
    this.refresh();
    this.toast('已完成并归档');
  }

  // 删除：仅新建方；二次确认后软删（中继置墓碑→对端轮询移除）
  onDelete(item: TaskItem): void {
    const name = item.title.length > 0 ? item.title : item.rawText;
    AlertDialog.show({
      title: '删除任务',
      message: '确定删除「' + name + '」？对方也会同步移除，不可恢复。',
      primaryButton: {
        value: '删除', fontColor: Constants.COLOR_DANGER,
        action: () => { this.doDelete(item); }
      },
      secondaryButton: { value: '取消', action: () => {} }
    });
  }

  private async doDelete(item: TaskItem): Promise<void> {
    await ReminderService.getInstance().cancelForTask(item.reminderIds);
    // 先通知中继软删（对端轮询到墓碑后本地移除），再删本机
    if (item.objectId.length > 0) {
      await RelayService.getInstance().remove(item.objectId);
    }
    await TaskStore.getInstance().remove(item.id);
    this.refresh();
    if (this.showArchive) {
      this.archivedTasks = TaskStore.getInstance().getArchived();
    }
    this.toast('已删除');
  }

  private isCreator(item: TaskItem): boolean {
    return item.fromUserId === AppConfig.MY_USER_ID;
  }

  private isReceiver(item: TaskItem): boolean {
    return item.toUserId === AppConfig.MY_USER_ID;
  }

  openArchive(): void {
    this.archivedTasks = TaskStore.getInstance().getArchived();
    this.showArchive = true;
  }

  closeArchive(): void {
    this.showArchive = false;
  }

  async onArchive(item: TaskItem): Promise<void> {
    item.archived = true;
    await TaskStore.getInstance().upsert(item);
    if (item.objectId.length > 0) {
      const patch: Record<string, Object> = { 'archived': true };
      await RelayService.getInstance().update(item.objectId, patch);
    }
    this.refresh();
  }

  async onUnarchive(item: TaskItem): Promise<void> {
    item.archived = false;
    await TaskStore.getInstance().upsert(item);
    if (item.objectId.length > 0) {
      const patch: Record<string, Object> = { 'archived': false };
      await RelayService.getInstance().update(item.objectId, patch);
    }
    this.refresh();
    this.archivedTasks = TaskStore.getInstance().getArchived();
  }

  // 一键归档所有"已完成但未归档"（清理历史 done 数据）
  async onArchiveAllDone(): Promise<void> {
    const all = TaskStore.getInstance().getActive();
    let n = 0;
    for (let i = 0; i < all.length; i++) {
      const it = all[i];
      if (it.status === TaskStatus.DONE && !it.archived) {
        it.archived = true;
        await TaskStore.getInstance().upsert(it);
        if (it.objectId.length > 0) {
          const patch: Record<string, Object> = { 'archived': true };
          await RelayService.getInstance().update(it.objectId, patch);
        }
        n++;
      }
    }
    this.refresh();
    this.toast(n > 0 ? ('已归档 ' + n + ' 条') : '没有待归档的已完成任务');
  }

  openEdit(item: TaskItem): void {
    this.editTaskId = item.id;
    this.editTitle = item.title;
    this.editDetail = item.detail;
    this.editDeadline = item.deadline;
    this.showEdit = true;
  }

  closeEdit(): void {
    this.showEdit = false;
  }

  setEditDeadline(code: number): void {
    this.editDeadline = code === 0 ? 0 : Constants.quickDeadline(code);
  }

  // 保存编辑（仅新建方）：改标题/细节/截止；若已收到且截止变了，重排提醒
  async onSaveEdit(): Promise<void> {
    const title = this.editTitle.trim();
    if (title.length === 0) {
      this.toast('标题不能为空');
      return;
    }
    const item = TaskStore.getInstance().getById(this.editTaskId);
    if (!item) {
      this.showEdit = false;
      return;
    }
    if (!this.isCreator(item)) {
      this.showEdit = false;
      this.toast('只有发起方能编辑');
      return;
    }
    const deadlineChanged = item.deadline !== this.editDeadline;
    item.title = title;
    item.detail = this.editDetail;
    item.deadline = this.editDeadline;
    if (deadlineChanged && item.status === TaskStatus.RECEIVED) {
      await ReminderService.getInstance().cancelForTask(item.reminderIds);
      item.reminderIds = [];
      if (item.deadline > Date.now()) {
        try {
          const titleForRing = item.title.length > 0 ? item.title : item.rawText;
          const ids = await ReminderService.getInstance().scheduleForTask(
            titleForRing, item.deadline, item.reminder.intervalMinutes, item.reminder.rampUpLastMinutes, item.id);
          item.reminderIds = ids;
        } catch (err) {
          // 重排失败静默
        }
      }
    }
    await TaskStore.getInstance().upsert(item);
    if (item.objectId.length > 0) {
      const patch: Record<string, Object> = {
        'title': item.title, 'detail': item.detail, 'deadline': item.deadline
      };
      await RelayService.getInstance().update(item.objectId, patch);
    }
    this.showEdit = false;
    this.refresh();
    this.toast('已保存');
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
