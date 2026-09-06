import BackgroundTasks
import Flutter
import Foundation
import HealthKit
import UIKit

/// Native-side wiring for iOS background constraints:
/// - `BGTaskScheduler` for deferred refresh windows (not continuous execution).
/// - Silent remote notifications (`content-available`) to nudge the app awake.
/// - HealthKit read + observer queries for **Fall Detection** samples that sync to Health.
///
/// **Apple’s system Crash Detection** (severe vehicle crash) is not exposed to third-party
/// apps via a public HealthKit type at the time of writing; entitlements + this bridge are the
/// supported integration surface when/if Apple documents read access.
final class IosBackgroundAndHealthPlugin: NSObject {
  static let shared = IosBackgroundAndHealthPlugin()

  static let bgRefreshTaskId = "com.example.roadsos.bg-refresh"
  static let lifecycleChannelName = "com.codestreak.roadsos/ios_lifecycle"

  private var messenger: FlutterBinaryMessenger?
  private let healthStore = HKHealthStore()
  private var didConfigureHealthKit = false

  /// Register BGTask handlers with the OS — call early from `application(_:didFinishLaunchingWithOptions:)`.
  func prepareBackgroundInfrastructure() {
    registerBackgroundTasks()
    submitAppRefreshRequest()
  }

  /// Call after a `FlutterBinaryMessenger` exists (same place you register other channels).
  func attachFlutterChannels(messenger: FlutterBinaryMessenger) {
    self.messenger = messenger
    let channel = FlutterMethodChannel(
      name: Self.lifecycleChannelName,
      binaryMessenger: messenger
    )
    channel.setMethodCallHandler { [weak self] call, result in
      switch call.method {
      case "scheduleBackgroundRefresh":
        self?.submitAppRefreshRequest()
        result(nil)
      default:
        result(FlutterMethodNotImplemented)
      }
    }
    configureHealthKit()
  }

  private func registerBackgroundTasks() {
    guard #available(iOS 13.0, *) else { return }
    BGTaskScheduler.shared.cancel(taskRequestWithIdentifier: Self.bgRefreshTaskId)
    BGTaskScheduler.shared.register(forTaskWithIdentifier: Self.bgRefreshTaskId, using: nil) {
      task in
      guard let refresh = task as? BGAppRefreshTask else {
        task.setTaskCompleted(success: false)
        return
      }
      self.handleAppRefresh(refresh)
    }
  }

  @available(iOS 13.0, *)
  private func handleAppRefresh(_ task: BGAppRefreshTask) {
    submitAppRefreshRequest()
    task.expirationHandler = {
      task.setTaskCompleted(success: false)
    }
    notifyFlutter(
      method: "onBackgroundPing",
      arguments: [
        "source": "bg_app_refresh",
        "timestamp": ISO8601DateFormatter().string(from: Date()),
      ])
    task.setTaskCompleted(success: true)
  }

  @available(iOS 13.0, *)
  func submitAppRefreshRequest() {
    let request = BGAppRefreshTaskRequest(identifier: Self.bgRefreshTaskId)
    request.earliestBeginDate = Date(timeIntervalSinceNow: 15 * 60)
    do {
      try BGTaskScheduler.shared.submit(request)
    } catch {
      NSLog("RoadSOS: BGTask submit failed — \(error.localizedDescription)")
    }
  }

  /// Called from `AppDelegate` when a silent push arrives (must use the
  /// `remote-notification` background mode + APNs payload with `content-available: 1`).
  func notifySilentPushReceived(userInfo: [AnyHashable: Any]) {
    notifyFlutter(
      method: "onBackgroundPing",
      arguments: [
        "source": "silent_push",
        "payload": userInfo,
        "timestamp": ISO8601DateFormatter().string(from: Date()),
      ])
  }

  private func configureHealthKit() {
    guard !didConfigureHealthKit else { return }
    didConfigureHealthKit = true
    guard HKHealthStore.isHealthDataAvailable() else {
      NSLog("RoadSOS: HealthKit not available on this device")
      return
    }
    var typesToRead = Set<HKObjectType>()
    if let fall = HKObjectType.categoryType(forIdentifier: .fall) {
      typesToRead.insert(fall)
    }
    guard !typesToRead.isEmpty else { return }

    healthStore.requestAuthorization(toShare: nil, read: typesToRead) { [weak self] success, error in
      if let error {
        NSLog("RoadSOS: HealthKit auth error — \(error.localizedDescription)")
      }
      guard success, let self else { return }
      for type in typesToRead {
        self.healthStore.enableBackgroundDelivery(for: type, frequency: .immediate) { ok, err in
          if let err {
            NSLog("RoadSOS: enableBackgroundDelivery — \(err.localizedDescription)")
          }
          _ = ok
        }
        let query = HKObserverQuery(sampleType: type, predicate: nil) {
          [weak self] _, completionHandler, error in
          if let error {
            NSLog("RoadSOS: HealthKit observer — \(error.localizedDescription)")
          }
          self?.notifyHealthKitUpdate(sampleType: type)
          completionHandler()
        }
        self.healthStore.execute(query)
      }
    }
  }

  private func notifyHealthKitUpdate(sampleType: HKObjectType) {
    notifyFlutter(
      method: "onHealthKitSignal",
      arguments: [
        "identifier": sampleType.identifier,
        "note":
          "Public HealthKit APIs do not currently expose Apple vehicle Crash Detection samples to third-party apps.",
        "timestamp": ISO8601DateFormatter().string(from: Date()),
      ])
  }

  private func notifyFlutter(method: String, arguments: Any?) {
    guard let messenger else {
      NSLog("RoadSOS: Flutter engine not ready — skipped \(method)")
      return
    }
    DispatchQueue.main.async {
      let channel = FlutterMethodChannel(
        name: Self.lifecycleChannelName,
        binaryMessenger: messenger
      )
      channel.invokeMethod(method, arguments: arguments)
    }
  }
}
