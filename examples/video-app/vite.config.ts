import { defineConfig, type Plugin } from 'vite';
import react from '@vitejs/plugin-react';
import appJson from './app.json' with { type: 'json' };

/** 保证安装包根目录含 app.json（含 aiEditable 等清单字段） */
function copyAppJson(): Plugin {
  return {
    name: 'copy-app-json',
    generateBundle() {
      this.emitFile({
        type: 'asset',
        fileName: 'app.json',
        source: `${JSON.stringify(appJson, null, 2)}\n`,
      });
    },
  };
}

// https://vite.dev/config/
export default defineConfig({
  plugins: [react(), copyAppJson()],
  base: './',
  build: {
    outDir: 'www',
    emptyOutDir: true,
  },
});
