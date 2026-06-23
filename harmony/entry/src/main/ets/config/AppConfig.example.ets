// 模板：复制本文件为 AppConfig.ets 并填入真实值。AppConfig.ets 已被 .gitignore 排除，不提交。
export class AppConfig {
  static readonly MINIMAX_API_KEY: string = '<填 MiniMax API Key>';
  static readonly MINIMAX_MODEL: string = 'MiniMax-M3';
  static readonly MINIMAX_URL: string = 'https://api.minimaxi.com/v1/chat/completions';

  // 自建中继（175 上的 Node + cloudflared）
  static readonly RELAY_BASE_URL: string = '<填 中继公网地址，如 https://xxx.trycloudflare.com>';
  static readonly RELAY_KEY: string = '<填 中继密钥>';

  // 家庭配对（两端同一个 familyId；本机 userId 与对方）
  static readonly FAMILY_ID: string = 'fam-xxx';
  static readonly MY_USER_ID: string = 'husband';
  static readonly OTHER_USER_ID: string = 'wife';
}
