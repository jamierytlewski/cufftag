import UserNotifications

enum NotificationPermission {
  static func request() async throws -> Bool {
    try await UNUserNotificationCenter.current().requestAuthorization(options: [.alert, .sound])
  }
}
