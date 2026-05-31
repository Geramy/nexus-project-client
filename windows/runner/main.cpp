#include <flutter/dart_project.h>
#include <flutter/flutter_view_controller.h>
#include <windows.h>

#include "flutter_window.h"
#include "utils.h"

int APIENTRY wWinMain(_In_ HINSTANCE instance, _In_opt_ HINSTANCE prev,
                      _In_ wchar_t *command_line, _In_ int show_command) {
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
  // Launch at 50% of the primary monitor's work area, centered. Win32Window::Create
  // scales these logical values to physical pixels by the monitor DPI, so we convert
  // the physical work area to logical units before halving. Falls back to a fixed
  // size if the work area can't be read.
  Win32Window::Point origin(10, 10);
  Win32Window::Size size(1280, 720);
  RECT work_area;
  if (::SystemParametersInfo(SPI_GETWORKAREA, 0, &work_area, 0)) {
    const double scale = ::GetDpiForSystem() / 96.0;
    const int work_w = static_cast<int>((work_area.right - work_area.left) / scale);
    const int work_h = static_cast<int>((work_area.bottom - work_area.top) / scale);
    const int win_w = work_w / 2;
    const int win_h = work_h / 2;
    origin = Win32Window::Point((work_w - win_w) / 2, (work_h - win_h) / 2);
    size = Win32Window::Size(win_w, win_h);
  }
  if (!window.Create(L"nexus_projects_client", origin, size)) {
    return EXIT_FAILURE;
  }
  window.SetQuitOnClose(true);

  ::MSG msg;
  while (::GetMessage(&msg, nullptr, 0, 0)) {
    ::TranslateMessage(&msg);
    ::DispatchMessage(&msg);
  }

  ::CoUninitialize();
  return EXIT_SUCCESS;
}
