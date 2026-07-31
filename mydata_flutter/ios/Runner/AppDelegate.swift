import Flutter
import UIKit

@main
@objc class AppDelegate: FlutterAppDelegate {
  private let channelName = "tech.shupi.mydata/api"

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

  /// iOS Syncthing 桥：对齐 Android MethodChannel。
  /// 引擎嵌入参考 sushitrain（gomobile 进程内节点）；当前返回未实现，待编入 xcframework。
  private func handle(call: FlutterMethodCall, result: @escaping FlutterResult) {
    switch call.method {
    case "startSyncthingService", "stopSyncthingService", "restartSyncthingService":
      // TODO: 调用 SushitrainCore 风格 Client.Start/Stop
      result(FlutterError(
        code: "UNIMPLEMENTED",
        message: "iOS Syncthing 引擎尚未编入（参考 sushitrain gomobile）。前台同步待 xcframework。",
        details: nil
      ))
    case "getServiceStatus":
      result("not_implemented")
    case "getSyncthingConfigPath":
      let support = FileManager.default.urls(
        for: .applicationSupportDirectory,
        in: .userDomainMask
      ).first!
      let syncHome = support.appendingPathComponent("syncthing", isDirectory: true)
      try? FileManager.default.createDirectory(at: syncHome, withIntermediateDirectories: true)
      let config = syncHome.appendingPathComponent("config.xml")
      result([
        "path": config.path,
        "deviceName": UIDevice.current.name,
      ])
    default:
      result(FlutterMethodNotImplemented)
    }
  }
}
