import 'dart:async';

import 'package:bett_box/clash/clash.dart';
import 'package:bett_box/common/common.dart';
import 'package:bett_box/models/models.dart';
import 'package:bett_box/providers/providers.dart';
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

// 对整组节点发起并行网速测试并弹出进度面板
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

// 网速测试进度面板:并行测试时按节点名汇总实时进度,结果列表取自 speedMap
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
  // 各节点最新实时进度,按节点名索引
  final Map<String, SpeedTestProgress> _progressMap = {};

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
    if (!mounted) return;
    setState(() {
      _progressMap[progress.name] = progress;
    });
  }

  String _formatSpeed(double bytesPerSecond) {
    return '${TrafficValue(value: bytesPerSecond.toInt()).show}/s';
  }

  // 顶部汇总:测试中显示并行节点的合计速率,完成后显示整体结束状态
  Widget _buildSummary(bool isTesting) {
    if (!isTesting) {
      return Text(
        appLocalizations.speedTestCompleted,
        style: context.textTheme.bodyMedium,
      );
    }
    final totalRate = _progressMap.values.fold<double>(
      0,
      (sum, progress) => sum + progress.speed,
    );
    return Row(
      children: [
        const SizedBox(
          width: 16,
          height: 16,
          child: CircularProgressIndicator(strokeWidth: 2),
        ),
        const SizedBox(width: 8),
        Text(
          '${_formatSpeed(totalRate)} · ${appLocalizations.testing}',
          style: context.textTheme.bodyMedium,
        ),
      ],
    );
  }

  Widget _buildResultItem(String name, double? speed) {
    final progress = _progressMap[name];
    final String speedText;
    if (speed == null) {
      speedText = '-';
    } else if (speed == 0) {
      // 测试中优先展示实时进度,无进度消息时回退到通用文案
      speedText = progress != null && progress.speed > 0
          ? _formatSpeed(progress.speed)
          : appLocalizations.testing;
    } else if (speed < 0) {
      speedText = appLocalizations.speedTestFailed;
    } else {
      speedText = _formatSpeed(speed);
    }
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
    return AnimatedBuilder(
      animation: speedTestCoordinator,
      builder: (_, _) {
        final isTesting = speedTestCoordinator.isTesting;
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
              _buildSummary(isTesting),
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
