import { TaskImage, TaskItem, TaskStatus } from './TaskModels';

export class HouseholdCard {
  id: string = '';
  familyId: string = '';
  list: string = '';
  title: string = '';
  detail: string = '';
  status: string = '';
  assignee: string = '';
  creator: string = '';
  createdAt: number = 0;
  doneAt: number = 0;
  revision: number = 0;
  images: TaskImage[] = [];
}

export class HouseholdDraft {
  id: string = '';
  title: string = '';
  detail: string = '';
  imageIds: string[] = [];
}

export function householdTask(card: HouseholdCard): TaskItem {
  const task = new TaskItem();
  task.id = card.id;
  task.objectId = card.id;
  task.familyId = card.familyId;
  task.toUserId = card.assignee;
  task.title = card.title;
  task.detail = card.detail;
  task.images = card.images;
  task.createdAt = card.createdAt;
  task.status = TaskStatus.RECEIVED;
  task.householdId = card.id;
  return task;
}
