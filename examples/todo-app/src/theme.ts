import { createTheme } from '@mui/material/styles';

const primary = '#2564cf';
const selectedBg = 'rgba(37, 100, 207, 0.22)';
const selectedHover = 'rgba(37, 100, 207, 0.32)';
const outline = 'rgba(0, 0, 0, 0.48)';

export const theme = createTheme({
  palette: {
    mode: 'light',
    primary: { main: primary },
    background: { default: '#f5f5f5', paper: '#ffffff' },
    divider: 'rgba(0, 0, 0, 0.22)',
    action: {
      selected: selectedBg,
      hover: 'rgba(37, 100, 207, 0.08)',
    },
  },
  typography: {
    fontFamily: [
      '"Segoe UI"',
      'Roboto',
      '"Helvetica Neue"',
      'Arial',
      'sans-serif',
    ].join(','),
  },
  shape: { borderRadius: 8 },
  components: {
    MuiOutlinedInput: {
      styleOverrides: {
        notchedOutline: {
          borderColor: outline,
          borderWidth: 1.5,
        },
        root: {
          '&:hover .MuiOutlinedInput-notchedOutline': {
            borderColor: primary,
          },
          '&.Mui-focused .MuiOutlinedInput-notchedOutline': {
            borderColor: primary,
            borderWidth: 2,
          },
        },
      },
    },
    MuiInputLabel: {
      styleOverrides: {
        root: {
          '&.Mui-focused': { color: primary },
        },
      },
    },
    MuiListItemButton: {
      styleOverrides: {
        root: {
          '&.Mui-selected': {
            backgroundColor: selectedBg,
            boxShadow: `inset 4px 0 0 ${primary}`,
            '&:hover': {
              backgroundColor: selectedHover,
            },
            '& .MuiListItemText-primary': {
              fontWeight: 700,
              color: '#123a8c',
            },
          },
        },
      },
    },
  },
});
