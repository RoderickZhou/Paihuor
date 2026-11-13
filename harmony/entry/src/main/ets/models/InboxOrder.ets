import { TaskItem, TaskStatus } from './TaskModels';

export enum InboxGroup {
  OVERDUE, TODAY, WAITING, OTHER
}

export class InboxOrder {
  static tomorrow(now: number): number {
    const date = new Date(now);
    date.setHours(0, 0, 0, 0);
    date.setDate(date.getDate() + 1);
    return date.getTime();
  }

  static group(task: TaskItem, user: string, now: number, tomorrow: number): InboxGroup {
    if (task.archived || task.deleted || task.status === TaskStatus.DONE) return InboxGroup.OTHER;
    if (task.deadline > 0 && task.deadline <= now) return InboxGroup.OVERDUE;
    if (task.deadline > 0 && task.deadline < tomorrow) return InboxGroup.TODAY;
    if (task.toUserId === user && task.status === TaskStatus.PENDING) return InboxGroup.WAITING;
    return InboxGroup.OTHER;
  }

  static sort(tasks: TaskItem[], user: string, now: number, tomorrow: number): TaskItem[] {
    return tasks.sort((a: TaskItem, b: TaskItem): number => {
      const left = InboxOrder.group(a, user, now, tomorrow);
      const right = InboxOrder.group(b, user, now, tomorrow);
      if (left !== right) return left - right;
      if (left === InboxGroup.OVERDUE || left === InboxGroup.TODAY) {
        if (a.deadline !== b.deadline) return a.deadline - b.deadline;
      }
      return b.createdAt - a.createdAt;
    });
  }
}
