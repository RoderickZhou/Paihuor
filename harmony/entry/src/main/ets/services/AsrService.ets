import { speechRecognizer } from '@kit.CoreSpeechKit';
import { audio } from '@kit.AudioKit';
import { hilog } from '@kit.PerformanceAnalysisKit';

const TAG = 'AsrService';
const CHUNK = 640; // writeAudio 要求每块 640 或 1280 字节

// 端侧实时中文语音识别（Core Speech Kit + AudioCapturer 采 16k/16bit/单声道 PCM）
export class AsrService {
  private static instance: AsrService;
  private engine: speechRecognizer.SpeechRecognitionEngine | null = null;
  private capturer: audio.AudioCapturer | null = null;
  private sessionId: string = '';
  private listening: boolean = false;
  private latestText: string = '';
  private pending: Uint8Array = new Uint8Array(0);

  private onPartial: ((t: string) => void) | null = null;
  private onFinal: ((t: string) => void) | null = null;
  private onErr: ((m: string) => void) | null = null;

  static getInstance(): AsrService {
    if (!AsrService.instance) {
      AsrService.instance = new AsrService();
    }
    return AsrService.instance;
  }

  private async ensureEngine(): Promise<void> {
    if (this.engine) {
      return;
    }
    const extra: Record<string, Object> = { 'locate': 'CN', 'recognizerMode': 'short' };
    const params: speechRecognizer.CreateEngineParams = {
      language: 'zh-CN',
      online: 1, // 1 = 离线端侧
      extraParams: extra
    };
    const engine = await speechRecognizer.createEngine(params);
    const listener: speechRecognizer.RecognitionListener = {
      onStart: (sessionId: string, eventMessage: string) => {
        hilog.info(0x0000, TAG, 'onStart ' + sessionId);
      },
      onEvent: (sessionId: string, eventCode: number, eventMessage: string) => {
        hilog.info(0x0000, TAG, 'onEvent ' + eventCode);
      },
      onResult: (sessionId: string, result: speechRecognizer.SpeechRecognitionResult) => {
        this.latestText = result.result;
        if (this.onPartial) {
          this.onPartial(result.result);
        }
      },
      onComplete: (sessionId: string, eventMessage: string) => {
        this.listening = false;
        if (this.onFinal) {
          this.onFinal(this.latestText);
        }
      },
      onError: (sessionId: string, errorCode: number, errorMessage: string) => {
        this.listening = false;
        if (this.onErr) {
          this.onErr('ASR ' + errorCode + ': ' + errorMessage);
        }
      }
    };
    engine.setListener(listener);
    this.engine = engine;
  }

  private async ensureCapturer(): Promise<void> {
    if (this.capturer) {
      return;
    }
    const streamInfo: audio.AudioStreamInfo = {
      samplingRate: audio.AudioSamplingRate.SAMPLE_RATE_16000,
      channels: audio.AudioChannel.CHANNEL_1,
      sampleFormat: audio.AudioSampleFormat.SAMPLE_FORMAT_S16LE,
      encodingType: audio.AudioEncodingType.ENCODING_TYPE_RAW
    };
    const capturerInfo: audio.AudioCapturerInfo = {
      source: audio.SourceType.SOURCE_TYPE_MIC,
      capturerFlags: 0
    };
    const options: audio.AudioCapturerOptions = {
      streamInfo: streamInfo,
      capturerInfo: capturerInfo
    };
    const capturer = await audio.createAudioCapturer(options);
    capturer.on('readData', (buffer: ArrayBuffer) => {
      this.feed(buffer);
    });
    this.capturer = capturer;
  }

  // 把采集到的 PCM 合并后按 640 字节切块写入识别引擎
  private feed(buffer: ArrayBuffer): void {
    const engine = this.engine;
    if (!engine || !this.listening) {
      return;
    }
    const incoming = new Uint8Array(buffer);
    const merged = new Uint8Array(this.pending.length + incoming.length);
    merged.set(this.pending, 0);
    merged.set(incoming, this.pending.length);

    let offset = 0;
    while (merged.length - offset >= CHUNK) {
      const chunk = merged.slice(offset, offset + CHUNK);
      engine.writeAudio(this.sessionId, chunk);
      offset += CHUNK;
    }
    this.pending = merged.slice(offset);
  }

  async start(onPartial: (t: string) => void, onFinal: (t: string) => void, onErr: (m: string) => void): Promise<void> {
    this.onPartial = onPartial;
    this.onFinal = onFinal;
    this.onErr = onErr;

    await this.ensureEngine();
    await this.ensureCapturer();

    const engine = this.engine;
    const capturer = this.capturer;
    if (!engine || !capturer) {
      onErr('引擎或录音初始化失败');
      return;
    }

    this.latestText = '';
    this.pending = new Uint8Array(0);
    this.sessionId = 'sess-' + Date.now();
    this.listening = true;

    const startParams: speechRecognizer.StartParams = {
      sessionId: this.sessionId,
      audioInfo: { audioType: 'pcm', sampleRate: 16000, soundChannel: 1, sampleBit: 16 }
    };
    engine.startListening(startParams);
    await capturer.start();
  }

  async stop(): Promise<void> {
    if (!this.listening) {
      return;
    }
    this.listening = false;
    if (this.capturer) {
      await this.capturer.stop();
    }
    if (this.engine) {
      this.engine.finish(this.sessionId);
    }
  }

  async cancel(): Promise<void> {
    this.listening = false;
    if (this.capturer) {
      await this.capturer.stop();
    }
    if (this.engine) {
      this.engine.cancel(this.sessionId);
    }
  }
}
