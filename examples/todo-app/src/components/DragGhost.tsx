import DragIndicatorIcon from '@mui/icons-material/DragIndicator';
import { Box } from '@mui/material';
import { useImperativeHandle, useRef, type Ref } from 'react';
import type { GhostHandle } from '../dnd';

export default function DragGhost({ handleRef }: { handleRef: Ref<GhostHandle> }) {
  const rootRef = useRef<HTMLDivElement>(null);
  const labelRef = useRef<HTMLSpanElement>(null);

  useImperativeHandle(handleRef, () => ({
    show(label, selected, x, y) {
      const el = rootRef.current;
      if (!el) return;
      el.style.display = 'flex';
      el.style.transform = `translate(${x + 12}px, ${y + 12}px)`;
      el.style.background = selected ? '#2564cf' : '#fff';
      el.style.color = selected ? '#fff' : 'inherit';
      if (labelRef.current) {
        labelRef.current.textContent = label;
        labelRef.current.style.fontWeight = selected ? '600' : '400';
      }
    },
    move(x, y) {
      const el = rootRef.current;
      if (!el || el.style.display === 'none') return;
      el.style.transform = `translate(${x + 12}px, ${y + 12}px)`;
    },
    hide() {
      const el = rootRef.current;
      if (!el) return;
      el.style.display = 'none';
    },
  }));

  return (
    <Box
      ref={rootRef}
      sx={{
        position: 'fixed',
        left: 0,
        top: 0,
        zIndex: 2000,
        pointerEvents: 'none',
        display: 'none',
        willChange: 'transform',
        filter: 'drop-shadow(0 4px 12px rgba(0,0,0,.35))',
        alignItems: 'center',
        minWidth: 160,
        maxWidth: 260,
        px: 1,
        py: 0.75,
        borderRadius: 1,
        border: 1,
        borderColor: 'divider',
      }}
    >
      <DragIndicatorIcon fontSize="small" sx={{ mr: 0.5, opacity: 0.55 }} />
      <Box
        component="span"
        ref={labelRef}
        sx={{
          flex: 1,
          typography: 'body2',
          overflow: 'hidden',
          textOverflow: 'ellipsis',
          whiteSpace: 'nowrap',
        }}
      />
    </Box>
  );
}
