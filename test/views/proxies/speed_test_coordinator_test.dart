import 'package:bett_box/models/models.dart';
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

  group('SpeedResult 与 SpeedTestProgress 解析', () {
    test('SpeedResult 正常解析', () {
      final result = SpeedResult.fromJson({
        'name': 'node-a',
        'url': 'https://speed.cloudflare.com/__down?bytes=104857600',
        'speed': 1310720.5,
        'bytes': 13107205,
        'duration': 10000,
      });

      expect(result.name, 'node-a');
      expect(result.speed, 1310720.5);
      expect(result.bytes, 13107205);
      expect(result.duration, 10000);
    });

    test('SpeedResult 缺省字段回落默认值', () {
      final result = SpeedResult.fromJson({
        'name': 'node-a',
        'url': 'https://example.com',
      });

      expect(result.speed, 0);
      expect(result.bytes, 0);
      expect(result.duration, 0);
    });

    test('SpeedTestProgress 正常解析', () {
      final progress = SpeedTestProgress.fromJson({
        'name': 'node-a',
        'url': 'https://example.com',
        'speed': 2048.0,
        'bytes': 20480,
        'elapsed': 10000,
      });

      expect(progress.name, 'node-a');
      expect(progress.speed, 2048.0);
      expect(progress.bytes, 20480);
      expect(progress.elapsed, 10000);
    });
  });
}
