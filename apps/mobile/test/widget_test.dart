import 'package:flutter_test/flutter_test.dart';
import 'package:youshu/store.dart';

void main() {
  test('金额使用整数分，不发生浮点舍入', () {
    expect(parseMoney('0.01'), 1);
    expect(parseMoney('12.3'), 1230);
    expect(parseMoney('999.99'), 99999);
    for (final value in ['0', '-1', '1.234', '1..2', 'NaN', '']) {
      expect(() => parseMoney(value), throwsFormatException);
    }
    expect(parseMoney('0', zero: true), 0);
  });
  test('收支预算不计入转账，并按月隔离', () {
    final s = LedgerStore();
    final l = freshLedger('测试');
    s.state['ledgers'] = [l];
    s.state['active'] = l['id'];
    l['entries'] = [
      for (final t in ['expense', 'income', 'transfer'])
        {
          'id': t,
          'kind': 'entry',
          'data': {
            'date': '2026-11-05',
            'type': t,
            'category': '餐饮',
            'amount': 100,
          },
          'deleted': false,
        },
      {
        'kind': 'entry',
        'data': {'date': '2026-10-05', 'type': 'expense', 'amount': 900},
        'deleted': false,
      },
    ];
    expect(s.total('2026-11', 'expense'), 100);
    expect(s.total('2026-11', 'income'), 100);
    expect(s.total('2026-10', 'expense'), 900);
  });
  test('恢复生成新的本地账本，清空待同步与共享状态', () {
    final l = freshLedger('家庭')
      ..['shared'] = true
      ..['pending'] = [
        {'secret': 'not replayed'},
      ];
    l['entries'] = [
      {
        'id': 'one',
        'kind': 'entry',
        'revision': 5,
        'deleted': false,
        'data': {
          'date': '2026-11-05',
          'type': 'expense',
          'amount': 1234,
          'category': '餐饮',
          'account': '微信',
        },
      },
    ];
    final restored = validateBackup({
      'schema': 1,
      'ledgers': [l],
    }).single;
    expect(restored['id'], isNot(l['id']));
    expect(restored['shared'], false);
    expect(restored['pending'], isEmpty);
    expect(restored['entries'][0]['id'], isNot('one'));
    expect(restored['entries'][0]['data']['amount'], 1234);
    l['entries'][0]['data']['amount'] = -1;
    expect(
      () => validateBackup({
        'schema': 1,
        'ledgers': [l],
      }),
      throwsFormatException,
    );
  });
}
