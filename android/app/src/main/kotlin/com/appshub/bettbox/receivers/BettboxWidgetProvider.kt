package com.appshub.bettbox.receivers

import android.app.PendingIntent
import android.appwidget.AppWidgetManager
import android.appwidget.AppWidgetProvider
import android.content.ComponentName
import android.content.Context
import android.content.Intent
import android.os.Handler
import android.os.Looper
import android.widget.RemoteViews
import com.appshub.bettbox.GlobalState
import com.appshub.bettbox.MainActivity
import com.appshub.bettbox.R
import com.appshub.bettbox.RunState

// 桌面网速小组件:数据由 Dart 经 service 通道(与通知速度同链路)直推原生渲染,
// 不经过 SharedPreferences 与插件广播;开关按钮复用磁贴的启停链路,
// 点击后延时多次刷新以呈现异步启停的最终状态
class BettboxWidgetProvider : AppWidgetProvider() {

    override fun onUpdate(
        context: Context,
        appWidgetManager: AppWidgetManager,
        appWidgetIds: IntArray,
    ) {
        render(context)
    }

    override fun onReceive(context: Context, intent: Intent) {
        if (intent.action == ACTION_TOGGLE) {
            GlobalState.handleToggle()
            // 启停是异步流程,先后多次刷新以反映最终状态
            val handler = Handler(Looper.getMainLooper())
            for (delay in longArrayOf(0, 1000, 2500)) {
                handler.postDelayed({ render(context.applicationContext) }, delay)
            }
            return
        }
        super.onReceive(context, intent)
    }

    companion object {
        const val ACTION_TOGGLE = "com.appshub.bettbox.WIDGET_TOGGLE"

        // 进程内存中的最近一次数据,供点击开关后的纯状态刷新使用
        @Volatile private var lastNode: String? = null

        @Volatile private var lastUp: String? = null

        @Volatile private var lastDown: String? = null

        // 运行状态变化时由 GlobalState 调用:停止时图标复位并把速度归零,
        // 使快捷面板/应用内开关代理后小组件立即跟随
        fun onRunStateChanged(context: Context, running: Boolean) {
            if (!running) {
                lastUp = null
                lastDown = null
            }
            render(context)
        }

        // Dart 每秒调用:直接更新全部小组件实例
        fun push(context: Context, node: String?, up: String?, down: String?) {
            lastNode = node
            lastUp = up
            lastDown = down
            render(context)
        }

        private fun render(context: Context) {
            val manager = AppWidgetManager.getInstance(context) ?: return
            val ids =
                manager.getAppWidgetIds(
                    ComponentName(context, BettboxWidgetProvider::class.java)
                )
            if (ids.isEmpty()) return

            // 开关状态取原生实时运行状态,与快速磁贴同源
            val running = GlobalState.currentRunState != RunState.STOP
            val views =
                RemoteViews(context.packageName, R.layout.bettbox_speed_widget).apply {
                    setTextViewText(
                        R.id.widget_node,
                        lastNode?.takeIf { it.isNotEmpty() } ?: "Bettbox",
                    )
                    setTextViewText(R.id.widget_up, "↑ ${lastUp ?: "0B/s"}")
                    setTextViewText(R.id.widget_down, "↓ ${lastDown ?: "0B/s"}")
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
            manager.updateAppWidget(ids, views)
        }
    }
}
