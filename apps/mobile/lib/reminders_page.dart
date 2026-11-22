import 'package:flutter/material.dart';

import 'store.dart';
import 'ui.dart';
import 'reminders.dart';

class RemindersPage extends StatefulWidget {
  final LedgerStore store;
  const RemindersPage(this.store, {super.key});
  @override
  State<RemindersPage> createState() => _RemindersPageState();
}

class _RemindersPageState extends State<RemindersPage> {
  late Json prefs = reminderSettings(widget.store);
  bool working = false;
  String clock(int minutes) =>
      '${(minutes ~/ 60).toString().padLeft(2, '0')}:${(minutes % 60).toString().padLeft(2, '0')}';
  Future<void> save() async {
    widget.store.state['reminders'] = prefs;
    await widget.store.persist(preferencesOnly: true);
    await AppReminders.instance.reconcile();
    if (mounted) setState(() {});
  }

  Future<void> time(String key) async {
    final value = key == 'record'
        ? prefs['hour'] * 60 + prefs['minute']
        : prefs[key];
    final chosen = await showTimePicker(
      context: context,
      initialTime: TimeOfDay(hour: value ~/ 60, minute: value % 60),
    );
    if (chosen == null) return;
    setState(() {
      if (key == 'record') {
        prefs['hour'] = chosen.hour;
        prefs['minute'] = chosen.minute;
      } else {
        prefs[key] = chosen.hour * 60 + chosen.minute;
      }
    });
    await save();
  }

  @override
  Widget build(BuildContext context) => Scaffold(
    appBar: AppBar(title: const Text('提醒与免打扰')),
    body: ListView(
      padding: const EdgeInsets.all(16),
      children: [
        FilledButton.icon(
          onPressed: working
              ? null
              : () async {
                  setState(() => working = true);
                  final allowed = await AppReminders.instance
                      .requestPermission();
                  await save();
                  if (context.mounted) {
                    setState(() => working = false);
                    message(context, allowed ? '通知权限已开启' : '请在系统设置中允许有数通知');
                  }
                },
          icon: const Icon(Icons.notifications_active_outlined),
          label: const Text('开启 / 检查系统通知权限'),
        ),
        if (AppReminders.instance.error != null)
          Text(
            AppReminders.instance.error!,
            style: TextStyle(color: Theme.of(context).colorScheme.error),
          ),
        SwitchListTile(
          title: const Text('预算预警'),
          subtitle: const Text('达到预算 80% 和 100% 时各提醒一次'),
          value: prefs['budget'],
          onChanged: (v) async {
            setState(() => prefs['budget'] = v);
            await save();
          },
        ),
        SwitchListTile(
          title: const Text('记账提醒'),
          subtitle: const Text('当天所有账本均没有流水时提醒'),
          value: prefs['record'],
          onChanged: (v) async {
            setState(() => prefs['record'] = v);
            await save();
          },
        ),
        ListTile(
          title: const Text('提醒时间'),
          trailing: Text(clock(prefs['hour'] * 60 + prefs['minute'])),
          onTap: () => time('record'),
        ),
        Wrap(
          spacing: 5,
          children: [
            for (var i = 1; i <= 7; i++)
              FilterChip(
                label: Text(['一', '二', '三', '四', '五', '六', '日'][i - 1]),
                selected: (prefs['weekdays'] as List).contains(i),
                onSelected: (v) async {
                  setState(() {
                    final days = List<int>.from(prefs['weekdays']);
                    v ? days.add(i) : days.remove(i);
                    prefs['weekdays'] = days..sort();
                  });
                  await save();
                },
              ),
          ],
        ),
        const Divider(height: 32),
        SwitchListTile(
          title: const Text('夜间静音'),
          subtitle: const Text('静音时段内的本地通知保留显示，不播放声音或振动'),
          value: prefs['quiet'],
          onChanged: (v) async {
            setState(() => prefs['quiet'] = v);
            await save();
          },
        ),
        ListTile(
          title: const Text('静音开始'),
          trailing: Text(clock(prefs['quietStart'])),
          onTap: () => time('quietStart'),
        ),
        ListTile(
          title: Text(
            prefs['quietEnd'] <= prefs['quietStart'] ? '次日结束' : '静音结束',
          ),
          trailing: Text(clock(prefs['quietEnd'])),
          onTap: () => time('quietEnd'),
        ),
        const Padding(
          padding: EdgeInsets.all(16),
          child: Text(
            '按设备当地时间提醒。每次打开 App 或记账后自动更新未来 60 次提醒；长期不打开 App 后需要再次打开以续排。安卓系统节电设置可能延迟提醒。',
            style: TextStyle(fontSize: 12),
          ),
        ),
      ],
    ),
  );
}
