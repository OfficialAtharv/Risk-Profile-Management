import 'dart:async';
import 'package:flutter_background_service/flutter_background_service.dart';
import 'package:flutter_background_service_android/flutter_background_service_android.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';

final FlutterLocalNotificationsPlugin flutterLocalNotificationsPlugin =
FlutterLocalNotificationsPlugin();

Future<void> initNotification() async {
  const AndroidInitializationSettings initializationSettingsAndroid =
  AndroidInitializationSettings('@mipmap/ic_launcher');

  const InitializationSettings initializationSettings =
  InitializationSettings(android: initializationSettingsAndroid);

  await flutterLocalNotificationsPlugin.initialize(initializationSettings);

  const AndroidNotificationChannel channel = AndroidNotificationChannel(
    'speed_monitor_channel',
    'Speed Monitor Service',
    description: 'Background tracking for speed monitoring',
    importance: Importance.low,
  );

  await flutterLocalNotificationsPlugin
      .resolvePlatformSpecificImplementation<
      AndroidFlutterLocalNotificationsPlugin>()
      ?.createNotificationChannel(channel);
}
Future<void> initializeService() async {
  await initNotification();
  final service = FlutterBackgroundService();

  await service.configure(
    androidConfiguration: AndroidConfiguration(
      onStart: onStart,
      isForegroundMode: true,
      autoStart: true,
      notificationChannelId: 'speed_monitor_channel',
      initialNotificationTitle: 'JEEVAN Running',
      initialNotificationContent: 'Tracking speed in background',
    ),
    iosConfiguration: IosConfiguration(
      onForeground: onStart,
      onBackground: (service) async => true,
    ),
  );

  service.startService();
}

@pragma('vm:entry-point')
void onStart(ServiceInstance service) async {
  final FlutterLocalNotificationsPlugin flutterLocalNotificationsPlugin =
  FlutterLocalNotificationsPlugin();

  // ✅ Create notification channel (MANDATORY for Android)
  const AndroidNotificationChannel channel = AndroidNotificationChannel(
    'speed_monitor_channel',
    'Speed Monitor Service',
    description: 'Background tracking for speed monitoring',
    importance: Importance.low,
  );

  await flutterLocalNotificationsPlugin
      .resolvePlatformSpecificImplementation<
      AndroidFlutterLocalNotificationsPlugin>()
      ?.createNotificationChannel(channel);

  // ✅ Set foreground notification
  if (service is AndroidServiceInstance) {
    service.setAsForegroundService();

    service.setForegroundNotificationInfo(
      title: "JEEVAN Running",
      content: "Tracking speed in background",
    );
  }

  // ✅ Background loop
  Timer.periodic(const Duration(seconds: 5), (timer) {
    print("🔥 Background Service Running...");
  });
}