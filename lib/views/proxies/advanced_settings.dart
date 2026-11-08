import 'package:bett_box/common/common.dart';
import 'package:bett_box/enum/enum.dart';
import 'package:bett_box/providers/providers.dart';
import 'package:bett_box/state.dart';
import 'package:bett_box/views/icon_sets.dart';
import 'package:bett_box/widgets/widgets.dart';
import 'package:material_ui/material_ui.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

class ProxiesAdvancedSettings extends ConsumerWidget {
  const ProxiesAdvancedSettings({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    return ScrollEdgeRise(
      builder: (_, rise) => ListView(
        padding: EdgeInsets.only(top: 8 + rise, bottom: 20),
        children: generateSection(
          items: [
            const _NodeExclusionWithInverseItem(),
            const _ConcurrencyLimitItem(),
            const _HealthCheckTimeoutItem(),
            const _DelayAnimationItem(),
            const _SpeedTestUrlItem(),
            const _SpeedTestDurationItem(),
            const _IconConfigItem(),
          ],
        ),
      ),
    );
  }
}

class _NodeExclusionWithInverseItem extends ConsumerWidget {
  const _NodeExclusionWithInverseItem();

  String? _validateRegex(String? value) {
    if (value == null || value.trim().isEmpty) return null;
    try {
      RegExp(value.trim());
      return null;
    } catch (e) {
      final detail = e is FormatException && e.message.isNotEmpty
          ? e.message
          : null;
      return detail != null
          ? '${appLocalizations.formatError}: $detail'
          : appLocalizations.formatError;
    }
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    // 通过响应式 provider 监听，对话框确认后立即重建
    final nodeExcludeFilter = ref.watch(nodeExcludeFilterProvider);

    return ListItem(
      leading: const Icon(Icons.filter_alt_outlined),
      title: Text(appLocalizations.nodeExclusion),
      subtitle: Text(appLocalizations.nodeExclusionDesc),
      onTap: () async {
        await globalState.showCommonDialog(
          child: _NodeExclusionDialog(
            currentValue: nodeExcludeFilter,
            validator: _validateRegex,
          ),
        );
      },
    );
  }
}

class _NodeExclusionDialog extends ConsumerStatefulWidget {
  final String currentValue;
  final String? Function(String?)? validator;

  const _NodeExclusionDialog({required this.currentValue, this.validator});

  @override
  ConsumerState<_NodeExclusionDialog> createState() =>
      _NodeExclusionDialogState();
}

class _NodeExclusionDialogState extends ConsumerState<_NodeExclusionDialog> {
  late TextEditingController _controller;
  final _formKey = GlobalKey<FormState>();

  @override
  void initState() {
    super.initState();
    _controller = TextEditingController(text: widget.currentValue);
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  void _handleSubmit() {
    if (_formKey.currentState?.validate() == false) return;

    final filter = _controller.text.trim();
    // 通过 provider notifier 更新，触发父 Widget 响应式重建
    ref.read(nodeExcludeFilterProvider.notifier).value = filter;
    globalState.appController.applyProfileDebounce();
    Navigator.of(context, rootNavigator: true).pop();
  }

  @override
  Widget build(BuildContext context) {
    return CommonDialog(
      title: appLocalizations.nodeExclusion,
      actions: [
        TextButton(
          onPressed: _handleSubmit,
          child: Text(appLocalizations.submit),
        ),
      ],
      child: Form(
        key: _formKey,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            TextFormField(
              controller: _controller,
              decoration: InputDecoration(
                border: const OutlineInputBorder(),
                labelText: appLocalizations.nodeExclusion,
                hintText: appLocalizations.nodeExclusionPlaceholder,
              ),
              validator: widget.validator,
              onFieldSubmitted: (_) => _handleSubmit(),
            ),
          ],
        ),
      ),
    );
  }
}

class _ConcurrencyLimitItem extends ConsumerWidget {
  const _ConcurrencyLimitItem();

  static const _options = [2, 8, 16, 32, maxDelayTestConcurrency];

  String _getDisplayText(int value, BuildContext context) {
    if (value == maxDelayTestConcurrency) {
      return 'MAX';
    }
    return '$value';
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final concurrencyLimit = ref.watch(
      proxiesStyleSettingProvider.select((state) => state.concurrencyLimit),
    );

    return ListItem<int>.options(
      leading: const Icon(Icons.speed),
      title: Text(appLocalizations.concurrencyLimit),
      subtitle: Text(appLocalizations.concurrencyLimitDesc),
      delegate: OptionsDelegate(
        title: appLocalizations.concurrencyLimit,
        options: _options,
        value: concurrencyLimit,
        textBuilder: (value) => _getDisplayText(value, context),
        onChanged: (value) {
          if (value != null) {
            ref
                .read(proxiesStyleSettingProvider.notifier)
                .updateState(
                  (state) => state.copyWith(concurrencyLimit: value),
                );
          }
        },
      ),
    );
  }
}

class _HealthCheckTimeoutItem extends ConsumerWidget {
  const _HealthCheckTimeoutItem();

  static const _options = [1000, 2000, 3000, 5000, 8000];

  String _getDisplayText(int value) {
    return '${value ~/ 1000}s';
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final timeout = ref.watch(healthCheckTimeoutProvider);

    return ListItem<int>.options(
      leading: const Icon(Icons.timer_outlined),
      title: Text(appLocalizations.healthCheckTimeout),
      subtitle: Text(appLocalizations.healthCheckTimeoutDesc),
      delegate: OptionsDelegate(
        title: appLocalizations.healthCheckTimeout,
        options: _options,
        value: timeout,
        textBuilder: _getDisplayText,
        onChanged: (value) {
          if (value != null) {
            ref
                .read(healthCheckTimeoutProvider.notifier)
                .updateState((_) => value);
            globalState.appController.applyProfileDebounce();
          }
        },
      ),
    );
  }
}

class _DelayAnimationItem extends ConsumerWidget {
  const _DelayAnimationItem();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final (delayAnimation, syncDelayAnimation) = ref.watch(
      proxiesStyleSettingProvider.select(
        (state) => (state.delayAnimation, state.syncDelayAnimation),
      ),
    );

    return ListItem(
      leading: const Icon(Icons.animation),
      title: Text(appLocalizations.delayAnimation),
      subtitle: Text(appLocalizations.delayAnimationDesc),
      onTap: () async {
        final value = await globalState
            .showCommonDialog<(DelayAnimationType, bool)>(
              child: DelayAnimationPickerDialog(
                title: appLocalizations.delayAnimation,
                initialValue: delayAnimation,
                initialSync: syncDelayAnimation,
              ),
            );
        if (value == null) return;
        ref
            .read(proxiesStyleSettingProvider.notifier)
            .updateState(
              (state) => state.copyWith(
                delayAnimation: value.$1,
                syncDelayAnimation: value.$2,
              ),
            );
      },
    );
  }
}

// 网速测试下载源设置:预设列表 + 自定义 URL
class _SpeedTestUrlItem extends ConsumerWidget {
  const _SpeedTestUrlItem();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final speedTestUrl = ref.watch(
      proxiesStyleSettingProvider.select((state) => state.speedTestUrl),
    );

    return ListItem(
      leading: const Icon(Icons.download_outlined),
      title: Text(appLocalizations.speedTestUrl),
      subtitle: SingleChildScrollView(
        scrollDirection: Axis.horizontal,
        child: Text(speedTestUrl),
      ),
      onTap: () async {
        await globalState.showCommonDialog(
          child: _SpeedTestUrlDialog(currentUrl: speedTestUrl),
        );
      },
    );
  }
}

class _IconConfigItem extends StatelessWidget {
  const _IconConfigItem();

  Future<void> _handleResetIconCache() async {
    final res = await globalState.showMessage(
      title: appLocalizations.resetIconCache,
      message: TextSpan(text: appLocalizations.resetIconCacheDesc),
    );
    if (res != true) return;
    await globalState.appController.safeRun(() async {
      await CommonTargetIcon.clearCache();
      globalState.showNotifier(appLocalizations.success);
    });
  }

  @override
  Widget build(BuildContext context) {
    return ListItem(
      leading: const Icon(Icons.style_outlined),
      title: Text(appLocalizations.iconConfiguration),
      subtitle: Text(appLocalizations.iconConfigurationDesc),
      onTap: () {
        showExtend(
          context,
          builder: (_, type) {
            return AdaptiveSheetScaffold(
              type: type,
              body: const _IconConfigView(),
              title: appLocalizations.iconConfiguration,
              actions: [
                IconButton(
                  onPressed: () => showIconSets(context),
                  tooltip: appLocalizations.iconSets,
                  icon: const Icon(Icons.collections_outlined),
                ),
                IconButton(
                  onPressed: _handleResetIconCache,
                  tooltip: appLocalizations.resetIconCache,
                  icon: const Icon(Icons.cleaning_services_outlined),
                ),
              ],
            );
          },
        );
      },
    );
  }
}

class _SpeedTestUrlDialog extends ConsumerWidget {
  final String currentUrl;

  const _SpeedTestUrlDialog({required this.currentUrl});

  @override
  Widget build(BuildContext context, ref) {
    final isPresetUrl = presetSpeedTestUrls.contains(currentUrl);

    return CommonDialog(
      title: appLocalizations.speedTestUrl,
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 16),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          ...presetSpeedTestUrls.map((url) {
            final isSelected = currentUrl == url;
            return Material(
              color: Colors.transparent,
              child: InkWell(
                onTap: () {
                  ref.read(proxiesStyleSettingProvider.notifier).updateState(
                        (state) => state.copyWith(speedTestUrl: url),
                      );
                  Navigator.of(context, rootNavigator: true).pop();
                },
                child: Container(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 16,
                    vertical: 12,
                  ),
                  child: Row(
                    children: [
                      Icon(
                        isSelected
                            ? Icons.check_circle_rounded
                            : Icons.circle_outlined,
                        size: 21,
                        color: isSelected
                            ? context.colorScheme.primary
                            : context.colorScheme.onSurfaceVariant.withValues(
                                alpha: 0.6,
                              ),
                      ),
                      const SizedBox(width: 12),
                      Expanded(
                        child: Text(
                          url,
                          style: context.textTheme.bodyMedium,
                          overflow: TextOverflow.ellipsis,
                          maxLines: 1,
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            );
          }),
          // 自定义下载源
          Material(
            color: Colors.transparent,
            child: InkWell(
              onTap: () async {
                final notifier = ref.read(proxiesStyleSettingProvider.notifier);
                Navigator.of(context, rootNavigator: true).pop();
                final customUrl = await globalState.showCommonDialog<String>(
                  child: InputDialog(
                    title: appLocalizations.customUrl,
                    value: isPresetUrl ? '' : currentUrl,
                    resetValue: defaultSpeedTestUrl,
                    validator: (String? inputValue) {
                      if (inputValue == null || inputValue.isEmpty) {
                        return appLocalizations.emptyTip(
                          appLocalizations.speedTestUrl,
                        );
                      }
                      if (!inputValue.isUrl) {
                        return appLocalizations.urlTip(
                          appLocalizations.speedTestUrl,
                        );
                      }
                      return null;
                    },
                  ),
                );

                if (customUrl != null) {
                  notifier.updateState(
                    (state) => state.copyWith(speedTestUrl: customUrl),
                  );
                }
              },
              child: Container(
                padding: const EdgeInsets.symmetric(
                  horizontal: 16,
                  vertical: 12,
                ),
                child: Row(
                  children: [
                    Icon(
                      !isPresetUrl
                          ? Icons.check_circle_rounded
                          : Icons.circle_outlined,
                      size: 21,
                      color: !isPresetUrl
                          ? context.colorScheme.primary
                          : context.colorScheme.onSurfaceVariant.withValues(
                              alpha: 0.6,
                            ),
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: Text(
                        appLocalizations.customUrl,
                        style: context.textTheme.bodyMedium,
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

// 网速测试时长设置
class _SpeedTestDurationItem extends ConsumerWidget {
  const _SpeedTestDurationItem();

  static const _options = [5, 10, 15, 30];

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final duration = ref.watch(
      proxiesStyleSettingProvider.select((state) => state.speedTestDuration),
    );

    return ListItem<int>.options(
      leading: const Icon(Icons.hourglass_bottom_outlined),
      title: Text(appLocalizations.speedTestDuration),
      subtitle: Text(appLocalizations.speedTestDurationDesc),
      delegate: OptionsDelegate(
        title: appLocalizations.speedTestDuration,
        options: _options,
        value: duration,
        textBuilder: (value) => '${value}s',
        onChanged: (value) {
          if (value != null) {
            ref.read(proxiesStyleSettingProvider.notifier).updateState(
                  (state) => state.copyWith(speedTestDuration: value),
                );
          }
        },
      ),
    );
  }
}

class _IconConfigView extends ConsumerWidget {
  const _IconConfigView();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final iconMap = ref.watch(
      proxiesStyleSettingProvider.select((state) => state.iconMap),
    );
    return MapInputPage(
      title: appLocalizations.iconConfiguration,
      map: iconMap,
      keyLabel: appLocalizations.regExp,
      valueLabel: appLocalizations.icon,
      titleBuilder: (item) => EmojiText(item.key),
      leadingBuilder: (item) => Container(
        decoration: BoxDecoration(borderRadius: BorderRadius.circular(16)),
        clipBehavior: Clip.antiAlias,
        child: CommonTargetIcon(src: item.value, size: 42),
      ),
      subtitleBuilder: (item) => Text(
        iconFileStem(item.value),
        maxLines: 1,
        overflow: TextOverflow.ellipsis,
      ),
      editor: (item) => showSheet<MapEntry<String, String>>(
        context: context,
        props: const SheetProps(expandable: false, initialFraction: 0.86),
        builder: (_, type) =>
            _IconRuleSheet(type: type, item: item, keys: iconMap.keys.toSet()),
      ),
      onChange: (value) {
        ref
            .read(proxiesStyleSettingProvider.notifier)
            .updateState((state) => state.copyWith(iconMap: value));
      },
    );
  }
}

class _IconRuleSheet extends StatefulWidget {
  final SheetType type;
  final MapEntry<String, String>? item;
  final Set<String> keys;

  const _IconRuleSheet({
    required this.type,
    required this.item,
    required this.keys,
  });

  @override
  State<_IconRuleSheet> createState() => _IconRuleSheetState();
}

class _IconRuleSheetState extends State<_IconRuleSheet> {
  late final _controller = TextEditingController(text: widget.item?.key);
  late String _icon = widget.item?.value ?? '';

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  String? get _error {
    final text = _controller.text;
    if (text.isEmpty) return null;
    if (text != widget.item?.key && widget.keys.contains(text)) {
      return appLocalizations.existsTip(appLocalizations.regExp);
    }
    try {
      RegExp(text);
    } catch (_) {
      return appLocalizations.formatError;
    }
    return null;
  }

  @override
  Widget build(BuildContext context) {
    final error = _error;
    final valid =
        _controller.text.isNotEmpty && error == null && _icon.isNotEmpty;
    final colorScheme = context.colorScheme;
    return AdaptiveSheetScaffold(
      type: widget.type,
      title: appLocalizations.iconConfiguration,
      actions: [
        const IconSetsButton(),
        IconButton(
          tooltip: appLocalizations.confirm,
          onPressed: valid
              ? () =>
                    Navigator.of(context).pop(MapEntry(_controller.text, _icon))
              : null,
          icon: const Icon(Icons.check),
        ),
      ],
      body: Column(
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 8, 16, 4),
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Container(
                  width: 56,
                  height: 56,
                  alignment: Alignment.center,
                  decoration: BoxDecoration(
                    color: colorScheme.surfaceContainerHigh,
                    borderRadius: BorderRadius.circular(16),
                  ),
                  child: _icon.isEmpty
                      ? Icon(
                          Icons.image_outlined,
                          color: colorScheme.onSurfaceVariant,
                        )
                      : CommonTargetIcon(
                          key: ValueKey(_icon),
                          src: _icon,
                          size: 36,
                        ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: TextField(
                    controller: _controller,
                    autofocus: widget.item == null,
                    onChanged: (_) => setState(() {}),
                    decoration: InputDecoration(
                      border: const OutlineInputBorder(),
                      labelText: appLocalizations.regExp,
                      hintText: 'YouTube|Netflix',
                      errorText: error,
                    ),
                  ),
                ),
              ],
            ),
          ),
          Expanded(
            child: IconPickerBody(
              selected: _icon.isEmpty ? null : _icon,
              suggest: _controller.text,
              onSelect: (value) => setState(() => _icon = value ?? ''),
            ),
          ),
        ],
      ),
    );
  }
}
