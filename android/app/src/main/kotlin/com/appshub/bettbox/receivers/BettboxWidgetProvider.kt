package com.appshub.bettbox.receivers

import android.app.PendingIntent
import android.appwidget.AppWidgetManager
import android.content.ComponentName
import android.content.Context
import android.content.Intent
import android.content.SharedPreferences
import android.widget.RemoteViews
import com.appshub.bettbox.GlobalState
import com.appshub.bettbox.MainActivity
import com.appshub.bettbox.R
import es.antonborri.home_widget.HomeWidgetPlugin
import es.antonborri.home_widget.HomeWidgetProvider

// 桌面网速小组件:展示当前节点与实时上下行速度,底部按钮复用磁贴的启停链路
class BettboxWidgetProvider : HomeWidgetProvider() {

    override fun onUpdate(
        context: Context,
        appWidgetManager: AppWidgetManager,
        appWidgetIds: IntArray,
        widgetData: SharedPreferences,
    ) {
        val nodeName = widgetData.getString(KEY_NODE, "").orEmpty()
        val upSpeed = widgetData.getString(KEY_UP, null) ?: "0B/s"
        val downSpeed = widgetData.getString(KEY_DOWN, null) ?: "0B/s"
        val running = widgetData.getBoolean(KEY_RUNNING, false)

        appWidgetIds.forEach { id ->
            val views =
                RemoteViews(context.packageName, R.layout.bettbox_speed_widget).apply {
                    setTextViewText(R.id.widget_node, nodeName.ifEmpty { "Bettbox" })
                    setTextViewText(R.id.widget_up, "↑ $upSpeed")
                    setTextViewText(R.id.widget_down, "↓ $downSpeed")
                    setTextViewText(R.id.widget_toggle, if (running) "⏸" else "▶")

                    // 点击主体打开应用
                    val openIntent =
                        PendingIntent.getActivity(
                            context,
                            0,
                            Intent(context, MainActivity::class.java),
                            PendingIntent.FLAG_UPDATE_CURRENT or PendingIntent.FLAG_IMMUTABLE,
                        )
                    setOnClickPendingIntent(R.id.widget_root, openIntent)

                    // 开关按钮:广播回自身,复用磁贴的启停链路
                    val toggleIntent =
                        PendingIntent.getBroadcast(
                            context,
                            1,
                            Intent(context, BettboxWidgetProvider::class.java)
                                .setAction(ACTION_TOGGLE),
                            PendingIntent.FLAG_UPDATE_CURRENT or PendingIntent.FLAG_IMMUTABLE,
                        )
                    setOnClickPendingIntent(R.id.widget_toggle, toggleIntent)
                }
            appWidgetManager.updateAppWidget(id, views)
        }
    }

    override fun onReceive(context: Context, intent: Intent) {
        if (intent.action == ACTION_TOGGLE) {
            GlobalState.handleToggle()
            // 立即刷新开关状态,不等下一秒推送
            val manager = AppWidgetManager.getInstance(context)
            val ids =
                manager.getAppWidgetIds(
                    ComponentName(context, BettboxWidgetProvider::class.java)
                )
            if (ids.isNotEmpty()) {
                onUpdate(
                    context,
                    manager,
                    ids,
                    HomeWidgetPlugin.getData(context),
                )
            }
            return
        }
        super.onReceive(context, intent)
    }

    companion object {
        const val ACTION_TOGGLE = "com.appshub.bettbox.WIDGET_TOGGLE"
        const val KEY_NODE = "speedWidget.node"
        const val KEY_UP = "speedWidget.up"
        const val KEY_DOWN = "speedWidget.down"
        const val KEY_RUNNING = "speedWidget.running"
    }
}
