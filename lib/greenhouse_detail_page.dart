// ignore_for_file: use_build_context_synchronously

// ignore: unused_import
import 'dart:async';
import 'package:flutter/material.dart';
import 'package:firebase_database/firebase_database.dart';
import 'package:fl_chart/fl_chart.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:greenhouse_monitor/notification_service.dart';
import 'package:url_launcher/url_launcher.dart';
// ignore: unused_import
import 'package:http/http.dart' as http;



class GreenhouseDetailPage extends StatefulWidget {
  final String greenhouseId;
  final String userId;

  const GreenhouseDetailPage({
    super.key,
    required this.greenhouseId,
    required this.userId,
  });

  @override
  State<GreenhouseDetailPage> createState() => _GreenhouseDetailPageState();
}

class _GreenhouseDetailPageState extends State<GreenhouseDetailPage> {
  StreamSubscription<DatabaseEvent>? _subscription; 
  Map<String, dynamic> latestValues = {};

  final database = FirebaseDatabase.instance.ref();
  List<FlSpot> _temperatureSpots = [];
  List<FlSpot> _humiditySpots = [];
  List<FlSpot> _co2Spots = [];
  List<FlSpot> _lightSpots = [];

  double? currentTemp, currentHum, currentCO2, currentLight;
  bool loading = true;
  String selectedRange = '7 днів';
  String greenhouseName = "";
  final rangeOptions = ['3 дні', '7 днів', '14 днів', '7 тижнів'];

  String? telegramChatId;
  bool telegramEnabled = false;

  @override
  void initState() {
    super.initState();
    _loadName();
    _loadHistory();
    listenToLiveUpdates();
  }

  Future<void> _loadName() async {
    final prefs = await SharedPreferences.getInstance();
    final stored = prefs.getString('greenhouse_name_${widget.greenhouseId}');
    if (!mounted) return;
    setState(() {
      greenhouseName = stored ?? 'Теплиця ${widget.greenhouseId}';
    });
  }

  Future<void> _loadTelegramData() async {
    final chatSnap = await database.child('users/${widget.userId}/telegram_chat_id').get();
    final notifSnap = await database
        .child('users/${widget.userId}/greenhouses/${widget.greenhouseId}/notification_thresholds/notifyTelegram')
        .get();

    if (!mounted) return;
    setState(() {
      telegramChatId = chatSnap.exists ? chatSnap.value.toString() : null;
      telegramEnabled = notifSnap.value == true;
    });
  }

  Future<void> _loadHistory() async {
    final snapshot = await database
        .child('users/${widget.userId}/greenhouses/${widget.greenhouseId}/greenhouse_data')
        .get();
    if (!snapshot.exists) {
      if (!mounted) return;
      setState(() => loading = false);
      return;
    }

    final allData = Map<String, dynamic>.from(snapshot.value as Map);
    final now = DateTime.now();
    final rangeDays = {
      '3 дні': 3,
      '7 днів': 7,
      '14 днів': 14,
      '7 тижнів': 49,
    }[selectedRange]!;
    final minDate = now.subtract(Duration(days: rangeDays));

    final tempPoints = <FlSpot>[];
    final humPoints = <FlSpot>[];
    final co2Points = <FlSpot>[];
    final lightPoints = <FlSpot>[];

    for (var dateKey in allData.keys) {
      final date = DateTime.tryParse(dateKey);
      if (date == null || date.isBefore(minDate)) continue;
      final timeMap = Map<String, dynamic>.from(allData[dateKey]);
      for (var timeKey in timeMap.keys) {
        final fullTime = DateTime.tryParse('$dateKey $timeKey');
        if (fullTime == null) continue;
        final data = Map<String, dynamic>.from(timeMap[timeKey]);
        final x = fullTime.millisecondsSinceEpoch.toDouble();
        tempPoints.add(FlSpot(x, (data['temperature'] ?? 0).toDouble()));
        humPoints.add(FlSpot(x, (data['humidity'] ?? 0).toDouble()));
        co2Points.add(FlSpot(x, (data['co2'] ?? 0).toDouble()));
        lightPoints.add(FlSpot(x, (data['light'] ?? 0).toDouble()));
      }
    }

    if (!mounted) return;
    setState(() {
      _temperatureSpots = tempPoints;
      _humiditySpots = humPoints;
      _co2Spots = co2Points;
      _lightSpots = lightPoints;
      currentTemp = tempPoints.isNotEmpty ? tempPoints.last.y : null;
      currentHum = humPoints.isNotEmpty ? humPoints.last.y : null;
      currentCO2 = co2Points.isNotEmpty ? co2Points.last.y : null;
      currentLight = lightPoints.isNotEmpty ? lightPoints.last.y : null;
      loading = false;
    });

    await NotificationService.checkAndNotify(
      userId: widget.userId,
      greenhouseId: widget.greenhouseId,
      greenhouseName: greenhouseName,
      temperature: currentTemp ?? 0,
      humidity: currentHum ?? 0,
      co2: currentCO2 ?? 0,
      light: currentLight ?? 0,
    );
  }

  Future<void> _openTelegramBot() async {
  final url = 'https://t.me/GreenhouseNotifierBot?start=${widget.userId}';
  final uri = Uri.parse(url);

  debugPrint('📨 Відкриваю Telegram Bot: $url');

  if (await canLaunchUrl(uri)) {
    final result = await launchUrl(uri, mode: LaunchMode.externalApplication);
    debugPrint('✅ Відкрито Telegram: $result');
    await Future.delayed(const Duration(seconds: 2));
    await _loadTelegramData();
  } else {
    debugPrint('❌ Не вдалося відкрити Telegram Bot URL');
  }
}

  Future<void> _showSettingsDialog() async {
    await _loadTelegramData();
    final prefs = await SharedPreferences.getInstance();
    final nameController = TextEditingController(text: greenhouseName);

    final tempMinCtrl = TextEditingController();
    final tempMaxCtrl = TextEditingController();
    final humMinCtrl = TextEditingController();
    final humMaxCtrl = TextEditingController();
    final co2MinCtrl = TextEditingController();
    final co2MaxCtrl = TextEditingController();
    final lightMinCtrl = TextEditingController();
    final lightMaxCtrl = TextEditingController();

    final thresholdsRef = database.child('users/${widget.userId}/greenhouses/${widget.greenhouseId}/notification_thresholds');
    final thresholdSnap = await thresholdsRef.get();
    final thresholdData = thresholdSnap.exists ? Map<String, dynamic>.from(thresholdSnap.value as Map) : {};

    tempMinCtrl.text = (thresholdData['temperatureMin'] ?? '').toString();
    tempMaxCtrl.text = (thresholdData['temperatureMax'] ?? '').toString();
    humMinCtrl.text = (thresholdData['humidityMin'] ?? '').toString();
    humMaxCtrl.text = (thresholdData['humidityMax'] ?? '').toString();
    co2MinCtrl.text = (thresholdData['co2Min'] ?? '').toString();
    co2MaxCtrl.text = (thresholdData['co2Max'] ?? '').toString();
    lightMinCtrl.text = (thresholdData['lightMin'] ?? '').toString();
    lightMaxCtrl.text = (thresholdData['lightMax'] ?? '').toString();

    showDialog(
      context: context,
      builder: (context) {
        return StatefulBuilder(
          builder: (context, setState) {
            return AlertDialog(
              title: const Text("Налаштування теплиці"),
              content: SingleChildScrollView(
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    TextField(controller: nameController, decoration: const InputDecoration(labelText: 'Назва теплиці')),
                    const SizedBox(height: 12),
                    if (telegramChatId != null) ...[
                      const Text("Прив'язаний Telegram:"),
                      const SizedBox(height: 4),
                      Text(telegramChatId!, style: const TextStyle(fontWeight: FontWeight.bold)),
                      SwitchListTile(
                        value: telegramEnabled,
                        title: const Text('Нотифікації в Telegram'),
                        onChanged: (val) async {
                          setState(() => telegramEnabled = val);
                          await thresholdsRef.child('notifyTelegram').set(val);
                        },
                      ),
                      ElevatedButton.icon(
                        onPressed: () async {
                          final chatId = telegramChatId;
                          await database.child('users/${widget.userId}/telegram_chat_id').remove();
                          await _loadTelegramData();
                          setState(() {});
                          if (chatId != null) {
                            await NotificationService.sendTelegramMessage(
                              chatId,
                              "🔌 Ваш Telegram було відвʼязано від теплиці '$greenhouseName'. Ви більше не отримуватимете сповіщення.",
                            );
                          }
                        },
                        icon: const Icon(Icons.logout),
                        label: const Text("Відвʼязати Telegram"),
                        style: ElevatedButton.styleFrom(backgroundColor: Colors.red),
                      ),
                    ] else ...[
                      ElevatedButton.icon(
                        onPressed: () async {
                          await _openTelegramBot();
                          setState(() {});
                        },
                        icon: const Icon(Icons.telegram),
                        label: const Text("Привʼязати Telegram"),
                      ),
                    ],
                    const SizedBox(height: 16),
                    const Text("Порогові значення"),
                    TextField(controller: tempMinCtrl, decoration: const InputDecoration(labelText: 'Мін. температура')),
                    TextField(controller: tempMaxCtrl, decoration: const InputDecoration(labelText: 'Макс. температура')),
                    TextField(controller: humMinCtrl, decoration: const InputDecoration(labelText: 'Мін. вологість')),
                    TextField(controller: humMaxCtrl, decoration: const InputDecoration(labelText: 'Макс. вологість')),
                    TextField(controller: co2MinCtrl, decoration: const InputDecoration(labelText: 'Мін. CO₂')),
                    TextField(controller: co2MaxCtrl, decoration: const InputDecoration(labelText: 'Макс. CO₂')),
                    TextField(controller: lightMinCtrl, decoration: const InputDecoration(labelText: 'Мін. освітлення')),
                    TextField(controller: lightMaxCtrl, decoration: const InputDecoration(labelText: 'Макс. освітлення')),
                  ],
                ),
              ),
              actions: [
                TextButton(onPressed: () => Navigator.pop(context), child: const Text('Скасувати')),
                TextButton(
                  onPressed: () async {
                    final newName = nameController.text.trim();
                    if (newName.isNotEmpty) {
                      await prefs.setString('greenhouse_name_${widget.greenhouseId}', newName);
                      if (mounted) setState(() => greenhouseName = newName);
                    }
                    await thresholdsRef.update({
                      'temperatureMin': double.tryParse(tempMinCtrl.text) ?? 0,
                      'temperatureMax': double.tryParse(tempMaxCtrl.text) ?? 100,
                      'humidityMin': double.tryParse(humMinCtrl.text) ?? 0,
                      'humidityMax': double.tryParse(humMaxCtrl.text) ?? 100,
                      'co2Min': double.tryParse(co2MinCtrl.text) ?? 0,
                      'co2Max': double.tryParse(co2MaxCtrl.text) ?? 2000,
                      'lightMin': double.tryParse(lightMinCtrl.text) ?? 0,
                      'lightMax': double.tryParse(lightMaxCtrl.text) ?? 10000,
                    });
                    Navigator.pop(context);
                  },
                  child: const Text('Зберегти'),
                ),
              ],
            );
          },
        );
      },
    );
  }

  Widget _buildCurrentValues() {
    return Padding(
      padding: const EdgeInsets.all(12),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          if (currentTemp != null) Text("🌡️ Температура: ${currentTemp!.toStringAsFixed(1)} °C"),
          if (currentHum != null) Text("💧 Вологість: ${currentHum!.toStringAsFixed(1)} %"),
          if (currentCO2 != null) Text("🫁 CO₂: ${currentCO2!.toStringAsFixed(0)} ppm"),
          if (currentLight != null) Text("🔆 Освітлення: ${currentLight!.toStringAsFixed(0)} лк"),
        ],
      ),
    );
  }

  Widget _buildChart(String label, List<FlSpot> spots) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 16.0, horizontal: 12),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(label, style: const TextStyle(fontWeight: FontWeight.bold)),
          SizedBox(
            height: 180,
            child: LineChart(
              LineChartData(
                lineBarsData: [
                  LineChartBarData(
                    spots: spots,
                    isCurved: true,
                    belowBarData: BarAreaData(show: false),
                    dotData: FlDotData(show: false),
                  ),
                ],
                titlesData: FlTitlesData(
                  bottomTitles: AxisTitles(sideTitles: SideTitles(showTitles: false)),
                  leftTitles: AxisTitles(sideTitles: SideTitles(showTitles: false)),
                  rightTitles: AxisTitles(sideTitles: SideTitles(showTitles: false)),
                  topTitles: AxisTitles(sideTitles: SideTitles(showTitles: false)),
                ),
                gridData: FlGridData(show: true),
              ),
            ),
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Text(greenhouseName),
        actions: [
          IconButton(icon: const Icon(Icons.settings), onPressed: _showSettingsDialog),
        ],
      ),
      body: loading
          ? const Center(child: CircularProgressIndicator())
          : ListView(
              children: [
                _buildCurrentValues(),
                Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 16.0, vertical: 8),
                  child: DropdownButton<String>(
                    value: selectedRange,
                    isExpanded: true,
                    items: rangeOptions.map((range) => DropdownMenuItem(value: range, child: Text(range))).toList(),
                    onChanged: (value) {
                      if (value != null) {
                        setState(() {
                          selectedRange = value;
                          loading = true;
                        });
                        _loadHistory();
                      }
                    },
                  ),
                ),
                _buildChart("Температура (°C)", _temperatureSpots),
                _buildChart("Вологість (%)", _humiditySpots),
                _buildChart("CO₂ (ppm)", _co2Spots),
                _buildChart("Освітлення (лк)", _lightSpots),
              ],
            ),
    );
  }


  void listenToLiveUpdates() {
  final dataRef = FirebaseDatabase.instance.ref(
    'users/${widget.userId}/greenhouses/${widget.greenhouseId}/greenhouse_data',
  );

  _subscription?.cancel();
  _subscription = dataRef.onChildAdded.listen((event) async {
    // event.snapshot.key = дата (yyyy-MM-dd), event.snapshot.value = Map часів
    final dateMap = Map<String, dynamic>.from(event.snapshot.value as Map);

    // вибрати лише найновіший час у цій даті
    final sortedTimes = dateMap.keys.toList()..sort();
    final lastTimeKey = sortedTimes.isNotEmpty ? sortedTimes.last : null;
    if (lastTimeKey == null) return;
    final value = Map<String, dynamic>.from(dateMap[lastTimeKey]);

    final DateTime timestamp = DateTime.parse('${event.snapshot.key} $lastTimeKey');
    final double seconds = timestamp.millisecondsSinceEpoch / 1000;

    setState(() {
      if (value['temperature'] != null) _temperatureSpots.add(FlSpot(seconds, (value['temperature'] as num).toDouble()));
      if (value['humidity'] != null) _humiditySpots.add(FlSpot(seconds, (value['humidity'] as num).toDouble()));
      if (value['co2'] != null) _co2Spots.add(FlSpot(seconds, (value['co2'] as num).toDouble()));
      if (value['light'] != null) _lightSpots.add(FlSpot(seconds, (value['light'] as num).toDouble()));

      latestValues = {
        'temperature': value['temperature'],
        'humidity': value['humidity'],
        'co2': value['co2'],
        'light': value['light'],
      };
      currentTemp = value['temperature'] != null ? (value['temperature'] as num).toDouble() : null;
      currentHum = value['humidity'] != null ? (value['humidity'] as num).toDouble() : null;
      currentCO2 = value['co2'] != null ? (value['co2'] as num).toDouble() : null;
      currentLight = value['light'] != null ? (value['light'] as num).toDouble() : null;
    });

    // ignore: unused_local_variable
    final name = await _getGreenhouseName();

    // надсилати сповіщення лише по свіжому запису
    //NotificationService.checkAndNotify(
    // userId: widget.userId,
    //  greenhouseId: widget.greenhouseId,
    //  greenhouseName: name,
    // temperature: value['temperature'],
    //  humidity: value['humidity'],
    //  co2: value['co2'],
    // light: value['light'],
    
  });
}


  @override
void dispose() {
  _subscription?.cancel();
  super.dispose();
}



  Future<String> _getGreenhouseName() async {
    final prefs = await SharedPreferences.getInstance();
    return prefs.getString('name_${widget.greenhouseId}') ?? 'Теплиця ${widget.greenhouseId}';
  }

}