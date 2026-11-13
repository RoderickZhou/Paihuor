import { common } from '@kit.AbilityKit';
import { preferences } from '@kit.ArkData';
import { hilog } from '@kit.PerformanceAnalysisKit';
import { util } from '@kit.ArkTS';
import { FamilyProfile } from '../models/FamilyProfile';

const TAG = 'ProfileService';
export const PROFILE_PREF_NAME: string = 'paihuor_store';
export const PROFILE_PREF_KEY: string = 'family_profile';

export class ProfileService {
  private static instance: ProfileService;
  private store: preferences.Preferences | null = null;
  private profile: FamilyProfile | null = null;
  private initPromise: Promise<void> | null = null;
  private installationId: string = '';

  static getInstance(): ProfileService {
    if (!ProfileService.instance) {
      ProfileService.instance = new ProfileService();
    }
    return ProfileService.instance;
  }

  init(context: common.Context): Promise<void> {
    if (!this.initPromise) {
      this.initPromise = this.doInit(context);
    }
    return this.initPromise;
  }

  async whenReady(): Promise<void> {
    if (this.initPromise) {
      await this.initPromise;
    }
  }

  getProfile(): FamilyProfile | null {
    return this.profile;
  }

  deviceId(): string {
    return this.installationId;
  }

  async save(familyId: string, userId: string, userName: string): Promise<FamilyProfile> {
    const profile = FamilyProfile.create(familyId, userId, userName);
    if (!profile.isValid()) {
      throw new Error('家庭配对信息不完整');
    }
    this.profile = profile;
    if (this.store) {
      await this.store.put(PROFILE_PREF_KEY, JSON.stringify(profile));
      await this.store.flush();
    }
    return profile;
  }

  private async doInit(context: common.Context): Promise<void> {
    try {
      this.store = await preferences.getPreferences(context, { name: PROFILE_PREF_NAME });
      this.installationId = await this.store.get('installation_id', '') as string;
      if (this.installationId.length === 0) {
        this.installationId = util.generateRandomUUID();
        await this.store.put('installation_id', this.installationId);
        await this.store.flush();
      }
      const raw = await this.store.get(PROFILE_PREF_KEY, '') as string;
      if (raw.length > 0) {
        const saved = JSON.parse(raw) as FamilyProfile;
        const profile = FamilyProfile.fromJson(saved);
        this.profile = profile.isValid() ? profile : null;
      }
    } catch (err) {
      hilog.error(0x0000, TAG, 'init failed: ' + JSON.stringify(err));
      this.profile = null;
    }
  }
}

export function readFamilyProfileSync(context: common.Context): FamilyProfile | null {
  try {
    const store = preferences.getPreferencesSync(context, { name: PROFILE_PREF_NAME });
    const raw = store.getSync(PROFILE_PREF_KEY, '') as string;
    if (raw.length === 0) {
      return null;
    }
    const saved = JSON.parse(raw) as FamilyProfile;
    const profile = FamilyProfile.fromJson(saved);
    return profile.isValid() ? profile : null;
  } catch (err) {
    hilog.warn(0x0000, TAG, 'sync read failed: ' + JSON.stringify(err));
    return null;
  }
}
