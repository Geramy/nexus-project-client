import Cocoa
import Darwin
import FlutterMacOS

@main
class AppDelegate: FlutterAppDelegate {
  override func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool {
    return true
  }

  override func applicationSupportsSecureRestorableState(_ app: NSApplication) -> Bool {
    return true
  }

  // The Silero VAD (onnxruntime, pulled in by the `vad` package) registers a
  // global OrtEnv whose C++ static destructor runs during normal exit()
  // finalization (__cxa_finalize_ranges). At that point its worker threads are
  // still alive, so onnxruntime::Environment::~Environment() calls
  // std::terminate() → SIGABRT on every quit. This fires after Flutter's normal
  // termination coordination but just before that crashing exit() finalization,
  // so we hard-exit with _exit() to bypass the C++ atexit/static destructors.
  // All our persistence is already durable here (Drift/SQLite WAL commits per
  // transaction); we flush UserDefaults first so no recent preference
  // (onboarding flags, layout, etc.) is lost.
  override func applicationWillTerminate(_ notification: Notification) {
    UserDefaults.standard.synchronize()
    _exit(0)
  }
}
