import Cocoa
import FlutterMacOS

@main
class AppDelegate: FlutterAppDelegate {
  override func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool {
    return true
  }

  override func applicationSupportsSecureRestorableState(_ app: NSApplication) -> Bool {
    return true
  }

  /// 关窗口退出时同步停掉 detached 的 Syncthing（Dart 钩子可能来不及跑完）
  override func applicationWillTerminate(_ notification: Notification) {
    let task = Process()
    task.executableURL = URL(fileURLWithPath: "/usr/bin/pkill")
    task.arguments = ["-x", "syncthing"]
    do {
      try task.run()
      task.waitUntilExit()
    } catch {
      // 忽略：进程可能已退出
    }
    super.applicationWillTerminate(notification)
  }
}
