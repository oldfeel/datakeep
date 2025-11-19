package main

import (
	"encoding/base64"
	"fmt"
	"io/ioutil"
	"log"
	"os"
	"path/filepath"
	"regexp"
	"strings"

	"golang.org/x/net/html"
)

const (
	emlRelPath  = "mail.eml"
	imageRelDir = "images"
	mdRelPath   = "chat.md"
	exampleDir  = "example"
)

func main() {
	emlPath := resolvePath(emlRelPath, true)
	baseDir := filepath.Dir(emlPath)
	if abs, err := filepath.Abs(baseDir); err == nil {
		baseDir = abs
	}

	imageDir := resolvePathWithBase(imageRelDir, baseDir, true)
	mdPath := filepath.Join(baseDir, mdRelPath)

	data, err := ioutil.ReadFile(emlPath)
	if err != nil {
		log.Fatalf("read eml: %v", err)
	}

	content := string(data)
	htmlPart := extractBase64Part(content, `Content-Type: text/html;`)
	if htmlPart == "" {
		log.Fatal("html part not found")
	}

	entries := buildEntries(htmlPart, imageDir)
	if err := writeMarkdown(entries, mdPath); err != nil {
		log.Fatalf("write markdown: %v", err)
	}
	fmt.Printf("Generated %s with %d entries\n", mdPath, len(entries))
}

type entry struct {
	Texts []string
	Image string
}

func buildEntries(htmlPart string, imageDir string) []entry {
	doc, err := html.Parse(strings.NewReader(htmlPart))
	if err != nil {
		log.Fatalf("parse html: %v", err)
	}

	var entries []entry
	var buffer []string
	imageRegex := regexp.MustCompile(`[^/\\]+$`)
	priceRegex := regexp.MustCompile(`\d+(?:\.\d+)?`)

	var walk func(*html.Node)
	walk = func(n *html.Node) {
		if n.Type == html.ElementNode && n.Data == "p" {
			raw := strings.TrimSpace(extractText(n))
			if raw != "" {
				for _, token := range priceRegex.FindAllString(raw, -1) {
					if token == "2025" || token == "11" {
						continue
					}
					if token != "" {
						buffer = append(buffer, token)
					}
				}
			}
			for c := n.FirstChild; c != nil; c = c.NextSibling {
				if c.Type == html.ElementNode && c.Data == "img" {
					src := getAttr(c, "src")
					if src == "" {
						continue
					}
					filename := imageRegex.FindString(src)
					if filename == "" {
						continue
					}
					fullPath := filepath.Join(imageDir, filename)
					entries = append(entries, entry{
						Texts: buffer,
						Image: fullPath,
					})
					buffer = nil
				}
			}
			return
		}
		for c := n.FirstChild; c != nil; c = c.NextSibling {
			walk(c)
		}
	}
	walk(doc)

	if len(buffer) > 0 {
		entries = append(entries, entry{Texts: buffer})
	}
	return entries
}

func extractText(n *html.Node) string {
	if n.Type == html.TextNode {
		return n.Data
	}
	var sb strings.Builder
	for c := n.FirstChild; c != nil; c = c.NextSibling {
		sb.WriteString(extractText(c))
	}
	return sb.String()
}

func getAttr(n *html.Node, name string) string {
	for _, attr := range n.Attr {
		if attr.Key == name {
			return attr.Val
		}
	}
	return ""
}

func writeMarkdown(entries []entry, outputPath string) error {
	if err := os.MkdirAll(filepath.Dir(outputPath), 0o755); err != nil {
		return err
	}
	var sb strings.Builder
	for i, e := range entries {
		if len(e.Texts) > 0 {
			for _, t := range e.Texts {
				sb.WriteString(t)
				sb.WriteString("\n")
			}
		}
		if e.Image != "" {
			relPath := e.Image
			if pathRel, err := filepath.Rel(filepath.Dir(outputPath), e.Image); err == nil {
				relPath = filepath.ToSlash(pathRel)
			} else {
				relPath = filepath.ToSlash(e.Image)
			}
			sb.WriteString(fmt.Sprintf("![image %d](<%s>)\n", i+1, relPath))
		}
		sb.WriteString("\n")
	}
	return ioutil.WriteFile(outputPath, []byte(sb.String()), 0o644)
}

func extractBase64Part(content, marker string) string {
	idx := strings.Index(content, marker)
	if idx == -1 {
		return ""
	}
	sub := content[idx:]
	idxEnc := strings.Index(sub, "Content-Transfer-Encoding: base64")
	if idxEnc == -1 {
		return ""
	}
	sub = sub[idxEnc:]

	body := splitAfter(sub, "\r\n\r\n")
	if body == "" {
		body = splitAfter(sub, "\n\n")
	}
	if body == "" {
		return ""
	}
	base := body
	if endIdx := strings.Index(base, "\r\n------"); endIdx != -1 {
		base = base[:endIdx]
	} else if endIdx := strings.Index(base, "\n------"); endIdx != -1 {
		base = base[:endIdx]
	}
	base = strings.Map(func(r rune) rune {
		if r == '\r' || r == '\n' || r == ' ' || r == '\t' {
			return -1
		}
		return r
	}, base)
	if base == "" {
		return ""
	}
	decoded, err := base64.StdEncoding.DecodeString(base)
	if err != nil {
		log.Fatalf("decode base64: %v", err)
	}
	return string(decoded)
}

func resolvePath(rel string, mustExist bool) string {
	candidates := []string{
		filepath.Join(".", rel),
		filepath.Join(exampleDir, rel),
		filepath.Join("..", exampleDir, rel),
	}
	for _, c := range candidates {
		if _, err := os.Stat(c); err == nil {
			return c
		}
	}
	if mustExist {
		log.Fatalf("could not resolve path for %s", rel)
	}
	return filepath.Join(exampleDir, rel)
}

func resolvePathWithBase(rel, base string, mustExist bool) string {
	if filepath.IsAbs(rel) {
		if !mustExist {
			return rel
		}
		if _, err := os.Stat(rel); err == nil {
			return rel
		}
		log.Fatalf("could not resolve path for %s", rel)
	}

	candidates := []string{
		filepath.Join(base, rel),
		filepath.Join(".", rel),
		filepath.Join(exampleDir, rel),
		filepath.Join("..", exampleDir, rel),
	}
	for _, c := range candidates {
		if _, err := os.Stat(c); err == nil {
			return c
		}
	}
	if mustExist {
		log.Fatalf("could not resolve path for %s", rel)
	}
	return filepath.Join(base, rel)
}

func splitAfter(s, sep string) string {
	idx := strings.Index(s, sep)
	if idx == -1 {
		return ""
	}
	return s[idx+len(sep):]
}
