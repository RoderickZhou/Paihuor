import { abilityAccessCtrl, common, Permissions } from '@kit.AbilityKit';
import { image } from '@kit.ImageKit';
import { util } from '@kit.ArkTS';
import { scanBarcode, scanCore } from '@kit.ScanKit';
import { Constants } from '../constants/Constants';
import { TaskItem, TaskStatus, ReminderConfig, NegotiationMsg, TaskImage, RepeatRule } from '../models/TaskModels';
import { TaskStore } from '../services/TaskStore';
import { AsrService } from '../services/AsrService';
import { AIService } from '../services/AIService';
import { ReminderService } from '../services/ReminderService';
import { RelayService } from '../services/RelayService';
import { ImageService } from '../services/ImageService';
import { NotificationService } from '../services/NotificationService';
import { DeviceService } from '../services/DeviceService';
import { updateAllCards } from '../services/WidgetCardData';
import { AppConfig } from '../config/AppConfig';
import { FamilyProfile, FamilyRole } from '../models/FamilyProfile';
import { ProfileService } from '../services/ProfileService';
import { InboxGroup, InboxOrder } from '../models/InboxOrder';
import { HouseholdCard, householdTask } from '../models/HouseholdCard';
import { HouseholdBoard } from './HouseholdBoard';

@Entry
@Component
struct Index {
  @State tasks: TaskItem[] = [];
  @State showCreate: boolean = false;
  @State draftTitle: string = '';
  @State draftDeadline: number = 0;
  @State draftDetail: string = '';
  @State draftRepeatKind: string = '';
  @State draftRepeatDays: string = '7';
  @State recording: boolean = false;
  @State transcribing: boolean = false;
  @State asrText: string = '';
  @State extracting: boolean = false;
  @State recordError: string = '';
  // 新建任务的图片附件：draftImages=已上传元数据，draftThumbs=本端预览缩略图（同序）
  @State draftImages: TaskImage[] = [];
  @State draftThumbs: image.PixelMap[] = [];
  @State uploadingImg: boolean = false;
  // 详情里对方图片解码后的 PixelMap（随下载逐张出现）
  @State detailImages: (image.PixelMap | null)[] = [];
  @State detailImgLoading: boolean = false;
  // 全屏看图
  @State previewImage: image.PixelMap | null = null;
  // 商量弹窗状态
  @State showNegotiate: boolean = false;
  @State negTaskId: string = '';
  @State negTaskTitle: string = '';
  @State negMsgs: NegotiationMsg[] = [];
  @State negDeadlineShown: number = 0;
  @State negText: string = '';
  @State negProposedDeadline: number = 0;
  @State negProposedCode: number = 0;
  // 主屏面板：收集箱 / 归档，和 iOS 一样在同一页内切换
  @State selectedBoard: string = 'inbox';
  @State showHousehold: boolean = false;
  @State householdCards: HouseholdCard[] = [];
  @State householdFailed: boolean = false;
  @State householdLoading: boolean = true;
  @State openedHouseholdCard: string = '';
  private householdFamily: string = '';
  private householdFetching: boolean = false;
  @State directionFilter: string = 'all';
  @State archivedTasks: TaskItem[] = [];
  @State archivedCount: number = 0;
  @State doneUnarchivedCount: number = 0;
  // 编辑弹窗（仅新建方）
  @State showEdit: boolean = false;
  @State editTaskId: string = '';
  @State editTitle: string = '';
  @State editDetail: string = '';
  @State editDeadline: number = 0;
  // 任务详情半屏
  @State showDetail: boolean = false;
  @State detailTaskId: string = '';
  @State profileReady: boolean = false;
  @State profileConfigured: boolean = false;
  @State showProfileSetup: boolean = false;
  @State familyId: string = '';
  @State myUserId: string = '';
  @State otherUserId: string = '';
  @State setupFamilyId: string = AppConfig.FAMILY_ID;
  @State setupUserId: string = '';
  @State setupUserName: string = '';
  @State showPairingQr: boolean = false;
  @State pairingHealth: string = '';
  @State savingDraft: boolean = false;
  private lastSync: number = 0;
  private boardNow: number = 0;
  private boardTomorrow: number = 0;
  private syncRunning: boolean = false;
  private syncGeneration: number = 0;
  private pollTimer: number = -1;
  private sessionStartedAt: number = Date.now();
  private notifiedObjectIds: string[] = [];
  private firstPollDone: boolean = false; // 首轮只建立基线，不弹通知，避免启动刷屏
  private voiceAttempt: number = 0;
  private voiceTimer: number = -1;
  private draftTranscript: string = '';
  private finalTranscript: string | null = null;

  async aboutToAppear(): Promise<void> {
    const ctx = this.getUIContext().getHostContext() as common.UIAbilityContext;
    await ProfileService.getInstance().init(ctx);
    const profile = ProfileService.getInstance().getProfile();
    this.profileReady = true;
    if (!profile) {
      this.profileConfigured = false;
      return;
    }
    this.applyProfile(profile);
    await this.startProfileSession(ctx);
  }

  private async startProfileSession(ctx: common.UIAbilityContext, changed: boolean = false): Promise<void> {
    await TaskStore.getInstance().whenReady();
    // 申请通知权限（角标/横幅需要）
    try {
      const enabled = await NotificationService.getInstance().ensureEnabled(ctx);
      if (!enabled) {
        this.toast('请允许通知，否则新任务不会弹窗');
      }
    } catch (err) {
      // 忽略
    }
    this.refresh();
    this.startPolling();
    DeviceService.getInstance().ensureRegisteredToken(changed);
    AsrService.getInstance().prewarm();
  }

  aboutToDisappear(): void {
    this.cancelVoice();
    this.stopPolling();
  }

  onPageHide(): void {
    if (this.recording) this.cancelVoice();
  }

  onPageShow(): void {
    this.poll();
    this.refreshHousehold();
  }

  onBackPress(): boolean {
    if (this.showHousehold) { this.showHousehold = false; return true; }
    if (!this.showCreate) return false;
    this.closeCreate();
    return true;
  }

  refresh(): void {
    const store = TaskStore.getInstance();
    const active = store.getActive().filter((t: TaskItem) => this.isRelevantTask(t));
    const arch = store.getArchived().filter((t: TaskItem) => this.isRelevantTask(t));
    this.archivedCount = arch.length;
    let doneU = 0;
    let unread = 0;
    for (let i = 0; i < active.length; i++) {
      const t = active[i];
      if (t.status === TaskStatus.DONE && !t.archived) {
        doneU++;
      }
      // 未读 = 派给我、还没点「收到」的活
      if (t.toUserId === this.myUserId && t.status === TaskStatus.PENDING) {
        unread++;
      }
    }
    this.doneUnarchivedCount = doneU;
    this.archivedTasks = arch;
    const board = this.selectedBoard === 'archive' ? arch : active;
    if (this.selectedBoard === 'inbox' && this.directionFilter !== 'outgoing' && this.householdFamily === this.familyId) {
      this.householdCards.filter((card: HouseholdCard) => card.status === 'claimed' && card.assignee === this.myUserId)
        .forEach((card: HouseholdCard) => { board.push(householdTask(card)); });
    }
    const visible = board.filter((t: TaskItem) => this.directionFilter === 'all'
      || (this.directionFilter === 'incoming' ? t.toUserId === this.myUserId : t.fromUserId === this.myUserId));
    this.boardNow = Date.now();
    this.boardTomorrow = InboxOrder.tomorrow(this.boardNow);
    this.tasks = this.selectedBoard === 'archive' ? visible : InboxOrder.sort(visible, this.myUserId, this.boardNow, this.boardTomorrow);
    NotificationService.getInstance().setBadge(unread); // 桌面图标角标未读数
    // 推送桌面服务卡片更新（App 活着时近实时；无卡片则内部直接返回）
    try {
      const ctx = this.getUIContext().getHostContext() as common.Context;
      updateAllCards(ctx);
    } catch (err) {
      // 忽略
    }
  }

  startPolling(): void {
    this.poll();
    this.refreshHousehold();
    // 8s 轮询：待办不需要秒级实时，省流量(免费穿透档)并降中继压力
    this.pollTimer = setInterval(() => { this.poll(); this.refreshHousehold(); }, 8000);
  }

  private openHousehold(id: string = ''): void {
    this.openedHouseholdCard = id;
    this.showHousehold = true;
    this.refreshHousehold();
  }

  private async refreshHousehold(): Promise<void> {
    const family = this.familyId;
    if (!this.profileConfigured || !family || this.householdFetching) return;
    if (family !== this.householdFamily) {
      this.householdFamily = family;
      this.householdCards = [];
      this.householdLoading = true;
      this.householdFailed = false;
    }
    this.householdFetching = true;
    try {
      const cards = await RelayService.getInstance().household(family);
      if (family !== this.familyId) return;
      this.householdFailed = cards === null;
      this.householdLoading = false;
      if (cards && (cards.length !== this.householdCards.length || cards.some((card: HouseholdCard, i: number) =>
        card.id !== this.householdCards[i].id || card.revision !== this.householdCards[i].revision))) {
        this.householdCards = cards;
        this.refresh();
      }
    } finally {
      this.householdFetching = false;
      if (family !== this.familyId) this.refreshHousehold();
    }
  }

  stopPolling(): void {
    if (this.pollTimer >= 0) {
      clearInterval(this.pollTimer);
      this.pollTimer = -1;
    }
  }

  // 轮询中继，把对方建/改的任务合并到本地
  async poll(): Promise<void> {
    if (this.syncRunning || !this.profileConfigured || !RelayService.getInstance().enabled()) {
      return;
    }
    this.syncRunning = true;
    const generation = this.syncGeneration;
    try {
      await this.syncTasks(this.familyId, this.myUserId, generation);
    } catch (err) {
      // The unchanged cursor and queued tasks are retried on the next poll.
    } finally {
      this.syncRunning = false;
      if (generation !== this.syncGeneration) this.poll();
    }
  }

  private async syncTasks(family: string, role: string, generation: number): Promise<void> {
    const store = TaskStore.getInstance();
    const relay = RelayService.getInstance();
    const pending = store.getAll().filter((t: TaskItem) => t.familyId === family && t.fromUserId === role && this.isQueued(t));
    for (const task of pending) {
      if (generation !== this.syncGeneration) return;
      const saved = await relay.create(task);
      if (!saved || saved.objectId.length === 0) break;
      await store.finishSending(task, saved);
      this.refresh();
    }
    if (generation !== this.syncGeneration) return;
    const remote = await relay.list(family, this.lastSync);
    if (remote === null || generation !== this.syncGeneration) return;
    if (remote.length === 0) {
      const now = Date.now();
      const tomorrow = InboxOrder.tomorrow(now);
      if (this.selectedBoard === 'inbox' && this.tasks.some((t: TaskItem) => t.deadline > 0
        && InboxOrder.group(t, this.myUserId, this.boardNow, this.boardTomorrow)
          !== InboxOrder.group(t, this.myUserId, now, tomorrow))) this.refresh();
      this.firstPollDone = true;
      await this.reportSync(family, role);
      return;
    }
    let mx = this.lastSync;
    for (let i = 0; i < remote.length; i++) {
      if (remote[i].updatedAt > mx) {
        mx = remote[i].updatedAt;
      }
    }
    // 合并前记录已知 objectId，用来识别"新到的活"
    const beforeIds: string[] = [];
    const known = TaskStore.getInstance().getAll();
    for (let i = 0; i < known.length; i++) {
      beforeIds.push(known[i].objectId);
    }
    const orphan = await TaskStore.getInstance().mergeRemote(remote);
    if (generation !== this.syncGeneration) return;
    this.lastSync = mx;
    // 远端删除的任务，撤掉本机为它排的提醒
    if (orphan.length > 0) {
      await ReminderService.getInstance().cancelForTask(orphan);
    }
    this.refresh();
    // 新到的、派给我的、未读(pending)活 → 弹本地通知。
    // 首轮只压住很老的历史待办；最近新到的任务仍然提醒，避免首次同步只出现角标不弹窗。
    const after = TaskStore.getInstance().getAll();
    for (let i = 0; i < after.length; i++) {
      const t = after[i];
      const notifyKey = t.objectId.length > 0 ? t.objectId : t.id;
      if (beforeIds.indexOf(t.objectId) < 0
        && this.notifiedObjectIds.indexOf(notifyKey) < 0
        && this.shouldNotifyNewTask(t)
        && this.canNotifyOnThisPoll(t)) {
        await NotificationService.getInstance().notifyNewTask(this.displayName(t.fromUserId), t.title);
        this.notifiedObjectIds.push(notifyKey);
      }
    }
    this.firstPollDone = true;
    // 商量弹窗开着时，把对方刚发来的商量记录也同步进来
    if (this.showNegotiate) {
      this.reloadNeg();
    }
    if (generation === this.syncGeneration) await this.reportSync(family, role);
  }

  private async reportSync(family: string, role: string): Promise<void> {
    const ids = TaskStore.getInstance().getAll().filter((t: TaskItem) => t.familyId === family && t.toUserId === role
      && !t.deleted && !t.recipientSyncedAt && /^[0-9a-f]{8}(-[0-9a-f]{4}){3}-[0-9a-f]{12}$/i.test(t.objectId))
      .slice(0, 100).map((t: TaskItem) => t.objectId);
    const device = ProfileService.getInstance().deviceId();
    if (device.length > 0) await RelayService.getInstance().acknowledge(family, role, device, ids);
  }

  private shouldNotifyNewTask(t: TaskItem): boolean {
    return t.toUserId === this.myUserId
      && t.status === TaskStatus.PENDING
      && !t.archived
      && !t.deleted && !t.repeat?.generated;
  }

  private canNotifyOnThisPoll(t: TaskItem): boolean {
    if (this.firstPollDone) {
      return true;
    }
    const recentCutoff = this.sessionStartedAt - 10 * 60 * 1000;
    return t.createdAt >= recentCutoff || t.updatedAt >= recentCutoff;
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

  private applyProfile(profile: FamilyProfile): void {
    this.familyId = profile.familyId;
    this.myUserId = profile.userId;
    this.otherUserId = profile.counterpartUserId();
    this.setupFamilyId = profile.familyId;
    this.setupUserId = profile.userId;
    this.setupUserName = profile.displayName();
    this.profileConfigured = true;
  }

  private isRelevantTask(item: TaskItem): boolean {
    const profile = ProfileService.getInstance().getProfile();
    return profile !== null
      && profile.isTaskRelevant(item.familyId, item.fromUserId, item.toUserId);
  }

  private canSaveProfile(): boolean {
    return this.setupFamilyId.trim().length > 0 && this.setupFamilyId.trim().length <= 120
      && (this.setupUserId === FamilyRole.WIFE || this.setupUserId === FamilyRole.HUSBAND);
  }

  private openProfileSettings(): void {
    const profile = ProfileService.getInstance().getProfile();
    if (profile) {
      this.setupFamilyId = profile.familyId;
      this.setupUserId = profile.userId;
      this.setupUserName = profile.displayName();
    }
    this.showProfileSetup = true;
    this.showPairingQr = false;
    this.pairingHealth = '正在检查同步…';
    this.loadPairingStatus();
  }

  private async loadPairingStatus(): Promise<void> {
    const status = await RelayService.getInstance().syncStatus(this.familyId, this.myUserId);
    if (!this.showProfileSetup) return;
    this.pairingHealth = status ? '本机同步：' + this.syncTime(status.selfSyncedAt)
      + '\n对方同步：' + this.syncTime(status.peerSyncedAt)
      + '\n本机推送：' + (status.selfPushRegistered ? '已登记' : '未登记') : '无法检查中继连接';
  }

  private syncTime(time: number): string {
    return time > 0 ? Constants.formatDeadline(time) : '暂无记录';
  }

  private async scanPairing(): Promise<void> {
    try {
      const ctx = this.getUIContext().getHostContext() as common.UIAbilityContext;
      const result = await scanBarcode.startScanForResult(ctx, { scanTypes: [scanCore.ScanType.QR_CODE] });
      const match = /^paihuor:pair:1:(wife|husband):(.+)$/.exec(result.originalValue);
      if (!match) { this.toast('这不是派活儿家庭二维码'); return; }
      const family = decodeURIComponent(match[2]).trim();
      if (family.length === 0 || family.length > 120) { this.toast('家庭码无效'); return; }
      this.setupFamilyId = family;
      this.setupUserId = match[1];
      this.toast('请核对家庭码和身份后保存');
    } catch (err) {
      this.toast('扫码未完成');
    }
  }

  private pairingCode(): string {
    return 'paihuor:pair:1:' + this.otherUserId + ':' + encodeURIComponent(this.familyId);
  }

  private async saveProfile(): Promise<void> {
    if (!this.canSaveProfile()) {
      return;
    }
    try {
      const profile = await ProfileService.getInstance().save(
        this.setupFamilyId, this.setupUserId, this.setupUserName);
      this.stopPolling();
      this.syncGeneration++;
      this.lastSync = 0;
      this.firstPollDone = false;
      this.notifiedObjectIds = [];
      this.sessionStartedAt = Date.now();
      this.applyProfile(profile);
      this.showProfileSetup = false;
      const ctx = this.getUIContext().getHostContext() as common.UIAbilityContext;
      await this.startProfileSession(ctx, true);
      this.toast('家庭身份已保存');
    } catch (err) {
      this.toast('保存失败，请检查家庭配对码');
    }
  }

  build() {
    if (!this.profileReady) {
      Column() {
        Text('派活儿').fontSize(30).fontWeight(FontWeight.Bold).fontColor(Constants.COLOR_TEXT_PRIMARY)
        Text('正在准备家庭信息').fontSize(15).fontColor(Constants.COLOR_TEXT_SECONDARY).margin({ top: 10 })
        LoadingProgress().width(34).height(34).color(Constants.COLOR_PRIMARY).margin({ top: 24 })
      }
      .width('100%').height('100%')
      .justifyContent(FlexAlign.Center).alignItems(HorizontalAlign.Center)
      .backgroundColor(Constants.COLOR_BG)
    } else if (!this.profileConfigured) {
      this.ProfileSetup(false)
    } else {
      this.MainContent()
    }
  }

  @Builder
  MainContent() {
    Stack({ alignContent: Alignment.BottomEnd }) {
      Column() {
        // 顶部标题 + 快捷入口
        Row() {
          this.SettingsIcon()
          Text(this.boardTitle())
            .fontSize(28)
            .fontWeight(FontWeight.Bold)
            .fontColor(Constants.COLOR_TEXT_PRIMARY)
            .margin({ left: 14 })
          Blank()
          if (this.doneUnarchivedCount > 0) {
            Text('归档已完成')
              .fontSize(13).fontColor(Constants.COLOR_PRIMARY)
              .padding({ left: 8, right: 8, top: 4, bottom: 4 })
              .margin({ right: 8 })
              .onClick(() => { this.onArchiveAllDone(); })
          }
        }
        .width('100%')
        .padding({ left: 24, right: 24, top: 16, bottom: 14 })

        Row({ space: 4 }) {
          this.DirectionButton('all', '全部')
          this.DirectionButton('incoming', '派给我')
          this.DirectionButton('outgoing', '我派出')
        }
        .width('100%').padding({ left: 18, right: 18, bottom: 8 })

        if (this.tasks.length === 0) {
          this.EmptyState()
        } else {
          List({ space: 12 }) {
            ForEach(this.tasks, (item: TaskItem, index: number) => {
              ListItem() {
                Column() {
                  if (this.selectedBoard === 'inbox' && this.startsInboxGroup(item, index)) {
                    Text(this.inboxGroupLabel(item)).fontSize(13).fontWeight(FontWeight.Medium)
                      .fontColor(this.inboxGroup(item) === InboxGroup.OVERDUE ? '#B43D45' : '#596274')
                      .width('100%').padding({ left: 2, bottom: 8, top: 4 })
                  }
                  this.TaskCard(item)
                }
              }
              .swipeAction({ end: this.SwipeEnd(item) })
            }, (item: TaskItem, index: number) => item.id + '-' + item.status + '-' + item.deadline + '-' + item.updatedAt + '-' + item.receivedAt + '-' + item.doneAt + '-' + item.negotiation.length + '-' + item.archived + '-' + item.title + '-' + this.inboxGroup(item) + '-' + this.startsInboxGroup(item, index))
          }
          .width('100%')
          .layoutWeight(1)
          .padding({ left: 18, right: 18, top: 4, bottom: 132 })
          .scrollBar(BarState.Off)
        }
      }
      .width('100%')
      .height('100%')
      .backgroundColor(Constants.COLOR_BG)

      this.BottomDock()

      // 右下角悬浮「＋」
      Button() {
        Text('＋').fontSize(34).fontColor(Color.White)
      }
      .width(66)
      .height(66)
      .borderRadius(33)
      .backgroundColor(Constants.COLOR_PRIMARY)
      .margin({ right: 30, bottom: 106 })
      .shadow({ radius: 14, color: '#33477CFF', offsetY: 8 })
      .onClick(() => {
        this.openCreate();
      })

      if (this.showDetail) {
        this.TaskDetailSheet(this.currentDetailTask())
      }

      if (this.showCreate) {
        this.CreateSheet()
      }

      if (this.showNegotiate) {
        this.NegotiationSheet()
      }

      if (this.showEdit) {
        this.EditSheet()
      }

      if (this.previewImage != null) {
        this.ImagePreviewOverlay()
      }

      if (this.showProfileSetup) {
        this.ProfileSetup(true)
      }

      if (this.showHousehold) {
        HouseholdBoard({ cards: this.householdCards, family: this.familyId, user: this.myUserId,
          openedCard: this.openedHouseholdCard, failed: this.householdFailed, loading: this.householdLoading,
          onClose: () => { this.showHousehold = false; }, onRefresh: () => { this.refreshHousehold(); } })
      }

    }
    .width('100%')
    .height('100%')
  }

  @Builder
  ProfileSetup(canCancel: boolean) {
    Scroll() {
    Column() {
      Row() {
        if (canCancel) {
          Button('取消')
            .type(ButtonType.Normal)
            .fontColor(Constants.COLOR_TEXT_SECONDARY)
            .backgroundColor(Color.Transparent)
            .onClick(() => { this.showProfileSetup = false; })
        }
        Blank()
        Text(canCancel ? '家庭设置' : '欢迎使用派活儿')
          .fontSize(24).fontWeight(FontWeight.Bold).fontColor(Constants.COLOR_TEXT_PRIMARY)
        Blank()
        if (canCancel) {
          Text('完成').fontSize(15).fontColor(Color.Transparent)
        }
      }
      .width('100%')

      Row({ space: 8 }) {
        Button('扫码配对').layoutWeight(1).height(42).onClick(() => { this.scanPairing(); })
        if (canCancel) {
          Button(this.showPairingQr ? '收起二维码' : '家庭二维码')
            .layoutWeight(1).height(42)
            .onClick(() => { this.showPairingQr = !this.showPairingQr; })
        }
      }
      .width('100%').margin({ top: 14, bottom: 18 })
      if (canCancel && this.showPairingQr) {
        QRCode(this.pairingCode()).width(208).height(208).backgroundColor(Color.White)
          .margin({ bottom: 18 })
      }

      Text('家庭配对码').fontSize(14).fontWeight(FontWeight.Medium).fontColor(Constants.COLOR_TEXT_PRIMARY)
        .width('100%').textAlign(TextAlign.Start)
      TextInput({ placeholder: '例如 1217', text: this.setupFamilyId })
        .height(52).fontSize(16).margin({ top: 8, bottom: 24 })
        .backgroundColor(Color.White).borderRadius(8)
        .fontColor(Color.Black).placeholderColor('#656B77').caretColor(Constants.COLOR_PRIMARY)
        .selectAll(true).maxLength(120)
        .onChange((value: string) => { this.setupFamilyId = value; })

      Text('我是').fontSize(14).fontWeight(FontWeight.Medium).fontColor(Constants.COLOR_TEXT_PRIMARY)
        .width('100%').textAlign(TextAlign.Start)
      Row({ space: 12 }) {
        this.RoleButton(FamilyRole.HUSBAND, '老公')
        this.RoleButton(FamilyRole.WIFE, '老婆')
      }
      .width('100%').margin({ top: 8, bottom: 24 })

      Text('显示名称（可选）').fontSize(14).fontWeight(FontWeight.Medium).fontColor(Constants.COLOR_TEXT_PRIMARY)
        .width('100%').textAlign(TextAlign.Start)
      TextInput({ placeholder: this.setupUserId === FamilyRole.WIFE ? '老婆' : '老公', text: this.setupUserName })
        .height(52).fontSize(16).margin({ top: 8 })
        .backgroundColor(Color.White).borderRadius(8)
        .fontColor(Color.Black).placeholderColor('#656B77').caretColor(Constants.COLOR_PRIMARY)
        .onChange((value: string) => { this.setupUserName = value; })

      Button('保存并继续')
        .type(ButtonType.Normal).fontSize(16).fontColor(Color.White)
        .width('100%').height(52).borderRadius(8)
        .backgroundColor(this.canSaveProfile() ? Constants.COLOR_PRIMARY : Constants.COLOR_TEXT_SECONDARY)
        .margin({ top: 32 })
        .enabled(this.canSaveProfile())
        .onClick(() => { this.saveProfile(); })
      if (canCancel && this.pairingHealth.length > 0) {
        Text(this.pairingHealth).fontSize(14).lineHeight(22).width('100%')
          .fontColor(Constants.COLOR_TEXT_SECONDARY).margin({ top: 16 })
      }
    }
    .width('100%')
    .padding({ left: 28, right: 28, top: 34, bottom: 30 })
    }
    .width('100%').height('100%').align(Alignment.Top).scrollBar(BarState.Off)
    .backgroundColor(Constants.COLOR_BG)
  }

  @Builder
  DirectionButton(key: string, label: string) {
    Button(label).type(ButtonType.Normal).height(40).layoutWeight(1).borderRadius(8).fontSize(14)
      .backgroundColor(this.directionFilter === key ? '#DDE6FF' : Color.Transparent)
      .fontColor(this.directionFilter === key ? Constants.COLOR_PRIMARY : Constants.COLOR_TEXT_PRIMARY)
      .accessibilitySelected(this.directionFilter === key)
      .onClick(() => { this.directionFilter = key; this.refresh(); })
  }

  private inboxGroup(item: TaskItem): InboxGroup {
    return InboxOrder.group(item, this.myUserId, this.boardNow, this.boardTomorrow);
  }

  private startsInboxGroup(item: TaskItem, index: number): boolean {
    return this.selectedBoard === 'inbox' && (index === 0 || this.inboxGroup(item) !== this.inboxGroup(this.tasks[index - 1]));
  }

  private inboxGroupLabel(item: TaskItem): string {
    switch (this.inboxGroup(item)) {
      case InboxGroup.OVERDUE: return '已超时';
      case InboxGroup.TODAY: return '今天到期';
      case InboxGroup.WAITING: return '待我接下';
      default: return '其他任务';
    }
  }

  @Builder
  RoleButton(userId: string, label: string) {
    Button(label)
      .type(ButtonType.Normal).fontSize(16).fontWeight(FontWeight.Medium)
      .fontColor(this.setupUserId === userId ? Color.White : Constants.COLOR_TEXT_PRIMARY)
      .layoutWeight(1).height(52).borderRadius(8)
      .backgroundColor(this.setupUserId === userId ? Constants.COLOR_PRIMARY : Color.White)
      .onClick(() => {
        this.setupUserId = userId;
        if (this.setupUserName.trim().length === 0) {
          this.setupUserName = FamilyRole.displayName(userId);
        }
      })
  }

  // 全屏看图：点任意处关闭
  @Builder
  ImagePreviewOverlay() {
    Stack() {
      Image(this.previewImage)
        .objectFit(ImageFit.Contain)
        .width('100%')
        .height('100%')
    }
    .width('100%')
    .height('100%')
    .backgroundColor('#E6000000')
    .onClick(() => { this.previewImage = null; })
  }

  @Builder
  SettingsIcon() {
    Stack() {
      Column()
        .width(52)
        .height(52)
        .borderRadius(26)
        .backgroundColor('#CCFFFFFF')
      Image($r('app.media.ic_top_menu')).width(26).height(26)
    }
    .width(52)
    .height(52)
    .accessibilityText('家庭设置')
    .onClick(() => { this.openProfileSettings(); })
  }

  @Builder
  BottomDock() {
    Row() {
      Row() {
        this.DockInboxIcon()
        Stack() {
          Image($r('app.media.ic_top_grid')).width(26).height(26)
        }
        .width(48).height(48).accessibilityText('家里待办')
        .onClick(() => { this.openHousehold(); })
        this.DockArchiveIcon()
        Stack() {
          Image($r('app.media.ic_refresh')).width(30).height(30)
        }
        .width(48).height(48).accessibilityText('刷新')
        .onClick(() => { this.poll(); this.refresh(); this.refreshHousehold(); })
      }
      .width('86%')
      .height(68)
      .justifyContent(FlexAlign.SpaceAround)
      .padding({ left: 22, right: 22 })
      .backgroundColor('#E6FFFFFF')
      .borderRadius(34)
      .shadow({ radius: 18, color: '#22000000', offsetY: 8 })
    }
    .width('100%')
    .justifyContent(FlexAlign.Center)
    .margin({ bottom: 22 })
  }

  @Builder
  DockInboxIcon() {
    Stack() {
      if (this.selectedBoard === 'inbox') {
        Column()
          .width(44).height(44)
          .borderRadius(22)
          .backgroundColor(Constants.COLOR_PRIMARY_LIGHT)
        Image($r('app.media.ic_inbox_active'))
          .width(30).height(30)
      } else {
        Image($r('app.media.ic_inbox'))
          .width(30).height(30)
      }
    }
    .width(48).height(48)
    .accessibilityText('收集箱')
    .onClick(() => { this.openInbox(); })
  }

  @Builder
  DockArchiveIcon() {
    Stack() {
      if (this.selectedBoard === 'archive') {
        Column()
          .width(44).height(44)
          .borderRadius(22)
          .backgroundColor(Constants.COLOR_PRIMARY_LIGHT)
        Image($r('app.media.ic_archive_active'))
          .width(30).height(30)
      } else {
        Image($r('app.media.ic_archive'))
          .width(30).height(30)
      }
    }
    .width(48).height(48)
    .accessibilityText('归档')
    .onClick(() => { this.openArchive(); })
  }

  @Builder
  EmptyState() {
    Column() {
      Image(this.selectedBoard === 'archive' ? $r('app.media.ic_empty_archive') : $r('app.media.ic_empty_inbox'))
        .width(120)
        .height(120)
        .margin({ bottom: 18 })
      Text(this.directionFilter !== 'all' ? '这个筛选下没有任务' : (this.selectedBoard === 'archive' ? '归档里还没有记录' : '没有任务'))
        .fontSize(22)
        .fontWeight(FontWeight.Bold)
        .fontColor(Constants.COLOR_TEXT_PRIMARY)
      Text(this.directionFilter !== 'all' ? '' : (this.selectedBoard === 'archive' ? '完成后的任务会收进这里' : '点击 + 按钮即可添加'))
        .fontSize(16)
        .fontColor(Constants.COLOR_TEXT_SECONDARY)
        .margin({ top: 8 })
    }
    .width('100%')
    .layoutWeight(1)
    .justifyContent(FlexAlign.Center)
    .alignItems(HorizontalAlign.Center)
    .padding({ bottom: 104 })
  }

  // 滴答清单风格卡片：左方形勾选框(点击推进状态) + 标题 + 截止(⏰,按紧急度变色) + 来源·状态。
  // 操作通过 左滑(商量/编辑/归档/删除) 与 点卡片(发起方编辑)，不再常驻按钮。
  @Builder
  TaskCard(item: TaskItem) {
    Row() {
      this.CheckBox(item)
      Column() {
        Text(item.title.length > 0 ? item.title : item.rawText)
          .fontSize(16)
          .fontWeight(FontWeight.Medium)
          .fontColor((item.status === TaskStatus.DONE || item.archived) ? Constants.COLOR_TEXT_SECONDARY : Constants.COLOR_TEXT_PRIMARY)
          .decoration({ type: (item.status === TaskStatus.DONE || item.archived) ? TextDecorationType.LineThrough : TextDecorationType.None })
          .maxLines(2).textOverflow({ overflow: TextOverflow.Ellipsis })
          .width('100%')

        if (item.detail.length > 0) {
          Text(item.detail)
            .fontSize(13).fontColor(Constants.COLOR_TEXT_SECONDARY)
            .maxLines(1).textOverflow({ overflow: TextOverflow.Ellipsis })
            .width('100%').margin({ top: 4 })
        }

        if (item.deadline > 0) {
          Text('⏰ ' + Constants.formatDeadline(item.deadline)
            + (item.status === TaskStatus.RECEIVED ? ('  ' + Constants.formatRemaining(item.deadline)) : ''))
            .fontSize(12).fontColor(this.deadlineColor(item))
            .width('100%').margin({ top: 6 })
        }

        Text(this.directionLabel(item))
          .fontSize(11).fontColor(Constants.COLOR_TEXT_SECONDARY)
          .width('100%').margin({ top: 4 })

        if (item.negotiation.length > 0) {
          this.NegPreview(item)
        }
      }
      .layoutWeight(1)
      .alignItems(HorizontalAlign.Start)
      .onClick(() => {
        if (item.householdId) this.openHousehold(item.householdId);
        else if (this.isQueued(item)) this.poll(); else this.openDetail(item);
      })
    }
    .width('100%')
    .padding(14)
    .backgroundColor(Constants.COLOR_CARD_BG)
    .borderRadius(8)
    .shadow({ radius: 8, color: '#0D000000', offsetY: 3 })
    .alignItems(VerticalAlign.Top)
    .opacity(item.archived ? 0.7 : 1)
  }

  // 左侧方形勾选框：点击推进状态(仅接收方)；已完成/归档显示对勾
  @Builder
  CheckBox(item: TaskItem) {
    Stack() {
      Column()
        .width(22).height(22).borderRadius(6)
        .border({ width: 2, color: this.circleColor(item) })
        .backgroundColor((item.status === TaskStatus.DONE || item.archived) ? Constants.COLOR_PRIMARY : Color.Transparent)
      if (item.status === TaskStatus.DONE || item.archived) {
        Text('✓').fontSize(13).fontColor(Color.White)
      }
    }
    .width(22).height(22).margin({ right: 12, top: 2 })
    .onClick(() => { this.onCheckbox(item); })
  }

  // 左滑出操作：按角色/状态给 商量/编辑/归档/删除
  @Builder
  SwipeEnd(item: TaskItem) {
    Row() {
      if (!this.isQueued(item) && !item.householdId) {
      if (!item.archived && item.status !== TaskStatus.DONE) {
        this.SwipeBtn('商量', Constants.COLOR_WARNING, () => { this.openNegotiate(item); })
      }
      if (item.archived) {
        this.SwipeBtn('取消归档', Constants.COLOR_PRIMARY_LIGHT, () => { this.onUnarchive(item); })
      } else if (item.status === TaskStatus.DONE) {
        this.SwipeBtn('归档', Constants.COLOR_PRIMARY, () => { this.onArchive(item); })
      }
      if (this.isCreator(item)) {
        this.SwipeBtn('编辑', Constants.COLOR_PRIMARY_DARK, () => { this.openEdit(item); })
        this.SwipeBtn('删除', Constants.COLOR_DANGER, () => { this.onDelete(item); })
      }
      }
    }
    .height('100%')
  }

  @Builder
  SwipeBtn(label: string, color: string, action: () => void) {
    Column() {
      Text(label).fontSize(13).fontColor(Color.White)
    }
    .width(68).height('100%')
    .justifyContent(FlexAlign.Center)
    .backgroundColor(color)
    .onClick(() => { action(); })
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

      Scroll() {
      Column() {
        Row() {
          Text('派一件活').fontSize(18).fontWeight(FontWeight.Bold).fontColor(Constants.COLOR_TEXT_PRIMARY)
          Blank()
          Button('复制上次').height(36).fontSize(13).fontColor(Constants.COLOR_PRIMARY).backgroundColor(Constants.COLOR_BG)
            .enabled(!this.recording && !this.transcribing && !this.extracting && !this.savingDraft && !this.uploadingImg)
            .onClick(() => { this.copyLast(); })
        }
        .width('100%').margin({ bottom: 8 })
        Text('接收人：' + this.displayName(this.otherUserId))
          .fontSize(15).fontColor(Constants.COLOR_TEXT_PRIMARY).width('100%').margin({ bottom: 12 })

        // 第二步：按住说话
        Button(this.recording ? '松开生成草稿' : (this.transcribing || this.extracting ? '正在生成草稿…' : '按住说话'))
          .type(ButtonType.Capsule)
          .fontSize(16).fontColor(Color.White)
          .backgroundColor(this.recording ? Constants.COLOR_DANGER : Constants.COLOR_PRIMARY)
          .width('100%').height(64)
          .enabled(!this.transcribing && !this.extracting)
          .gesture(
            LongPressGesture({ repeat: false, duration: 150 })
              .onAction(() => { this.startRecord(); })
              .onActionEnd(() => { this.stopRecord(); })
              .onActionCancel(() => { if (this.recording) this.cancelVoice(); })
          )

        if (this.recording || this.asrText.length > 0) {
          Text(this.asrText.length > 0 ? this.asrText : '请说话…')
            .fontSize(14).fontColor(Constants.COLOR_TEXT_SECONDARY)
            .maxLines(3).textOverflow({ overflow: TextOverflow.Ellipsis })
            .width('100%').margin({ top: 12 })
        }

        if (this.transcribing || this.extracting) {
          Row() {
            LoadingProgress().width(20).height(20).color(Constants.COLOR_PRIMARY)
            Text(this.transcribing ? ' 正在转写…' : ' 正在整理草稿…')
              .fontSize(13).fontColor(Constants.COLOR_TEXT_SECONDARY)
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
          .fontColor(Constants.COLOR_TEXT_PRIMARY).placeholderColor('#656B77')
          .borderRadius(10)
          .enabled(!this.recording && !this.transcribing && !this.extracting)
          .onChange((v: string) => { this.draftTitle = v; })

        TextArea({ text: this.draftDetail, placeholder: '补充细节（可选）' })
          .height(68).width('100%').fontSize(14).margin({ top: 8 })
          .backgroundColor(Constants.COLOR_BG).borderRadius(10)
          .fontColor(Constants.COLOR_TEXT_PRIMARY).placeholderColor('#656B77')
          .enabled(!this.recording && !this.transcribing && !this.extracting)
          .onChange((v: string) => { this.draftDetail = v; })

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
        .enabled(!this.recording && !this.transcribing && !this.extracting)

        Row() {
          Text(this.draftDeadline > 0 ? Constants.formatDeadline(this.draftDeadline) : '未设置')
            .fontSize(13)
            .fontColor(Constants.COLOR_TEXT_PRIMARY).layoutWeight(1)
          Button(this.draftDeadline > 0 ? '修改' : '选择时间').fontSize(13).height(36)
            .fontColor(Constants.COLOR_PRIMARY).backgroundColor(Color.Transparent)
            .onClick(() => { this.pickDraftDeadline(); })
          if (this.draftDeadline > 0) {
            Button('清除').fontSize(13).height(36)
              .fontColor(Constants.COLOR_PRIMARY).backgroundColor(Color.Transparent)
              .onClick(() => { this.draftDeadline = 0; })
          }
        }
        .width('100%').margin({ top: 10 })
        .enabled(!this.recording && !this.transcribing && !this.extracting)

        Row() {
          Text('重复').fontSize(14).fontColor(Constants.COLOR_TEXT_PRIMARY)
          Blank()
          Button(this.repeatLabel(this.draftRepeatKind, Number(this.draftRepeatDays)))
            .height(38).fontSize(14).fontColor(Constants.COLOR_PRIMARY).backgroundColor(Constants.COLOR_BG)
            .bindMenu([
              { value: '不重复', action: () => { this.draftRepeatKind = ''; } },
              { value: '每周', action: () => { this.draftRepeatKind = 'weekly'; } },
              { value: '每月', action: () => { this.draftRepeatKind = 'monthly'; } },
              { value: '完成后隔 N 天', action: () => { this.draftRepeatKind = 'afterDone'; } }
            ])
        }
        .width('100%').margin({ top: 10 })
        .enabled(!this.recording && !this.transcribing && !this.extracting)

        if (this.draftRepeatKind === 'afterDone') {
          Row({ space: 8 }) {
            Text('完成后隔').fontSize(14).fontColor(Constants.COLOR_TEXT_PRIMARY)
            TextInput({ text: this.draftRepeatDays, placeholder: '1–365' })
              .type(InputType.Number).maxLength(3).width(88).height(42)
              .fontColor(Constants.COLOR_TEXT_PRIMARY).backgroundColor(Constants.COLOR_BG)
              .onChange((value: string) => { this.draftRepeatDays = value; })
            Text('天').fontSize(14).fontColor(Constants.COLOR_TEXT_PRIMARY)
          }
          .width('100%').margin({ top: 8 })
        }

        // 图片附件
        Row() {
          Text('图片')
            .fontSize(14).fontColor(Constants.COLOR_TEXT_SECONDARY)
          Blank()
          if (this.uploadingImg) {
            Row() {
              LoadingProgress().width(16).height(16).color(Constants.COLOR_PRIMARY)
              Text(' 上传中…').fontSize(12).fontColor(Constants.COLOR_TEXT_SECONDARY)
            }
          } else {
            Text(this.draftImages.length + '/9')
              .fontSize(12).fontColor(Constants.COLOR_TEXT_SECONDARY)
          }
        }
        .width('100%').margin({ top: 16, bottom: 8 })

        this.DraftImagesRow()

        // 第四步：发送
        Row() {
          Button('取消')
            .type(ButtonType.Normal).fontColor(Constants.COLOR_TEXT_SECONDARY)
            .backgroundColor(Constants.COLOR_BG).layoutWeight(1).height(46)
            .borderRadius(10).margin({ right: 10 })
            .onClick(() => { this.closeCreate(); })
          Button('发送给' + this.displayName(this.otherUserId))
            .type(ButtonType.Normal).fontColor(Color.White)
            .backgroundColor(Constants.COLOR_PRIMARY).layoutWeight(1).height(46)
            .borderRadius(10)
            .enabled(!this.recording && !this.transcribing && !this.extracting && !this.savingDraft && !this.uploadingImg)
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
      .width('100%').constraintSize({ maxHeight: '94%' })
      .align(Alignment.Bottom)
      .scrollBar(BarState.Off)
    }
    .width('100%')
    .height('100%')
    .backgroundColor('#66000000')
  }

  // 新建任务时的图片缩略图行：已选图 + 末尾「＋」添加按钮
  @Builder
  DraftImagesRow() {
    Row() {
      ForEach(this.draftThumbs, (pm: image.PixelMap, idx: number) => {
        Stack({ alignContent: Alignment.TopEnd }) {
          Image(pm)
            .width(64).height(64)
            .borderRadius(10)
            .objectFit(ImageFit.Cover)
            .backgroundColor(Constants.COLOR_BG)
          Text('✕')
            .fontSize(12).fontColor(Color.White)
            .width(20).height(20)
            .textAlign(TextAlign.Center)
            .borderRadius(10)
            .backgroundColor('#B3000000')
            .margin({ top: -6, right: -6 })
            .onClick(() => { this.removeDraftImage(idx); })
        }
        .margin({ right: 10 })
      }, (pm: image.PixelMap, idx: number) => 'draft-' + (this.draftImages[idx] ? this.draftImages[idx].id : idx))

      if (this.draftImages.length < 9) {
        Column() {
          Text('＋').fontSize(26).fontColor(Constants.COLOR_TEXT_SECONDARY)
        }
        .width(64).height(64)
        .justifyContent(FlexAlign.Center)
        .borderRadius(10)
        .backgroundColor(Constants.COLOR_BG)
        .border({ width: 1, color: Constants.COLOR_PRIMARY_LIGHT })
        .onClick(() => { this.onAddImages(); })
      }
    }
    .width('100%')
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
  TaskDetailSheet(item: TaskItem) {
    Column() {
      Column().layoutWeight(1).width('100%')

      Column() {
        Row() {
          Text('‹')
            .fontSize(28)
            .fontWeight(FontWeight.Bold)
            .fontColor(Constants.COLOR_TEXT_SECONDARY)
            .width(44)
            .height(44)
            .textAlign(TextAlign.Center)
            .onClick(() => { this.closeDetail(); })

          Blank()
          Text('收集箱⌄')
            .fontSize(18)
            .fontWeight(FontWeight.Bold)
            .fontColor(Constants.COLOR_TEXT_PRIMARY)
          Blank()

          Text('⋯')
            .fontSize(26)
            .fontWeight(FontWeight.Bold)
            .fontColor(Constants.COLOR_TEXT_SECONDARY)
            .width(44)
            .height(44)
            .textAlign(TextAlign.Center)
            .onClick(() => {
              if (this.isCreator(item) && !item.archived) {
                this.closeDetail();
                this.openEdit(item);
              }
            })
        }
        .width('100%')
        .margin({ bottom: 12 })

        Row() {
          this.CheckBox(item)
          Text(item.deadline > 0 ? Constants.formatDeadline(item.deadline) : '未设截止时间')
            .fontSize(17)
            .fontWeight(FontWeight.Bold)
            .fontColor(item.deadline > 0 ? Constants.COLOR_PRIMARY : Constants.COLOR_TEXT_SECONDARY)
          Blank()
          Text('⚑')
            .fontSize(20)
            .fontColor(Constants.COLOR_TEXT_SECONDARY)
        }
        .width('100%')
        .margin({ bottom: 20 })

        Text(this.taskDisplayTitle(item))
          .fontSize(30)
          .fontWeight(FontWeight.Bold)
          .fontColor(Constants.COLOR_TEXT_PRIMARY)
          .maxLines(3)
          .textOverflow({ overflow: TextOverflow.Ellipsis })
          .width('100%')
          .margin({ bottom: 14 })

        Text(this.taskDetailText(item).length > 0 ? this.taskDetailText(item) : '描述')
          .fontSize(18)
          .fontColor(this.taskDetailText(item).length > 0 ? Constants.COLOR_TEXT_SECONDARY : '#668F97A6')
          .maxLines(6)
          .textOverflow({ overflow: TextOverflow.Ellipsis })
          .width('100%')
          .margin({ bottom: 18 })

        this.RepeatDetail(item)

        if (item.images.length > 0) {
          this.DetailImagesBlock(item)
        }

        if (item.negotiation.length > 0) {
          this.DetailNegotiationBlock(item)
        }

        this.DetailActionRow(item)
      }
      .width('100%')
      .padding({ left: 24, right: 24, top: 14, bottom: 22 })
      .backgroundColor(Constants.COLOR_CARD_BG)
      .borderRadius({ topLeft: 24, topRight: 24 })
      .shadow({ radius: 18, color: '#22000000', offsetY: -6 })
    }
    .width('100%').height('100%')
    .backgroundColor('#33000000')
  }

  @Builder
  RepeatDetail(item: TaskItem) {
    Column({ space: 8 }) {
      if (item.repeat) {
        Text(this.repeatLabel(item.repeat.kind, item.repeat.days) + (item.repeat.current && item.repeat.paused ? ' · 已暂停' : '')
          + (item.repeat.skippedAt > 0 ? ' · 已跳过' : ''))
          .fontSize(14).fontColor(Constants.COLOR_TEXT_PRIMARY).width('100%')
        if (item.repeat.current) {
          Row({ space: 8 }) {
            if (item.status !== TaskStatus.DONE) {
              Button('跳过本次').fontSize(13).height(36).layoutWeight(1)
                .onClick(() => { this.confirmRepeatAction(item, 'skip', '跳过本次'); })
            }
            if (this.isCreator(item)) {
              Button(item.repeat.paused ? '恢复重复' : '暂停重复').fontSize(13).height(36).layoutWeight(1)
                .onClick(() => {
                  const paused = item.repeat?.paused === true;
                  this.confirmRepeatAction(item, paused ? 'resume' : 'pause', paused ? '恢复重复' : '暂停重复');
                })
            }
          }
          .width('100%')
        }
      }
      Button('复制为新任务').fontSize(13).height(38).width('100%')
        .fontColor(Constants.COLOR_PRIMARY).backgroundColor(Constants.COLOR_BG)
        .onClick(() => { this.copyTask(item); })
    }
    .width('100%').margin({ bottom: 10 })
  }

  // 详情里显示图片：3 列网格，点图全屏查看。图片随下载逐张出现
  @Builder
  DetailImagesBlock(item: TaskItem) {
    Column() {
      Row() {
        Text('图片 · ' + item.images.length + ' 张')
          .fontSize(12).fontWeight(FontWeight.Bold)
          .fontColor(Constants.COLOR_TEXT_SECONDARY)
        Blank()
        if (this.detailImgLoading) {
          Row() {
            LoadingProgress().width(14).height(14).color(Constants.COLOR_PRIMARY)
            Text(' 加载中…').fontSize(11).fontColor(Constants.COLOR_TEXT_SECONDARY)
          }
        }
      }
      .width('100%').margin({ bottom: 8 })

      Flex({ wrap: FlexWrap.Wrap }) {
        ForEach(this.detailImages, (pm: image.PixelMap | null, idx: number) => {
          Column() {
            if (pm != null) {
              Image(pm)
                .width('100%').height(100)
                .borderRadius(8)
                .objectFit(ImageFit.Cover)
                .onClick(() => { this.previewImage = pm; })
            } else {
              Column() {
                LoadingProgress().width(20).height(20).color(Constants.COLOR_PRIMARY)
              }
              .width('100%').height(100)
              .justifyContent(FlexAlign.Center)
              .borderRadius(8)
              .backgroundColor(Constants.COLOR_BG)
            }
          }
          .width('31%')
          .margin({ right: '2%', bottom: 8 })
        }, (pm: image.PixelMap | null, idx: number) => 'det-' + this.detailTaskId + '-' + idx + '-' + (pm != null ? '1' : '0'))
      }
      .width('100%')
    }
    .width('100%')
    .margin({ bottom: 16 })
    .alignItems(HorizontalAlign.Start)
  }

  @Builder
  DetailNegotiationBlock(item: TaskItem) {
    Column() {
      Text(this.latestNegotiationIsMine(item) ? '我提出的商量' : '对方提出的商量')
        .fontSize(12)
        .fontWeight(FontWeight.Bold)
        .fontColor(this.needsNegotiationReply(item) ? Constants.COLOR_WARNING : Constants.COLOR_TEXT_SECONDARY)
        .width('100%')
        .margin({ bottom: 8 })
      Text(item.negotiation[item.negotiation.length - 1].text)
        .fontSize(15)
        .fontColor(Constants.COLOR_TEXT_PRIMARY)
        .width('100%')
      if (item.negotiation[item.negotiation.length - 1].proposedDeadline > 0) {
        Text('建议改到 ' + Constants.formatDeadline(item.negotiation[item.negotiation.length - 1].proposedDeadline))
          .fontSize(12)
          .fontColor(Constants.COLOR_PRIMARY)
          .width('100%')
          .margin({ top: 8 })
      }
      if (this.needsNegotiationReply(item)) {
        Row() {
          Button('同意')
            .type(ButtonType.Normal)
            .fontSize(13)
            .fontColor(Color.White)
            .backgroundColor(Constants.COLOR_PRIMARY)
            .height(34)
            .borderRadius(8)
            .padding({ left: 14, right: 14 })
            .onClick(() => {
              this.onAcceptDetailProposal(item);
            })
          Button('回复')
            .type(ButtonType.Normal)
            .fontSize(13)
            .fontColor(Constants.COLOR_TEXT_PRIMARY)
            .backgroundColor(Constants.COLOR_BG)
            .height(34)
            .borderRadius(8)
            .padding({ left: 14, right: 14 })
            .margin({ left: 10 })
            .onClick(() => {
              this.closeDetail();
              this.openNegotiate(item);
            })
        }
        .margin({ top: 10 })
      }
    }
    .width('100%')
    .padding(14)
    .margin({ bottom: 16 })
    .backgroundColor(this.needsNegotiationReply(item) ? '#1FFF9F1C' : Constants.COLOR_BG)
    .borderRadius(8)
    .alignItems(HorizontalAlign.Start)
  }

  @Builder
  DetailActionRow(item: TaskItem) {
    Row() {
      if (this.isReceiver(item) && item.status === TaskStatus.PENDING) {
        Button('收到')
          .type(ButtonType.Normal)
          .fontSize(14)
          .fontWeight(FontWeight.Bold)
          .fontColor(Color.White)
          .backgroundColor(Constants.COLOR_PRIMARY)
          .height(42)
          .borderRadius(10)
          .padding({ left: 16, right: 16 })
          .margin({ right: 10 })
          .onClick(() => { this.onReceive(item); })
      } else if (this.isReceiver(item) && item.status === TaskStatus.RECEIVED) {
        Button('完成')
          .type(ButtonType.Normal)
          .fontSize(14)
          .fontWeight(FontWeight.Bold)
          .fontColor(Color.White)
          .backgroundColor(Constants.COLOR_PRIMARY)
          .height(42)
          .borderRadius(10)
          .padding({ left: 16, right: 16 })
          .margin({ right: 10 })
          .onClick(() => { this.onDone(item); this.closeDetail(); })
      }

      if (!item.archived && item.status !== TaskStatus.DONE) {
        Button(item.status === TaskStatus.NEGOTIATING ? '回复' : '商量')
          .type(ButtonType.Normal)
          .fontSize(14)
          .fontWeight(FontWeight.Bold)
          .fontColor(Constants.COLOR_TEXT_PRIMARY)
          .backgroundColor(Constants.COLOR_BG)
          .height(42)
          .borderRadius(10)
          .padding({ left: 16, right: 16 })
          .margin({ right: 10 })
          .onClick(() => {
            this.closeDetail();
            this.openNegotiate(item);
          })
      }

      if (item.status === TaskStatus.DONE && !item.archived) {
        Button('归档')
          .type(ButtonType.Normal)
          .fontSize(14)
          .fontWeight(FontWeight.Bold)
          .fontColor(Constants.COLOR_TEXT_PRIMARY)
          .backgroundColor(Constants.COLOR_BG)
          .height(42)
          .borderRadius(10)
          .padding({ left: 16, right: 16 })
          .margin({ right: 10 })
          .onClick(() => { this.onArchive(item); this.closeDetail(); })
      }

      Blank()

      if (this.isCreator(item)) {
        Button('删除')
          .type(ButtonType.Normal)
          .fontSize(14)
          .fontWeight(FontWeight.Bold)
          .fontColor(Constants.COLOR_DANGER)
          .backgroundColor(Constants.COLOR_BG)
          .height(42)
          .borderRadius(10)
          .padding({ left: 16, right: 16 })
          .onClick(() => { this.onDelete(item); })
      }
    }
    .width('100%')
    .margin({ top: 4 })
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
          .fontColor(m.fromUserId === this.myUserId ? Constants.COLOR_PRIMARY_DARK : Constants.COLOR_TEXT_PRIMARY)
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
          if (m.fromUserId !== this.myUserId && m.proposedDeadline !== this.negDeadlineShown) {
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

        Text('本次截止时间').fontSize(14).fontColor(Constants.COLOR_TEXT_SECONDARY)
          .width('100%').margin({ top: 14, bottom: 8 })
        Row() {
          this.EditTimeChip('2分钟后', 2)
          this.EditTimeChip('1小时后', 60)
          this.EditTimeChip('今晚20点', -1)
          this.EditTimeChip('清除', 0)
        }
        .width('100%').justifyContent(FlexAlign.SpaceBetween)
        Button(this.editDeadline > 0 ? Constants.formatDeadline(this.editDeadline) : '选择时间')
          .fontSize(13).fontColor(Constants.COLOR_PRIMARY).backgroundColor(Constants.COLOR_BG)
          .height(42).width('100%').margin({ top: 10 })
          .onClick(() => {
            this.getUIContext().showDatePickerDialog({ selected: new Date(this.editDeadline || Date.now()),
              showTime: true, useMilitaryTime: true,
              onDateAccept: (value: Date) => { if (this.showEdit) this.editDeadline = value.getTime(); } });
          })

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
            .swipeAction({ end: this.SwipeEnd(item) })
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
    this.cancelVoice();
    this.draftTitle = '';
    this.draftDeadline = 0;
    this.draftDetail = '';
    this.draftRepeatKind = '';
    this.draftRepeatDays = '7';
    this.asrText = '';
    this.draftTranscript = '';
    this.recording = false;
    this.extracting = false;
    this.recordError = '';
    this.draftImages = [];
    this.draftThumbs = [];
    this.uploadingImg = false;
    this.showCreate = true;
  }

  private repeatLabel(kind: string, days: number): string {
    if (kind === 'weekly') return '每周';
    if (kind === 'monthly') return '每月';
    if (kind === 'afterDone') return days > 0 ? '完成后隔 ' + days + ' 天' : '完成后隔 N 天';
    return '不重复';
  }

  private copyTask(item: TaskItem): void {
    this.closeDetail();
    this.openCreate();
    this.draftTitle = this.taskDisplayTitle(item);
    this.draftDetail = item.detail;
  }

  private copyLast(): void {
    const last = TaskStore.getInstance().getAll().find((t: TaskItem) => t.familyId === this.familyId
      && this.isCreator(t) && !t.deleted && !this.isQueued(t) && !t.repeat?.generated);
    if (last) this.copyTask(last);
    else this.toast('还没有派出的任务');
  }

  private confirmRepeatAction(item: TaskItem, action: string, label: string): void {
    this.getUIContext().showAlertDialog({ title: label + '？', message: this.taskDisplayTitle(item),
      primaryButton: { value: '确定', action: () => { this.applyRepeatAction(item, action); } },
      secondaryButton: { value: '取消', action: () => {} } });
  }

  private async applyRepeatAction(item: TaskItem, action: string): Promise<void> {
    const saved = await RelayService.getInstance().repeatAction(item, this.myUserId, action);
    if (!saved) { this.toast('更新重复任务失败，请同步后重试'); return; }
    try {
      const orphan = await TaskStore.getInstance().mergeRemote([saved]);
      await ReminderService.getInstance().cancelForTask(orphan);
      this.closeDetail();
      this.refresh();
      this.poll();
    } catch (err) {
      this.toast('操作已提交，请刷新任务');
    }
  }

  private pickDraftDeadline(): void {
    const selected = new Date(this.draftDeadline || Date.now());
    this.getUIContext().showDatePickerDialog({
      selected: selected,
      showTime: true,
      useMilitaryTime: true,
      onDateAccept: (value: Date) => { if (this.showCreate) this.draftDeadline = value.getTime(); }
    });
  }

  // 选图 → 逐张转码降采样 → 上传中继 → 记录元数据+预览缩略图
  async onAddImages(): Promise<void> {
    if (this.uploadingImg) {
      return;
    }
    const remain = 9 - this.draftImages.length;
    if (remain <= 0) {
      this.toast('最多 9 张');
      return;
    }
    const uris = await ImageService.pick(remain);
    if (uris.length === 0) {
      return;
    }
    this.uploadingImg = true;
    let failed = 0;
    for (let i = 0; i < uris.length; i++) {
      const prep = await ImageService.prepare(uris[i]);
      if (!prep) {
        failed++;
        continue;
      }
      const pmv = prep.pixelMap;
      if (!pmv) {
        failed++;
        continue;
      }
      const meta = await RelayService.getInstance().uploadImage(
        prep.jpeg, 'image/jpeg', this.familyId, prep.w, prep.h);
      if (meta && meta.id.length > 0) {
        this.draftImages = this.draftImages.concat([meta]);
        this.draftThumbs = this.draftThumbs.concat([pmv]);
      } else {
        failed++;
      }
    }
    this.uploadingImg = false;
    if (failed > 0) {
      this.toast('有 ' + failed + ' 张上传失败');
    }
  }

  removeDraftImage(idx: number): void {
    if (idx < 0 || idx >= this.draftImages.length) {
      return;
    }
    const imgs = this.draftImages.slice();
    const thumbs = this.draftThumbs.slice();
    imgs.splice(idx, 1);
    thumbs.splice(idx, 1);
    this.draftImages = imgs;
    this.draftThumbs = thumbs;
  }

  openDetail(item: TaskItem): void {
    this.detailTaskId = item.id;
    this.detailImages = [];
    this.showDetail = true;
    this.loadDetailImages(item);
  }

  // 逐张下载并解码任务图片，边下边显示（先铺占位，解码好就替换）
  private async loadDetailImages(item: TaskItem): Promise<void> {
    if (!item.images || item.images.length === 0) {
      return;
    }
    const slots: (image.PixelMap | null)[] = [];
    for (let i = 0; i < item.images.length; i++) {
      slots.push(null);
    }
    this.detailImages = slots.slice();
    this.detailImgLoading = true;
    const loadingFor = this.detailTaskId;
    for (let i = 0; i < item.images.length; i++) {
      const bytes = await RelayService.getInstance().downloadImage(item.images[i].id);
      // 详情已切走则丢弃结果
      if (this.detailTaskId !== loadingFor) {
        return;
      }
      if (bytes) {
        const pm = await ImageService.decode(bytes);
        if (this.detailTaskId !== loadingFor) {
          return;
        }
        if (pm) {
          const next = this.detailImages.slice();
          next[i] = pm;
          this.detailImages = next;
        }
      }
    }
    this.detailImgLoading = false;
  }

  closeDetail(): void {
    this.showDetail = false;
    this.detailImages = [];
  }

  private currentDetailTask(): TaskItem {
    const item = TaskStore.getInstance().getById(this.detailTaskId);
    if (item) {
      return item;
    }
    return new TaskItem();
  }

  private taskDisplayTitle(item: TaskItem): string {
    const title = item.title.trim();
    if (title.length > 0) {
      return title;
    }
    const raw = item.rawText.trim();
    return raw.length > 0 ? raw : '未命名任务';
  }

  private taskDetailText(item: TaskItem): string {
    const detail = item.detail.trim();
    if (detail.length > 0) {
      return detail;
    }
    const raw = item.rawText.trim();
    return raw === this.taskDisplayTitle(item) ? '' : raw;
  }

  async onSend(): Promise<void> {
    if (this.recording || this.transcribing || this.extracting || this.savingDraft || this.uploadingImg) return;
    if (this.draftTitle.trim().length === 0) {
      this.toast('说点什么吧');
      return;
    }
    const repeatDays = Number(this.draftRepeatDays);
    if ((this.draftRepeatKind === 'weekly' || this.draftRepeatKind === 'monthly') && this.draftDeadline <= Date.now()) {
      this.toast('请为第一次设定未来的截止时间');
      return;
    }
    if (this.draftRepeatKind === 'afterDone' && (!Number.isInteger(repeatDays) || repeatDays < 1 || repeatDays > 365)) {
      this.toast('请输入 1 到 365 天');
      return;
    }
    const t = new TaskItem();
    t.id = util.generateRandomUUID();
    t.clientRequestId = t.id;
    t.familyId = this.familyId;
    t.fromUserId = this.myUserId;
    t.toUserId = this.otherUserId;
    t.rawText = this.draftTranscript.length > 0 ? this.draftTranscript : this.draftTitle.trim();
    t.title = this.draftTitle.trim();
    t.detail = this.draftDetail;
    t.deadline = this.draftDeadline;
    if (this.draftRepeatKind.length > 0) {
      t.repeat = new RepeatRule();
      t.repeat.kind = this.draftRepeatKind;
      t.repeat.days = this.draftRepeatKind === 'afterDone' ? repeatDays : 0;
    }
    t.status = TaskStatus.PENDING;
    t.reminder = new ReminderConfig();
    t.images = this.draftImages.slice();
    t.createdAt = Date.now();
    this.savingDraft = true;
    try {
      await TaskStore.getInstance().queue(t);
      this.closeCreate();
      this.selectedBoard = 'inbox';
      if (this.directionFilter === 'incoming') this.directionFilter = 'outgoing';
      this.refresh();
      this.toast('已加入待发送');
      this.poll();
    } catch (err) {
      this.toast('保存草稿失败，请重试');
    } finally {
      this.savingDraft = false;
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
    msg.fromUserId = this.myUserId;
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

  async onAcceptDetailProposal(item: TaskItem): Promise<void> {
    if (item.negotiation.length === 0) {
      return;
    }
    const m = item.negotiation[item.negotiation.length - 1];
    if (m.proposedDeadline <= 0) {
      this.toast('这条商量没有新时间');
      return;
    }
    item.deadline = m.proposedDeadline;
    await TaskStore.getInstance().upsert(item);
    this.refresh();
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
    if (item.repeat && item.objectId.length > 0) {
      const updated = await RelayService.getInstance().update(item.objectId,
        { 'status': TaskStatus.DONE, 'doneAt': Date.now(), 'archived': true });
      if (!updated) { this.toast('完成未同步，请联网后重试'); return; }
      await ReminderService.getInstance().cancelForTask(item.reminderIds);
      await this.poll();
      this.toast('已完成并归档');
      return;
    }
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
    // 先通知中继软删（对端轮询到墓碑后本地移除），再删本机；带上发起人
    if (item.objectId.length > 0) {
      await RelayService.getInstance().remove(item.objectId, this.myUserId);
    }
    await TaskStore.getInstance().remove(item.id);
    this.showDetail = false;
    this.refresh();
    this.toast('已删除');
  }

  private isCreator(item: TaskItem): boolean {
    return item.fromUserId === this.myUserId;
  }

  private isReceiver(item: TaskItem): boolean {
    return item.toUserId === this.myUserId;
  }

  private latestNegotiationIsMine(item: TaskItem): boolean {
    if (item.negotiation.length === 0) {
      return false;
    }
    return item.negotiation[item.negotiation.length - 1].fromUserId === this.myUserId;
  }

  private needsNegotiationReply(item: TaskItem): boolean {
    return item.status === TaskStatus.NEGOTIATING
      && item.negotiation.length > 0
      && !this.latestNegotiationIsMine(item);
  }

  // 点方形框推进状态：仅接收方；待收到/商量中→收到，收到→完成(并自动归档)
  onCheckbox(item: TaskItem): void {
    if (item.householdId) { this.openHousehold(item.householdId); return; }
    if (item.archived || !this.isReceiver(item)) {
      return;
    }
    if (item.status === TaskStatus.PENDING || item.status === TaskStatus.NEGOTIATING) {
      this.onReceive(item);
    } else if (item.status === TaskStatus.RECEIVED) {
      this.onDone(item);
    }
  }

  private directionLabel(item: TaskItem): string {
    if (item.householdId) return '家里待办 · 我已认领';
    let st = item.repeat?.skippedAt ? '已跳过' : this.statusLabel(item.status);
    const img = (item.images.length > 0 ? (' · 📷' + item.images.length) : '')
      + (item.repeat ? (' · ' + this.repeatLabel(item.repeat.kind, item.repeat.days)
        + (item.repeat.current && item.repeat.paused ? '（已暂停）' : '')) : '');
    if (this.isReceiver(item)) {
      return '来自 ' + this.displayName(item.fromUserId) + ' · ' + st + img;
    }
    if (this.isQueued(item)) st = '待发送';
    else if (item.status === TaskStatus.PENDING) st = item.recipientSyncedAt > 0 ? '对方已同步' : '已发出';
    else if (item.status === TaskStatus.RECEIVED) st = '对方已接下';
    return '给 ' + this.displayName(item.toUserId) + ' · ' + st + img;
  }

  private isQueued(item: TaskItem): boolean {
    return !item.objectId && !!item.clientRequestId;
  }

  openArchive(): void {
    this.selectedBoard = 'archive';
    this.refresh();
  }

  closeArchive(): void {
    this.openInbox();
  }

  openInbox(): void {
    this.selectedBoard = 'inbox';
    this.refresh();
  }

  private boardTitle(): string {
    return this.selectedBoard === 'archive' ? '归档' : '收集箱';
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

  private closeCreate(): void {
    this.cancelVoice();
    this.showCreate = false;
  }

  private clearVoiceTimer(): void {
    if (this.voiceTimer < 0) return;
    clearTimeout(this.voiceTimer);
    this.voiceTimer = -1;
  }

  private cancelVoice(): void {
    this.voiceAttempt++;
    this.clearVoiceTimer();
    this.finalTranscript = null;
    this.recording = false;
    this.transcribing = false;
    this.extracting = false;
    AsrService.getInstance().cancel().catch(() => {});
  }

  async startRecord(): Promise<void> {
    if (!this.showCreate || this.recording || this.transcribing || this.extracting) return;
    const attempt = ++this.voiceAttempt;
    const atManager = abilityAccessCtrl.createAtManager();
    const ctx = this.getUIContext().getHostContext() as common.UIAbilityContext;
    if (atManager.verifyAccessTokenSync(ctx.applicationInfo.accessTokenId, 'ohos.permission.MICROPHONE') !== 0) {
      const ok = await this.ensureMicPermission();
      if (attempt === this.voiceAttempt && this.showCreate) {
        this.recordError = ok ? '已允许麦克风，请重新按住说话' : '需要麦克风权限，也可手动填写';
      }
      return;
    }
    this.asrText = '';
    this.finalTranscript = null;
    this.recordError = '';
    this.recording = true;
    this.voiceTimer = setTimeout(() => { this.failVoice(attempt); }, 45000);
    try {
      await AsrService.getInstance().start(
        (t: string) => { if (attempt === this.voiceAttempt) this.asrText = t; },
        (t: string) => {
          if (attempt !== this.voiceAttempt) return;
          if (this.recording) this.finalTranscript = t;
          else this.onAsrFinal(t, attempt);
        },
        (_: string) => { this.failVoice(attempt); }
      );
    } catch (err) {
      this.failVoice(attempt);
    }
  }

  private failVoice(attempt: number): void {
    if (attempt !== this.voiceAttempt) return;
    this.cancelVoice();
    this.recordError = '语音识别未完成，请重试或手动填写';
  }

  async stopRecord(): Promise<void> {
    if (!this.recording) {
      return;
    }
    this.clearVoiceTimer();
    this.recording = false;
    const attempt = this.voiceAttempt;
    if (this.finalTranscript !== null) {
      await this.onAsrFinal(this.finalTranscript, attempt);
      return;
    }
    this.transcribing = true;
    this.voiceTimer = setTimeout(() => { this.failVoice(attempt); }, 10000);
    try {
      await AsrService.getInstance().stop();
    } catch (err) {
      this.failVoice(attempt);
    }
  }

  async onAsrFinal(text: string, attempt: number): Promise<void> {
    this.clearVoiceTimer();
    this.finalTranscript = null;
    this.recording = false;
    this.transcribing = false;
    this.asrText = text;
    const trimmed = text.trim();
    if (trimmed.length === 0) {
      this.recordError = '没听清，请再说一次或手动填写';
      return;
    }
    this.extracting = true;
    this.recordError = '';
    try {
      const r = await AIService.getInstance().extractTask(trimmed);
      if (attempt !== this.voiceAttempt) return;
      this.draftTranscript = trimmed;
      this.draftTitle = r.title;
      this.draftDetail = r.detail;
      this.draftDeadline = r.deadline;
    } catch (err) {
      if (attempt !== this.voiceAttempt) return;
      this.draftTranscript = trimmed;
      this.recordError = '未能自动整理，已填入原话，请手动确认';
      this.draftTitle = trimmed;
      this.draftDetail = '';
      this.draftDeadline = 0;
    } finally {
      if (attempt === this.voiceAttempt) this.extracting = false;
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
