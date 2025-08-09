// API 配置
export const API_CONFIG = {
  // HTTPS API 基础 URL
  BASE_URL: 'https://localhost:8443',
  
  // 请求配置
  REQUEST_CONFIG: {
    // 对于自签名证书，需要忽略证书验证（仅开发环境）
    // 在生产环境中应该使用有效的 SSL 证书
    mode: 'cors' as RequestMode,
    headers: {
      'Content-Type': 'application/json',
    },
  },
  
  // 超时配置
  TIMEOUT: 30000, // 30秒
};

// 创建带有错误处理的 fetch 函数
export async function apiFetch(url: string, options: RequestInit = {}) {
  const fullUrl = url.startsWith('http') ? url : `${API_CONFIG.BASE_URL}${url}`;
  
  const config: RequestInit = {
    ...API_CONFIG.REQUEST_CONFIG,
    ...options,
    headers: {
      ...API_CONFIG.REQUEST_CONFIG.headers,
      ...options.headers,
    },
  };

  try {
    const response = await fetch(fullUrl, config);
    
    if (!response.ok) {
      throw new Error(`HTTP ${response.status}: ${response.statusText}`);
    }
    
    return response;
  } catch (error) {
    console.error('API 请求失败:', error);
    throw error;
  }
}

// 创建 JSON fetch 函数
export async function apiFetchJson<T>(url: string, options: RequestInit = {}): Promise<T> {
  const response = await apiFetch(url, options);
  return response.json();
}
