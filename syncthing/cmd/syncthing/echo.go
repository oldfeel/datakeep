package main

import (
	"fmt"
	"net/http"
	"time"

	"github.com/labstack/echo/v4"
	"github.com/labstack/echo/v4/middleware"
)

type EchoServer struct {
	e    *echo.Echo
	port int
}

func NewEchoServer(port int) *EchoServer {
	e := echo.New()

	// 添加中间件
	e.Use(middleware.Logger())
	e.Use(middleware.Recover())

	return &EchoServer{
		e:    e,
		port: port,
	}
}

func (s *EchoServer) Start() error {
	// 基础路由
	s.e.GET("/", func(c echo.Context) error {
		return c.String(http.StatusOK, "Welcome to Syncthing Echo Server!")
	})

	// 健康检查
	s.e.GET("/health", func(c echo.Context) error {
		return c.JSON(http.StatusOK, map[string]string{
			"status": "healthy",
			"time":   time.Now().Format(time.RFC3339),
		})
	})

	// 启动服务器
	return s.e.Start(fmt.Sprintf(":%d", s.port))
}

func (s *EchoServer) Stop() error {
	return s.e.Close()
}
