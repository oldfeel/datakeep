package handlers

import (
	"archive/zip"
	"bytes"
	"crypto/sha256"
	"encoding/json"
	"fmt"
	"io"
	"strings"
	"time"

	"github.com/gofiber/fiber/v2"
	"github.com/golang-jwt/jwt/v5"
	"github.com/yuncommunity/mydata/market_server/config"
	"github.com/yuncommunity/mydata/market_server/models"
	"github.com/yuncommunity/mydata/market_server/storage"
	"golang.org/x/crypto/bcrypt"
	"gorm.io/gorm"
)

type Handler struct {
	DB  *gorm.DB
	Cfg config.Config
	Sto *storage.Provider
}

func OK(c *fiber.Ctx, data any) error {
	return c.JSON(fiber.Map{"code": 0, "data": data})
}

func Fail(c *fiber.Ctx, code int, msg string) error {
	return c.Status(fiber.StatusOK).JSON(fiber.Map{"code": code, "data": msg})
}

func (h *Handler) Login(c *fiber.Ctx) error {
	var body struct {
		Username string `json:"username"`
		Password string `json:"password"`
	}
	if err := c.BodyParser(&body); err != nil {
		return Fail(c, 1001, "参数错误")
	}
	var admin models.Admin
	if err := h.DB.Where("username = ?", body.Username).First(&admin).Error; err != nil {
		return Fail(c, 1003, "用户名或密码错误")
	}
	if bcrypt.CompareHashAndPassword([]byte(admin.PasswordHash), []byte(body.Password)) != nil {
		return Fail(c, 1003, "用户名或密码错误")
	}
	claims := jwt.MapClaims{
		"sub": admin.ID,
		"usr": admin.Username,
		"exp": time.Now().Add(7 * 24 * time.Hour).Unix(),
	}
	token := jwt.NewWithClaims(jwt.SigningMethodHS256, claims)
	signed, err := token.SignedString([]byte(h.Cfg.JWTSecret))
	if err != nil {
		return Fail(c, 1005, "签发 token 失败")
	}
	return OK(c, fiber.Map{"token": signed, "username": admin.Username})
}

func (h *Handler) Me(c *fiber.Ctx) error {
	return OK(c, fiber.Map{"username": c.Locals("username")})
}

type appBody struct {
	AppKey      string `json:"appKey"`
	Name        string `json:"name"`
	Description string `json:"description"`
	IconURL     string `json:"iconUrl"`
}

func (h *Handler) AdminListApps(c *fiber.Ctx) error {
	var apps []models.App
	if err := h.DB.Preload("CurrentVersion").Order("id desc").Find(&apps).Error; err != nil {
		return Fail(c, 1005, err.Error())
	}
	return OK(c, apps)
}

func (h *Handler) AdminCreateApp(c *fiber.Ctx) error {
	var body appBody
	if err := c.BodyParser(&body); err != nil || body.AppKey == "" || body.Name == "" {
		return Fail(c, 1001, "需要 appKey 与 name")
	}
	app := models.App{
		AppKey:      strings.TrimSpace(body.AppKey),
		Name:        body.Name,
		Description: body.Description,
		IconURL:     body.IconURL,
	}
	if err := h.DB.Create(&app).Error; err != nil {
		return Fail(c, 1003, "创建失败（appKey 可能重复）")
	}
	return OK(c, app)
}

func (h *Handler) AdminUpdateApp(c *fiber.Ctx) error {
	id, err := c.ParamsInt("id")
	if err != nil {
		return Fail(c, 1001, "无效 id")
	}
	var app models.App
	if err := h.DB.First(&app, id).Error; err != nil {
		return Fail(c, 1004, "应用不存在")
	}
	var body appBody
	if err := c.BodyParser(&body); err != nil {
		return Fail(c, 1001, "参数错误")
	}
	if body.Name != "" {
		app.Name = body.Name
	}
	if body.Description != "" || c.Request().URI().QueryArgs().Has("description") {
		app.Description = body.Description
	}
	// 允许清空 description：若 JSON 带了字段
	raw := c.Body()
	var m map[string]any
	_ = json.Unmarshal(raw, &m)
	if _, ok := m["description"]; ok {
		app.Description = body.Description
	}
	if _, ok := m["iconUrl"]; ok {
		app.IconURL = body.IconURL
	}
	if _, ok := m["name"]; ok && body.Name != "" {
		app.Name = body.Name
	}
	if err := h.DB.Save(&app).Error; err != nil {
		return Fail(c, 1005, err.Error())
	}
	return OK(c, app)
}

func (h *Handler) AdminDeleteApp(c *fiber.Ctx) error {
	id, err := c.ParamsInt("id")
	if err != nil {
		return Fail(c, 1001, "无效 id")
	}
	h.DB.Where("app_id = ?", id).Delete(&models.AppVersion{})
	if err := h.DB.Delete(&models.App{}, id).Error; err != nil {
		return Fail(c, 1005, err.Error())
	}
	return OK(c, fiber.Map{"ok": true})
}

func (h *Handler) AdminUploadToken(c *fiber.Ctx) error {
	var body struct {
		AppID   uint   `json:"appId"`
		Version string `json:"version"`
	}
	if err := c.BodyParser(&body); err != nil || body.AppID == 0 || body.Version == "" {
		return Fail(c, 1001, "需要 appId 与 version")
	}
	var app models.App
	if err := h.DB.First(&app, body.AppID).Error; err != nil {
		return Fail(c, 1004, "应用不存在")
	}
	tok, err := h.Sto.IssueUploadToken(app.AppKey, body.Version)
	if err != nil {
		return Fail(c, 1005, err.Error())
	}
	return OK(c, tok)
}

// AdminUploadFile 浏览器 → Go → 对象存储（避开 CORS）
func (h *Handler) AdminUploadFile(c *fiber.Ctx) error {
	appID, err := c.ParamsInt("id")
	if err != nil {
		return Fail(c, 1001, "无效 id")
	}
	version := strings.TrimSpace(c.FormValue("version"))
	if version == "" {
		return Fail(c, 1001, "需要 version")
	}
	var app models.App
	if err := h.DB.First(&app, appID).Error; err != nil {
		return Fail(c, 1004, "应用不存在")
	}
	fh, err := c.FormFile("file")
	if err != nil {
		return Fail(c, 1001, "需要 file")
	}
	f, err := fh.Open()
	if err != nil {
		return Fail(c, 1005, err.Error())
	}
	defer f.Close()

	data, err := io.ReadAll(f)
	if err != nil {
		return Fail(c, 1005, err.Error())
	}
	sum := sha256.Sum256(data)
	shaHex := fmt.Sprintf("%x", sum[:])
	key := h.Sto.ObjectKey(app.AppKey, version)
	if err := h.Sto.PutObject(key, bytes.NewReader(data), int64(len(data)), "application/zip"); err != nil {
		return Fail(c, 1005, "上传存储失败: "+err.Error())
	}
	return OK(c, fiber.Map{
		"objectKey": key,
		"sha256":    shaHex,
		"size":      len(data),
		"version":   version,
	})
}

func (h *Handler) AdminRegisterVersion(c *fiber.Ctx) error {
	id, err := c.ParamsInt("id")
	if err != nil {
		return Fail(c, 1001, "无效 id")
	}
	var body struct {
		Version   string `json:"version"`
		ObjectKey string `json:"objectKey"`
		SHA256    string `json:"sha256"`
		Size      int64  `json:"size"`
		Changelog string `json:"changelog"`
		SkipCheck bool   `json:"skipCheck"`
	}
	if err := c.BodyParser(&body); err != nil || body.Version == "" || body.ObjectKey == "" || body.SHA256 == "" {
		return Fail(c, 1001, "需要 version、objectKey、sha256")
	}
	var app models.App
	if err := h.DB.First(&app, id).Error; err != nil {
		return Fail(c, 1004, "应用不存在")
	}
	if !body.SkipCheck {
		if err := h.validatePackage(body.ObjectKey, app.AppKey); err != nil {
			return Fail(c, 1006, "包校验失败: "+err.Error())
		}
	}
	ver := models.AppVersion{
		AppID:     app.ID,
		Version:   body.Version,
		ObjectKey: body.ObjectKey,
		SHA256:    strings.ToLower(body.SHA256),
		Size:      body.Size,
		Changelog: body.Changelog,
	}
	if err := h.DB.Transaction(func(tx *gorm.DB) error {
		if err := tx.Create(&ver).Error; err != nil {
			return err
		}
		app.CurrentVersionID = &ver.ID
		return tx.Save(&app).Error
	}); err != nil {
		return Fail(c, 1005, err.Error())
	}
	_ = h.DB.Preload("CurrentVersion").First(&app, app.ID)
	return OK(c, app)
}

func (h *Handler) validatePackage(objectKey, expectAppKey string) error {
	data, err := h.Sto.DownloadObject(objectKey)
	if err != nil {
		return err
	}
	zr, err := zip.NewReader(bytes.NewReader(data), int64(len(data)))
	if err != nil {
		return err
	}
	var hasAppJSON, hasEntry bool
	var entry = "index.html"
	var appKey string
	for _, f := range zr.File {
		name := f.Name
		// strip single top-level dir
		parts := strings.Split(name, "/")
		base := name
		if len(parts) >= 2 && !strings.Contains(parts[0], ".") {
			base = strings.Join(parts[1:], "/")
		}
		base = strings.TrimPrefix(base, "/")
		if base == "app.json" {
			hasAppJSON = true
			rc, err := f.Open()
			if err != nil {
				return err
			}
			var meta struct {
				ID    string `json:"id"`
				Entry string `json:"entry"`
			}
			_ = json.NewDecoder(rc).Decode(&meta)
			rc.Close()
			appKey = meta.ID
			if meta.Entry != "" {
				entry = meta.Entry
			}
		}
	}
	for _, f := range zr.File {
		name := f.Name
		parts := strings.Split(name, "/")
		base := name
		if len(parts) >= 2 && !strings.Contains(parts[0], ".") {
			base = strings.Join(parts[1:], "/")
		}
		if base == entry {
			hasEntry = true
			break
		}
	}
	if !hasAppJSON {
		return fmt.Errorf("缺少 app.json")
	}
	if !hasEntry {
		return fmt.Errorf("缺少入口 %s", entry)
	}
	if expectAppKey != "" && appKey != "" && appKey != expectAppKey {
		return fmt.Errorf("app.json id 与应用 appKey 不一致")
	}
	return nil
}

func (h *Handler) PublicListApps(c *fiber.Ctx) error {
	var apps []models.App
	if err := h.DB.Preload("CurrentVersion").Where("current_version_id IS NOT NULL").Order("id desc").Find(&apps).Error; err != nil {
		return Fail(c, 1005, err.Error())
	}
	out := make([]fiber.Map, 0, len(apps))
	for _, a := range apps {
		out = append(out, h.publicApp(a))
	}
	return OK(c, out)
}

func (h *Handler) PublicGetApp(c *fiber.Ctx) error {
	key := c.Params("appKey")
	var app models.App
	q := h.DB.Preload("CurrentVersion").Where("app_key = ?", key)
	if err := q.First(&app).Error; err != nil {
		return Fail(c, 1004, "应用不存在")
	}
	if app.CurrentVersionID == nil {
		return Fail(c, 1004, "应用暂无可用版本")
	}
	return OK(c, h.publicApp(app))
}

func (h *Handler) PublicDownloadInfo(c *fiber.Ctx) error {
	key := c.Params("appKey")
	var app models.App
	if err := h.DB.Preload("CurrentVersion").Where("app_key = ?", key).First(&app).Error; err != nil {
		return Fail(c, 1004, "应用不存在")
	}
	if app.CurrentVersion == nil {
		return Fail(c, 1004, "应用暂无可用版本")
	}
	v := app.CurrentVersion
	return OK(c, fiber.Map{
		"appKey":      app.AppKey,
		"version":     v.Version,
		"sha256":      v.SHA256,
		"size":        v.Size,
		"objectKey":   v.ObjectKey,
		"url":         h.packageURL(c, app.AppKey),
		"storageUrl":  h.Sto.PublicURL(v.ObjectKey),
	})
}

// PublicDownloadPackage 经服务端凭证拉取 zip（私有桶无法匿名直链）
func (h *Handler) PublicDownloadPackage(c *fiber.Ctx) error {
	key := c.Params("appKey")
	var app models.App
	if err := h.DB.Preload("CurrentVersion").Where("app_key = ?", key).First(&app).Error; err != nil {
		return Fail(c, 1004, "应用不存在")
	}
	if app.CurrentVersion == nil || app.CurrentVersion.ObjectKey == "" {
		return Fail(c, 1004, "应用暂无可用版本")
	}
	objectKey := app.CurrentVersion.ObjectKey
	fmt.Printf("[market] package download appKey=%s objectKey=%s\n", key, objectKey)
	data, err := h.Sto.DownloadObject(objectKey)
	if err != nil {
		fmt.Printf("[market] package download failed: %v\n", err)
		return Fail(c, 1005, "下载失败: "+err.Error())
	}
	c.Set("Content-Type", "application/zip")
	c.Set("Content-Disposition", fmt.Sprintf(`attachment; filename="%s-%s.zip"`, app.AppKey, app.CurrentVersion.Version))
	c.Set("X-Content-SHA256", app.CurrentVersion.SHA256)
	return c.Send(data)
}

func (h *Handler) packageURL(c *fiber.Ctx, appKey string) string {
	base := strings.TrimRight(c.BaseURL(), "/")
	return fmt.Sprintf("%s/api/apps/%s/package", base, appKey)
}

func (h *Handler) publicApp(a models.App) fiber.Map {
	m := fiber.Map{
		"id":          a.ID,
		"appKey":      a.AppKey,
		"name":        a.Name,
		"description": a.Description,
		"iconUrl":     a.IconURL,
	}
	if a.CurrentVersion != nil {
		m["version"] = a.CurrentVersion.Version
		m["sha256"] = a.CurrentVersion.SHA256
		m["size"] = a.CurrentVersion.Size
		// 私有桶不能匿名 GET 对象存储直链；客户端走本服务代下
		m["downloadUrl"] = fmt.Sprintf("/api/apps/%s/package", a.AppKey)
		m["storageUrl"] = h.Sto.PublicURL(a.CurrentVersion.ObjectKey)
	}
	return m
}

func (h *Handler) GetStorageSettings(c *fiber.Ctx) error {
	s := h.loadOrInitStorage()
	return OK(c, fiber.Map{
		"provider":            s.Provider,
		"qiniuAccessKey":      s.QiniuAccessKey,
		"qiniuSecretKeySet":   s.QiniuSecretKey != "",
		"qiniuBucket":         s.QiniuBucket,
		"qiniuUploadUrl":      s.QiniuUploadURL,
		"qiniuDomain":         s.QiniuDomain,
		"s3Endpoint":          s.S3Endpoint,
		"s3Region":            s.S3Region,
		"s3Bucket":            s.S3Bucket,
		"s3AccessKey":         s.S3AccessKey,
		"s3SecretKeySet":      s.S3SecretKey != "",
		"s3PublicBaseUrl":     s.S3PublicBaseURL,
		"s3ForcePathStyle":    s.S3ForcePathStyle,
	})
}

func (h *Handler) PutStorageSettings(c *fiber.Ctx) error {
	var body struct {
		Provider         string `json:"provider"`
		QiniuAccessKey   string `json:"qiniuAccessKey"`
		QiniuSecretKey   string `json:"qiniuSecretKey"`
		QiniuBucket      string `json:"qiniuBucket"`
		QiniuUploadURL   string `json:"qiniuUploadUrl"`
		QiniuDomain      string `json:"qiniuDomain"`
		S3Endpoint       string `json:"s3Endpoint"`
		S3Region         string `json:"s3Region"`
		S3Bucket         string `json:"s3Bucket"`
		S3AccessKey      string `json:"s3AccessKey"`
		S3SecretKey      string `json:"s3SecretKey"`
		S3PublicBaseURL  string `json:"s3PublicBaseUrl"`
		S3ForcePathStyle *bool  `json:"s3ForcePathStyle"`
	}
	if err := c.BodyParser(&body); err != nil {
		return Fail(c, 1001, "参数错误")
	}
	s := h.loadOrInitStorage()
	if body.Provider != "" {
		s.Provider = body.Provider
	}
	s.QiniuAccessKey = body.QiniuAccessKey
	if body.QiniuSecretKey != "" {
		s.QiniuSecretKey = body.QiniuSecretKey
	}
	s.QiniuBucket = body.QiniuBucket
	if body.QiniuUploadURL != "" {
		s.QiniuUploadURL = body.QiniuUploadURL
	}
	s.QiniuDomain = body.QiniuDomain
	s.S3Endpoint = body.S3Endpoint
	if body.S3Region != "" {
		s.S3Region = body.S3Region
	}
	s.S3Bucket = body.S3Bucket
	s.S3AccessKey = body.S3AccessKey
	if body.S3SecretKey != "" {
		s.S3SecretKey = body.S3SecretKey
	}
	s.S3PublicBaseURL = body.S3PublicBaseURL
	if body.S3ForcePathStyle != nil {
		s.S3ForcePathStyle = *body.S3ForcePathStyle
	}
	if err := h.DB.Save(&s).Error; err != nil {
		return Fail(c, 1005, err.Error())
	}
	h.Sto.ApplyDB(s)
	return h.GetStorageSettings(c)
}

func (h *Handler) loadOrInitStorage() models.StorageSetting {
	var s models.StorageSetting
	err := h.DB.First(&s, 1).Error
	if err == nil {
		return s
	}
	s = models.StorageSetting{
		ID:               1,
		Provider:         "s3",
		QiniuAccessKey:   h.Cfg.QiniuAccessKey,
		QiniuSecretKey:   h.Cfg.QiniuSecretKey,
		QiniuBucket:      h.Cfg.QiniuBucket,
		QiniuUploadURL:   h.Cfg.QiniuUploadURL,
		QiniuDomain:      h.Cfg.QiniuDomain,
		S3Endpoint:       h.Cfg.S3Endpoint,
		S3Region:         h.Cfg.S3Region,
		S3Bucket:         h.Cfg.S3Bucket,
		S3AccessKey:      h.Cfg.S3AccessKey,
		S3SecretKey:      h.Cfg.S3SecretKey,
		S3PublicBaseURL:  h.Cfg.S3PublicBaseURL,
		S3ForcePathStyle: h.Cfg.S3ForcePathStyle,
	}
	if s.QiniuAccessKey != "" && s.QiniuBucket != "" {
		s.Provider = "qiniu"
	}
	_ = h.DB.Create(&s).Error
	return s
}

// LoadStorageFromDB 启动时把库中配置应用到 Provider
func (h *Handler) LoadStorageFromDB() {
	s := h.loadOrInitStorage()
	h.Sto.ApplyDB(s)
}
