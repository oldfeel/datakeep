package main

import (
	"log"
	"strings"

	"github.com/gofiber/fiber/v2"
	"github.com/gofiber/fiber/v2/middleware/cors"
	"github.com/gofiber/fiber/v2/middleware/logger"
	"github.com/gofiber/fiber/v2/middleware/recover"
	"github.com/yuncommunity/mydata/market_server/config"
	"github.com/yuncommunity/mydata/market_server/database"
	"github.com/yuncommunity/mydata/market_server/handlers"
	"github.com/yuncommunity/mydata/market_server/routes"
	"github.com/yuncommunity/mydata/market_server/storage"
)

func main() {
	cfg := config.Load()
	db := database.Connect(cfg)
	sto := storage.New(cfg)
	h := &handlers.Handler{DB: db, Cfg: cfg, Sto: sto}
	h.LoadStorageFromDB()

	app := fiber.New(fiber.Config{AppName: "mydata-market"})
	app.Use(recover.New())
	app.Use(logger.New())
	app.Use(cors.New(cors.Config{
		AllowOrigins: strings.Join(cfg.CORSOrigins, ","),
		AllowHeaders: "Origin, Content-Type, Accept, Authorization",
		AllowMethods: "GET,POST,PUT,DELETE,OPTIONS",
	}))

	routes.Setup(app, h)
	log.Printf("market_server 监听 %s", cfg.Addr)
	log.Fatal(app.Listen(cfg.Addr))
}
