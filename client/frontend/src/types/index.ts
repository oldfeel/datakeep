export interface Folder {
  id: string;
  label: string;
  path: string;
  type?: string;
  paused?: boolean;
  rescanIntervalS?: number;
  fsWatcherEnabled?: boolean;
  ignorePerms?: boolean;
  autoNormalize?: boolean;
  minDiskFree?: {
    value: number;
    unit: string;
  };
  versioning?: {
    type: string;
    params: any;
  };
  devices?: Array<{
    deviceID: string;
    introducer?: boolean;
    encryptionPassword?: string;
  }>;
  sharedDevices?: string[];
}

export interface Device {
  deviceID: string;
  name: string;
  addresses?: string[] | null;
  connected: boolean;
  isLocalNetwork: boolean;
} 