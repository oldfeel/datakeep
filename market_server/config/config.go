package config

import (
	"bufio"
	"os"
	"strconv"
	"strings"
)

type Config struct {
	Addr             string
	DatabaseURL      string
	JWTSecret        string
	AdminUsername    string
	AdminPassword    string
	CORSOrigins      []string
	S3Endpoint       string
	S3Region         string
	S3Bucket         string
	S3AccessKey      string
	S3SecretKey      string
	S3PublicBaseURL  string
	S3ForcePathStyle bool
	QiniuAccessKey   string
	QiniuSecretKey   string
	QiniuBucket      string
	QiniuUploadURL   string
	QiniuDomain      string
}

func Load() Config {
	loadDotEnv(".env")
	return Config{
		Addr:             env("ADDR", ":8088"),
		DatabaseURL:      env("DATABASE_URL", "host=127.0.0.1 user=postgres password=postgres dbname=datakeep_market port=5432 sslmode=disable"),
		JWTSecret:        env("JWT_SECRET", "change-me-market-jwt-secret"),
		AdminUsername:    env("ADMIN_USERNAME", "admin"),
		AdminPassword:    env("ADMIN_PASSWORD", "admin123"),
		CORSOrigins:      splitCSV(env("CORS_ORIGINS", "*")),
		S3Endpoint:       env("S3_ENDPOINT", ""),
		S3Region:         env("S3_REGION", "cn-east-1"),
		S3Bucket:         env("S3_BUCKET", ""),
		S3AccessKey:      env("S3_ACCESS_KEY", ""),
		S3SecretKey:      env("S3_SECRET_KEY", ""),
		S3PublicBaseURL:  strings.TrimRight(env("S3_PUBLIC_BASE_URL", ""), "/"),
		S3ForcePathStyle: envBool("S3_FORCE_PATH_STYLE", true),
		QiniuAccessKey:   env("QINIU_ACCESS_KEY", ""),
		QiniuSecretKey:   env("QINIU_SECRET_KEY", ""),
		QiniuBucket:      env("QINIU_BUCKET", ""),
		QiniuUploadURL:   env("QINIU_UPLOAD_URL", "https://upload.qiniup.com"),
		QiniuDomain:      strings.TrimRight(env("QINIU_DOMAIN", ""), "/"),
	}
}

// loadDotEnv 读取工作目录 .env（不覆盖已有环境变量）
func loadDotEnv(path string) {
	f, err := os.Open(path)
	if err != nil {
		return
	}
	defer f.Close()
	sc := bufio.NewScanner(f)
	for sc.Scan() {
		line := strings.TrimSpace(sc.Text())
		if line == "" || strings.HasPrefix(line, "#") {
			continue
		}
		i := strings.IndexByte(line, '=')
		if i <= 0 {
			continue
		}
		k := strings.TrimSpace(line[:i])
		v := strings.TrimSpace(line[i+1:])
		if len(v) >= 2 {
			if (v[0] == '"' && v[len(v)-1] == '"') || (v[0] == '\'' && v[len(v)-1] == '\'') {
				v = v[1 : len(v)-1]
			}
		}
		if os.Getenv(k) == "" {
			_ = os.Setenv(k, v)
		}
	}
}

func env(k, def string) string {
	if v := os.Getenv(k); v != "" {
		return v
	}
	return def
}

func envBool(k string, def bool) bool {
	v := os.Getenv(k)
	if v == "" {
		return def
	}
	b, err := strconv.ParseBool(v)
	if err != nil {
		return def
	}
	return b
}

func splitCSV(s string) []string {
	parts := strings.Split(s, ",")
	out := make([]string, 0, len(parts))
	for _, p := range parts {
		p = strings.TrimSpace(p)
		if p != "" {
			out = append(out, p)
		}
	}
	return out
}
