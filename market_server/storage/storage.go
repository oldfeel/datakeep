package storage

import (
	"bytes"
	"context"
	"crypto/hmac"
	"crypto/sha1"
	"encoding/base64"
	"encoding/json"
	"fmt"
	"io"
	"mime/multipart"
	"net/http"
	"path/filepath"
	"strings"
	"sync"
	"time"

	"github.com/aws/aws-sdk-go-v2/aws"
	"github.com/aws/aws-sdk-go-v2/credentials"
	"github.com/aws/aws-sdk-go-v2/service/s3"
	"github.com/yuncommunity/mydata/market_server/config"
	"github.com/yuncommunity/mydata/market_server/models"
)

type runtimeCfg struct {
	Provider         string
	QiniuAccessKey   string
	QiniuSecretKey   string
	QiniuBucket      string
	QiniuUploadURL   string
	QiniuDomain      string
	S3Endpoint       string
	S3Region         string
	S3Bucket         string
	S3AccessKey      string
	S3SecretKey      string
	S3PublicBaseURL  string
	S3ForcePathStyle bool
}

type Provider struct {
	mu     sync.RWMutex
	env    config.Config
	rt     runtimeCfg
	s3     *s3.Client
	bucket string
	useQin bool
}

func New(cfg config.Config) *Provider {
	p := &Provider{env: cfg}
	p.apply(runtimeCfg{
		Provider:         "s3",
		QiniuAccessKey:   cfg.QiniuAccessKey,
		QiniuSecretKey:   cfg.QiniuSecretKey,
		QiniuBucket:      cfg.QiniuBucket,
		QiniuUploadURL:   cfg.QiniuUploadURL,
		QiniuDomain:      cfg.QiniuDomain,
		S3Endpoint:       cfg.S3Endpoint,
		S3Region:         cfg.S3Region,
		S3Bucket:         cfg.S3Bucket,
		S3AccessKey:      cfg.S3AccessKey,
		S3SecretKey:      cfg.S3SecretKey,
		S3PublicBaseURL:  cfg.S3PublicBaseURL,
		S3ForcePathStyle: cfg.S3ForcePathStyle,
	})
	return p
}

func (p *Provider) ApplyDB(s models.StorageSetting) {
	p.apply(runtimeCfg{
		Provider:         s.Provider,
		QiniuAccessKey:   s.QiniuAccessKey,
		QiniuSecretKey:   s.QiniuSecretKey,
		QiniuBucket:      s.QiniuBucket,
		QiniuUploadURL:   s.QiniuUploadURL,
		QiniuDomain:      s.QiniuDomain,
		S3Endpoint:       s.S3Endpoint,
		S3Region:         s.S3Region,
		S3Bucket:         s.S3Bucket,
		S3AccessKey:      s.S3AccessKey,
		S3SecretKey:      s.S3SecretKey,
		S3PublicBaseURL:  s.S3PublicBaseURL,
		S3ForcePathStyle: s.S3ForcePathStyle,
	})
}

func (p *Provider) Snapshot() runtimeCfg {
	p.mu.RLock()
	defer p.mu.RUnlock()
	return p.rt
}

func (p *Provider) apply(rt runtimeCfg) {
	if rt.QiniuUploadURL == "" {
		rt.QiniuUploadURL = "https://upload.qiniup.com"
	}
	if rt.S3Region == "" {
		rt.S3Region = "cn-east-1"
	}
	if rt.Provider == "" {
		if rt.QiniuAccessKey != "" && rt.QiniuBucket != "" {
			rt.Provider = "qiniu"
		} else {
			rt.Provider = "s3"
		}
	}

	p.mu.Lock()
	defer p.mu.Unlock()
	// 纠正误把 bucket 写进 endpoint：xxx.s3.region.qiniucs.com → s3.region.qiniucs.com
	if rt.S3Bucket != "" && rt.S3Endpoint != "" {
		prefix := rt.S3Bucket + "."
		ep := strings.TrimPrefix(strings.TrimPrefix(rt.S3Endpoint, "https://"), "http://")
		if strings.HasPrefix(ep, prefix) {
			ep = strings.TrimPrefix(ep, prefix)
			rt.S3Endpoint = ep
		}
	}
	p.rt = rt
	p.useQin = rt.Provider == "qiniu" && rt.QiniuAccessKey != "" && rt.QiniuSecretKey != "" && rt.QiniuBucket != ""
	p.s3 = nil
	p.bucket = ""
	if !p.useQin && rt.S3Endpoint != "" && rt.S3AccessKey != "" && rt.S3Bucket != "" {
		ep := rt.S3Endpoint
		if !strings.HasPrefix(ep, "http://") && !strings.HasPrefix(ep, "https://") {
			ep = "https://" + ep
		}
		p.bucket = rt.S3Bucket
		p.s3 = s3.New(s3.Options{
			Region:       rt.S3Region,
			Credentials:  credentials.NewStaticCredentialsProvider(rt.S3AccessKey, rt.S3SecretKey, ""),
			BaseEndpoint: aws.String(ep),
			UsePathStyle: rt.S3ForcePathStyle,
		})
	}
}

type UploadToken struct {
	Uptoken   string `json:"uptoken,omitempty"`
	UploadURL string `json:"uploadUrl"`
	Key       string `json:"key"`
	Method    string `json:"method"` // qiniu | s3_put
	PutURL    string `json:"putUrl,omitempty"`
}

func (p *Provider) IssueUploadToken(appKey, version string) (*UploadToken, error) {
	key := fmt.Sprintf("apps/%s/%s.zip", appKey, version)
	p.mu.RLock()
	defer p.mu.RUnlock()
	if p.useQin {
		token, err := p.qiniuUploadTokenLocked(key)
		if err != nil {
			return nil, err
		}
		return &UploadToken{
			Uptoken:   token,
			UploadURL: p.rt.QiniuUploadURL,
			Key:       key,
			Method:    "qiniu",
		}, nil
	}
	if p.s3 == nil {
		return nil, fmt.Errorf("未配置对象存储：请在管理后台「设置」中填写七牛或 S3")
	}
	presign := s3.NewPresignClient(p.s3)
	out, err := presign.PresignPutObject(context.Background(), &s3.PutObjectInput{
		Bucket:      aws.String(p.bucket),
		Key:         aws.String(key),
		ContentType: aws.String("application/zip"),
	}, s3.WithPresignExpires(30*time.Minute))
	if err != nil {
		return nil, err
	}
	return &UploadToken{
		UploadURL: out.URL,
		PutURL:    out.URL,
		Key:       key,
		Method:    "s3_put",
	}, nil
}

func (p *Provider) PublicURL(objectKey string) string {
	p.mu.RLock()
	defer p.mu.RUnlock()
	if p.rt.QiniuDomain != "" && p.useQin {
		return strings.TrimRight(p.rt.QiniuDomain, "/") + "/" + objectKey
	}
	if p.rt.S3PublicBaseURL != "" {
		return strings.TrimRight(p.rt.S3PublicBaseURL, "/") + "/" + objectKey
	}
	if p.rt.S3Endpoint != "" && p.rt.S3Bucket != "" {
		ep := strings.TrimRight(p.rt.S3Endpoint, "/")
		if !strings.HasPrefix(ep, "http") {
			ep = "https://" + ep
		}
		return fmt.Sprintf("%s/%s/%s", ep, p.rt.S3Bucket, objectKey)
	}
	return objectKey
}

func (p *Provider) DownloadObject(objectKey string) ([]byte, error) {
	p.mu.RLock()
	s3c := p.s3
	bucket := p.bucket
	useQin := p.useQin
	p.mu.RUnlock()

	if s3c != nil {
		out, err := s3c.GetObject(context.Background(), &s3.GetObjectInput{
			Bucket: aws.String(bucket),
			Key:    aws.String(objectKey),
		})
		if err != nil {
			return nil, err
		}
		defer out.Body.Close()
		return io.ReadAll(out.Body)
	}
	_ = useQin
	u := p.PublicURL(objectKey)
	resp, err := http.Get(u)
	if err != nil {
		return nil, err
	}
	defer resp.Body.Close()
	if resp.StatusCode >= 300 {
		return nil, fmt.Errorf("下载对象失败: HTTP %d", resp.StatusCode)
	}
	return io.ReadAll(resp.Body)
}

// PutObject 服务端直传（避免浏览器 CORS）
func (p *Provider) PutObject(objectKey string, body io.Reader, size int64, contentType string) error {
	p.mu.RLock()
	defer p.mu.RUnlock()
	if p.useQin {
		return p.putQiniuFormLocked(objectKey, body, size)
	}
	if p.s3 == nil {
		return fmt.Errorf("未配置对象存储：请在管理后台「设置」中填写七牛或 S3")
	}
	if contentType == "" {
		contentType = "application/zip"
	}
	_, err := p.s3.PutObject(context.Background(), &s3.PutObjectInput{
		Bucket:        aws.String(p.bucket),
		Key:           aws.String(objectKey),
		Body:          body,
		ContentLength: aws.Int64(size),
		ContentType:   aws.String(contentType),
	})
	return err
}

func (p *Provider) putQiniuFormLocked(key string, body io.Reader, size int64) error {
	token, err := p.qiniuUploadTokenLocked(key)
	if err != nil {
		return err
	}
	var buf bytes.Buffer
	w := multipart.NewWriter(&buf)
	_ = w.WriteField("token", token)
	_ = w.WriteField("key", key)
	part, err := w.CreateFormFile("file", filepath.Base(key))
	if err != nil {
		return err
	}
	if _, err := io.Copy(part, body); err != nil {
		return err
	}
	_ = w.Close()
	req, err := http.NewRequest(http.MethodPost, p.rt.QiniuUploadURL, &buf)
	if err != nil {
		return err
	}
	req.Header.Set("Content-Type", w.FormDataContentType())
	resp, err := http.DefaultClient.Do(req)
	if err != nil {
		return err
	}
	defer resp.Body.Close()
	if resp.StatusCode >= 300 {
		b, _ := io.ReadAll(resp.Body)
		return fmt.Errorf("七牛上传失败: HTTP %d %s", resp.StatusCode, string(b))
	}
	return nil
}

func (p *Provider) ObjectKey(appKey, version string) string {
	return fmt.Sprintf("apps/%s/%s.zip", appKey, version)
}

func (p *Provider) qiniuUploadTokenLocked(key string) (string, error) {
	deadline := time.Now().Add(time.Hour).Unix()
	policy := map[string]any{
		"scope":    p.rt.QiniuBucket + ":" + key,
		"deadline": deadline,
	}
	raw, err := json.Marshal(policy)
	if err != nil {
		return "", err
	}
	encodedPutPolicy := base64.URLEncoding.EncodeToString(raw)
	mac := hmac.New(sha1.New, []byte(p.rt.QiniuSecretKey))
	mac.Write([]byte(encodedPutPolicy))
	sign := base64.URLEncoding.EncodeToString(mac.Sum(nil))
	return p.rt.QiniuAccessKey + ":" + sign + ":" + encodedPutPolicy, nil
}
