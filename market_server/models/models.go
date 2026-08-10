package models

import "time"

type Admin struct {
	ID           uint      `gorm:"primaryKey" json:"id"`
	Username     string    `gorm:"uniqueIndex;size:64;not null" json:"username"`
	PasswordHash string    `gorm:"size:255;not null" json:"-"`
	CreatedAt    time.Time `json:"createdAt"`
	UpdatedAt    time.Time `json:"updatedAt"`
}

// App 市场应用；CurrentVersionID 指向当前可安装版本
type App struct {
	ID               uint       `gorm:"primaryKey" json:"id"`
	AppKey           string     `gorm:"uniqueIndex;size:128;not null;column:app_key" json:"appKey"` // 对应 app.json id
	Name             string     `gorm:"size:255;not null" json:"name"`
	Description      string     `gorm:"type:text" json:"description"`
	IconURL          string     `gorm:"size:512" json:"iconUrl"`
	CurrentVersionID *uint      `json:"currentVersionId"`
	CurrentVersion   *AppVersion `gorm:"foreignKey:CurrentVersionID" json:"currentVersion,omitempty"`
	CreatedAt        time.Time  `json:"createdAt"`
	UpdatedAt        time.Time  `json:"updatedAt"`
}

type AppVersion struct {
	ID        uint      `gorm:"primaryKey" json:"id"`
	AppID     uint      `gorm:"index;not null" json:"appId"`
	Version   string    `gorm:"size:64;not null" json:"version"`
	ObjectKey string    `gorm:"size:512;not null" json:"objectKey"`
	SHA256    string    `gorm:"size:64;not null" json:"sha256"`
	Size      int64     `json:"size"`
	Changelog string    `gorm:"type:text" json:"changelog"`
	CreatedAt time.Time `json:"createdAt"`
}

// StorageSetting 市场对象存储配置（单行，id=1）
type StorageSetting struct {
	ID               uint   `gorm:"primaryKey" json:"id"`
	Provider         string `gorm:"size:16;not null;default:s3" json:"provider"` // qiniu | s3
	QiniuAccessKey   string `gorm:"size:255" json:"qiniuAccessKey"`
	QiniuSecretKey   string `gorm:"size:255" json:"-"`
	QiniuBucket      string `gorm:"size:255" json:"qiniuBucket"`
	QiniuUploadURL   string `gorm:"size:512" json:"qiniuUploadUrl"`
	QiniuDomain      string `gorm:"size:512" json:"qiniuDomain"`
	S3Endpoint       string `gorm:"size:512" json:"s3Endpoint"`
	S3Region         string `gorm:"size:64" json:"s3Region"`
	S3Bucket         string `gorm:"size:255" json:"s3Bucket"`
	S3AccessKey      string `gorm:"size:255" json:"s3AccessKey"`
	S3SecretKey      string `gorm:"size:255" json:"-"`
	S3PublicBaseURL  string `gorm:"size:512" json:"s3PublicBaseUrl"`
	S3ForcePathStyle bool   `gorm:"default:true" json:"s3ForcePathStyle"`
}
