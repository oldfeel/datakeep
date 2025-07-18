// 设备类型定义
export interface Device {
  id: string;
  name: string;
  address: string;
  status: 'connected' | 'disconnected' | 'unknown';
  isLocal: boolean;
}

// 文件夹类型定义
export interface Folder {
  id: string;
  label: string;
  path: string;
  type: 'sendonly' | 'receiveonly' | 'sendreceive';
  devices: string[]; // 设备ID列表
}

// API 响应格式
export interface ApiResponse<T> {
  code: number;
  data: T;
}

// 搜索框状态
export interface SearchState {
  query: string;
  isSearching: boolean;
}

// 应用状态
export interface AppState {
  devices: Device[];
  folders: Folder[];
  isLoading: boolean;
  error: string | null;
} 