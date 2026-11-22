import 'belongings_domain.dart';

import 'dart:async';
import 'dart:convert';

import 'package:flutter/widgets.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:flutter_timezone/flutter_timezone.dart';
import 'package:timezone/data/latest.dart' as tzdata;
import 'package:timezone/timezone.dart' as tz;

import 'store.dart';

Json reminderSettings(LedgerStore s) => {
  'record': true,
  'budget': true,
  'hour': 20,
  'minute': 0,
  'weekdays': [1, 2, 3, 4, 5, 6, 7],
  'quiet': true,
  'quietStart': 22 * 60,
  'quietEnd': 8 * 60,
  ...?s.state['reminders'] as Map?,
};

bool isQuiet(Json settings, DateTime at) {
  if (settings['quiet'] != true) return false;
  final minute = at.hour * 60 + at.minute;
  final start = settings['quietStart'] as int,
      end = settings['quietEnd'] as int;
  return start == end ||
      (start < end
          ? minute >= start && minute < end
          : minute >= start || minute < end);
}

/// One-shot dates allow cancellation of today's reminder after recording.
/// Reconcile caps these at 54, reserving six item and three recurring slots.
List<tz.TZDateTime> reminderDates(
  Json settings,
  tz.TZDateTime now,
  bool recordedToday,
) {
  if (settings['record'] != true || (settings['weekdays'] as List).isEmpty) {
    return [];
  }
  final dates = <tz.TZDateTime>[];
  for (var offset = 0; dates.length < 60 && offset <= 420; offset++) {
    final d = tz.TZDateTime(
      now.location,
      now.year,
      now.month,
      now.day + offset,
      settings['hour'],
      settings['minute'],
    );
    if (d.isAfter(now) &&
        (offset != 0 || !recordedToday) &&
        (settings['weekdays'] as List).contains(d.weekday)) {
      dates.add(d);
    }
  }
  return dates;
}

class AppReminders with WidgetsBindingObserver {
  static final instance = AppReminders._();
  AppReminders._();
  final plugin = FlutterLocalNotificationsPlugin();
  LedgerStore? store;
  Timer? timer;
  bool ready = false, running = false, again = false;
  String signature = '';
  String queuedBusiness = '';
  String? error;
  String get businessKey {
    final s = store!;
    return '${s.state['dataRevision']}/${s.belongings?.revision}/${s.active['id']}/${today()}/${jsonEncode(reminderSettings(s))}';
  }

  Future<void> start(LedgerStore s) async {
    store?.removeListener(queue);
    store?.belongings?.removeListener(queue);
    store = s;
    try {
      await s.openBelongings();
      s.belongings?.addListener(queue);
    } catch (_) {
      /* Ledger reminders remain available if the independent database is unavailable. */
    }
    if (ready) {
      s.addListener(queue);
      signature = queuedBusiness = '';
      await reconcile();
      return;
    }
    try {
      tzdata.initializeTimeZones();
      tz.setLocalLocation(
        tz.getLocation((await FlutterTimezone.getLocalTimezone()).identifier),
      );
      await plugin.initialize(
        settings: const InitializationSettings(
          android: AndroidInitializationSettings('@drawable/ic_notification'),
          iOS: DarwinInitializationSettings(
            requestAlertPermission: false,
            requestBadgePermission: false,
            requestSoundPermission: false,
          ),
        ),
      );
      ready = true;
      s.addListener(queue);
      WidgetsBinding.instance.addObserver(this);
      await reconcile();
    } catch (_) {
      error = '提醒初始化失败，请在提醒设置中重试';
    }
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed) {
      signature = '';
      queuedBusiness = '';
      queue();
    }
  }

  void queue() {
    if (store == null || (businessKey == queuedBusiness && error == null)) {
      return;
    }
    queuedBusiness = businessKey;
    timer?.cancel();
    timer = Timer(const Duration(milliseconds: 350), () => reconcile());
  }

  Future<bool> requestPermission() async {
    final s = store;
    if (!ready && s != null) await start(s);
    if (!ready) return false;
    final android = plugin
        .resolvePlatformSpecificImplementation<
          AndroidFlutterLocalNotificationsPlugin
        >();
    final ios = plugin
        .resolvePlatformSpecificImplementation<
          IOSFlutterLocalNotificationsPlugin
        >();
    final allowed =
        await android?.requestNotificationsPermission() ??
        await ios?.requestPermissions(alert: true, badge: true, sound: true) ??
        false;
    signature = '';
    await reconcile();
    return allowed;
  }

  NotificationDetails details(String type, Json prefs, DateTime at) {
    final silent = isQuiet(prefs, at);
    return NotificationDetails(
      android: AndroidNotificationDetails(
        'youshu_${type}_${silent ? 'quiet' : 'sound'}',
        '${type == 'record'
            ? '记账提醒'
            : type == 'belongings'
            ? '物品到期'
            : type == 'recurring'
            ? '周期记账'
            : '预算预警'}${silent ? '（静音）' : ''}',
        importance: silent ? Importance.low : Importance.defaultImportance,
        priority: silent ? Priority.low : Priority.defaultPriority,
        playSound: !silent,
        enableVibration: !silent,
      ),
      iOS: DarwinNotificationDetails(
        presentSound: !silent,
        presentAlert: true,
        presentBanner: true,
        presentList: true,
        interruptionLevel: silent
            ? InterruptionLevel.passive
            : InterruptionLevel.active,
      ),
    );
  }

  Future<void> reconcile() async {
    if (!ready || store == null) return;
    if (running) {
      again = true;
      return;
    }
    running = true;
    final s = store!;
    queuedBusiness = businessKey;
    try {
      tz.setLocalLocation(
        tz.getLocation((await FlutterTimezone.getLocalTimezone()).identifier),
      );
      final prefs = reminderSettings(s), now = tz.TZDateTime.now(tz.local);
      final recorded = s.ledgers.any(
        (l) => s.records(l).any((e) => e['data']['date'] == dateKey(now)),
      );
      final recurringDays = recurringReminderDays(s.ledgers, dateKey(now));
      final itemDays = belongingReminderDays(
        s.belongings?.items ?? [],
        dateKey(now),
      );
      final nextSignature = jsonEncode([
        itemDays,
        recurringDays,
        prefs,
        dateKey(now),
        tz.local.name,
        recorded,
      ]);
      if (nextSignature != signature) {
        for (var i = 0; i < 60; i++) {
          await plugin.cancel(id: 1000 + i);
        }
        final dates = reminderDates(prefs, now, recorded).take(54).toList();
        for (var i = 0; i < dates.length; i++) {
          await plugin.zonedSchedule(
            id: 1000 + i,
            title: '今天还没有记账',
            body: '花一分钟，记下今天的收支吧。',
            scheduledDate: dates[i],
            notificationDetails: details('record', prefs, dates[i]),
            androidScheduleMode: AndroidScheduleMode.inexactAllowWhileIdle,
          );
        }
        for (var i = 0; i < 3; i++) {
          await plugin.cancel(id: 1100 + i);
        }
        for (var i = 0; i < recurringDays.length; i++) {
          final item = recurringDays[i],
              day = calendarDate(recurringDays[i]['day']);
          final at = tz.TZDateTime(
            tz.local,
            day.year,
            day.month,
            day.day,
            prefs['hour'],
            prefs['minute'],
          );
          if (!at.isAfter(now)) continue;
          await plugin.zonedSchedule(
            id: 1100 + i,
            title: '周期账单待确认',
            body: '${item['names']}，打开有数核对实际收付后记账。',
            scheduledDate: at,
            notificationDetails: details('recurring', prefs, at),
            androidScheduleMode: AndroidScheduleMode.inexactAllowWhileIdle,
          );
        }
        for (var i = 0; i < 6; i++) {
          await plugin.cancel(id: 1200 + i);
        }
        for (var i = 0; i < itemDays.length; i++) {
          final item = itemDays[i], day = calendarDate(itemDays[i]['day']);
          final at = tz.TZDateTime(
            tz.local,
            day.year,
            day.month,
            day.day,
            prefs['hour'],
            prefs['minute'],
          );
          if (!at.isAfter(now)) continue;
          await plugin.zonedSchedule(
            id: 1200 + i,
            title: '物品到期与保修提醒',
            body:
                '${item['names']}${item['count'] > 3 ? ' 等 ${item['count']} 项' : ''}',
            scheduledDate: at,
            notificationDetails: details('belongings', prefs, at),
            androidScheduleMode: AndroidScheduleMode.inexactAllowWhileIdle,
          );
        }
        signature = nextSignature;
      }
      if (prefs['budget'] != true) {
        await plugin.cancel(id: 900);
      } else {
        final android = plugin
            .resolvePlatformSpecificImplementation<
              AndroidFlutterLocalNotificationsPlugin
            >();
        final ios = plugin
            .resolvePlatformSpecificImplementation<
              IOSFlutterLocalNotificationsPlugin
            >();
        final allowed =
            await android?.areNotificationsEnabled() ??
            (await ios?.checkPermissions())?.isEnabled ??
            false;
        if (!allowed) return;
        final limit = s.budget(today(), '全部'), spent = s.budgetSpent(today());
        final threshold = limit > 0
            ? (spent >= limit
                  ? 100
                  : spent >= limit * .8
                  ? 80
                  : 0)
            : 0;
        final key = '${s.active['id']}/${s.period(today()).id}/$threshold';
        final seen = List<String>.from(s.state['budgetAlerts'] ?? []);
        if (threshold > 0 && !seen.contains(key)) {
          await plugin.show(
            id: 900,
            title: threshold == 100 ? '预算已达上限' : '预算即将用完',
            body:
                '${s.active['name']}：已用 ${s.display(spent)}，预算 ${s.display(limit)}。',
            notificationDetails: details('budget', prefs, now),
          );
          s.state['budgetAlerts'] = [
            ...seen.skip(seen.length > 99 ? seen.length - 99 : 0),
            key,
          ];
          await s.persist(preferencesOnly: true);
        }
      }
      error = null;
    } catch (_) {
      error = '系统提醒未成功更新，请检查通知权限后重试';
    } finally {
      running = false;
      if (again) {
        again = false;
        queuedBusiness = '';
        queue();
      }
    }
  }
}
