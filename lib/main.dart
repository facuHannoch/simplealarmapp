import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:alarm/alarm.dart';
import 'package:alarm/model/alarm_settings.dart';
import 'package:alarm/model/notification_settings.dart';
import 'package:alarm/model/volume_settings.dart';
import 'package:alarm/utils/alarm_set.dart';
import 'package:flutter/material.dart';

const int _alarmId = 1001;
const String _alarmAudioAsset = 'assets/alarm.wav';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  await Alarm.init();
  runApp(const AlarmWithSignedMessageApp());
}

class AlarmWithSignedMessageApp extends StatelessWidget {
  const AlarmWithSignedMessageApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'Signed Alarm',
      theme: ThemeData(
        colorScheme: ColorScheme.fromSeed(seedColor: const Color(0xFF0D6E4C)),
        useMaterial3: true,
      ),
      home: const AlarmHomePage(),
    );
  }
}

class AlarmPayload {
  const AlarmPayload({required this.message});

  final String message;

  String encode() => jsonEncode(<String, String>{'message': message});

  static AlarmPayload? tryDecode(String? payload) {
    if (payload == null || payload.isEmpty) return null;
    try {
      final Object decoded = jsonDecode(payload);
      if (decoded is Map<String, dynamic>) {
        final Object? message = decoded['message'];
        if (message is String && message.isNotEmpty) {
          return AlarmPayload(message: message);
        }
      }
    } catch (_) {}
    return null;
  }
}

class AlarmHomePage extends StatefulWidget {
  const AlarmHomePage({super.key});

  @override
  State<AlarmHomePage> createState() => _AlarmHomePageState();
}

class _AlarmHomePageState extends State<AlarmHomePage> {
  final TextEditingController _messageController = TextEditingController();

  TimeOfDay? _alarmTime;
  DateTime? _scheduledAt;
  AlarmSettings? _activeAlarm;
  bool _isRinging = false;
  StreamSubscription<AlarmSet>? _ringSubscription;

  @override
  void initState() {
    super.initState();
    _ringSubscription = Alarm.ringing.listen(_handleRinging);
  }

  @override
  void dispose() {
    _ringSubscription?.cancel();
    _messageController.dispose();
    super.dispose();
  }

  Future<void> _pickTime() async {
    final TimeOfDay now = TimeOfDay.now();
    final TimeOfDay? picked = await showTimePicker(
      context: context,
      initialTime: _alarmTime ?? now,
    );
    if (picked == null) return;
    setState(() {
      _alarmTime = picked;
    });
  }

  DateTime _nextOccurrence(TimeOfDay time) {
    final DateTime now = DateTime.now();
    DateTime candidate = DateTime(
      now.year,
      now.month,
      now.day,
      time.hour,
      time.minute,
    );
    if (!candidate.isAfter(now)) {
      candidate = candidate.add(const Duration(days: 1));
    }
    return candidate;
  }

  Future<void> _scheduleAlarm() async {
    final TimeOfDay? alarmTime = _alarmTime;
    final String message = _messageController.text.trim();
    if (alarmTime == null) {
      _showSnackBar('Pick a time for the alarm.');
      return;
    }
    if (message.isEmpty) {
      _showSnackBar('Enter the custom dismissal message.');
      return;
    }

    final DateTime scheduled = _nextOccurrence(alarmTime);
    final AlarmPayload payload = AlarmPayload(message: message);

    final AlarmSettings settings = AlarmSettings(
      id: _alarmId,
      dateTime: scheduled,
      assetAudioPath: _alarmAudioAsset,
      loopAudio: true,
      vibrate: true,
      warningNotificationOnKill: Platform.isIOS,
      androidFullScreenIntent: true,
      allowAlarmOverlap: false,
      payload: payload.encode(),
      volumeSettings: VolumeSettings.fixed(
        volume: 1.0,
        volumeEnforced: true,
      ),
      notificationSettings: const NotificationSettings(
        title: 'Alarm ringing',
        body: 'Tap to open and dismiss.',
      ),
    );

    final bool success = await Alarm.set(alarmSettings: settings);
    if (!success) {
      _showSnackBar('Could not schedule the alarm.');
      return;
    }

    setState(() {
      _activeAlarm = settings;
      _scheduledAt = scheduled;
    });

    _showSnackBar('Alarm scheduled for ${_formatDateTime(scheduled)}.');
  }

  Future<void> _cancelAlarm() async {
    await Alarm.stop(_alarmId);
    setState(() {
      _activeAlarm = null;
      _scheduledAt = null;
      _isRinging = false;
    });
    _showSnackBar('Alarm cancelled.');
  }

  void _handleRinging(AlarmSet alarmSet) {
    if (!mounted || _isRinging || alarmSet.alarms.isEmpty) return;
    final AlarmSettings alarm = alarmSet.alarms.firstWhere(
      (AlarmSettings alarm) => alarm.id == _alarmId,
      orElse: () => alarmSet.alarms.first,
    );

    setState(() {
      _isRinging = true;
      _activeAlarm = alarm;
      _scheduledAt = alarm.dateTime;
    });

    Navigator.of(context).push(
      MaterialPageRoute<void>(
        builder: (BuildContext context) => AlarmRingScreen(
          alarmSettings: alarm,
          onDismissed: _handleDismissed,
        ),
        fullscreenDialog: true,
      ),
    );
  }

  void _handleDismissed() {
    setState(() {
      _isRinging = false;
      _activeAlarm = null;
      _scheduledAt = null;
    });
    _showSnackBar('Alarm dismissed.');
  }

  void _showSnackBar(String message) {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text(message)),
    );
  }

  String _formatDateTime(DateTime dateTime) {
    final String hour = dateTime.hour.toString().padLeft(2, '0');
    final String minute = dateTime.minute.toString().padLeft(2, '0');
    final String day = dateTime.day.toString().padLeft(2, '0');
    final String month = dateTime.month.toString().padLeft(2, '0');
    return '${dateTime.year}-$month-$day $hour:$minute';
  }

  @override
  Widget build(BuildContext context) {
    final String timeLabel = _alarmTime == null
        ? 'Pick alarm time'
        : 'Alarm time: ${_alarmTime!.format(context)}';
    final bool hasAlarm = _scheduledAt != null;
    final AlarmPayload? payload = AlarmPayload.tryDecode(_activeAlarm?.payload);
    final String? message = payload?.message;

    return Scaffold(
      appBar: AppBar(
        title: const Text('Signed Alarm'),
        backgroundColor: Theme.of(context).colorScheme.primaryContainer,
      ),
      body: ListView(
        padding: const EdgeInsets.all(20),
        children: <Widget>[
          Text(
            'Set an alarm and lock it with a custom message.',
            style: Theme.of(context).textTheme.titleMedium,
          ),
          const SizedBox(height: 20),
          ElevatedButton.icon(
            onPressed: _isRinging ? null : _pickTime,
            icon: const Icon(Icons.alarm),
            label: Text(timeLabel),
          ),
          const SizedBox(height: 16),
          TextField(
            controller: _messageController,
            decoration: const InputDecoration(
              labelText: 'Custom dismissal message',
              border: OutlineInputBorder(),
              hintText: 'e.g. delete-prod-2026-01-19',
            ),
            enabled: !_isRinging,
          ),
          const SizedBox(height: 12),
          Row(
            children: <Widget>[
              Expanded(
                child: FilledButton(
                  onPressed: _isRinging ? null : _scheduleAlarm,
                  child: const Text('Set Alarm'),
                ),
              ),
              const SizedBox(width: 12),
                Expanded(
                  child: OutlinedButton(
                    onPressed: hasAlarm && !_isRinging ? _cancelAlarm : null,
                    child: const Text('Cancel'),
                  ),
                ),
            ],
          ),
          const SizedBox(height: 24),
          if (hasAlarm)
            Card(
              child: ListTile(
                leading: const Icon(Icons.schedule),
                title: Text('Next alarm: ${_formatDateTime(_scheduledAt!)}'),
                subtitle: Text(
                  message == null ? 'Message saved.' : 'Message: $message',
                ),
              ),
            ),
          if (_isRinging)
            Padding(
              padding: const EdgeInsets.only(top: 16),
              child: Text(
                'Alarm is ringing — complete the dismissal message.',
                style: TextStyle(
                  color: Colors.red.shade700,
                  fontWeight: FontWeight.w600,
                ),
              ),
            ),
        ],
      ),
    );
  }
}

class AlarmRingScreen extends StatefulWidget {
  const AlarmRingScreen({
    super.key,
    required this.alarmSettings,
    required this.onDismissed,
  });

  final AlarmSettings alarmSettings;
  final VoidCallback onDismissed;

  @override
  State<AlarmRingScreen> createState() => _AlarmRingScreenState();
}

class _AlarmRingScreenState extends State<AlarmRingScreen> {
  final TextEditingController _dismissController = TextEditingController();

  AlarmPayload? get _payload =>
      AlarmPayload.tryDecode(widget.alarmSettings.payload);

  @override
  void dispose() {
    _dismissController.dispose();
    super.dispose();
  }

  Future<void> _stopAlarm() async {
    await Alarm.stop(widget.alarmSettings.id);
    if (!mounted) return;
    Navigator.of(context).pop();
    widget.onDismissed();
  }

  @override
  Widget build(BuildContext context) {
    final String expectedMessage = _payload?.message ?? '';
    final String typedMessage = _dismissController.text.trim();
    final bool hasExpected = expectedMessage.isNotEmpty;
    final bool matches =
        hasExpected ? typedMessage == expectedMessage : typedMessage.isNotEmpty;

    return WillPopScope(
      onWillPop: () async => false,
      child: Scaffold(
        appBar: AppBar(
          automaticallyImplyLeading: false,
          title: const Text('Alarm ringing'),
          backgroundColor: Theme.of(context).colorScheme.primaryContainer,
        ),
        body: Padding(
          padding: const EdgeInsets.all(20),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: <Widget>[
              Text(
                'Type the exact message to stop the alarm:',
                style: Theme.of(context).textTheme.titleMedium,
              ),
              const SizedBox(height: 16),
              Container(
                padding: const EdgeInsets.all(16),
                decoration: BoxDecoration(
                  borderRadius: BorderRadius.circular(12),
                  color: Theme.of(context).colorScheme.secondaryContainer,
                ),
                child: Text(
                  expectedMessage.isEmpty ? 'No message found.' : expectedMessage,
                  textAlign: TextAlign.center,
                  style: Theme.of(context).textTheme.titleLarge,
                ),
              ),
              const SizedBox(height: 16),
              TextField(
                controller: _dismissController,
                autofocus: true,
                decoration: const InputDecoration(
                  labelText: 'Dismissal message',
                  border: OutlineInputBorder(),
                ),
                onChanged: (_) => setState(() {}),
              ),
              const SizedBox(height: 12),
                Text(
                  matches
                      ? (hasExpected
                          ? 'Message matches.'
                          : 'Fallback enabled — any message will stop.')
                      : 'Message does not match.',
                  style: TextStyle(
                    color:
                        matches ? Colors.green.shade700 : Colors.red.shade700,
                  ),
                ),
              const Spacer(),
              FilledButton(
                onPressed: matches ? _stopAlarm : null,
                child: const Text('Stop Alarm'),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
