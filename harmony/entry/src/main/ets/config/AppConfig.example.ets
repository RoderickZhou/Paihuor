// 模板：复制本文件为同目录下的 AppConfig.ets 并填入真实值。
// AppConfig.ets 已被 .gitignore 排除（含密钥），绝不提交。
export class AppConfig {
  // MiniMax（语义抽取：一句话 → {title, detail, deadline}）
  static readonly MINIMAX_API_KEY: string = '<填 MiniMax API Key>';
  static readonly MINIMAX_MODEL: string = 'MiniMax-M3'; // M3 可关思考、低延迟（M2.7 强制思考慢）
  static readonly MINIMAX_URL: string = 'https://api.minimaxi.com/v1/chat/completions';

  // 后端中继（10.1.30.175 上的 Node，端口 8787）。
  // 公网经 SakuraFrp TCP 隧道暴露（国内节点封明文 HTTP，故用海外节点，如东京 frp-xxx.com:端口）。
  static readonly RELAY_BASE_URL: string = '<填 公网中继地址，如 http://frp-xxx.com:64728>';
  static readonly RELAY_LAN_URL: string = 'http://10.1.30.175:8787'; // 同局域网直连(快)，连不上自动回退公网
  static readonly RELAY_KEY: string = '<填 中继密钥 PAIHUOR_KEY>';

  // 家庭配对（两端填同一个 familyId；本机=老公/Pura70，对方=老婆/iPhone）
  static readonly FAMILY_ID: string = 'fam-xxx';
  static readonly MY_USER_ID: string = 'husband';
  static readonly OTHER_USER_ID: string = 'wife';
}
