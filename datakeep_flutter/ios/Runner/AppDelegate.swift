import Flutter
import UIKit
import DataKeepSyncthing

@main
@objc class AppDelegate: FlutterAppDelegate {
  private let channelName = "tech.shupi.datakeep/api"
  private var client: MdstClient?
  private var status: String = "stopped"

  override func application(
    _ application: UIApplication,
    didFinishLaunchingWithOptions launchOptions: [UIApplication.LaunchOptionsKey: Any]?
  ) -> Bool {
    GeneratedPluginRegistrant.register(with: self)

    let controller = window?.rootViewController as! FlutterViewController
    let channel = FlutterMethodChannel(
      name: channelName,
      binaryMessenger: controller.binaryMessenger
    )
    channel.setMethodCallHandler { [weak self] call, result in
      self?.handle(call: call, result: result)
    }

    return super.application(application, didFinishLaunchingWithOptions: launchOptions)
  }

  /// iOS Syncthing 桥：对齐 Android MethodChannel；引擎为 gomobile 进程内节点。
  private func handle(call: FlutterMethodCall, result: @escaping FlutterResult) {
    switch call.method {
    case "startSyncthingService":
      DispatchQueue.global(qos: .userInitiated).async { [weak self] in
        guard let self else { return }
        do {
          try self.startEngine()
          DispatchQueue.main.async { result(true) }
        } catch {
          DispatchQueue.main.async {
            result(FlutterError(
              code: "START_FAILED",
              message: error.localizedDescription,
              details: nil
            ))
          }
        }
      }
    case "stopSyncthingService":
      DispatchQueue.global(qos: .userInitiated).async { [weak self] in
        self?.client?.stop()
        self?.status = "stopped"
        DispatchQueue.main.async { result(true) }
      }
    case "restartSyncthingService":
      DispatchQueue.global(qos: .userInitiated).async { [weak self] in
        guard let self else { return }
        do {
          self.client?.stop()
          self.status = "stopped"
          try self.startEngine()
          DispatchQueue.main.async { result(true) }
        } catch {
          DispatchQueue.main.async {
            result(FlutterError(
              code: "RESTART_FAILED",
              message: error.localizedDescription,
              details: nil
            ))
          }
        }
      }
    case "getServiceStatus":
      result(status)
    case "getSyncthingConfigPath":
      let home = syncthingHomeURL()
      let config = home.appendingPathComponent("config.xml")
      result([
        "path": config.path,
        "deviceName": UIDevice.current.name,
      ])
    case "getDefaultDeviceName":
      result(UIDevice.current.name)
    case "getDefaultSyncFolderPath":
      let args = call.arguments as? [String: Any]
      let folderId = (args?["folderId"] as? String)?.trimmingCharacters(in: .whitespacesAndNewlines)
      guard let folderId, !folderId.isEmpty else {
        result(FlutterError(code: "BAD_ARGS", message: "缺少 folderId", details: nil))
        return
      }
      let docs = documentsURL()
      let syncRoot = docs.appendingPathComponent("sync", isDirectory: true)
      let folder = syncRoot.appendingPathComponent(folderId, isDirectory: true)
      try? FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
      result(folder.path)
    default:
      result(FlutterMethodNotImplemented)
    }
  }

  private func startEngine() throws {
    if let existing = client, existing.isRunning() {
      status = "running"
      return
    }

    status = "starting"
    let home = syncthingHomeURL().path
    let files = documentsURL().path
    guard let c = client ?? MdstNewClient(home, files) else {
      status = "stopped"
      throw NSError(domain: "DataKeepSyncthing", code: 1, userInfo: [
        NSLocalizedDescriptionKey: "无法创建 Syncthing Client",
      ])
    }
    client = c
    c.setDeviceName(UIDevice.current.name)
    try c.start()
    status = c.isRunning() ? "running" : "stopped"
    if !c.isRunning() {
      let err = c.lastError()
      let msg = err.isEmpty ? "Syncthing 启动失败" : err
      throw NSError(domain: "DataKeepSyncthing", code: 1, userInfo: [
        NSLocalizedDescriptionKey: msg,
      ])
    }
  }

  private func syncthingHomeURL() -> URL {
    let support = FileManager.default.urls(
      for: .applicationSupportDirectory,
      in: .userDomainMask
    ).first!
    let syncHome = support.appendingPathComponent("syncthing", isDirectory: true)
    try? FileManager.default.createDirectory(at: syncHome, withIntermediateDirectories: true)
    return syncHome
  }

  private func documentsURL() -> URL {
    FileManager.default.urls(for: .documentDirectory, in: .userDomainMask).first!
  }
}
