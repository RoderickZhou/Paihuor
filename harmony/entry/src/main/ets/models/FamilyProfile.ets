export class FamilyRole {
  static readonly WIFE: string = 'wife';
  static readonly HUSBAND: string = 'husband';

  static counterpart(userId: string): string {
    return userId === FamilyRole.WIFE ? FamilyRole.HUSBAND : FamilyRole.WIFE;
  }

  static displayName(userId: string): string {
    return userId === FamilyRole.WIFE ? '老婆' : '老公';
  }
}

export class FamilyProfile {
  familyId: string = '';
  userId: string = FamilyRole.HUSBAND;
  userName: string = '';

  static create(familyId: string, userId: string, userName: string): FamilyProfile {
    const profile = new FamilyProfile();
    profile.familyId = familyId.trim();
    profile.userId = userId === FamilyRole.WIFE ? FamilyRole.WIFE : FamilyRole.HUSBAND;
    profile.userName = userName.trim();
    return profile;
  }

  static fromJson(value: FamilyProfile): FamilyProfile {
    return FamilyProfile.create(value.familyId, value.userId, value.userName);
  }

  counterpartUserId(): string {
    return FamilyRole.counterpart(this.userId);
  }

  displayName(): string {
    return this.userName.length > 0 ? this.userName : FamilyRole.displayName(this.userId);
  }

  isTaskRelevant(familyId: string, fromUserId: string, toUserId: string): boolean {
    return familyId === this.familyId
      && (fromUserId === this.userId || toUserId === this.userId);
  }

  isValid(): boolean {
    return this.familyId.length > 0
      && (this.userId === FamilyRole.WIFE || this.userId === FamilyRole.HUSBAND);
  }
}
