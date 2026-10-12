import BackgroundTasks
import Foundation
import UIKit

/// iOS 后台同步（对齐 sushitrain 思路，精简版）：
/// - BGProcessingTask：充电/有网时较长窗口跑 Syncthing
/// - BGAppRefreshTask：短刷新（可选）
/// - 退到后台时 beginBackgroundTask 再撑几十秒
final class BackgroundSyncManager {
  static let longTaskId = "site.datakeep.background-sync"
  static let shortTaskId = "site.datakeep.short-background-sync"

  private static let longEnabledKey = "ios_bg_sync_long_enabled"
  private static let shortEnabledKey = "ios_bg_sync_short_enabled"
  private static let lastRunKey = "ios_bg_sync_last_run"
  private static let backgroundTimeReserve: TimeInterval = 5.6

  private weak var appDelegate: AppDelegate?
  private var currentTask: BGTask?
  private var expireTimer: Timer?
  private var uiBackgroundTaskId: UIBackgroundTaskIdentifier = .invalid
  private var isEnding = false

  var longEnabled: Bool {
    get {
      if UserDefaults.standard.object(forKey: Self.longEnabledKey) == nil { return true }
      return UserDefaults.standard.bool(forKey: Self.longEnabledKey)
    }
    set {
      UserDefaults.standard.set(newValue, forKey: Self.longEnabledKey)
      _ = schedule()
    }
  }

  var shortEnabled: Bool {
    get { UserDefaults.standard.bool(forKey: Self.shortEnabledKey) }
    set {
      UserDefaults.standard.set(newValue, forKey: Self.shortEnabledKey)
      _ = schedule()
    }
  }

  init(appDelegate: AppDelegate) {
    self.appDelegate = appDelegate
    BGTaskScheduler.shared.register(
      forTaskWithIdentifier: Self.longTaskId,
      using: DispatchQueue.main
    ) { [weak self] task in
      self?.handle(task: task)
    }
    BGTaskScheduler.shared.register(
      forTaskWithIdentifier: Self.shortTaskId,
      using: DispatchQueue.main
    ) { [weak self] task in
      self?.handle(task: task)
    }
    _ = schedule()
    NSLog("[bg-sync] registered long/short handlers")
  }

  @discardableResult
  func schedule() -> Bool {
    var ok = true
    BGTaskScheduler.shared.cancel(taskRequestWithIdentifier: Self.longTaskId)
    BGTaskScheduler.shared.cancel(taskRequestWithIdentifier: Self.shortTaskId)

    if longEnabled {
      let req = BGProcessingTaskRequest(identifier: Self.longTaskId)
      req.earliestBeginDate = Date(timeIntervalSinceNow: 15 * 60)
      req.requiresNetworkConnectivity = true
      // 与 sushitrain 一致：长任务偏好充电，降低耗电与审核风险
      req.requiresExternalPower = true
      do {
        try BGTaskScheduler.shared.submit(req)
        NSLog("[bg-sync] scheduled long task")
      } catch {
        NSLog("[bg-sync] schedule long failed: \(error.localizedDescription)")
        ok = false
      }
    }

    if shortEnabled {
      let req = BGAppRefreshTaskRequest(identifier: Self.shortTaskId)
      req.earliestBeginDate = Date(timeIntervalSinceNow: 30 * 60)
      do {
        try BGTaskScheduler.shared.submit(req)
        NSLog("[bg-sync] scheduled short task")
      } catch {
        NSLog("[bg-sync] schedule short failed: \(error.localizedDescription)")
        ok = false
      }
    }
    return ok
  }

  /// 用户切到后台：短时续命 + 重新预约系统任务
  func handleEnterBackground() {
    _ = schedule()
    guard uiBackgroundTaskId == .invalid else { return }
    uiBackgroundTaskId = UIApplication.shared.beginBackgroundTask(withName: "datakeep-sync") { [weak self] in
      self?.endUIBackgroundTask()
    }
    NSLog(
      "[bg-sync] beginBackgroundTask remaining=\(UIApplication.shared.backgroundTimeRemaining)"
    )
    // 确保引擎在跑（Flutter 可能已挂起）
    DispatchQueue.global(qos: .userInitiated).async { [weak self] in
      do {
        try self?.appDelegate?.ensureEngineRunning()
      } catch {
        NSLog("[bg-sync] ensure engine on background failed: \(error.localizedDescription)")
      }
    }
  }

  func handleEnterForeground() {
    endUIBackgroundTask()
    _ = schedule()
  }

  func statusMap() -> [String: Any] {
    let last = UserDefaults.standard.object(forKey: Self.lastRunKey) as? Date
    return [
      "longEnabled": longEnabled,
      "shortEnabled": shortEnabled,
      "lastRunEpochMs": last.map { Int($0.timeIntervalSince1970 * 1000) } as Any,
      "bgTaskActive": currentTask != nil,
    ]
  }

  private func handle(task: BGTask) {
    NSLog("[bg-sync] launch \(task.identifier) remaining=\(UIApplication.shared.backgroundTimeRemaining)")
    if currentTask != nil {
      task.setTaskCompleted(success: false)
      return
    }
    currentTask = task
    isEnding = false
    _ = schedule()

    let enabled =
      (task.identifier == Self.longTaskId && longEnabled)
      || (task.identifier == Self.shortTaskId && shortEnabled)
    guard enabled else {
      finish(success: true)
      return
    }

    task.expirationHandler = { [weak self] in
      NSLog("[bg-sync] expirationHandler")
      self?.finish(success: true)
    }

    DispatchQueue.global(qos: .userInitiated).async { [weak self] in
      guard let self else { return }
      do {
        try self.appDelegate?.ensureEngineRunning()
      } catch {
        NSLog("[bg-sync] start engine failed: \(error.localizedDescription)")
        DispatchQueue.main.async { self.finish(success: false) }
        return
      }
      DispatchQueue.main.async {
        self.expireTimer?.invalidate()
        self.expireTimer = Timer.scheduledTimer(withTimeInterval: 1.0, repeats: true) { [weak self] _ in
          guard let self else { return }
          let remaining = UIApplication.shared.backgroundTimeRemaining
          if remaining <= Self.backgroundTimeReserve {
            NSLog("[bg-sync] nearing end remaining=\(remaining)")
            self.finish(success: true)
          }
        }
      }
    }
  }

  private func finish(success: Bool) {
    guard !isEnding else { return }
    isEnding = true
    expireTimer?.invalidate()
    expireTimer = nil
    UserDefaults.standard.set(Date(), forKey: Self.lastRunKey)
    if let task = currentTask {
      task.setTaskCompleted(success: success)
      NSLog("[bg-sync] completed success=\(success)")
    }
    currentTask = nil
    isEnding = false
  }

  private func endUIBackgroundTask() {
    guard uiBackgroundTaskId != .invalid else { return }
    UIApplication.shared.endBackgroundTask(uiBackgroundTaskId)
    uiBackgroundTaskId = .invalid
    NSLog("[bg-sync] endBackgroundTask")
  }
}
