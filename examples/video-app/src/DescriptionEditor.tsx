import { useEffect, useId, useRef } from 'react';
import EditorJS, { type OutputData, type ToolConstructable } from '@editorjs/editorjs';
import Header from '@editorjs/header';
import List from '@editorjs/list';
import Paragraph from '@editorjs/paragraph';
import { Box } from '@mui/material';

type Props = {
  initial?: OutputData | null;
  onReady?: (api: { save: () => Promise<OutputData> }) => void;
  disabled?: boolean;
  minHeight?: number;
};

export default function DescriptionEditor({
  initial,
  onReady,
  disabled,
  minHeight = 160,
}: Props) {
  const holderId = useId().replace(/:/g, '');
  const editorRef = useRef<EditorJS | null>(null);

  useEffect(() => {
    let destroyed = false;
    const editor = new EditorJS({
      holder: holderId,
      readOnly: !!disabled,
      placeholder: '添加描述…',
      data: initial && initial.blocks ? initial : undefined,
      tools: {
        header: Header as unknown as ToolConstructable,
        list: List as unknown as ToolConstructable,
        paragraph: {
          class: Paragraph as unknown as ToolConstructable,
          inlineToolbar: true,
        },
      },
      minHeight,
    });
    editorRef.current = editor;
    editor.isReady
      .then(() => {
        if (destroyed) return;
        onReady?.({
          save: () => editor.save(),
        });
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
        border: 1,
        borderColor: 'divider',
        borderRadius: 1,
        px: 1.5,
        py: 1,
        minHeight,
        bgcolor: 'background.paper',
        '& .ce-block__content, & .ce-toolbar__content': {
          maxWidth: '100%',
        },
      }}
    />
  );
}
