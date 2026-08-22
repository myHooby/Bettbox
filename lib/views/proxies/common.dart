import 'package:bett_box/clash/clash.dart';
import 'package:bett_box/common/common.dart';
import 'package:bett_box/enum/enum.dart';
import 'package:bett_box/models/models.dart';
import 'package:bett_box/state.dart';

import 'package:flutter/foundation.dart';

class DelayTestCoordinator extends ChangeNotifier {
  String? _testingGroupName;

  String? get testingGroupName => _testingGroupName;

  bool get isTesting => _testingGroupName != null;

  bool isTestingGroup(String groupName) => _testingGroupName == groupName;

  Future<bool> run(String groupName, Future<void> Function() action) async {
    if (isTesting) {
      return false;
    }

    _testingGroupName = groupName;
    notifyListeners();
    try {
      await action();
      return true;
    } finally {
      _testingGroupName = null;
      notifyListeners();
    }
  }
}

final delayTestCoordinator = DelayTestCoordinator();

// 网速测试全局互斥协调器:带宽测试必须串行独占,任意时刻仅允许一个节点在测
class SpeedTestCoordinator extends ChangeNotifier {
  String? _testingGroupName;

  String? _currentProxyName;

  String? get testingGroupName => _testingGroupName;

  // 当前正在测试的节点名,供对话框与进度展示使用
  String? get currentProxyName => _currentProxyName;

  bool get isTesting => _testingGroupName != null;

  bool isTestingGroup(String groupName) => _testingGroupName == groupName;

  Future<bool> run(String groupName, Future<void> Function() action) async {
    if (isTesting) {
      return false;
    }

    _testingGroupName = groupName;
    notifyListeners();
    try {
      await action();
      return true;
    } finally {
      _testingGroupName = null;
      _currentProxyName = null;
      notifyListeners();
    }
  }

  void setCurrentProxy(String proxyName) {
    if (_currentProxyName == proxyName) return;
    _currentProxyName = proxyName;
    notifyListeners();
  }
}

final speedTestCoordinator = SpeedTestCoordinator();

@immutable
class DelayTestTarget {
  final String name;
  final String url;

  const DelayTestTarget({required this.name, required this.url});

  @override
  bool operator ==(Object other) {
    return other is DelayTestTarget && other.name == name && other.url == url;
  }

  @override
  int get hashCode => Object.hash(name, url);
}

class DelayTestRequestPool {
  final Map<DelayTestTarget, Future<Delay>> _pendingRequests = {};

  int get pendingCount => _pendingRequests.length;

  Future<Delay> run(DelayTestTarget target, Future<Delay> Function() action) {
    final pendingRequest = _pendingRequests[target];
    if (pendingRequest != null) {
      return pendingRequest;
    }

    final request = action();
    _pendingRequests[target] = request;
    return request.whenComplete(() {
      if (identical(_pendingRequests[target], request)) {
        _pendingRequests.remove(target);
      }
    });
  }
}

final _delayTestRequestPool = DelayTestRequestPool();

double get listHeaderHeight {
  final measure = globalState.measure;
  return 20 + measure.titleMediumHeight + 4 + measure.bodyMediumHeight;
}

double getItemHeight(ProxyCardType proxyCardType) {
  final measure = globalState.measure;
  final baseHeight =
      16 + measure.bodyMediumHeight * 2 + measure.bodySmallHeight + 8 + 4;
  return switch (proxyCardType) {
    ProxyCardType.expand => baseHeight - measure.bodySmallHeight + measure.labelSmallHeight * 2 + 4,
    ProxyCardType.shrink => baseHeight,
    ProxyCardType.min => baseHeight - measure.bodyMediumHeight,
  };
}

Future<void> proxyDelayTest(Proxy proxy, [String? testUrl]) async {
  if (_isNonTestableProxy(proxy)) return;
  final appController = globalState.appController;
  final state = appController.getProxyCardState(proxy.name);
  final url = appController.getRealTestUrl(
    state.testUrl.getSafeValue(testUrl ?? ''),
  );
  if (state.proxyName.isEmpty) {
    return;
  }
  await _testProxyDelay(DelayTestTarget(name: state.proxyName, url: url));
  appController.addSortNum();
}

Future<Delay> _testProxyDelay(DelayTestTarget target) {
  return _delayTestRequestPool.run(target, () async {
    final appController = globalState.appController;
    appController.setDelay(Delay(url: target.url, name: target.name, value: 0));
    final delay = await clashCore.getDelay(target.url, target.name);
    appController.setDelay(delay);
    return delay;
  });
}

bool _isNonTestableProxyName(String proxyName) {
  final name = proxyName.toUpperCase();
  return name == 'REJECT' || name == 'REJECT-DROP' || name == 'PASS';
}

bool _isNonTestableProxyType(String proxyType) {
  return proxyType.toUpperCase() == 'REMATCH';
}

bool _isNonTestableProxy(Proxy proxy) {
  return _isNonTestableProxyName(proxy.name) ||
      _isNonTestableProxyType(proxy.type);
}

String? _getProxyType(String proxyName) {
  final groups = globalState.appController.getCurrentGroups();
  for (final group in groups) {
    if (group.name == proxyName) return group.type.name;
    for (final proxy in group.all) {
      if (proxy.name == proxyName) return proxy.type;
    }
  }
  return null;
}

Future<void> delayTest(
  List<Proxy> proxies, {
  String? testUrl,
  String? groupName,
  Future<void> Function()? onDelayUpdated,
}) async {
  Future<void> runTest() async {
    final appController = globalState.appController;
    final targets = <DelayTestTarget>{};
    for (final proxy in proxies) {
      if (_isNonTestableProxy(proxy)) {
        continue;
      }
      final state = appController.getProxyCardState(proxy.name);
      final url = appController.getRealTestUrl(
        state.testUrl.getSafeValue(testUrl ?? ''),
      );
      final name = state.proxyName;
      if (name.isEmpty ||
          _isNonTestableProxyName(name) ||
          _isNonTestableProxyType(_getProxyType(name) ?? '')) {
        continue;
      }
      targets.add(DelayTestTarget(name: name, url: url));
    }
    final concurrencyLimit = globalState.config.proxiesStyle.concurrencyLimit;

    // 按实际节点和实际测试地址创建任务，避免多个代理组别名重复测速。
    final delayTasks = targets.map((target) {
      return () async {
        await _testProxyDelay(target);
        await onDelayUpdated?.call();
      };
    }).toList();

    // Execute tasks in batches
    final batchedTasks = delayTasks.batch(concurrencyLimit);
    for (final batchTasks in batchedTasks) {
      await Future.wait(batchTasks.map((task) => task()));
    }
    appController.addSortNum();
  }

  if (groupName == null || groupName.isEmpty) {
    await runTest();
    return;
  }
  await delayTestCoordinator.run(groupName, runTest);
}

double getScrollToSelectedOffset({
  required String groupName,
  required List<Proxy> proxies,
}) {
  final appController = globalState.appController;
  final columns = appController.getProxiesColumns();
  final proxyCardType = globalState.config.proxiesStyle.cardType;
  final selectedProxyName = appController.getSelectedProxyName(groupName);
  final findSelectedIndex = proxies.indexWhere(
    (proxy) => proxy.name == selectedProxyName,
  );
  final selectedIndex = findSelectedIndex != -1 ? findSelectedIndex : 0;
  final rows = (selectedIndex / columns).floor();
  return rows * getItemHeight(proxyCardType) + (rows - 1) * 8;
}

// 对单个节点执行网速测试,经协调器互斥,测试期间卡片显示进行中状态
Future<bool> proxySpeedTest(Proxy proxy) async {
  if (_isNonTestableProxy(proxy)) return false;
  final state = globalState.appController.getProxyCardState(proxy.name);
  if (state.proxyName.isEmpty) return false;
  return speedTest([proxy], groupName: proxy.name);
}

Future<bool> _testProxySpeed(String proxyName) async {
  final appController = globalState.appController;
  final proxiesStyle = globalState.config.proxiesStyle;
  speedTestCoordinator.setCurrentProxy(proxyName);
  // 置 0 表示测试中,与延迟测试的展示约定一致
  appController.setSpeed(
    SpeedResult(name: proxyName, url: proxiesStyle.speedTestUrl, speed: 0),
  );
  try {
    final result = await clashCore.getSpeed(
      proxiesStyle.speedTestUrl,
      proxyName,
      proxiesStyle.speedTestDuration * 1000,
    );
    appController.setSpeed(result);
    return result.speed >= 0;
  } catch (_) {
    appController.setSpeed(
      SpeedResult(
        name: proxyName,
        url: proxiesStyle.speedTestUrl,
        speed: -1,
      ),
    );
    return false;
  }
}

// 网速测试入口:组内可测节点按实际节点名去重后串行执行(独占带宽保证结果准确)
Future<bool> speedTest(
  List<Proxy> proxies, {
  String? groupName,
}) async {
  Future<void> runTest() async {
    final appController = globalState.appController;
    final names = <String>{};
    for (final proxy in proxies) {
      if (_isNonTestableProxy(proxy)) {
        continue;
      }
      final state = appController.getProxyCardState(proxy.name);
      final name = state.proxyName;
      if (name.isEmpty ||
          _isNonTestableProxyName(name) ||
          _isNonTestableProxyType(_getProxyType(name) ?? '')) {
        continue;
      }
      names.add(name);
    }
    for (final name in names) {
      await _testProxySpeed(name);
    }
  }

  final name = groupName ?? '';
  if (name.isEmpty) {
    await runTest();
    return true;
  }
  return speedTestCoordinator.run(name, runTest);
}
