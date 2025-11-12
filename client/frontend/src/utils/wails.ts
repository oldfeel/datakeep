// Wails 运行时检查工具

/**
 * 检查 Wails 运行时是否可用
 */
export function isWailsAvailable(): boolean {
  try {
    if (typeof window === 'undefined') {
      return false;
    }
    // @ts-ignore - Wails 运行时动态注入到 window 对象
    const w = window as any;
    return w.go !== undefined && 
           w.go.main !== undefined &&
           w.go.main.App !== undefined;
  } catch (e) {
    return false;
  }
}

/**
 * 等待 Wails 运行时加载（最多等待 5 秒）
 */
export async function waitForWails(maxWait: number = 5000): Promise<boolean> {
  if (isWailsAvailable()) {
    return true;
  }

  const startTime = Date.now();
  return new Promise((resolve) => {
    const checkInterval = setInterval(() => {
      if (isWailsAvailable()) {
        clearInterval(checkInterval);
        resolve(true);
      } else if (Date.now() - startTime > maxWait) {
        clearInterval(checkInterval);
        resolve(false);
      }
    }, 100);
  });
}

/**
 * 安全调用 Wails 函数，如果 Wails 不可用则返回 null
 */
export async function safeWailsCall<T>(
  fn: () => Promise<T>,
  fallback?: () => Promise<T>
): Promise<T | null> {
  try {
    if (!isWailsAvailable()) {
      // 在浏览器环境中，Wails 运行时不可用是正常的，不显示警告
      if (fallback) {
        try {
          return await fallback();
        } catch (fallbackError: any) {
          // 检查是否是 CORS 或网络错误
          const errorMessage = fallbackError?.message || String(fallbackError);
          if (fallbackError instanceof TypeError || 
              errorMessage.includes('Failed to fetch') || 
              errorMessage.includes('Load failed') ||
              errorMessage.includes('CORS') ||
              errorMessage.includes('access control') ||
              errorMessage.includes('NetworkError')) {
            // 静默处理 CORS 和网络错误
            return null;
          }
          // 其他错误也静默处理，避免未处理的 Promise rejection
          return null;
        }
      }
      return null;
    }
    return await fn();
  } catch (error) {
    console.error('Wails 调用失败:', error);
    if (fallback) {
      try {
        return await fallback();
      } catch (fallbackError: any) {
        // 检查是否是 CORS 或网络错误
        const errorMessage = fallbackError?.message || String(fallbackError);
        if (fallbackError instanceof TypeError || 
            errorMessage.includes('Failed to fetch') || 
            errorMessage.includes('Load failed') ||
            errorMessage.includes('CORS') ||
            errorMessage.includes('access control') ||
            errorMessage.includes('NetworkError')) {
          // 静默处理 CORS 和网络错误
          return null;
        }
        // 其他错误也静默处理，避免未处理的 Promise rejection
        return null;
      }
    }
    return null;
  }
}

