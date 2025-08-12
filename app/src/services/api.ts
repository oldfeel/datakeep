import { Device, Folder, ApiResponse } from '../types';
import ApiModule from '../types/ApiModule';

class ApiService {
  // 获取设备列表
  async getDevices(): Promise<Device[]> {
    try {
      console.log('🌐 通过 Native Module 获取设备列表...');
      const response = await ApiModule.getDevices();
      const data = JSON.parse(response);
      console.log('✅ 设备列表获取成功，设备数量:', data.data?.length || 0);
      return data.data || [];
    } catch (error) {
      console.error('❌ 获取设备列表失败:', error);
      throw error;
    }
  }

  // 获取文件夹列表
  async getFolders(): Promise<Folder[]> {
    try {
      console.log('🌐 通过 Native Module 获取文件夹列表...');
      const response = await ApiModule.getDeviceFolders('local');
      const data = JSON.parse(response);
      console.log('✅ 文件夹列表获取成功，文件夹数量:', data.data?.length || 0);
      return data.data || [];
    } catch (error) {
      console.error('❌ 获取文件夹列表失败:', error);
      throw error;
    }
  }

  // 获取特定设备的文件夹
  async getDeviceFolders(deviceId: string): Promise<Folder[]> {
    try {
      console.log(`🌐 通过 Native Module 获取设备 ${deviceId} 的文件夹...`);
      const response = await ApiModule.getDeviceFolders(deviceId);
      const data = JSON.parse(response);
      console.log('✅ 设备文件夹获取成功，文件夹数量:', data.data?.length || 0);
      return data.data || [];
    } catch (error) {
      console.error('❌ 获取设备文件夹失败:', error);
      throw error;
    }
  }

  // 获取文件夹内容
  async getFolderContent(folderId: string, path: string = ''): Promise<any> {
    try {
      console.log(`🌐 通过 Native Module 获取文件夹 ${folderId} 的内容...`);
      const response = await ApiModule.getFolderFiles(folderId);
      const data = JSON.parse(response);
      console.log('✅ 文件夹内容获取成功');
      return data.data || [];
    } catch (error) {
      console.error('❌ 获取文件夹内容失败:', error);
      throw error;
    }
  }

  // 获取本机设备ID
  async getLocalDeviceId(): Promise<string> {
    try {
      console.log('🌐 通过 Native Module 获取本机设备ID...');
      const response = await ApiModule.getLocalDeviceId();
      const data = JSON.parse(response);
      console.log('✅ 本机设备ID获取成功');
      return data.data?.deviceId || '';
    } catch (error) {
      console.error('❌ 获取本机设备ID失败:', error);
      throw error;
    }
  }

  // 获取WiFi信息
  async getWifiInfo(): Promise<any> {
    try {
      console.log('🌐 通过 Native Module 获取WiFi信息...');
      const response = await ApiModule.getWifiInfo();
      const data = JSON.parse(response);
      console.log('✅ WiFi信息获取成功');
      return data.data || {};
    } catch (error) {
      console.error('❌ 获取WiFi信息失败:', error);
      throw error;
    }
  }

  // 获取附近发现的设备
  async getNearbyDevices(): Promise<string[]> {
    try {
      console.log('🌐 通过 Native Module 获取附近设备...');
      const response = await ApiModule.getNearbyDevices();
      const result = JSON.parse(response);
      console.log('✅ 附近设备获取成功，响应数据:', result);
      
      // 检查响应格式
      if (result.success && result.data) {
        const deviceIds = Object.keys(result.data);
        console.log('✅ 附近设备获取成功，设备数量:', deviceIds.length);
        return deviceIds;
      } else {
        console.warn('⚠️ 响应格式不正确:', result);
        return [];
      }
    } catch (error) {
      console.error('❌ 获取附近设备失败:', error);
      throw error;
    }
  }

  // 添加设备
  async addDevice(deviceConfig: {
    deviceID: string;
    name: string;
    addresses?: string[];
    compression?: string;
    introducer?: boolean;
    autoAcceptFolders?: boolean;
    untrusted?: boolean;
    numConnections?: number;
    maxRecvKbps?: number;
    maxSendKbps?: number;
  }): Promise<Device> {
    try {
      console.log('🌐 通过 Native Module 添加设备...');
      console.log('📋 设备配置:', deviceConfig);
      
      const response = await ApiModule.addDevice(JSON.stringify(deviceConfig));
      const data = JSON.parse(response);
      console.log('✅ 设备添加成功');
      return data.data;
    } catch (error) {
      console.error('❌ 添加设备失败:', error);
      throw error;
    }
  }

  // 添加文件夹（暂未实现）
  async addFolder(folder: Omit<Folder, 'id'>): Promise<Folder> {
    throw new Error('添加文件夹功能暂未实现');
  }

  // 删除文件夹（暂未实现）
  async deleteFolder(folderId: string): Promise<void> {
    throw new Error('删除文件夹功能暂未实现');
  }

  // 更新文件夹（暂未实现）
  async updateFolder(folderId: string, updates: Partial<Folder>): Promise<Folder> {
    throw new Error('更新文件夹功能暂未实现');
  }
}

export const apiService = new ApiService(); 