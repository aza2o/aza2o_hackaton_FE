import Flutter
import HealthKit
import UIKit
import UserNotifications

@main
@objc class AppDelegate: FlutterAppDelegate, FlutterImplicitEngineDelegate {
  private let healthStore = HKHealthStore()

  override func application(
    _ application: UIApplication,
    didFinishLaunchingWithOptions launchOptions: [UIApplication.LaunchOptionsKey: Any]?
  ) -> Bool {
    // flutter_local_notifications README §iOS setup — 알림 탭 처리를 위해 필요.
    UNUserNotificationCenter.current().delegate = self as? UNUserNotificationCenterDelegate
    return super.application(application, didFinishLaunchingWithOptions: launchOptions)
  }

  func didInitializeImplicitFlutterEngine(_ engineBridge: FlutterImplicitEngineBridge) {
    GeneratedPluginRegistrant.register(with: engineBridge.pluginRegistry)

    // HKQuantityTypeIdentifierTimeInDaylight — Flutter `health` 패키지(v13.3.2)에
    // 이 타입이 없어 Swift 채널로 직접 구현 (SHIFT_개발기획서.md §7-1).
    let daylightChannel = FlutterMethodChannel(
      name: "shift/health_daylight",
      binaryMessenger: engineBridge.applicationRegistrar.messenger()
    )
    daylightChannel.setMethodCallHandler { [weak self] call, result in
      guard call.method == "timeInDaylight" else {
        result(FlutterMethodNotImplemented)
        return
      }
      self?.handleTimeInDaylight(call: call, result: result)
    }
  }

  private func handleTimeInDaylight(call: FlutterMethodCall, result: @escaping FlutterResult) {
    // HKQuantityTypeIdentifier.timeInDaylight는 iOS 17부터 존재한다.
    guard #available(iOS 17.0, *) else {
      result(FlutterError(code: "unsupported_os", message: "TimeInDaylight requires iOS 17 or newer", details: nil))
      return
    }

    guard
      let args = call.arguments as? [String: Any],
      let startMillis = (args["startMillis"] as? NSNumber)?.doubleValue,
      let endMillis = (args["endMillis"] as? NSNumber)?.doubleValue,
      let daylightType = HKQuantityType.quantityType(forIdentifier: .timeInDaylight)
    else {
      result(FlutterError(code: "bad_args", message: "startMillis/endMillis required", details: nil))
      return
    }

    guard HKHealthStore.isHealthDataAvailable() else {
      result(FlutterError(code: "unavailable", message: "HealthKit not available on this device", details: nil))
      return
    }

    healthStore.requestAuthorization(toShare: [], read: [daylightType]) { [weak self] _, error in
      guard let self else { return }
      if let error {
        result(FlutterError(code: "auth_failed", message: error.localizedDescription, details: nil))
        return
      }

      let start = Date(timeIntervalSince1970: startMillis / 1000)
      let end = Date(timeIntervalSince1970: endMillis / 1000)
      let predicate = HKQuery.predicateForSamples(withStart: start, end: end, options: .strictStartDate)

      var anchorComponents = Calendar.current.dateComponents([.year, .month, .day], from: start)
      anchorComponents.timeZone = Calendar.current.timeZone
      let anchor = Calendar.current.date(from: anchorComponents) ?? start

      let query = HKStatisticsCollectionQuery(
        quantityType: daylightType,
        quantitySamplePredicate: predicate,
        options: .cumulativeSum,
        anchorDate: anchor,
        intervalComponents: DateComponents(hour: 1)
      )

      query.initialResultsHandler = { _, collection, error in
        if let error {
          result(FlutterError(code: "query_failed", message: error.localizedDescription, details: nil))
          return
        }
        var points: [[String: Any]] = []
        collection?.enumerateStatistics(from: start, to: end) { stats, _ in
          let minutes = stats.sumQuantity()?.doubleValue(for: .minute()) ?? 0
          points.append([
            "t": stats.startDate.timeIntervalSince1970 * 1000,
            "v": minutes,
          ])
        }
        result(points)
      }

      self.healthStore.execute(query)
    }
  }
}
