// 设备类型定义
export interface Device {
  deviceID: string;
  name: string;
  addresses: string[];
  compression: string;
  certName: string;
  introducer: boolean;
  skipIntroductionRemovals: boolean;
  introducedBy: string;
  paused: boolean;
  allowedNetworks: string[];
  autoAcceptFolders: boolean;
  maxSendKbps: number;
  maxRecvKbps: number;
  ignoredFolders: string[];
  maxRequestKiB: number;
  untrusted: boolean;
  remoteGUIPort: number;
  numConnections: number;
  // 增强字段
  connected?: boolean;
  connectionType?: string;
  clientVersion?: string;
  inBytesTotal?: number;
  outBytesTotal?: number;
  isLocalNetwork?: boolean;
  crypto?: string;
  lanAddresses?: string[];
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