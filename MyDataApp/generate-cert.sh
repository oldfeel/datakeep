#!/bin/bash

# 生成自签名证书和私钥的脚本

echo "生成自签名证书和私钥..."

# 创建 assets 目录（如果不存在）
mkdir -p android/app/src/main/assets

# 生成私钥
echo "生成私钥..."
openssl genrsa -out android/app/src/main/assets/private.key 2048

# 生成证书签名请求
echo "生成证书签名请求..."
openssl req -new -key android/app/src/main/assets/private.key -out cert.csr -subj "/C=CN/ST=Beijing/L=Beijing/O=MyDataApp/OU=Development/CN=localhost"

# 生成自签名证书
echo "生成自签名证书..."
openssl x509 -req -days 365 -in cert.csr -signkey android/app/src/main/assets/private.key -out android/app/src/main/assets/certificate.crt

# 清理临时文件
rm cert.csr

echo "证书和私钥生成完成！"
echo "文件位置："
echo "  - android/app/src/main/assets/certificate.crt"
echo "  - android/app/src/main/assets/private.key" 