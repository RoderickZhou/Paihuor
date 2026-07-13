import { image } from '@kit.ImageKit';
import { fileIo } from '@kit.CoreFileKit';
import { photoAccessHelper } from '@kit.MediaLibraryKit';
import { hilog } from '@kit.PerformanceAnalysisKit';

const TAG = 'ImageService';
const MAX_EDGE = 1600;   // 最长边上限：省穿透隧道流量、加快对端加载
const JPEG_QUALITY = 85;

// 处理好的一张图：jpeg 用于上传，pixelMap 用于本端预览
export class PreparedImage {
  jpeg: ArrayBuffer = new ArrayBuffer(0);
  pixelMap: image.PixelMap | null = null;
  w: number = 0;
  h: number = 0;
}

interface Wh {
  w: number;
  h: number;
}

// 图片选择/编解码工具：统一把选中的图（可能是 HEIC）转成跨端可显示的 JPEG 并降采样
export class ImageService {
  // 拉起系统相册选择器（免权限），返回选中的 file uri 列表
  static async pick(maxCount: number): Promise<string[]> {
    try {
      const options = new photoAccessHelper.PhotoSelectOptions();
      options.MIMEType = photoAccessHelper.PhotoViewMIMETypes.IMAGE_TYPE;
      options.maxSelectNumber = maxCount > 0 ? maxCount : 1;
      const picker = new photoAccessHelper.PhotoViewPicker();
      const result = await picker.select(options);
      return result.photoUris ? result.photoUris : [];
    } catch (err) {
      hilog.error(0x0000, TAG, 'pick: ' + JSON.stringify(err));
      return [];
    }
  }

  // 读取选中图片的原始字节
  private static readUriBytes(uri: string): ArrayBuffer {
    const f = fileIo.openSync(uri, fileIo.OpenMode.READ_ONLY);
    try {
      const st = fileIo.statSync(f.fd);
      const buf = new ArrayBuffer(st.size);
      fileIo.readSync(f.fd, buf);
      return buf;
    } finally {
      fileIo.closeSync(f);
    }
  }

  // 按最长边等比缩放，得到目标像素尺寸（不放大）
  private static scaledSize(w: number, h: number): Wh {
    const longest = Math.max(w, h);
    if (longest <= 0 || longest <= MAX_EDGE) {
      return { w: w, h: h };
    }
    const factor = MAX_EDGE / longest;
    return { w: Math.max(1, Math.round(w * factor)), h: Math.max(1, Math.round(h * factor)) };
  }

  // 选中图片 → 解码 → 等比降采样 → 重编码为 JPEG（顺带把 HEIC 转成跨端可显示格式）
  static async prepare(uri: string): Promise<PreparedImage | null> {
    let src: image.ImageSource | null = null;
    let packer: image.ImagePacker | null = null;
    try {
      const raw = ImageService.readUriBytes(uri);
      src = image.createImageSource(raw);
      const info = await src.getImageInfo();
      const target = ImageService.scaledSize(info.size.width, info.size.height);
      const decodeOpts: image.DecodingOptions = {
        desiredSize: { width: target.w, height: target.h }
      };
      const pm = await src.createPixelMap(decodeOpts);
      packer = image.createImagePacker();
      const packOpts: image.PackingOption = { format: 'image/jpeg', quality: JPEG_QUALITY };
      const jpeg = await packer.packing(pm, packOpts);
      const out = new PreparedImage();
      out.jpeg = jpeg;
      out.pixelMap = pm;
      out.w = target.w;
      out.h = target.h;
      return out;
    } catch (err) {
      hilog.error(0x0000, TAG, 'prepare: ' + JSON.stringify(err));
      return null;
    } finally {
      if (src) {
        try { await src.release(); } catch (e) { }
      }
      if (packer) {
        try { await packer.release(); } catch (e) { }
      }
    }
  }

  // 字节 → PixelMap（用于详情/全屏显示对方发来的图）
  static async decode(bytes: ArrayBuffer): Promise<image.PixelMap | null> {
    let src: image.ImageSource | null = null;
    try {
      src = image.createImageSource(bytes);
      return await src.createPixelMap();
    } catch (err) {
      hilog.error(0x0000, TAG, 'decode: ' + JSON.stringify(err));
      return null;
    } finally {
      if (src) {
        try { await src.release(); } catch (e) { }
      }
    }
  }
}
