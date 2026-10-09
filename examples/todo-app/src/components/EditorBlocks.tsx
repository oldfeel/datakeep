import type { OutputData } from '@editorjs/editorjs';
import { Box, Typography } from '@mui/material';

function listItems(data: Record<string, unknown>): string[] {
  const items = data.items;
  if (!Array.isArray(items)) return [];
  return items.map((it) => {
    if (typeof it === 'string') return it;
    if (it && typeof it === 'object' && 'content' in it) {
      return String((it as { content?: unknown }).content || '');
    }
    return String(it ?? '');
  });
}

export default function EditorBlocks({ data }: { data: OutputData }) {
  const blocks = data.blocks || [];
  if (!blocks.length) return null;
  return (
    <Box sx={{ '& p': { m: 0, mb: 0.75 }, '& img': { maxWidth: '100%' } }}>
      {blocks.map((b, i) => {
        const d = (b.data || {}) as Record<string, unknown>;
        if (b.type === 'header') {
          const level = Number(d.level) || 3;
          const variant = level <= 2 ? 'h6' : 'subtitle1';
          return (
            <Typography
              key={i}
              variant={variant}
              sx={{ fontWeight: 700, mb: 0.75 }}
              dangerouslySetInnerHTML={{ __html: String(d.text || '') }}
            />
          );
        }
        if (b.type === 'list') {
          const items = listItems(d);
          const ordered = d.style === 'ordered';
          const ListTag = ordered ? 'ol' : 'ul';
          return (
            <Box
              key={i}
              component={ListTag}
              sx={{ m: 0, mb: 0.75, pl: 2.5, typography: 'body2' }}
            >
              {items.map((it, j) => (
                <li key={j} dangerouslySetInnerHTML={{ __html: it }} />
              ))}
            </Box>
          );
        }
        if (b.type === 'image') {
          const url = String(d.url || '');
          if (!url) return null;
          return (
            <Box
              key={i}
              component="a"
              href={url}
              target="_blank"
              rel="noreferrer"
              sx={{ display: 'block', my: 0.75, lineHeight: 0 }}
            >
              <Box
                component="img"
                src={url}
                alt={String(d.caption || '')}
                sx={{ maxWidth: '100%', borderRadius: 1 }}
              />
            </Box>
          );
        }
        return (
          <Typography
            key={i}
            variant="body2"
            sx={{ mb: 0.75, whiteSpace: 'pre-wrap' }}
            dangerouslySetInnerHTML={{ __html: String(d.text || '') }}
          />
        );
      })}
    </Box>
  );
}
