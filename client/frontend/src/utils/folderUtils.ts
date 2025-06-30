// 生成随机文件夹 ID
export function generateFolderId(): string {
  const chars = 'abcdefghijklmnopqrstuvwxyz0123456789';
  let result = '';
  for (let i = 0; i < 10; i++) {
    if (i === 5) result += '-';
    result += chars.charAt(Math.floor(Math.random() * chars.length));
  }
  return result;
} 