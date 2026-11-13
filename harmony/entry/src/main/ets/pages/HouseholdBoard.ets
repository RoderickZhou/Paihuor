import { util } from '@kit.ArkTS';
import { image } from '@kit.ImageKit';
import { Constants } from '../constants/Constants';
import { HouseholdCard, HouseholdDraft } from '../models/HouseholdCard';
import { ImageService } from '../services/ImageService';
import { RelayService } from '../services/RelayService';

@Component
export struct HouseholdBoard {
  @Prop cards: HouseholdCard[] = [];
  @Prop family: string = '';
  @Prop user: string = '';
  @Prop failed: boolean = false;
  @Prop loading: boolean = true;
  @Prop openedCard: string = '';
  onClose: () => void = () => {};
  onRefresh: () => void = () => {};
  @State tab: string = 'available';
  @State list: string = '';
  @State editing: boolean = false;
  @State draftList: string = '日常';
  @State draftTitles: string = '';
  @State draftDetail: string = '';
  @State draftPhotos: string[] = [];
  @State writing: boolean = false;
  @State uploading: boolean = false;
  @State detailId: string = '';
  @State photos: image.PixelMap[] = [];
  private signature: string = '';
  private batch: HouseholdDraft[] = [];

  aboutToAppear(): void {
    if (this.openedCard.length > 0) {
      this.tab = 'claimed';
      const card = this.cards.find((value: HouseholdCard) => value.id === this.openedCard);
      if (card) this.openDetail(card);
    }
  }

  build() {
    Stack({ alignContent: Alignment.Bottom }) {
      Column({ space: 8 }) {
        Row({ space: 8 }) {
          Button('‹').fontSize(28).width(44).height(44).accessibilityText('返回收集箱')
            .backgroundColor(Color.Transparent).fontColor(Constants.COLOR_TEXT_PRIMARY).onClick(() => { this.onClose(); })
          Text('家里待办').fontSize(24).fontWeight(FontWeight.Bold).fontColor(Constants.COLOR_TEXT_PRIMARY).layoutWeight(1)
          Button('＋').fontSize(25).width(44).height(44).accessibilityText('添加卡片')
            .backgroundColor(Constants.COLOR_PRIMARY).onClick(() => { this.openEditor(); })
        }.width('100%')
        Button((this.list || '全部清单') + ' ▾').height(44).width('100%').fontSize(14)
          .backgroundColor(Color.White).fontColor(Constants.COLOR_TEXT_PRIMARY).bindMenu(this.listOptions())
        Row({ space: 4 }) {
          this.Tab('available', '待认领')
          this.Tab('claimed', '进行中')
          this.Tab('done', '已完成')
        }.width('100%')
        if (this.failed) {
          Button('同步失败 · 重试').height(42).fontSize(14).fontColor(Constants.COLOR_DANGER).backgroundColor(Color.White)
            .onClick(() => { this.onRefresh(); })
        }
        if (this.visible().length === 0) {
          Column() {
            if (this.loading) LoadingProgress().width(30).height(30).color(Constants.COLOR_PRIMARY)
            else Text(this.tab === 'available' ? '暂无待认领卡片' : this.tab === 'claimed' ? '暂无进行中卡片' : '暂无已完成卡片')
              .fontSize(16).fontColor('#596274')
          }.width('100%').layoutWeight(1).justifyContent(FlexAlign.Center)
        } else {
          List({ space: 8 }) {
            ForEach(this.visible(), (card: HouseholdCard, index: number) => {
              ListItem() {
                Column() {
                  if (this.startsList(card, index)) {
                    Text(card.list).fontSize(14).fontWeight(FontWeight.Medium).fontColor('#596274')
                      .width('100%').padding({ top: 6, bottom: 8 })
                  }
                  Column({ space: 6 }) {
                    Column({ space: 6 }) {
                      Text(card.title).fontSize(16).fontWeight(FontWeight.Medium).fontColor(Constants.COLOR_TEXT_PRIMARY)
                        .width('100%').maxLines(3).textOverflow({ overflow: TextOverflow.Ellipsis })
                      if (card.detail.length > 0) {
                        Text(card.detail).fontSize(14).fontColor('#596274').width('100%').maxLines(2)
                          .textOverflow({ overflow: TextOverflow.Ellipsis })
                      }
                      if (this.meta(card).length > 0) Text(this.meta(card)).fontSize(13).fontColor('#596274').width('100%')
                    }.width('100%').onClick(() => { this.openDetail(card); })
                    this.Actions(card)
                  }.width('100%').padding(12).borderRadius(8).backgroundColor(Color.White)
                }.width('100%')
              }
            }, (card: HouseholdCard, index: number) => card.id + ':' + card.revision + ':' + this.startsList(card, index))
          }.width('100%').layoutWeight(1).scrollBar(BarState.Off)
        }
      }.width('100%').height('100%').padding({ left: 18, right: 18, top: 12, bottom: 14 }).backgroundColor(Constants.COLOR_BG)

      if (this.editing) this.Editor()
      if (this.detailId.length > 0) {
        ForEach(this.cards.filter((card: HouseholdCard) => card.id === this.detailId), (card: HouseholdCard) => {
          this.Detail(card)
        }, (card: HouseholdCard) => card.id + ':' + card.revision)
      }
    }.width('100%').height('100%')
  }

  @Builder
  Tab(state: string, label: string) {
    Button(label + ' ' + this.count(state)).type(ButtonType.Normal).height(42).layoutWeight(1).borderRadius(8).fontSize(13)
      .backgroundColor(this.tab === state ? Constants.COLOR_PRIMARY_LIGHT : Color.Transparent)
      .fontColor(this.tab === state ? Constants.COLOR_PRIMARY_DARK : Constants.COLOR_TEXT_PRIMARY)
      .accessibilitySelected(this.tab === state).onClick(() => { this.tab = state; })
  }

  @Builder
  Actions(card: HouseholdCard) {
    Row({ space: 8 }) {
      if (card.status === 'available') this.ActionButton('认领', 'claim', card)
      if (card.status === 'claimed' && card.assignee === this.user) {
        this.ActionButton('放回', 'release', card)
        this.ActionButton('完成', 'complete', card)
      }
    }.width('100%')
  }

  @Builder
  ActionButton(label: string, action: string, card: HouseholdCard) {
    Button(label).height(40).fontSize(14).enabled(!this.writing)
      .fontColor(action === 'release' ? Constants.COLOR_PRIMARY_DARK : Color.White)
      .backgroundColor(action === 'release' ? Constants.COLOR_BG : Constants.COLOR_PRIMARY)
      .onClick(() => { this.change(card, action); })
  }

  @Builder
  Editor() {
    Column() {
      Blank().layoutWeight(1)
      Scroll() {
        Column({ space: 10 }) {
          Text('添加卡片').fontSize(19).fontWeight(FontWeight.Bold).fontColor(Constants.COLOR_TEXT_PRIMARY).width('100%')
          TextInput({ text: this.draftList, placeholder: '清单名' }).height(44).fontColor(Color.Black)
            .backgroundColor(Constants.COLOR_BG).maxLength(40).onChange((value: string) => { this.draftList = value; })
          TextArea({ text: this.draftTitles, placeholder: '卡片标题（每行一张）' }).height(118).fontColor(Color.Black)
            .backgroundColor(Constants.COLOR_BG).onChange((value: string) => { this.draftTitles = value; })
          TextArea({ text: this.draftDetail, placeholder: '备注（单张卡片）' }).height(65).fontColor(Color.Black)
            .backgroundColor(Constants.COLOR_BG).maxLength(2000).onChange((value: string) => { this.draftDetail = value; })
          Row({ space: 8 }) {
            Button(this.uploading ? '上传中…' : '添加照片 · ' + this.draftPhotos.length + '/9')
              .height(42).fontSize(14).enabled(!this.uploading && !this.writing && this.draftPhotos.length < 9)
              .fontColor(Constants.COLOR_PRIMARY_DARK).backgroundColor(Constants.COLOR_BG).onClick(() => { this.addPhotos(); })
            if (this.draftPhotos.length > 0) {
              Button('清除照片').height(42).fontSize(14).enabled(!this.uploading && !this.writing)
                .fontColor(Constants.COLOR_PRIMARY_DARK).backgroundColor(Color.Transparent).onClick(() => { this.draftPhotos = []; })
            }
          }.width('100%')
          Row({ space: 8 }) {
            Button('取消').height(44).layoutWeight(1).enabled(!this.writing && !this.uploading)
              .fontColor(Constants.COLOR_PRIMARY_DARK).backgroundColor(Constants.COLOR_BG).onClick(() => { this.editing = false; })
            Button('添加').height(44).layoutWeight(1).enabled(!this.writing && !this.uploading)
              .backgroundColor(Constants.COLOR_PRIMARY).onClick(() => { this.save(); })
          }.width('100%')
        }.width('100%').padding(18).backgroundColor(Color.White)
      }.width('100%').constraintSize({ maxHeight: '92%' }).scrollBar(BarState.Off)
    }.width('100%').height('100%').backgroundColor('#66000000')
  }

  @Builder
  Detail(card: HouseholdCard) {
    Column() {
      Blank().layoutWeight(1)
      Scroll() {
        Column({ space: 10 }) {
          Text(card.title).fontSize(20).fontWeight(FontWeight.Bold).fontColor(Constants.COLOR_TEXT_PRIMARY).width('100%')
          Text(card.list + (this.meta(card) ? ' · ' + this.meta(card) : '')).fontSize(14).fontColor('#596274').width('100%')
          if (card.detail.length > 0) Text(card.detail).fontSize(16).fontColor(Constants.COLOR_TEXT_PRIMARY).width('100%')
          ForEach(this.photos, (photo: image.PixelMap) => {
            Image(photo).height(180).width('100%').objectFit(ImageFit.Contain).accessibilityText('卡片照片')
          })
          this.Actions(card)
          Button('关闭').height(44).width('100%').fontColor(Constants.COLOR_PRIMARY_DARK).backgroundColor(Constants.COLOR_BG)
            .onClick(() => { this.detailId = ''; this.photos = []; })
        }.width('100%').padding(18).backgroundColor(Color.White)
      }.width('100%').constraintSize({ maxHeight: '92%' }).scrollBar(BarState.Off)
    }.width('100%').height('100%').backgroundColor('#66000000')
  }

  private listOptions(): MenuElement[] {
    const names = new Set<string>(['日常']);
    this.cards.forEach((card: HouseholdCard) => { names.add(card.list); });
    const options: MenuElement[] = [{ value: '全部清单', action: () => { this.list = ''; } }];
    names.forEach((name: string) => { options.push({ value: name, action: () => { this.list = name; } }); });
    return options;
  }

  private count(state: string): number {
    return this.cards.filter((card: HouseholdCard) => card.status === state && (!this.list || this.list === card.list)).length;
  }

  private visible(): HouseholdCard[] {
    const result = this.cards.filter((card: HouseholdCard) => card.status === this.tab && (!this.list || this.list === card.list));
    return result.sort((left: HouseholdCard, right: HouseholdCard) => this.tab === 'done'
      ? right.doneAt - left.doneAt : left.list.localeCompare(right.list));
  }

  private startsList(card: HouseholdCard, index: number): boolean {
    return this.tab !== 'done' && !this.list && (index === 0 || this.visible()[index - 1]?.list !== card.list);
  }

  private meta(card: HouseholdCard): string {
    let label = card.assignee ? (card.assignee === 'wife' ? '老婆' : '老公') : '';
    if (card.doneAt > 0) label += ' · ' + Constants.formatDeadline(card.doneAt);
    if (card.images.length > 0) label += (label ? ' · ' : '') + card.images.length + ' 张照片';
    return label;
  }

  private async openDetail(card: HouseholdCard): Promise<void> {
    this.detailId = card.id;
    this.photos = [];
    for (const photo of card.images) {
      const bytes = await RelayService.getInstance().downloadImage(photo.id);
      if (!bytes || this.detailId !== card.id) return;
      const pixel = await ImageService.decode(bytes);
      if (pixel && this.detailId === card.id) this.photos = this.photos.concat([pixel]);
    }
  }

  private async change(card: HouseholdCard, action: string): Promise<void> {
    if (this.writing) return;
    this.writing = true;
    try {
      const ok = await RelayService.getInstance().householdAction(card, this.user, action);
      this.detailId = '';
      this.photos = [];
      if (!ok) this.toast('卡片状态可能已变化，正在刷新');
      this.onRefresh();
    } finally { this.writing = false; }
  }

  private openEditor(): void {
    this.draftList = this.list || '日常';
    this.draftTitles = '';
    this.draftDetail = '';
    this.draftPhotos = [];
    this.signature = '';
    this.editing = true;
  }

  private async addPhotos(): Promise<void> {
    this.uploading = true;
    try {
      const uris = await ImageService.pick(9 - this.draftPhotos.length);
      for (const uri of uris) {
        if (this.draftPhotos.length >= 9) break;
        const photo = await ImageService.prepare(uri);
        if (!photo) { this.toast('无法读取照片'); continue; }
        const saved = await RelayService.getInstance().uploadImage(photo.jpeg, 'image/jpeg', this.family, photo.w, photo.h);
        if (photo.pixelMap) await photo.pixelMap.release();
        if (saved) this.draftPhotos = this.draftPhotos.concat([saved.id]);
        else this.toast('照片上传失败');
      }
    } catch (err) { this.toast('照片上传失败'); }
    finally { this.uploading = false; }
  }

  private async save(): Promise<void> {
    const titles = this.draftTitles.split(/\r?\n/).map((line: string) => line.trim()).filter((line: string) => line.length > 0);
    const detail = this.draftDetail.trim();
    const name = this.draftList.trim() || '日常';
    if (name.length > 40 || titles.length === 0 || titles.length > 50 || titles.some((line: string) => line.length > 120)) {
      this.toast('请检查清单名、标题和数量（最多 50 张）'); return;
    }
    if (titles.length > 1 && (detail || this.draftPhotos.length > 0)) { this.toast('备注和照片仅用于单张卡片'); return; }
    const key = JSON.stringify([name, titles, detail, this.draftPhotos]);
    if (key !== this.signature) {
      this.signature = key;
      this.batch = titles.map((title: string) => {
        const card = new HouseholdDraft();
        card.id = util.generateRandomUUID(); card.title = title; card.detail = detail; card.imageIds = this.draftPhotos.slice();
        return card;
      });
    }
    this.writing = true;
    try {
      const ok = await RelayService.getInstance().addHousehold(this.family, this.user, name, this.batch);
      if (!ok) { this.toast('添加失败，原稿已保留，可以重试'); return; }
      this.editing = false; this.tab = 'available'; this.list = name; this.onRefresh();
    } finally { this.writing = false; }
  }

  private toast(message: string): void { this.getUIContext().getPromptAction().showToast({ message: message }); }
}
