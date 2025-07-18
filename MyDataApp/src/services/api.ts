import { Device, Folder, ApiResponse } from '../types';

const API_BASE_URL = 'https://localhost:8443/api';

class ApiService {
  private async request<T>(endpoint: string, options?: RequestInit): Promise<ApiResponse<T>> {
    try {
      const response = await fetch(`${API_BASE_URL}${endpoint}`, {
        headers: {
          'Content-Type': 'application/json',
          ...options?.headers,
        },
        ...options,
      });

      if (!response.ok) {
        throw new Error(`HTTP error! status: ${response.status}`);
      }

      const data = await response.json();
      return data;
    } catch (error) {
      console.error('API request failed:', error);
      throw error;
    }
  }

  // 获取设备列表
  async getDevices(): Promise<Device[]> {
    const response = await this.request<Device[]>('/devices');
    return response.data;
  }

  // 获取文件夹列表
  async getFolders(): Promise<Folder[]> {
    const response = await this.request<Folder[]>('/folders');
    return response.data;
  }

  // 获取特定设备的文件夹
  async getDeviceFolders(deviceId: string): Promise<Folder[]> {
    const response = await this.request<Folder[]>(`/device/${deviceId}/folders`);
    return response.data;
  }

  // 获取文件夹内容
  async getFolderContent(folderId: string, path: string = ''): Promise<any> {
    const response = await this.request<any>(`/folder/${folderId}?path=${encodeURIComponent(path)}`);
    return response.data;
  }

  // 添加文件夹
  async addFolder(folder: Omit<Folder, 'id'>): Promise<Folder> {
    const response = await this.request<Folder>('/folders', {
      method: 'POST',
      body: JSON.stringify(folder),
    });
    return response.data;
  }

  // 删除文件夹
  async deleteFolder(folderId: string): Promise<void> {
    await this.request<void>(`/folders/${folderId}`, {
      method: 'DELETE',
    });
  }

  // 更新文件夹
  async updateFolder(folderId: string, updates: Partial<Folder>): Promise<Folder> {
    const response = await this.request<Folder>(`/folders/${folderId}`, {
      method: 'PUT',
      body: JSON.stringify(updates),
    });
    return response.data;
  }
}

export const apiService = new ApiService(); 