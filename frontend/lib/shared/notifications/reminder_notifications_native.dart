import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:timezone/data/latest.dart' as tz_data;
import 'package:timezone/timezone.dart' as tz;

final _notifications = FlutterLocalNotificationsPlugin();
var _initialized = false;

Future<void> _ensureInitialized() async {
  if (_initialized) return;
  tz_data.initializeTimeZones();
  const android = AndroidInitializationSettings('@mipmap/ic_launcher');
  const darwin = DarwinInitializationSettings();
  await _notifications.initialize(
    settings: const InitializationSettings(android: android, iOS: darwin),
  );
  _initialized = true;
}

Future<bool> requestReminderPermission() async {
  await _ensureInitialized();
  final android = _notifications.resolvePlatformSpecificImplementation<
      AndroidFlutterLocalNotificationsPlugin>();
  final androidGranted = await android?.requestNotificationsPermission();
  final ios = _notifications.resolvePlatformSpecificImplementation<
      IOSFlutterLocalNotificationsPlugin>();
  final iosGranted = await ios?.requestPermissions(
    alert: true,
    badge: true,
    sound: true,
  );
  return androidGranted ?? iosGranted ?? true;
}

Future<bool> showReminderNotification({
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
}) async {
  await _ensureInitialized();
  if (!scheduledAt.isAfter(DateTime.now())) return;
  await _notifications.zonedSchedule(
    id: _notificationId(reminderId),
    title: title,
    body: body,
    scheduledDate: tz.TZDateTime.from(scheduledAt.toLocal(), tz.local),
    androidScheduleMode: AndroidScheduleMode.inexactAllowWhileIdle,
    notificationDetails: const NotificationDetails(
      android: AndroidNotificationDetails(
        'note_reminders',
        'Erinnerungen',
        channelDescription: 'Lokale Erinnerungen für Notizen',
        importance: Importance.high,
        priority: Priority.high,
      ),
      iOS: DarwinNotificationDetails(),
    ),
  );
}

Future<void> cancelReminderNotification(String reminderId) async {
  await _ensureInitialized();
  await _notifications.cancel(id: _notificationId(reminderId));
}

int _notificationId(String value) {
  var hash = 0;
  for (final unit in value.codeUnits) {
    hash = (hash * 31 + unit) & 0x7fffffff;
  }
  return hash;
}
