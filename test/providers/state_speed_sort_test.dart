import 'package:bett_box/enum/enum.dart';
import 'package:bett_box/models/models.dart';
import 'package:bett_box/providers/state.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('sortProxies 按网速排序', () {
    test('速度快的在前,未测与失败沉底,测试中置顶', () {
      final proxies = [
        Proxy(name: 'untested', type: 'Vless'),
        Proxy(name: 'failed', type: 'Vless'),
        Proxy(name: 'testing', type: 'Vless'),
        Proxy(name: 'slow', type: 'Vless'),
        Proxy(name: 'fast', type: 'Vless'),
      ];
      double? speedOf(String name) => switch (name) {
        'untested' => null,
        'failed' => -1.0,
        'testing' => 0.0,
        'slow' => 1024.0,
        'fast' => 10485760.0,
        _ => null,
      };

      final sorted = sortProxies(
        proxies,
        ProxiesSortType.speed,
        speedOf: speedOf,
      );

      // ignore: avoid_print
      print(sorted.map((e) => e.name).toList());
      final names = sorted.map((e) => e.name).toList();
      expect(names.first, 'testing');
      expect(names[1], 'fast');
      expect(names[2], 'slow');
      expect(names.last, anyOf('untested', 'failed'));
    });
  });
}
