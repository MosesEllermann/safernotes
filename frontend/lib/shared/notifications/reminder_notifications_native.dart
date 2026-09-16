import 'dart:ui';

import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:timezone/data/latest.dart' as tz_data;
import 'package:timezone/timezone.dart' as tz;

final _notifications = FlutterLocalNotificationsPlugin();
var _initialized = false;
Future<void>? _initialization;
Future<void> _notificationQueue = Future.value();

Future<void> _ensureInitialized() {
  if (_initialized) return Future.value();
  final active = _initialization;
  if (active != null) return active;
  final initialization = _initialize();
  _initialization = initialization;
  return initialization.whenComplete(() {
    if (identical(_initialization, initialization)) _initialization = null;
  });
}

Future<void> _initialize() async {
  tz_data.initializeTimeZones();
  const android = AndroidInitializationSettings('@drawable/ic_notification');
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
  if (androidGranted == false) return false;
  final ios = _notifications.resolvePlatformSpecificImplementation<
      IOSFlutterLocalNotificationsPlugin>();
  final iosGranted = await ios?.requestPermissions(
    alert: true,
    badge: true,
    sound: true,
  );
  return androidGranted ?? iosGranted ?? true;
}

Future<void> openReminderNotificationSettings() async {
  await _ensureInitialized();
  await _notifications.openAppNotificationSettings();
}

Future<bool> showReminderNotification({
  required String reminderId,
  required String title,
  required String body,
}) async {
  await _ensureInitialized();
  final android = _notifications.resolvePlatformSpecificImplementation<
      AndroidFlutterLocalNotificationsPlugin>();
  if (await android?.areNotificationsEnabled() == false) return false;
  await _notifications.show(
    id: _notificationId(reminderId),
    title: title,
    body: body,
    notificationDetails: _notificationDetails(),
  );
  return true;
}

Future<void> scheduleReminderNotification({
  required String reminderId,
  required String title,
  required String body,
  required DateTime scheduledAt,
}) {
  return _serializeNotificationMutation(() async {
    await _ensureInitialized();
    if (!scheduledAt.isAfter(DateTime.now())) return;
    final android = _notifications.resolvePlatformSpecificImplementation<
        AndroidFlutterLocalNotificationsPlugin>();
    final exact = await android?.canScheduleExactNotifications() ?? false;
    await _notifications.zonedSchedule(
      id: _notificationId(reminderId),
      title: title,
      body: body,
      scheduledDate: tz.TZDateTime.from(scheduledAt.toLocal(), tz.local),
      androidScheduleMode: exact
          ? AndroidScheduleMode.exactAllowWhileIdle
          : AndroidScheduleMode.inexactAllowWhileIdle,
      notificationDetails: _notificationDetails(),
    );
  });
}

Future<void> cancelReminderNotification(String reminderId) {
  return _serializeNotificationMutation(() async {
    await _ensureInitialized();
    await _notifications.cancel(id: _notificationId(reminderId));
  });
}

Future<void> _serializeNotificationMutation(Future<void> Function() action) {
  final operation = _notificationQueue.then((_) => action());
  _notificationQueue = operation.then<void>(
    (_) {},
    onError: (Object _, StackTrace __) {},
  );
  return operation;
}

NotificationDetails _notificationDetails() {
  final german = PlatformDispatcher.instance.locale.languageCode == 'de';
  return NotificationDetails(
    android: AndroidNotificationDetails(
      'note_reminders',
      german ? 'Erinnerungen' : 'Reminders',
      icon: 'ic_notification',
      channelDescription: german
          ? 'Lokale Erinnerungen für Notizen'
          : 'Local reminders for notes',
      importance: Importance.high,
      priority: Priority.high,
    ),
    iOS: const DarwinNotificationDetails(),
  );
}

int _notificationId(String value) {
  var hash = 0;
  for (final unit in value.codeUnits) {
    hash = (hash * 31 + unit) & 0x7fffffff;
  }
  return hash;
}
