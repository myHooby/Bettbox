import 'package:bett_box/common/common.dart';
import 'package:bett_box/models/models.dart';
import 'package:bett_box/plugins/service.dart' as vpn_service;
import 'package:bett_box/state.dart';

var _speedWidgetLogged = false;

// 桌面网速小组件推送:数据经与通知速度相同的 service 通道直达原生渲染。
// 调用方(updateTraffic)已按设置开关把关,这里不再重复读配置
Future<void> updateSpeedWidget(Traffic traffic) async {
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
          : (appController.getSelectedProxyName(groupName) ?? '');

  try {
    await vpn_service.service?.updateSpeedWidget(
      nodeName,
      traffic.up.show,
      traffic.down.show,
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
