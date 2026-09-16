// ignore_for_file: avoid_web_libraries_in_flutter, deprecated_member_use

import 'dart:html' as html;

Future<bool> requestReminderPermission() async {
  if (!html.Notification.supported) return false;
  if (html.Notification.permission == 'granted') return true;
  final permission = await html.Notification.requestPermission();
  return permission == 'granted';
}

Future<void> openReminderNotificationSettings() async {}

Future<bool> showReminderNotification({
  required String reminderId,
  required String title,
  required String body,
}) async {
  if (!await requestReminderPermission()) return false;
  html.Notification(title, body: body);
  return true;
}

Future<void> scheduleReminderNotification({
  required String reminderId,
  required String title,
  required String body,
  required DateTime scheduledAt,
}) async {}

Future<void> cancelReminderNotification(String reminderId) async {}
