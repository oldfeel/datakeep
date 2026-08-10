package middleware

import (
	"strings"

	"github.com/gofiber/fiber/v2"
	"github.com/golang-jwt/jwt/v5"
)

func JWT(secret string) fiber.Handler {
	return func(c *fiber.Ctx) error {
		h := c.Get("Authorization")
		if !strings.HasPrefix(h, "Bearer ") {
			return c.Status(fiber.StatusUnauthorized).JSON(fiber.Map{"code": 401, "data": "未登录"})
		}
		raw := strings.TrimPrefix(h, "Bearer ")
		token, err := jwt.Parse(raw, func(t *jwt.Token) (any, error) {
			return []byte(secret), nil
		})
		if err != nil || !token.Valid {
			return c.Status(fiber.StatusUnauthorized).JSON(fiber.Map{"code": 401, "data": "token 无效"})
		}
		claims, ok := token.Claims.(jwt.MapClaims)
		if !ok {
			return c.Status(fiber.StatusUnauthorized).JSON(fiber.Map{"code": 401, "data": "token 无效"})
		}
		if usr, ok := claims["usr"].(string); ok {
			c.Locals("username", usr)
		}
		c.Locals("adminId", claims["sub"])
		return c.Next()
	}
}
