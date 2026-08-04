import { AbilityConstant, ConfigurationConstant, UIAbility, Want } from '@kit.AbilityKit';
import { hilog } from '@kit.PerformanceAnalysisKit';
import { window } from '@kit.ArkUI';
import { TaskStore } from '../services/TaskStore';
import { DeviceService } from '../services/DeviceService';
import { ProfileService } from '../services/ProfileService';

const DOMAIN = 0x0000;

export default class EntryAbility extends UIAbility {
  onCreate(want: Want, launchParam: AbilityConstant.LaunchParam): void {
    try {
      this.context.getApplicationContext().setColorMode(ConfigurationConstant.ColorMode.COLOR_MODE_NOT_SET);
    } catch (err) {
      hilog.error(DOMAIN, 'testTag', 'Failed to set colorMode. Cause: %{public}s', JSON.stringify(err));
    }
    // 启动即初始化本地任务存储
    TaskStore.getInstance().init(this.context);
    this.initializeProfile();
    // 点击通知冷启动：参数在 want.parameters
    if (want.parameters) {
      hilog.info(DOMAIN, 'PushKit', 'cold start params: %{public}s', JSON.stringify(want.parameters));
    }
    hilog.info(DOMAIN, 'testTag', '%{public}s', 'Ability onCreate');
  }

  // 点击通知热启动（launchType=singleton 才可靠触发）
  onNewWant(want: Want, launchParam: AbilityConstant.LaunchParam): void {
    if (want.parameters) {
      hilog.info(DOMAIN, 'PushKit', 'hot start params: %{public}s', JSON.stringify(want.parameters));
    }
  }

  onDestroy(): void {
    hilog.info(DOMAIN, 'testTag', '%{public}s', 'Ability onDestroy');
  }

  onWindowStageCreate(windowStage: window.WindowStage): void {
    // Main window is created, set main page for this ability
    hilog.info(DOMAIN, 'testTag', '%{public}s', 'Ability onWindowStageCreate');

    windowStage.loadContent('pages/Index', (err) => {
      if (err.code) {
        hilog.error(DOMAIN, 'testTag', 'Failed to load the content. Cause: %{public}s', JSON.stringify(err));
        return;
      }
      hilog.info(DOMAIN, 'testTag', 'Succeeded in loading the content.');
    });
  }

  onWindowStageDestroy(): void {
    // Main window is destroyed, release UI related resources
    hilog.info(DOMAIN, 'testTag', '%{public}s', 'Ability onWindowStageDestroy');
  }

  onForeground(): void {
    // Ability has brought to foreground
    hilog.info(DOMAIN, 'testTag', '%{public}s', 'Ability onForeground');
    ProfileService.getInstance().whenReady().then(() => {
      DeviceService.getInstance().ensureRegisteredToken();
    });
  }

  onBackground(): void {
    // Ability has back to background
    hilog.info(DOMAIN, 'testTag', '%{public}s', 'Ability onBackground');
  }

  private async initializeProfile(): Promise<void> {
    await ProfileService.getInstance().init(this.context);
    if (ProfileService.getInstance().getProfile()) {
      await DeviceService.getInstance().ensureRegisteredToken();
    }
  }
}
