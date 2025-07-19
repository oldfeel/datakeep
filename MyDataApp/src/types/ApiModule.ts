import { NativeModules } from 'react-native';

interface ApiModuleInterface {
  getDevices(): Promise<string>;
  getDeviceFolders(deviceId: string): Promise<string>;
  getFolderFiles(folderId: string): Promise<string>;
  getLocalDeviceId(): Promise<string>;
  getWifiInfo(): Promise<string>;
}

const { ApiModule } = NativeModules;

export default ApiModule as ApiModuleInterface; 