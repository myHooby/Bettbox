import 'dart:convert';

import 'package:bett_box/common/common.dart';
import 'package:bett_box/enum/enum.dart';
import 'package:bett_box/models/config.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('ProxiesStyle 自定义样式标记与序列化', () {
    test('默认情况下 hasCustomizedStyle 为 false', () {
      const style = ProxiesStyle();

      expect(style.type, ProxiesType.tab);
      expect(style.iconStyle, ProxiesIconStyle.none);
      expect(style.hasCustomizedStyle, isFalse);
    });

    test('序列化后能够正确恢复 hasCustomizedStyle 状态', () {
      const style = ProxiesStyle(
        type: ProxiesType.list,
        iconStyle: ProxiesIconStyle.icon,
        hasCustomizedStyle: true,
      );

      final restored = ProxiesStyle.fromJson(
        jsonDecode(jsonEncode(style.toJson())) as Map<String, dynamic>,
      );

      expect(restored.type, ProxiesType.list);
      expect(restored.iconStyle, ProxiesIconStyle.icon);
      expect(restored.hasCustomizedStyle, isTrue);
    });

    test('从没有 hasCustomizedStyle 字段的旧 JSON 反序列化时默认为 false', () {
      final oldJson = {
        'type': 'tab',
        'iconStyle': 'none',
      };

      final restored = ProxiesStyle.fromJson(oldJson);

      expect(restored.hasCustomizedStyle, isFalse);
    });
  });

  group('ProxiesStyle 网速测试配置', () {
    test('默认测速下载源与时长', () {
      const style = ProxiesStyle();

      expect(style.speedTestUrl, defaultSpeedTestUrl);
      expect(style.speedTestDuration, 10);
      expect(style.speedTestConcurrency, 8);
    });

    test('测速配置序列化往返一致', () {
      const style = ProxiesStyle(
        speedTestUrl: 'https://example.com/__down?bytes=1024',
        speedTestDuration: 30,
        speedTestConcurrency: 16,
      );

      final restored = ProxiesStyle.fromJson(
        jsonDecode(jsonEncode(style.toJson())) as Map<String, dynamic>,
      );

      expect(restored.speedTestUrl, style.speedTestUrl);
      expect(restored.speedTestDuration, 30);
      expect(restored.speedTestConcurrency, 16);
    });

    test('旧 JSON 缺少测速字段时回落默认值', () {
      final oldJson = {
        'type': 'tab',
        'iconStyle': 'none',
      };

      final restored = ProxiesStyle.fromJson(oldJson);

      expect(restored.speedTestUrl, defaultSpeedTestUrl);
      expect(restored.speedTestDuration, 10);
    });
  });
}
