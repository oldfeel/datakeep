package database

import (
	"log"

	"github.com/oldfeel/datakeep/market_server/config"
	"github.com/oldfeel/datakeep/market_server/models"
	"golang.org/x/crypto/bcrypt"
	"gorm.io/driver/postgres"
	"gorm.io/gorm"
	"gorm.io/gorm/logger"
)

func Connect(cfg config.Config) *gorm.DB {
	db, err := gorm.Open(postgres.Open(cfg.DatabaseURL), &gorm.Config{
		Logger: logger.Default.LogMode(logger.Warn),
	})
	if err != nil {
		log.Fatalf("连接数据库失败: %v", err)
	}
	if err := db.AutoMigrate(&models.Admin{}, &models.App{}, &models.AppVersion{}, &models.StorageSetting{}); err != nil {
		log.Fatalf("AutoMigrate 失败: %v", err)
	}
	seedAdmin(db, cfg)
	return db
}

func seedAdmin(db *gorm.DB, cfg config.Config) {
	var n int64
	db.Model(&models.Admin{}).Count(&n)
	if n > 0 {
		return
	}
	hash, err := bcrypt.GenerateFromPassword([]byte(cfg.AdminPassword), bcrypt.DefaultCost)
	if err != nil {
		log.Fatalf("生成管理员密码失败: %v", err)
	}
	admin := models.Admin{Username: cfg.AdminUsername, PasswordHash: string(hash)}
	if err := db.Create(&admin).Error; err != nil {
		log.Fatalf("创建初始管理员失败: %v", err)
	}
	log.Printf("已创建初始管理员: %s", cfg.AdminUsername)
}
