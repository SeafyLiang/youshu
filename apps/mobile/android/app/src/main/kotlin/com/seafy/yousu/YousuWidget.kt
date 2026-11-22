package com.seafy.yousu

import android.app.PendingIntent
import android.appwidget.AppWidgetManager
import android.appwidget.AppWidgetProvider
import android.content.ComponentName
import android.content.Context
import android.content.Intent
import android.net.Uri
import android.widget.RemoteViews

class YousuWidget : AppWidgetProvider() {
    override fun onUpdate(context: Context, manager: AppWidgetManager, ids: IntArray) { render(context, manager, ids) }
    companion object {
        fun updateAll(context: Context) {
            val manager = AppWidgetManager.getInstance(context)
            render(context, manager, manager.getAppWidgetIds(ComponentName(context, YousuWidget::class.java)))
        }
        private fun render(context: Context, manager: AppWidgetManager, ids: IntArray) {
            val prefs = context.getSharedPreferences("yousu_widget", Context.MODE_PRIVATE)
            for (id in ids) {
                val view = RemoteViews(context.packageName, R.layout.yousu_widget)
                view.setTextViewText(R.id.ledger, "有数 · " + prefs.getString("ledger", "日常账本"))
                view.setTextViewText(R.id.expense, prefs.getString("expense", "CNY 0.00"))
                view.setTextViewText(R.id.remaining, "预算剩余 " + prefs.getString("remaining", "未设预算"))
                view.setTextViewText(R.id.updated, "更新 " + (prefs.getString("updated", "打开 App 后更新") ?: "").take(16).replace("T", " "))
                view.setTextViewText(R.id.period, prefs.getString("period", "打开 App 更新账期"))
                val intent = Intent(context, MainActivity::class.java).setAction(Intent.ACTION_VIEW).setData(Uri.parse("youshu://record"))
                val pending = PendingIntent.getActivity(context, 0, intent, PendingIntent.FLAG_UPDATE_CURRENT or PendingIntent.FLAG_IMMUTABLE)
                view.setOnClickPendingIntent(R.id.widget_root, pending)
                manager.updateAppWidget(id, view)
            }
        }
    }
}
