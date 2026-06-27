// 桌面服务卡片 UI（ArkTS 卡片，独立卡片运行时，组件能力受限，颜色硬编码）
let storage = new LocalStorage();

@Entry(storage)
@Component
struct WidgetCard {
  @LocalStorageProp('count') count: number = 0;
  @LocalStorageProp('t1') t1: string = '';
  @LocalStorageProp('t2') t2: string = '';
  @LocalStorageProp('empty') empty: boolean = true;

  build() {
    Column() {
      Row() {
        Text('🌱 派活儿')
          .fontSize(14).fontWeight(FontWeight.Bold).fontColor('#212121')
        Blank()
        if (!this.empty && this.count > 0) {
          Text('' + this.count)
            .fontSize(11).fontColor('#FFFFFF')
            .backgroundColor('#F44336').borderRadius(9)
            .padding({ left: 6, right: 6, top: 1, bottom: 1 })
        }
      }
      .width('100%')

      if (this.empty) {
        Column() {
          Text('暂无待办').fontSize(13).fontColor('#9E9E9E')
        }
        .layoutWeight(1).width('100%').justifyContent(FlexAlign.Center)
      } else {
        Column() {
          Text(this.t1)
            .fontSize(13).fontColor('#212121')
            .maxLines(1).textOverflow({ overflow: TextOverflow.Ellipsis })
            .width('100%').margin({ top: 8 })
          if (this.t2.length > 0) {
            Text(this.t2)
              .fontSize(13).fontColor('#212121')
              .maxLines(1).textOverflow({ overflow: TextOverflow.Ellipsis })
              .width('100%').margin({ top: 6 })
          }
          if (this.count > 2) {
            Text('还有 ' + (this.count - 2) + ' 件…')
              .fontSize(12).fontColor('#9E9E9E').margin({ top: 6 })
          }
        }
        .layoutWeight(1).width('100%').alignItems(HorizontalAlign.Start)
      }
    }
    .width('100%').height('100%').padding(12)
    .backgroundColor('#FFFFFF')
    .onClick(() => {
      postCardAction(this, {
        action: 'router',
        abilityName: 'EntryAbility',
        params: {}
      });
    })
  }
}
