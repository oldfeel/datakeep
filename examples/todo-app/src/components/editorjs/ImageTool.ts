import type {
  API,
  BlockTool,
  BlockToolConstructorOptions,
  PasteEvent,
} from '@editorjs/editorjs';
import {
  isPickCancelled,
  pickAndUploadImages,
  uploadTaskImage,
} from '../../imageUpload';

type ImageData = {
  url?: string;
  rel?: string;
  caption?: string;
};

type Config = {
  taskId: string;
  kind?: 'note' | 'comment';
  onBusy?: (busy: boolean) => void;
  onUploaded?: () => void;
};

export default class NoteImageTool implements BlockTool {
  static get toolbox() {
    return {
      title: '图片',
      icon: '<svg xmlns="http://www.w3.org/2000/svg" width="18" height="18" viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="2"><rect x="3" y="3" width="18" height="18" rx="2"/><circle cx="8.5" cy="8.5" r="1.5"/><path d="M21 15l-5-5L5 21"/></svg>',
    };
  }

  private api: API;
  private config: Config;
  private data: ImageData;
  private wrapper: HTMLDivElement | null = null;

  constructor({ data, api, config }: BlockToolConstructorOptions<ImageData, Config>) {
    this.api = api;
    this.config = config || { taskId: '', kind: 'note' };
    this.data = data || {};
  }

  render(): HTMLElement {
    const wrap = document.createElement('div');
    wrap.className = 'todo-note-image';
    this.wrapper = wrap;
    this.redraw();
    return wrap;
  }

  save(): ImageData {
    return { ...this.data };
  }

  validate(saved: ImageData): boolean {
    return Boolean(saved.url);
  }

  private redraw(): void {
    const wrap = this.wrapper;
    if (!wrap) return;
    wrap.replaceChildren();
    wrap.style.cssText = 'margin:8px 0;';

    if (this.data.url) {
      const img = document.createElement('img');
      img.src = this.data.url;
      img.alt = this.data.caption || '';
      img.style.cssText = 'max-width:100%;border-radius:8px;display:block;';
      wrap.appendChild(img);
      return;
    }

    const btn = document.createElement('button');
    btn.type = 'button';
    btn.textContent = '选择图片';
    btn.style.cssText =
      'border:1.5px dashed rgba(0,0,0,.48);background:transparent;border-radius:8px;padding:16px;width:100%;cursor:pointer;color:inherit;';
    btn.addEventListener('click', () => {
      void this.pickFromHost();
    });
    wrap.appendChild(btn);
  }

  static get pasteConfig() {
    return {
      files: {
        mimeTypes: ['image/*'],
        extensions: ['gif', 'jpg', 'jpeg', 'png', 'webp', 'bmp', 'svg'],
      },
    };
  }

  onPaste(event: PasteEvent): void {
    const detail = event.detail as { file?: File };
    if (detail.file) void this.uploadFile(detail.file);
  }

  private async pickFromHost(): Promise<void> {
    const taskId = this.config.taskId;
    if (!taskId) {
      this.api.notifier.show({ message: '无法上传：缺少任务' });
      return;
    }
    this.config.onBusy?.(true);
    const btn = this.wrapper?.querySelector('button');
    if (btn instanceof HTMLButtonElement) {
      btn.textContent = '选择中…';
      btn.disabled = true;
    }
    try {
      const kind = this.config.kind || 'note';
      const ups = await pickAndUploadImages(kind, taskId, false);
      const up = ups[0];
      if (!up) return;
      this.data = { url: up.url, rel: up.rel, caption: up.name };
      this.redraw();
      this.config.onUploaded?.();
    } catch (e) {
      if (isPickCancelled(e)) {
        if (btn instanceof HTMLButtonElement) {
          btn.textContent = '选择图片';
          btn.disabled = false;
        }
        return;
      }
      console.error(e);
      this.api.notifier.show({
        message: e instanceof Error ? e.message : '图片上传失败',
      });
      if (btn instanceof HTMLButtonElement) {
        btn.textContent = '选择图片';
        btn.disabled = false;
      }
    } finally {
      this.config.onBusy?.(false);
    }
  }

  private async uploadFile(file: File): Promise<void> {
    const taskId = this.config.taskId;
    if (!taskId) {
      this.api.notifier.show({ message: '无法上传：缺少任务' });
      return;
    }
    this.config.onBusy?.(true);
    const btn = this.wrapper?.querySelector('button');
    if (btn instanceof HTMLButtonElement) {
      btn.textContent = '上传中…';
      btn.disabled = true;
    }
    try {
      const kind = this.config.kind || 'note';
      const up = await uploadTaskImage(kind, taskId, file);
      this.data = { url: up.url, rel: up.rel, caption: file.name };
      this.redraw();
      this.config.onUploaded?.();
    } catch (e) {
      console.error(e);
      this.api.notifier.show({
        message: e instanceof Error ? e.message : '图片上传失败',
      });
      if (btn instanceof HTMLButtonElement) {
        btn.textContent = '选择图片';
        btn.disabled = false;
      }
    } finally {
      this.config.onBusy?.(false);
    }
  }
}
