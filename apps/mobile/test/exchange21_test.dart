import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:youshu/store.dart';

class Offline extends HttpOverrides {
  @override
  HttpClient createHttpClient(SecurityContext? context) =>
      throw const SocketException('offline');
}

void main() {
  test('内置汇率覆盖全部币种并保留报价日，离线失败保留缓存', () async {
    final store = LedgerStore();
    for (final from in currencies.keys) {
      for (final to in currencies.keys) {
        final quote = await store.exchange(from, to, today());
        expect(double.parse(quote['rate']), greaterThan(0));
        expect(quote['date'], '2026-11-19');
        if (from == to) expect(double.parse(quote['rate']), 1);
      }
    }
    store.state['referenceRates'] = {
      'date': '2026-11-19',
      'source': '缓存',
      'rates': {'USD': 1, 'CNY': 7},
    };
    await HttpOverrides.runWithHttpOverrides(() async {
      await expectLater(
        store.updateRates(force: true),
        throwsA(isA<SocketException>()),
      );
    }, Offline());
    expect(
      (await store.exchange('USD', 'CNY', today()))['rate'],
      '7.000000000000',
    );
    expect(store.updatingRates, false);
    store.dispose();
  });
  test('成功更新日与关闭开关阻止自动请求，手动更新仍尝试联网', () async {
    final store = LedgerStore();
    await HttpOverrides.runWithHttpOverrides(() async {
      store.state['ratesCheckedDay'] = today();
      await store.updateRates();
      store.state['ratesCheckedDay'] = '';
      store.state['autoRates'] = false;
      await store.updateRates();
      await expectLater(
        store.updateRates(force: true),
        throwsA(isA<SocketException>()),
      );
    }, Offline());
    store.dispose();
  });
}
