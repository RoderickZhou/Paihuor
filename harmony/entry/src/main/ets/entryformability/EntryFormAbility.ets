import { FormExtensionAbility, formBindingData, formInfo, formProvider } from '@kit.FormKit';
import { Want } from '@kit.AbilityKit';
import { buildCardData, addFormId, removeFormId } from '../services/WidgetCardData';

// 桌面服务卡片提供方：添加卡片时记下 formId 并给初始数据；系统定时/App 主动触发更新时刷新
export default class EntryFormAbility extends FormExtensionAbility {
  onAddForm(want: Want): formBindingData.FormBindingData {
    let formId = '';
    if (want.parameters) {
      formId = want.parameters[formInfo.FormParam.IDENTITY_KEY] as string;
    }
    addFormId(this.context, formId);
    return formBindingData.createFormBindingData(buildCardData(this.context));
  }

  onUpdateForm(formId: string): void {
    const binding = formBindingData.createFormBindingData(buildCardData(this.context));
    formProvider.updateForm(formId, binding);
  }

  onRemoveForm(formId: string): void {
    removeFormId(this.context, formId);
  }
}
