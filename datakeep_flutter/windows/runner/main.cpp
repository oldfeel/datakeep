#include <flutter/dart_project.h>
#include <flutter/flutter_view_controller.h>
#include <windows.h>

#include "flutter_window.h"
#include "utils.h"
#include "webview_cef/webview_cef_plugin_c_api.h"

// CEF 149：通过导入符号强制 EXE 依赖 chrome_elf.dll（须早于 libcef 加载）
extern "C" __declspec(dllimport) int GetApplyHookResult();

int APIENTRY wWinMain(_In_ HINSTANCE instance, _In_opt_ HINSTANCE prev,
                      _In_ wchar_t *command_line, _In_ int show_command) {
  // 触达导入，确保链接器保留 chrome_elf 依赖；返回值本身无关键。
  (void)GetApplyHookResult();

  // CEF 多进程：必须最先初始化子进程
  int exit_code = initCEFProcesses(instance);
  if (exit_code >= 0) {
    return exit_code;
  }

  // Attach to console when present (e.g., 'flutter run') or create a
  // new console when running with a debugger.
  if (!::AttachConsole(ATTACH_PARENT_PROCESS) && ::IsDebuggerPresent()) {
    CreateAndAttachConsole();
  }

  // Initialize COM, so that it is available for use in the library and/or
  // plugins.
  ::CoInitializeEx(nullptr, COINIT_APARTMENTTHREADED);

  flutter::DartProject project(L"data");

  std::vector<std::string> command_line_arguments =
      GetCommandLineArguments();

  project.set_dart_entrypoint_arguments(std::move(command_line_arguments));

  FlutterWindow window(project);
  Win32Window::Point origin(10, 10);
  Win32Window::Size size(1280, 720);
  // 窗口标题：数据管理
  if (!window.Create(L"\u6570\u636e\u7ba1\u7406", origin, size)) {
    return EXIT_FAILURE;
  }
  window.SetQuitOnClose(true);

  ::MSG msg;
  while (::GetMessage(&msg, nullptr, 0, 0)) {
    ::TranslateMessage(&msg);
    ::DispatchMessage(&msg);
    // CEF 键盘/IME 与主线程消息转发
    handleWndProcForCEF(msg.hwnd, msg.message, msg.wParam, msg.lParam);
  }

  ::CoUninitialize();
  return EXIT_SUCCESS;
}
