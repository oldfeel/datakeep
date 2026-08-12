import { Link as RouterLink, Outlet, useLocation } from 'react-router-dom';
import {
  AppBar,
  Box,
  Button,
  Container,
  IconButton,
  Toolbar,
  Typography,
} from '@mui/material';
import LogoutIcon from '@mui/icons-material/Logout';
import SettingsIcon from '@mui/icons-material/Settings';
import AppsIcon from '@mui/icons-material/Apps';
import { useAuth } from '../auth';

export default function AdminLayout() {
  const { username, logout } = useAuth();
  const loc = useLocation();

  return (
    <Box>
      <AppBar position="static" color="primary">
        <Toolbar>
          <Typography variant="h6" sx={{ flexGrow: 1 }}>
            DataKeep 应用市场
          </Typography>
          <Button
            color="inherit"
            component={RouterLink}
            to="/"
            startIcon={<AppsIcon />}
            sx={{ fontWeight: loc.pathname === '/' ? 700 : 400 }}
          >
            应用
          </Button>
          <Button
            color="inherit"
            component={RouterLink}
            to="/settings"
            startIcon={<SettingsIcon />}
            sx={{ fontWeight: loc.pathname.startsWith('/settings') ? 700 : 400 }}
          >
            设置
          </Button>
          <Typography sx={{ mx: 2 }}>{username}</Typography>
          <IconButton color="inherit" onClick={logout} aria-label="退出">
            <LogoutIcon />
          </IconButton>
        </Toolbar>
      </AppBar>
      <Container sx={{ mt: 3, mb: 4 }}>
        <Outlet />
      </Container>
    </Box>
  );
}
