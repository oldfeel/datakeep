#include <webview_cef/webview_cef_plugin.h>
#include "my_application.h"

#include <cstdio>
#include <cstdlib>
#include <cstring>
#include <fstream>
#include <string>

/// NVIDIA 专有驱动 + CEF Texture 时，Flutter 光栅线程易在 libnvidia-eglcore 闪退。
static bool linux_has_nvidia_driver() {
  std::ifstream ver("/proc/driver/nvidia/version");
  if (ver.good()) {
    return true;
  }
  std::ifstream mods("/proc/modules");
  std::string line;
  while (std::getline(mods, line)) {
    if (line.rfind("nvidia", 0) == 0) {
      return true;
    }
  }
  return false;
}

static void maybe_mitigate_nvidia_cef_crash() {
  // 显式逃生：DATAKEEP_ALLOW_NVIDIA_GL=1 时不做任何改写
  if (const char* allow = std::getenv("DATAKEEP_ALLOW_NVIDIA_GL");
      allow != nullptr && allow[0] != '\0' && std::strcmp(allow, "0") != 0) {
    return;
  }
  if (!linux_has_nvidia_driver()) {
    return;
  }

  // Flutter 的 software 合成器不支持 CEF 的 FlPixelBufferTexture → 应用页白屏。
  // 若用户/脚本设了 FLUTTER_LINUX_RENDERER=software，自动撤掉并改用 Mesa 软 GL。
  if (const char* renderer = std::getenv("FLUTTER_LINUX_RENDERER");
      renderer != nullptr && std::strcmp(renderer, "software") == 0) {
    unsetenv("FLUTTER_LINUX_RENDERER");
    std::fprintf(stderr,
                 "[datakeep] 已取消 FLUTTER_LINUX_RENDERER=software"
                 "（会导致 CEF 内嵌页白屏）\n");
  }

  // 保持 OpenGL 合成路径（CEF 纹理可显示），但走 Mesa 软件实现，避开 nvidia eglcore。
  if (std::getenv("LIBGL_ALWAYS_SOFTWARE") == nullptr) {
    setenv("LIBGL_ALWAYS_SOFTWARE", "1", 0);
  }
  std::fprintf(stderr,
               "[datakeep] 检测到 NVIDIA：使用 LIBGL_ALWAYS_SOFTWARE=1，"
               "减轻打开应用时闪退（界面可能略慢）\n");
}

int main(int argc, char** argv) {
  maybe_mitigate_nvidia_cef_crash();

  int exit_code = initCEFProcesses(argc, argv);
  if (exit_code >= 0) {
    return exit_code;
  }
  g_autoptr(MyApplication) app = my_application_new();
  return g_application_run(G_APPLICATION(app), argc, argv);
}
