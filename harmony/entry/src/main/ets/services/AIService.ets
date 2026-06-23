import { http } from '@kit.NetworkKit';
import { hilog } from '@kit.PerformanceAnalysisKit';
import { AppConfig } from '../config/AppConfig';
import { Constants } from '../constants/Constants';

const TAG = 'AIService';

// MiniMax 抽取结果（已转成本地用的结构）
export interface ExtractResult {
  title: string;
  detail: string;
  hasDeadline: boolean;
  deadline: number; // epoch ms，0 表示无
}

// 模型原始 JSON 形状（与跨端契约一致）
interface ExtractRaw {
  title: string;
  detail: string;
  hasDeadline: boolean;
  deadlineISO: string;
}

interface ChatMessage {
  role: string;
  content: string;
}

interface ThinkingConfig {
  type: string;
}

interface ChatRequestBody {
  model: string;
  messages: ChatMessage[];
  temperature: number;
  max_tokens: number;
  thinking: ThinkingConfig;
}

interface RespMessage {
  content: string;
}

interface RespChoice {
  message: RespMessage;
}

interface ChatResponse {
  choices: RespChoice[];
}

interface RequestHeader {
  'Content-Type': string;
  'Authorization': string;
}

// 跨端共享的 system prompt（与 docs/CONTRACT.md 逐字一致，改动须双方同步）
const SYSTEM_PROMPT: string =
`你是"派活儿"App 的待办解析助手。用户会口述/输入一件要交代对方做的事。
只输出一个严格的 JSON 对象，不要任何多余文字、不要 markdown 代码块：
{"title":"一句话动作标题(不超过15字)","detail":"补充细节，没有则空字符串","hasDeadline":true或false,"deadlineISO":"ISO8601带时区的截止时间，如 2026-06-21T20:00:00+08:00；无截止则空字符串"}
解析规则：
- 基于用户消息里给出的"当前时间"解析相对时间。
- "今晚X点"=当天X:00；"明早/明天X点"=次日X:00；"X小时后/X分钟后"=当前时间加对应时长；"下班前"约当天18:00；没提到时间则 hasDeadline=false。
- 时区固定 Asia/Shanghai (+08:00)。`;

export class AIService {
  private static instance: AIService;
  private httpClient: http.HttpRequest;

  private constructor() {
    this.httpClient = http.createHttp();
  }

  static getInstance(): AIService {
    if (!AIService.instance) {
      AIService.instance = new AIService();
    }
    return AIService.instance;
  }

  // 把一句话抽成 {标题, 细节, 截止时间}
  async extractTask(text: string): Promise<ExtractResult> {
    const nowIso = AIService.nowIsoCST();
    const userMsg = '当前时间：' + nowIso + '\n口述内容：' + text;

    const sysMsg: ChatMessage = { role: 'system', content: SYSTEM_PROMPT };
    const usrMsg: ChatMessage = { role: 'user', content: userMsg };
    const body: ChatRequestBody = {
      model: AppConfig.MINIMAX_MODEL,
      messages: [sysMsg, usrMsg],
      temperature: 0.2,
      max_tokens: 400,
      thinking: { type: 'disabled' } // 关闭思考，降延迟（仅 M3 生效）
    };
    const header: RequestHeader = {
      'Content-Type': 'application/json',
      'Authorization': 'Bearer ' + AppConfig.MINIMAX_API_KEY
    };

    // 失败(超时/网络抖动)自动重试一次
    let lastErr: string = '';
    for (let attempt = 0; attempt < 2; attempt++) {
      try {
        return await this.callOnce(body, header, text);
      } catch (err) {
        lastErr = err instanceof Error ? err.message : JSON.stringify(err);
        hilog.warn(0x0000, TAG, 'extract attempt ' + attempt + ' failed: ' + lastErr);
      }
    }
    throw new Error(lastErr);
  }

  private async callOnce(body: ChatRequestBody, header: RequestHeader, text: string): Promise<ExtractResult> {
    const client = http.createHttp();
    try {
      const response = await client.request(AppConfig.MINIMAX_URL, {
        method: http.RequestMethod.POST,
        header: header,
        extraData: JSON.stringify(body),
        connectTimeout: 20000,
        readTimeout: 20000
      });
      if (response.responseCode !== 200) {
        throw new Error('MiniMax HTTP ' + response.responseCode);
      }
      const parsed: ChatResponse = JSON.parse(response.result as string) as ChatResponse;
      if (!parsed.choices || parsed.choices.length === 0) {
        throw new Error('MiniMax 无返回内容');
      }
      // 思考型模型会带 <think>…</think>，先剥掉再取 JSON
      let content = parsed.choices[0].message.content;
      content = AIService.stripThink(content);
      const jsonStr = AIService.sliceJson(content);
      const raw: ExtractRaw = JSON.parse(jsonStr) as ExtractRaw;
      let deadlineMs = 0;
      if (raw.hasDeadline && raw.deadlineISO && raw.deadlineISO.length > 0) {
        const t = Date.parse(raw.deadlineISO);
        deadlineMs = isNaN(t) ? 0 : t;
      }
      const result: ExtractResult = {
        title: raw.title ? raw.title : text,
        detail: raw.detail ? raw.detail : '',
        hasDeadline: raw.hasDeadline === true,
        deadline: deadlineMs
      };
      hilog.info(0x0000, TAG, 'extract ok: ' + JSON.stringify(result));
      return result;
    } finally {
      client.destroy();
    }
  }

  // 去掉 <think>…</think> 思考段
  private static stripThink(s: string): string {
    const tag = '</think>';
    const end = s.indexOf(tag);
    if (end >= 0) {
      return s.substring(end + tag.length);
    }
    return s;
  }

  // 从文本中截取第一个 { 到最后一个 } 之间的 JSON
  private static sliceJson(s: string): string {
    const start = s.indexOf('{');
    const end = s.lastIndexOf('}');
    if (start >= 0 && end > start) {
      return s.substring(start, end + 1);
    }
    return s;
  }

  // 当前时间，固定 +08:00，如 2026-06-21T15:30:00+08:00
  private static nowIsoCST(): string {
    const d = new Date();
    return d.getFullYear() + '-' + Constants.pad2(d.getMonth() + 1) + '-' + Constants.pad2(d.getDate())
      + 'T' + Constants.pad2(d.getHours()) + ':' + Constants.pad2(d.getMinutes()) + ':' + Constants.pad2(d.getSeconds())
      + '+08:00';
  }
}
