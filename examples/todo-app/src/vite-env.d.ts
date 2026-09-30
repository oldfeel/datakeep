/// <reference types="vite/client" />

declare module 'sql.js/dist/sql-wasm-browser.wasm?url' {
  const url: string;
  export default url;
}

declare module 'sql.js/dist/sql-wasm-browser.js' {
  import type { SqlJsStatic } from 'sql.js';
  const initSqlJs: (config?: {
    locateFile?: (file: string, prefix?: string) => string;
  }) => Promise<SqlJsStatic>;
  export default initSqlJs;
}
