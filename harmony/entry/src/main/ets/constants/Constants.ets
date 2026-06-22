// 全局常量 + 主题色 + 时间工具（薄荷绿主题沿用《归零》）
export class Constants {
  // 主题色
  static readonly COLOR_PRIMARY: string = '#4CAF50';
  static readonly COLOR_PRIMARY_LIGHT: string = '#81C784';
  static readonly COLOR_PRIMARY_DARK: string = '#388E3C';
  static readonly COLOR_BG: string = '#F5F7F6';
  static readonly COLOR_CARD_BG: string = '#FFFFFF';
  static readonly COLOR_TEXT_PRIMARY: string = '#212121';
  static readonly COLOR_TEXT_SECONDARY: string = '#9E9E9E';
  static readonly COLOR_WARNING: string = '#FF9800';
  static readonly COLOR_DANGER: string = '#F44336';

  // 本地存储
  static readonly PREF_NAME: string = 'paihuor_store';
  static readonly PREF_TASKS_KEY: string = 'tasks';

  // 快捷截止时间：code>0 表示 N 分钟后；-1 今晚20点；-2 明早9点
  static quickDeadline(code: number): number {
    if (code > 0) {
      return Date.now() + code * 60 * 1000;
    }
    const d = new Date();
    if (code === -1) {
      d.setHours(20, 0, 0, 0);
      return d.getTime();
    }
    if (code === -2) {
      d.setDate(d.getDate() + 1);
      d.setHours(9, 0, 0, 0);
      return d.getTime();
    }
    return Date.now();
  }

  static pad2(n: number): string {
    return n < 10 ? '0' + n : '' + n;
  }

  static formatDeadline(ms: number): string {
    if (!ms || ms <= 0) {
      return '未设时间';
    }
    const d = new Date(ms);
    const now = new Date();
    const hh = Constants.pad2(d.getHours());
    const mm = Constants.pad2(d.getMinutes());
    const sameDay = d.getFullYear() === now.getFullYear() && d.getMonth() === now.getMonth() && d.getDate() === now.getDate();
    const tmr = new Date(now.getTime());
    tmr.setDate(now.getDate() + 1);
    const isTmr = d.getFullYear() === tmr.getFullYear() && d.getMonth() === tmr.getMonth() && d.getDate() === tmr.getDate();
    if (sameDay) {
      return '今天 ' + hh + ':' + mm;
    }
    if (isTmr) {
      return '明天 ' + hh + ':' + mm;
    }
    return Constants.pad2(d.getMonth() + 1) + '-' + Constants.pad2(d.getDate()) + ' ' + hh + ':' + mm;
  }

  static formatRemaining(ms: number): string {
    if (!ms || ms <= 0) {
      return '';
    }
    const diff = ms - Date.now();
    if (diff <= 0) {
      return '已超时';
    }
    const mins = Math.floor(diff / 60000);
    const h = Math.floor(mins / 60);
    const m = mins % 60;
    if (h > 0) {
      return '还剩 ' + h + ' 小时 ' + m + ' 分';
    }
    return '还剩 ' + m + ' 分';
  }
}
