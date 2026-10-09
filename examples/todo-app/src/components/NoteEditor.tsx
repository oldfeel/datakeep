import { useEffect, useId, useRef } from 'react';
import EditorJS, { type OutputData, type ToolConstructable } from '@editorjs/editorjs';
import Header from '@editorjs/header';
import List from '@editorjs/list';
import Paragraph from '@editorjs/paragraph';
import { Box } from '@mui/material';
import NoteImageTool from './editorjs/ImageTool';

type Props = {
  taskId: string;
  imageKind?: 'note' | 'comment';
  placeholder?: string;
  initial?: OutputData | null;
  onReady?: (api: { save: () => Promise<OutputData> }) => void;
  onBusy?: (busy: boolean) => void;
  onImageUploaded?: () => void;
  disabled?: boolean;
  minHeight?: number;
};

export default function NoteEditor({
  taskId,
  imageKind = 'note',
  placeholder = '添加备注…可插入图片',
  initial,
  onReady,
  onBusy,
  onImageUploaded,
  disabled,
  minHeight = 140,
}: Props) {
  const holderId = useId().replace(/:/g, '');
  const editorRef = useRef<EditorJS | null>(null);

  useEffect(() => {
    let destroyed = false;
    const editor = new EditorJS({
      holder: holderId,
      readOnly: !!disabled,
      placeholder,
      data: initial && initial.blocks ? initial : undefined,
      tools: {
        header: Header as unknown as ToolConstructable,
        list: List as unknown as ToolConstructable,
        paragraph: {
          class: Paragraph as unknown as ToolConstructable,
          inlineToolbar: true,
        },
        image: {
          class: NoteImageTool as unknown as ToolConstructable,
          config: { taskId, kind: imageKind, onBusy, onUploaded: onImageUploaded },
        },
      },
      minHeight,
    });
    editorRef.current = editor;
    editor.isReady
      .then(() => {
        if (destroyed) return;
        onReady?.({ save: () => editor.save() });
      })
      .catch((e) => console.error('Editor.js 初始化失败', e));

    return () => {
      destroyed = true;
      editorRef.current = null;
      editor.isReady
        .then(() => editor.destroy())
        .catch(() => {});
    };
    // eslint-disable-next-line react-hooks/exhaustive-deps
  }, [holderId]);

  return (
    <Box
      id={holderId}
      sx={{
        border: '1.5px solid',
        borderColor: 'rgba(0,0,0,0.48)',
        borderRadius: 1,
        px: 1.5,
        py: 1,
        minHeight,
        bgcolor: 'background.paper',
        '&:focus-within': {
          borderColor: 'primary.main',
          borderWidth: 2,
        },
        '& .ce-block__content, & .ce-toolbar__content': { maxWidth: '100%' },
      }}
    />
  );
}
