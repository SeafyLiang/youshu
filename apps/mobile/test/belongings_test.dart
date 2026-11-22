import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:crypto/crypto.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';
import 'package:youshu/belongings_store.dart';

Belonging object({String id = 'bike', String? purchase, int price = 599900}) =>
    Belonging({
      'id': id,
      'name': '九号电动车',
      'purchase': purchase ?? '2025-11-21',
      'price': price,
      'category': '出行',
      'icon': 'motor_scooter',
      'state': '在用',
      'currency': 'CNY',
      'remind': 7,
    });
BelongingCost cost({
  String id = 'repair',
  String itemId = 'bike',
  String date = '2026-05-01',
  int amount = 56000,
}) => BelongingCost({
  'id': id,
  'itemId': itemId,
  'amount': amount,
  'date': date,
  'title': '更换轮胎',
  'kind': '维修',
});
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  sqfliteFfiInit();
  databaseFactory = databaseFactoryFfi;
  late Directory dir;
  late BelongingsStore s;
  setUp(() async {
    dir = await Directory.systemTemp.createTemp('youshu-items-test-');
    s = BelongingsStore('${dir.path}/items.sqlite');
    await s.open();
  });
  tearDown(() async {
    if (!s.closed) await s.close();
    await dir.delete(recursive: true);
  });
  test('日均含购买日，养护增加投入，退役冻结且回收不为负', () {
    final i = object();
    expect(i.days('2026-11-20'), 365);
    expect(dailyCost(i, [cost()], now: '2026-11-20'), closeTo(1796.9863, .001));
    expect(
      dailyCost(i, [
        cost(),
        cost(id: 'second', amount: 26000),
      ], now: '2026-11-20'),
      closeTo(1868.219178, .001),
    );
    final sold = Belonging({
      ...i.data,
      'state': '已售出',
      'end': '2026-11-20',
      'recovery': 300000,
    });
    expect(
      dailyCost(sold, [
        cost(),
        cost(id: 'second', amount: 26000),
      ], now: '2028-01-01'),
      closeTo(1046.30136986, .001),
    );
    expect(dailyCost(Belonging({...sold.data, 'recovery': 9999999}), []), 0);
    expect(object(purchase: bDay()).days(), 1);
  });
  test('曲线按真实维修日期计入，售出只在结束日扣除回收', () {
    final i = Belonging({
      ...object(purchase: '2026-11-01').data,
      'state': '已售出',
      'end': '2026-11-04',
      'recovery': 10000,
    });
    final values = belongingCurve(i, [cost(date: '2026-11-03', amount: 30000)]);
    expect(values.map((v) => v.$2), [599900, 299950, 629900 / 3, 619900 / 4]);
  });
  test('金额、非法日期及费用区间验证', () {
    for (final v in [
      '-1',
      '1.001',
      'NaN',
      '1e5',
      '',
      '184467440737095517',
      '999999999999999999999999999999999999999',
    ]) {
      expect(() => bCents(v), throwsFormatException);
    }
    expect(bCents('0'), 0);
    expect(bCents('12.3'), 1230);
    expect(() => bDate('2026-02-30'), throwsFormatException);
    expect(
      () => cost(date: '2025-01-01').validate(object()),
      throwsFormatException,
    );
    expect(
      () => cost(date: '2200-01-01').validate(object()),
      throwsFormatException,
    );
    expect(
      () => Belonging({...object().data, 'state': '已退役'}).validate(),
      throwsFormatException,
    );
  });
  test('独立SQLite持久化、编辑不级联丢失费用、陈旧写入拒绝', () async {
    await s.saveItem(object());
    await s.saveCost(cost());
    final original = s.item('bike');
    await s.saveItem(Belonging({...original.data, 'name': '新的名字'}));
    expect(s.costsFor('bike').length, 1);
    await expectLater(s.saveItem(original), throwsFormatException);
    await expectLater(
      s.saveItem(Belonging({...s.item('bike').data, 'purchase': '2026-06-01'})),
      throwsFormatException,
    );
    final path = s.path;
    await s.close();
    s = BelongingsStore(path);
    await s.open();
    expect(s.item('bike').name, '新的名字');
    expect(s.costsFor('bike').single.amount, 56000);
  });
  test('并发修改同一费用仅一笔成功，删除费用重算', () async {
    await s.saveItem(object());
    await s.saveCost(cost());
    final c = s.costs.single;
    final results = await Future.wait([
      for (final amount in [26000, 30000])
        s
            .saveCost(BelongingCost({...c.data, 'amount': amount}))
            .then((_) => true)
            .catchError((Object _) => false),
    ]);
    expect(results.where((v) => v).length, 1);
    expect(s.costs.length, 1);
    await s.deleteCost(s.costs.single);
    expect(s.costs, isEmpty);
    expect(investedCost(s.items.single, s.costs), 599900);
  });
  test('图片、维修备份校验恢复副本，原数据和提醒不受影响', () async {
    final image = await s.addMedia(
      Uint8List.fromList([137, 80, 78, 71, 1, 2, 3]),
    );
    await s.saveItem(
      Belonging({
        ...object().data,
        'cover': image,
        'photos': [image],
        'expiry': '2027-11-01',
      }),
    );
    await s.saveCost(BelongingCost({...cost().data, 'receipt': image}));
    final bytes = await s.exportBackup(),
        backup = BelongingsStore.inspectBackup(bytes);
    expect(backup.media.length, 1);
    await s.restoreCopies(backup);
    expect(s.items.length, 2);
    expect(s.costs.length, 2);
    final copy = s.items.singleWhere((i) => i.id != 'bike');
    expect(copy.remind, -1);
    expect(s.item('bike').remind, 7);
    expect(s.costsFor(copy.id).single.receipt, image);
    expect(await s.mediaFile(image).readAsBytes(), backup.media[image]);
    await s.deleteItem(copy);
    expect(s.items.length, 1);
    expect(s.costs.length, 1);
    expect(await s.mediaFile(image).exists(), true);
  });
  test('0.8.1 原图、透明封面、裁剪参数和购买链接备份恢复', () async {
    final cover = await s.addMedia(Uint8List.fromList([137, 80, 78, 71, 4]));
    final source = await s.addMedia(Uint8List.fromList([137, 80, 78, 71, 5]));
    final edit = {
      'rect': [.1, .2, .6, .7],
      'subject': true,
    };
    const url = 'https://item.jd.com/123.html?orderId=example';
    await s.saveItem(
      Belonging({
        ...object().data,
        'cover': cover,
        'coverSource': source,
        'coverEdit': edit,
        'purchaseUrl': url,
      }),
    );
    final backup = BelongingsStore.inspectBackup(await s.exportBackup());
    expect(backup.media.keys.toSet(), {cover, source});
    await s.restoreCopies(backup);
    final copy = s.items.singleWhere((i) => i.id != 'bike');
    expect(copy.coverSource, source);
    expect(copy.coverEdit, edit);
    expect(copy.purchaseUrl, url);
    final path = s.path;
    await s.close();
    s = BelongingsStore(path);
    await s.open();
    expect(s.item(copy.id).coverEdit, edit);
    expect(await s.mediaFile(source).exists(), true);
  });
  test('损坏摘要、图片缺失、非法相对路径均在写库前拒绝', () async {
    await s.saveItem(object());
    final original = await s.exportBackup();
    final root = jsonDecode(utf8.decode(original)) as Map<String, dynamic>;
    root['sha256'] = 'tampered';
    expect(
      () => BelongingsStore.inspectBackup(
        Uint8List.fromList(utf8.encode(jsonEncode(root))),
      ),
      throwsFormatException,
    );
    final badId = '${'a' * 64}.png';
    root['data']['items'][0]['cover'] = badId;
    root['sha256'] = sha256
        .convert(utf8.encode(jsonEncode(root['data'])))
        .toString();
    expect(
      () => BelongingsStore.inspectBackup(
        Uint8List.fromList(utf8.encode(jsonEncode(root))),
      ),
      throwsFormatException,
    );
    expect(() => s.mediaFile('../secret'), throwsFormatException);
    expect(s.items.length, 1);
  });
  test('恢复事务中途故障整组回滚', () async {
    await s.saveItem(object());
    await s.saveCost(cost());
    final backup = BelongingsStore.inspectBackup(await s.exportBackup());
    final db = await openDatabase(s.path);
    await db.execute(
      "CREATE TRIGGER block_import BEFORE INSERT ON costs BEGIN SELECT RAISE(ABORT, 'test failure'); END",
    );
    await expectLater(
      s.restoreCopies(backup),
      throwsA(isA<DatabaseException>()),
    );
    expect(s.items.length, 1);
    expect((await db.query('items')).length, 1);
    expect((await db.query('costs')).length, 1);
  });
  test('提醒合并同日、最多六日、退役及副本关闭排除', () {
    final items = [
      Belonging({
        ...object().data,
        'expiry': '2026-11-27',
        'warranty': '2026-11-27',
      }),
      Belonging({
        ...object(id: 'retired').data,
        'state': '已退役',
        'end': '2026-11-01',
        'expiry': '2026-11-27',
      }),
      Belonging({
        ...object(id: 'copy').data,
        'remind': -1,
        'expiry': '2026-11-27',
      }),
    ];
    final days = belongingReminderDays(items, '2026-11-20');
    expect(days.length, 2);
    expect(days.first['count'], 2);
    expect(days.first['day'], '2026-11-20');
    expect(belongingReminderDays(items, '2026-12-01'), isEmpty);
  });
}
