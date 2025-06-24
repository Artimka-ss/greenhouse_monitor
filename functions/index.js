const functions = require("firebase-functions/v1");
const admin = require("firebase-admin");
const axios = require("axios");

admin.initializeApp();

const TELEGRAM_BOT_TOKEN = "7631390122:AAEii3zxNiM0UO-cfSo9m_uLpls3cmOCFdA"; // ← твій токен

exports.notifyOnLimitExceed = functions.database
  .ref("/users/{userId}/greenhouses/{greenhouseId}/greenhouse_data/{date}/{time}")
  .onCreate(async (snapshot, context) => {
    const data = snapshot.val();
    const { userId, greenhouseId } = context.params;

    // 1. Отримати порогові значення та налаштування
    const thresholdsSnap = await admin.database()
      .ref(`/users/${userId}/greenhouses/${greenhouseId}/notification_thresholds`)
      .once("value");
    const thresholds = thresholdsSnap.val();

    if (!thresholds) return null;

    // 2. Отримати Telegram chat_id
    const chatIdSnap = await admin.database()
      .ref(`/users/${userId}/telegram_chat_id`)
      .once("value");
    const chatId = chatIdSnap.val();

    // 3. Отримати FCM-токен користувача
    const fcmTokenSnap = await admin.database()
      .ref(`/users/${userId}/fcm_token`)
      .once("value");
    const fcmToken = fcmTokenSnap.val();

    // 4. Перевірка порогів
    const params = [
      {
        key: "temperature",
        min: thresholds.temperatureMin,
        max: thresholds.temperatureMax,
        label: "Температура",
        unit: "°C"
      },
      {
        key: "humidity",
        min: thresholds.humidityMin,
        max: thresholds.humidityMax,
        label: "Вологість",
        unit: "%"
      },
      {
        key: "co2",
        min: thresholds.co2Min,
        max: thresholds.co2Max,
        label: "CO₂",
        unit: "ppm"
      },
      {
        key: "light",
        min: thresholds.lightMin,
        max: thresholds.lightMax,
        label: "Освітлення",
        unit: "лк"
      }
    ];

    let sent = false;

    for (const param of params) {
      const value = data[param.key];
      if (value === undefined || value === null) continue;
      if ((param.min !== undefined && value < param.min) || (param.max !== undefined && value > param.max)) {
        const msg = `🚨 Теплиця ${greenhouseId}: ${param.label} вийшла за межі: ${value} ${param.unit}`;

        // Надіслати в Telegram
        if (thresholds.notifyTelegram && chatId) {
          await axios.get(`https://api.telegram.org/bot${TELEGRAM_BOT_TOKEN}/sendMessage`, {
            params: { chat_id: chatId, text: msg }
          });
        }

        // Надіслати пуш-повідомлення через FCM
        if (thresholds.notifyMobile && fcmToken) {
          const payload = {
            notification: {
              title: "Перевищено поріг теплиці",
              body: msg,
              sound: "default",
            },
            data: {
              greenhouseId: greenhouseId,
              param: param.key,
              value: value.toString(),
              type: "limit_exceed",
            }
          };
          await admin.messaging().sendToDevice(fcmToken, payload);
        }

        sent = true;
      }
    }

    return sent ? true : null;
  });
