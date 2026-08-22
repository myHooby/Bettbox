import 'dart:async';

import 'package:bett_box/clash/clash.dart';
import 'package:bett_box/common/common.dart';
import 'package:bett_box/models/models.dart';
import 'package:bett_box/providers/providers.dart';
import 'package:bett_box/state.dart';
import 'package:bett_box/views/proxies/common.dart';
import 'package:bett_box/widgets/widgets.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

// 对单个节点发起网速测试并弹出进度面板
void showProxySpeedTestSheet(BuildContext context, Proxy proxy) {
  unawaited(proxySpeedTest(proxy));
  showSheet(
    context: context,
    builder: (_, type) {
      return AdaptiveSheetScaffold(
        type: type,
        title: appLocalizations.speedTest,
        body: SpeedTestSheet(proxyNames: [proxy.name], isBatch: false),
      );
    },
  );
}

// 对整组节点发起串行网速测试并弹出进度面板
void showGroupSpeedTestSheet(BuildContext context, List<Proxy> proxies,
    {required String groupName}) {
  unawaited(speedTest(proxies, groupName: groupName));
  final names = proxies.map((proxy) => proxy.name).toList();
  showSheet(
    context: context,
    builder: (_, type) {
      return AdaptiveSheetScaffold(
        type: type,
        title: appLocalizations.speedTest,
        body: SpeedTestSheet(proxyNames: names, isBatch: true),
      );
    },
  );
}

// 网速测试进度面板:监听内核进度消息展示实时速度,结果列表取自 speedMap
class SpeedTestSheet extends StatefulWidget {
  final List<String> proxyNames;

  final bool isBatch;

  const SpeedTestSheet({
    super.key,
    required this.proxyNames,
    required this.isBatch,
  });

  @override
  State<SpeedTestSheet> createState() => _SpeedTestSheetState();
}

class _SpeedTestSheetState extends State<SpeedTestSheet> with AppMessageListener {
  SpeedTestProgress? _progress;

  @override
  void initState() {
    super.initState();
    clashMessage.addListener(this);
  }

  @override
  void dispose() {
    clashMessage.removeListener(this);
    super.dispose();
  }

  @override
  void onSpeedTest(SpeedTestProgress progress) {
    // 仅展示当前正在测试节点的进度,避免过期消息干扰
    if (!mounted || progress.name != speedTestCoordinator.currentProxyName) {
      return;
    }
    setState(() {
      _progress = progress;
    });
  }

  String _formatSpeed(double bytesPerSecond) {
    return '${TrafficValue(value: bytesPerSecond.toInt()).show}/s';
  }

  Widget _buildCurrent(String current, int durationMs) {
    final progress = _progress;
    final speedText = progress == null || progress.speed <= 0
        ? appLocalizations.testing
        : _formatSpeed(progress.speed);
    final elapsed = progress?.elapsed ?? 0;
    final progressValue = durationMs > 0
        ? (elapsed / durationMs).clamp(0.0, 1.0)
        : 0.0;
    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.start,
      spacing: 8,
      children: [
        Text(
          current,
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
          style: context.textTheme.bodyMedium,
        ),
        Text(
          speedText,
          style: context.textTheme.headlineSmall,
        ),
        LinearProgressIndicator(value: progressValue),
        Text(
          '${TrafficValue(value: progress?.bytes ?? 0).show} · ${(elapsed / 1000).fixed(decimals: 1)}s',
          style: context.textTheme.bodySmall,
        ),
      ],
    );
  }

  Widget _buildResultItem(String name, double? speed) {
    final speedText = switch (speed) {
      null => '-',
      0 => appLocalizations.testing,
      -1.0 => appLocalizations.speedTestFailed,
      _ => _formatSpeed(speed),
    };
    final color = switch (speed) {
      -1.0 => context.colorScheme.error,
      _ => context.textTheme.bodyMedium?.color,
    };
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 4),
      child: Row(
        children: [
          Expanded(
            child: Text(
              name,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: context.textTheme.bodyMedium,
            ),
          ),
          const SizedBox(width: 8),
          Text(
            speedText,
            style: context.textTheme.bodyMedium?.copyWith(color: color),
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final durationMs = globalState.config.proxiesStyle.speedTestDuration * 1000;
    return AnimatedBuilder(
      animation: speedTestCoordinator,
      builder: (_, _) {
        final isTesting = speedTestCoordinator.isTesting;
        final current = speedTestCoordinator.currentProxyName;
        return SingleChildScrollView(
          padding: const EdgeInsets.all(16),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            spacing: 12,
            children: [
              if (widget.isBatch)
                Text(
                  appLocalizations.speedTestTrafficTip,
                  style: context.textTheme.bodySmall?.copyWith(
                    color: context.colorScheme.tertiary,
                  ),
                ),
              if (isTesting && current != null)
                _buildCurrent(current, durationMs)
              else
                Text(
                  appLocalizations.speedTestCompleted,
                  style: context.textTheme.bodyMedium,
                ),
              const Divider(height: 1),
              Consumer(
                builder: (_, ref, _) {
                  final speedMap = ref.watch(speedDataSourceProvider);
                  return Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      for (final name in widget.proxyNames)
                        _buildResultItem(name, speedMap[name]),
                    ],
                  );
                },
              ),
            ],
          ),
        );
      },
    );
  }
}
