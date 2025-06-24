// ignore_for_file: avoid_print, unused_import

import 'dart:convert';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:flutter/material.dart';
import 'package:firebase_database/firebase_database.dart';
import 'package:http/http.dart' as http;

class NotificationService {
  static final FlutterLocalNotificationsPlugin flutterLocalNotificationsPlugin =
      FlutterLocalNotificationsPlugin();

  static const String _botToken = '7631390122:AAEii3zxNiM0UO-cfSo9m_uLpls3cmOCFdA';

  static Future<void> initialize() async {
    if (kIsWeb) return;

    const AndroidInitializationSettings initializationSettingsAndroid =
        AndroidInitializationSettings('@mipmap/ic_launcher');

    const DarwinInitializationSettings initializationSettingsIOS =
        DarwinInitializationSettings();

    const InitializationSettings initializationSettings = InitializationSettings(
      android: initializationSettingsAndroid,
      iOS: initializationSettingsIOS,
    );

    await flutterLocalNotificationsPlugin.initialize(initializationSettings);
  }

  static Future<void> showNotification({
    required String title,
    required String body,
  }) async {
    if (kIsWeb) return;

    const AndroidNotificationDetails androidPlatformChannelSpecifics =
        AndroidNotificationDetails(
      'greenhouse_channel_id',
      'Greenhouse Notifications',
      importance: Importance.max,
      priority: Priority.high,
    );

    const DarwinNotificationDetails iOSPlatformChannelSpecifics =
        DarwinNotificationDetails();

    const NotificationDetails platformChannelSpecifics = NotificationDetails(
      android: androidPlatformChannelSpecifics,
      iOS: iOSPlatformChannelSpecifics,
    );

    await flutterLocalNotificationsPlugin.show(
      0,
      title,
      body,
      platformChannelSpecifics,
    );
  }

  static Future<void> checkAndNotify({
    required String userId,
    required String greenhouseId,
    required String greenhouseName,
    required double? temperature,
    required double? humidity,
    required double? co2,
    required double? light,
  }) async {
    print('🔔 [checkAndNotify] Викликано перевірку...');
    await checkThresholdsAndNotify(
      userId: userId,
      greenhouseId: greenhouseId,
      greenhouseName: greenhouseName,
      temperature: temperature ?? 0,
      humidity: humidity ?? 0,
      co2: co2 ?? 0,
      light: light ?? 0,
    );
  }

  static Future<void> checkThresholdsAndNotify({
    required String userId,
    required String greenhouseId,
    required String greenhouseName,
    required double temperature,
    required double humidity,
    required double co2,
    required double light,
  }) async {
    print('📡 Починаємо перевірку порогів для $greenhouseName');

    final thresholdRef = FirebaseDatabase.instance.ref(
      'users/$userId/greenhouses/$greenhouseId/notification_thresholds',
    );

    final snapshot = await thresholdRef.get();

    if (!snapshot.exists) {
      print('❗ Дані порогів не знайдено у Firebase!');
      return;
    }

    final data = Map<String, dynamic>.from(snapshot.value as Map);
    print('🧾 Отримано дані порогів: $data');

    final bool notifyMobile = data['notifyMobile'] ?? false;
    final bool notifyTelegram = data['notifyTelegram'] ?? false;

    // Оновлено: чат айді з users/{userId}/telegram_chat_id
    final telegramIdSnapshot = await FirebaseDatabase.instance
        .ref('users/$userId/telegram_chat_id')
        .get();

    final String? telegramId = telegramIdSnapshot.exists
        ? telegramIdSnapshot.value.toString()
        : null;

    print('📱 Mobile: $notifyMobile | 📨 Telegram: $notifyTelegram | ChatID: $telegramId');

    final thresholds = {
      'temperature': (
        data['temperatureMin'] ?? double.negativeInfinity,
        data['temperatureMax'] ?? double.infinity,
      ),
      'humidity': (
        data['humidityMin'] ?? double.negativeInfinity,
        data['humidityMax'] ?? double.infinity,
      ),
      'co2': (
        data['co2Min'] ?? double.negativeInfinity,
        data['co2Max'] ?? double.infinity,
      ),
      'light': (
        data['lightMin'] ?? double.negativeInfinity,
        data['lightMax'] ?? double.infinity,
      ),
    };

    final currentValues = {
      'temperature': temperature,
      'humidity': humidity,
      'co2': co2,
      'light': light,
    };

    for (final entry in currentValues.entries) {
      final key = entry.key;
      final value = entry.value;
      final (min, max) = thresholds[key]!;

      print('🔍 Перевірка $key: $value (порог $min – $max)');

      if (value < min || value > max) {
        final paramName = {
          'temperature': 'Температура',
          'humidity': 'Вологість',
          'co2': 'CO₂',
          'light': 'Освітлення',
        }[key];

        final unit = {
          'temperature': '°C',
          'humidity': '%',
          'co2': 'ppm',
          'light': 'лк',
        }[key];

        final message =
            '🚨 $greenhouseName: $paramName вийшла за межі: ${value.toStringAsFixed(1)} $unit';

        print('🚨 Порог перевищено: $message');

        if (notifyMobile) {
          print('📲 Надсилаємо локальне повідомлення...');
          await showNotification(
            title: 'Увага: перевищення порогу',
            body: message,
          );
        }

        if (notifyTelegram && telegramId != null) {
          print('📨 Надсилаємо повідомлення в Telegram...');
          await sendTelegramMessage(telegramId, message);
        }
      }
    }
  }

  static Future<void> sendTelegramMessage(String chatId, String message) async {
    final url =
        'https://api.telegram.org/bot$_botToken/sendMessage?chat_id=$chatId&text=${Uri.encodeComponent(message)}';

    print('📤 Відправка в Telegram: $url');

    try {
      final res = await http.get(Uri.parse(url));
      print('📬 Відповідь Telegram: ${res.statusCode}, ${res.body}');
    } catch (e) {
      print('❌ Помилка надсилання Telegram: $e');
    }
  }
}
