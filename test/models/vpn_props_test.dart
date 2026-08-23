import 'dart:convert';

import 'package:bett_box/enum/enum.dart';
import 'package:bett_box/models/config.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('VpnProps 托盘点击行为', () {
    test('默认保留托盘增强关闭，左键显示面板、右键显示菜单', () {
      const props = VpnProps();

      expect(props.trayEnhancement, isFalse);
      expect(props.trayLeftClickBehavior, TrayClickBehavior.showPanel);
      expect(props.trayRightClickBehavior, TrayClickBehavior.showMenu);
    });

    test('序列化后能够独立恢复左右键设置及托盘增强设置', () {
      const props = VpnProps(
        trayEnhancement: true,
        trayLeftClickBehavior: TrayClickBehavior.showMenu,
        trayRightClickBehavior: TrayClickBehavior.showPanel,
      );

      final restored = VpnProps.fromJson(
        jsonDecode(jsonEncode(props.toJson())) as Map<String, dynamic>,
      );

      expect(restored.trayEnhancement, isTrue);
      expect(restored.trayLeftClickBehavior, TrayClickBehavior.showMenu);
      expect(restored.trayRightClickBehavior, TrayClickBehavior.showPanel);
    });
  });

  group('VpnProps 桌面网速小组件', () {
    test('默认关闭,开启后序列化往返一致', () {
      const props = VpnProps();
      expect(props.enableSpeedWidget, isFalse);

      const enabled = VpnProps(enableSpeedWidget: true);
      final restored = VpnProps.fromJson(
        jsonDecode(jsonEncode(enabled.toJson())) as Map<String, dynamic>,
      );
      expect(restored.enableSpeedWidget, isTrue);
    });

    test('旧 JSON 缺少字段时回落默认关闭', () {
      final restored = VpnProps.fromJson({});
      expect(restored.enableSpeedWidget, isFalse);
    });
  });
}
