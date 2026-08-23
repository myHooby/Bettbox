import 'package:bett_box/common/common.dart';
import 'package:bett_box/models/models.dart';
import 'package:bett_box/state.dart';
import 'package:home_widget/home_widget.dart';

var _speedWidgetLogged = false;

// 桌面网速小组件推送:由 updateTraffic 每秒调用,数据经 home_widget 写入
// SharedPreferences 后触发原生 BettboxWidgetProvider 渲染。
// 键名与 BettboxWidgetProvider.kt 的常量保持一致;
// qualifiedAndroidName 必须用完整限定名,类位于 receivers 子包
Future<void> updateSpeedWidget(Traffic traffic) async {
  if (!globalState.config.vpnProps.enableSpeedWidget) return;

  final appController = globalState.appController;
  var groupName = appController.getCurrentGroupName();
  if (groupName == null || groupName.isEmpty) {
    final groups = appController.getCurrentGroups();
    if (groups.isNotEmpty) {
      groupName = groups.first.name;
    }
  }
  final nodeName =
      (groupName == null || groupName.isEmpty)
          ? ''
          : appController.getSelectedProxyName(groupName);

  try {
    await Future.wait([
      HomeWidget.saveWidgetData<String>('speedWidget.node', nodeName),
      HomeWidget.saveWidgetData<String>('speedWidget.up', traffic.up.show),
      HomeWidget.saveWidgetData<String>('speedWidget.down', traffic.down.show),
    ]);
    await HomeWidget.updateWidget(
      qualifiedAndroidName:
          'com.appshub.bettbox.receivers.BettboxWidgetProvider',
    );
    if (!_speedWidgetLogged) {
      _speedWidgetLogged = true;
      commonPrint.log(
        'speed widget pushed: node=$nodeName up=${traffic.up.show} '
        'down=${traffic.down.show}',
      );
    }
  } catch (e) {
    // 推送失败不中断 updateTraffic 的通知等其他分支
    commonPrint.log('speed widget push error: $e');
  }
}
