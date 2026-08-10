package routes

import (
	"github.com/gofiber/fiber/v2"
	"github.com/yuncommunity/mydata/market_server/handlers"
	"github.com/yuncommunity/mydata/market_server/middleware"
)

func Setup(app *fiber.App, h *handlers.Handler) {
	app.Get("/health", func(c *fiber.Ctx) error {
		return c.JSON(fiber.Map{"ok": true})
	})

	api := app.Group("/api")
	api.Get("/apps", h.PublicListApps)
	api.Get("/apps/:appKey", h.PublicGetApp)
	api.Get("/apps/:appKey/download", h.PublicDownloadInfo)
	api.Get("/apps/:appKey/package", h.PublicDownloadPackage)

	// /admin/login 必须在 JWT 组之外
	admin := app.Group("/admin")
	admin.Post("/login", h.Login)

	auth := admin.Group("", middleware.JWT(h.Cfg.JWTSecret))
	auth.Get("/me", h.Me)
	auth.Get("/apps", h.AdminListApps)
	auth.Post("/apps", h.AdminCreateApp)
	auth.Put("/apps/:id", h.AdminUpdateApp)
	auth.Delete("/apps/:id", h.AdminDeleteApp)
	auth.Post("/uploads/token", h.AdminUploadToken)
	auth.Post("/apps/:id/upload", h.AdminUploadFile)
	auth.Post("/apps/:id/versions", h.AdminRegisterVersion)
	auth.Get("/settings/storage", h.GetStorageSettings)
	auth.Put("/settings/storage", h.PutStorageSettings)
}
