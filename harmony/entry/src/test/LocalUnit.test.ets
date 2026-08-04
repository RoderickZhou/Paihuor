import { describe, it, expect } from '@ohos/hypium';
import { FamilyProfile, FamilyRole } from '../main/ets/models/FamilyProfile';

export default function localUnitTest() {
  describe('FamilyProfile', () => {
    it('normalizes pairing data and resolves the counterpart', 0, () => {
      const wife: FamilyProfile = FamilyProfile.create(' fam-zx-001 ', FamilyRole.WIFE, ' 老婆 ');
      const husband: FamilyProfile = FamilyProfile.create('fam-zx-001', FamilyRole.HUSBAND, '老公');

      expect(wife.familyId).assertEqual('fam-zx-001');
      expect(wife.userName).assertEqual('老婆');
      expect(wife.counterpartUserId()).assertEqual(FamilyRole.HUSBAND);
      expect(husband.counterpartUserId()).assertEqual(FamilyRole.WIFE);
      expect(wife.isValid()).assertTrue();
    });

    it('only accepts tasks for the current family and user', 0, () => {
      const wife: FamilyProfile = FamilyProfile.create('fam-zx-001', FamilyRole.WIFE, '老婆');

      expect(wife.isTaskRelevant('fam-zx-001', FamilyRole.WIFE, FamilyRole.HUSBAND)).assertTrue();
      expect(wife.isTaskRelevant('fam-zx-001', FamilyRole.HUSBAND, FamilyRole.WIFE)).assertTrue();
      expect(wife.isTaskRelevant('fam-other', FamilyRole.HUSBAND, FamilyRole.WIFE)).assertFalse();
    });
  });
}
