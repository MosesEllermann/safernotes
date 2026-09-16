Future<bool> requestReminderPermission() async => false;

Future<void> openReminderNotificationSettings() async {}

Future<bool> showReminderNotification({
  required String reminderId,
  required String title,
  required String body,
}) async {
  return false;
}

Future<void> scheduleReminderNotification({
  required String reminderId,
  required String title,
  required String body,
  required DateTime scheduledAt,
}) async {}

Future<void> cancelReminderNotification(String reminderId) async {}
