import 'package:bett_box/views/proxies/common.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('SpeedTestCoordinator 全局互斥', () {
    test('测试期间持有状态并拒绝并发测试', () async {
      final coordinator = SpeedTestCoordinator();

      expect(coordinator.isTesting, isFalse);
      expect(coordinator.testingGroupName, null);

      var actionExecuted = false;
      final testFuture = coordinator.run('ProxyGroup', () async {
        actionExecuted = true;
        expect(coordinator.isTesting, isTrue);
        expect(coordinator.testingGroupName, 'ProxyGroup');
        expect(coordinator.isTestingGroup('ProxyGroup'), isTrue);
        expect(coordinator.isTestingGroup('OtherGroup'), isFalse);
      });

      final secondTestStarted = await coordinator.run('OtherGroup', () async {});
      expect(secondTestStarted, isFalse);

      await testFuture;

      expect(actionExecuted, isTrue);
      expect(coordinator.isTesting, isFalse);
      expect(coordinator.testingGroupName, null);
    });

    test('测试失败时清理测试状态', () async {
      final coordinator = SpeedTestCoordinator();

      try {
        await coordinator.run('ProxyGroup', () async {
          throw Exception('network error');
        });
      } catch (_) {}

      expect(coordinator.isTesting, isFalse);
      expect(coordinator.testingGroupName, null);
    });

    test('开始与结束时各通知监听器一次', () async {
      final coordinator = SpeedTestCoordinator();
      var notifications = 0;
      coordinator.addListener(() {
        notifications++;
      });

      await coordinator.run('ProxyGroup', () async {});

      expect(notifications, 2);
    });
  });

}
