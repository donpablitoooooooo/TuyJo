package com.privatemessaging.private_messaging

import android.app.AlarmManager
import android.app.PendingIntent
import android.appwidget.AppWidgetManager
import android.appwidget.AppWidgetProvider
import android.content.ComponentName
import android.content.Context
import android.content.Intent
import android.os.Bundle
import android.util.Log
import android.view.View
import android.widget.RemoteViews
import org.json.JSONObject
import java.text.SimpleDateFormat
import java.util.Calendar
import java.util.Date
import java.util.Locale

/**
 * Widget della schermata Home.
 *
 * Non decifra nulla: legge i dati preparati dall'app (HomeWidgetService in
 * Flutter) nelle SharedPreferences di home_widget.
 * - `tuyjo_widget`: JSON con i todo, ognuno con la sua finestra di visibilità
 *   (`start`..`end`) e le etichette di data già pronte per ogni giorno.
 * - `tuyjo_unread`: numero dei messaggi non letti (lo aggiorna anche il push).
 *
 * Priorità: todo visibili adesso, poi numero dei non letti, poi "tutto letto".
 * La cornetta è sempre presente e apre l'app sulla chiamata.
 * Un allarme ridisegna il widget quando un todo compare o scade, e a
 * mezzanotte per cambiare "Domani" in "Oggi".
 */
class TuyJoWidgetProvider : AppWidgetProvider() {

    override fun onUpdate(context: Context, manager: AppWidgetManager, ids: IntArray) {
        val state = WidgetState.load(context)
        for (id in ids) render(context, manager, id, state)
        scheduleNextUpdate(context, state)
    }

    override fun onAppWidgetOptionsChanged(
        context: Context,
        manager: AppWidgetManager,
        id: Int,
        newOptions: Bundle
    ) {
        render(context, manager, id, WidgetState.load(context))
    }

    override fun onReceive(context: Context, intent: Intent) {
        super.onReceive(context, intent)
        if (intent.action == ACTION_TICK) updateAll(context)
    }

    override fun onDisabled(context: Context) {
        alarmManager(context).cancel(tickIntent(context))
    }

    private fun render(context: Context, manager: AppWidgetManager, id: Int, state: WidgetState) {
        val options = manager.getAppWidgetOptions(id)
        val minWidth = options.getInt(AppWidgetManager.OPTION_APPWIDGET_MIN_WIDTH, 250)
        val minHeight = options.getInt(AppWidgetManager.OPTION_APPWIDGET_MIN_HEIGHT, 110)
        val small = minWidth < 200
        val views = RemoteViews(
            context.packageName,
            if (small) R.layout.tuyjo_widget_small else R.layout.tuyjo_widget_medium
        )

        val now = System.currentTimeMillis()
        val todos = state.visibleTodos(now)
        val unread = state.unread

        // Il numero dei non letti resta visibile anche quando ci sono todo
        if (unread > 0 && todos.isNotEmpty()) {
            views.setViewVisibility(R.id.header_badge, View.VISIBLE)
            views.setTextViewText(R.id.header_badge, if (unread > 99) "99+" else unread.toString())
        } else {
            views.setViewVisibility(R.id.header_badge, View.GONE)
        }

        hideContent(views, small)
        when {
            todos.isNotEmpty() -> {
                views.setImageViewResource(R.id.header_icon, R.drawable.ic_widget_event)
                views.setTextViewText(R.id.header_title, state.string("todo", "To do"))
                val maxRows = if (small) 0 else if (minHeight >= 180) 4 else 2
                if (todos.size == 1 || maxRows == 0) {
                    showSingle(views, todos.first(), state, now)
                    if (todos.size > 1) {
                        views.setViewVisibility(R.id.more, View.VISIBLE)
                        views.setTextViewText(R.id.more, "+${todos.size - 1}")
                    }
                } else {
                    showList(views, todos, state, now, maxRows)
                }
            }
            unread > 0 -> {
                views.setImageViewResource(R.id.header_icon, R.drawable.ic_widget_chat)
                views.setTextViewText(R.id.header_title, state.string("partner", "My love"))
                views.setViewVisibility(R.id.big_text, View.VISIBLE)
                views.setTextViewText(
                    R.id.big_text,
                    if (unread == 1) state.string("unreadOne", "1 new message")
                    else state.string("unreadOther", "%d new messages").replace("%d", unread.toString())
                )
            }
            else -> {
                views.setImageViewResource(R.id.header_icon, R.drawable.ic_widget_favorite)
                views.setTextViewText(R.id.header_title, state.string("partner", "My love"))
                views.setViewVisibility(R.id.big_text, View.VISIBLE)
                views.setTextViewText(R.id.big_text, state.string("allRead", "All caught up"))
            }
        }

        views.setOnClickPendingIntent(R.id.widget_root, openAppIntent(context))
        views.setOnClickPendingIntent(R.id.call, callIntent(context))
        manager.updateAppWidget(id, views)
    }

    private fun hideContent(views: RemoteViews, small: Boolean) {
        views.setViewVisibility(R.id.single_title, View.GONE)
        views.setViewVisibility(R.id.single_date_row, View.GONE)
        views.setViewVisibility(R.id.single_alert, View.GONE)
        views.setViewVisibility(R.id.more, View.GONE)
        views.setViewVisibility(R.id.big_text, View.GONE)
        if (!small) {
            for (row in ROW_IDS) views.setViewVisibility(row[0], View.GONE)
        }
    }

    private fun showSingle(views: RemoteViews, todo: WidgetTodo, state: WidgetState, now: Long) {
        views.setViewVisibility(R.id.single_title, View.VISIBLE)
        views.setTextViewText(R.id.single_title, todo.text)
        views.setViewVisibility(R.id.single_date_row, View.VISIBLE)
        views.setTextViewText(R.id.single_date, todo.labelAt(now))
        if (todo.alert != null) {
            views.setViewVisibility(R.id.single_alert, View.VISIBLE)
            views.setTextViewText(R.id.single_alert, todo.alert)
        }
    }

    private fun showList(
        views: RemoteViews,
        todos: List<WidgetTodo>,
        state: WidgetState,
        now: Long,
        maxRows: Int
    ) {
        val overflow = todos.size > maxRows
        val shown = if (overflow) maxRows - 1 else todos.size
        for (i in 0 until shown) {
            val row = ROW_IDS[i]
            views.setViewVisibility(row[0], View.VISIBLE)
            views.setTextViewText(row[1], todos[i].labelAt(now))
            views.setTextViewText(row[2], todos[i].text)
        }
        if (overflow) {
            views.setViewVisibility(R.id.more, View.VISIBLE)
            views.setTextViewText(R.id.more, "+${todos.size - shown}")
        }
    }

    private fun openAppIntent(context: Context): PendingIntent {
        val intent = Intent(context, MainActivity::class.java).apply {
            action = Intent.ACTION_MAIN
            addCategory(Intent.CATEGORY_LAUNCHER)
            flags = Intent.FLAG_ACTIVITY_NEW_TASK
        }
        return PendingIntent.getActivity(
            context, 0, intent,
            PendingIntent.FLAG_UPDATE_CURRENT or PendingIntent.FLAG_IMMUTABLE
        )
    }

    private fun callIntent(context: Context): PendingIntent {
        val intent = Intent(context, MainActivity::class.java).apply {
            action = ACTION_CALL
            flags = Intent.FLAG_ACTIVITY_NEW_TASK or Intent.FLAG_ACTIVITY_SINGLE_TOP
        }
        return PendingIntent.getActivity(
            context, 1, intent,
            PendingIntent.FLAG_UPDATE_CURRENT or PendingIntent.FLAG_IMMUTABLE
        )
    }

    companion object {
        private const val TAG = "TuyJoWidget"
        const val ACTION_CALL = "com.privatemessaging.tuyjo.WIDGET_CALL"
        const val ACTION_TICK = "com.privatemessaging.tuyjo.WIDGET_TICK"

        private val ROW_IDS = arrayOf(
            intArrayOf(R.id.row1, R.id.row1_date, R.id.row1_text),
            intArrayOf(R.id.row2, R.id.row2_date, R.id.row2_text),
            intArrayOf(R.id.row3, R.id.row3_date, R.id.row3_text),
            intArrayOf(R.id.row4, R.id.row4_date, R.id.row4_text),
        )

        fun updateAll(context: Context) {
            val manager = AppWidgetManager.getInstance(context)
            val ids = manager.getAppWidgetIds(ComponentName(context, TuyJoWidgetProvider::class.java))
            if (ids.isNotEmpty()) TuyJoWidgetProvider().onUpdate(context, manager, ids)
        }

        private fun alarmManager(context: Context) =
            context.getSystemService(Context.ALARM_SERVICE) as AlarmManager

        private fun tickIntent(context: Context): PendingIntent {
            val intent = Intent(context, TuyJoWidgetProvider::class.java).apply { action = ACTION_TICK }
            return PendingIntent.getBroadcast(
                context, 2, intent,
                PendingIntent.FLAG_UPDATE_CURRENT or PendingIntent.FLAG_IMMUTABLE
            )
        }

        /**
         * Prossimo momento in cui il widget cambia: un todo che compare o scade,
         * oppure la mezzanotte se c'è un todo visibile con etichette giornaliere.
         * Allarme non esatto: non serve il permesso SCHEDULE_EXACT_ALARM e
         * qualche minuto di ritardo va bene.
         */
        private fun scheduleNextUpdate(context: Context, state: WidgetState) {
            val now = System.currentTimeMillis()
            var next = Long.MAX_VALUE
            for (todo in state.todos) {
                if (todo.start > now) next = minOf(next, todo.start)
                if (todo.end > now) next = minOf(next, todo.end)
            }
            if (state.visibleTodos(now).any { it.labels.isNotEmpty() }) {
                next = minOf(next, nextMidnight(now))
            }
            val manager = alarmManager(context)
            val pending = tickIntent(context)
            if (next == Long.MAX_VALUE) {
                manager.cancel(pending)
                return
            }
            try {
                manager.setAndAllowWhileIdle(AlarmManager.RTC, next + 1000, pending)
            } catch (e: Exception) {
                Log.e(TAG, "Alarm not scheduled: ${e.message}")
            }
        }

        private fun nextMidnight(now: Long): Long {
            val cal = Calendar.getInstance().apply {
                timeInMillis = now
                add(Calendar.DAY_OF_YEAR, 1)
                set(Calendar.HOUR_OF_DAY, 0)
                set(Calendar.MINUTE, 0)
                set(Calendar.SECOND, 0)
                set(Calendar.MILLISECOND, 0)
            }
            return cal.timeInMillis
        }
    }
}

/** Un todo come lo prepara l'app. */
data class WidgetTodo(
    val text: String,
    val due: Long,
    val start: Long,
    val end: Long,
    val alert: String?,
    val label: String,
    val labels: Map<String, String>,
) {
    fun labelAt(now: Long): String {
        val key = SimpleDateFormat("yyyy-MM-dd", Locale.US).format(Date(now))
        return labels[key] ?: label
    }
}

/** Dati salvati da HomeWidgetService (vedi lib/services/home_widget_service.dart). */
class WidgetState(
    val todos: List<WidgetTodo>,
    val unread: Int,
    private val strings: Map<String, String>,
) {
    fun visibleTodos(now: Long): List<WidgetTodo> =
        todos.filter { it.start <= now && now < it.end }.sortedBy { it.due }

    fun string(key: String, fallback: String): String = strings[key] ?: fallback

    companion object {
        private const val PREFERENCES = "HomeWidgetPreferences"

        fun load(context: Context): WidgetState {
            val prefs = context.getSharedPreferences(PREFERENCES, Context.MODE_PRIVATE)
            val unread = prefs.getString("tuyjo_unread", null)?.toIntOrNull() ?: 0
            val raw = prefs.getString("tuyjo_widget", null) ?: return WidgetState(emptyList(), unread, emptyMap())
            return try {
                val json = JSONObject(raw)
                val strings = mutableMapOf<String, String>()
                json.optJSONObject("strings")?.let { obj ->
                    for (key in obj.keys()) strings[key] = obj.getString(key)
                }
                val todos = mutableListOf<WidgetTodo>()
                val array = json.optJSONArray("todos")
                if (array != null) {
                    for (i in 0 until array.length()) {
                        val item = array.getJSONObject(i)
                        val labels = mutableMapOf<String, String>()
                        item.optJSONObject("labels")?.let { obj ->
                            for (key in obj.keys()) labels[key] = obj.getString(key)
                        }
                        todos.add(
                            WidgetTodo(
                                text = item.optString("text"),
                                due = item.getLong("due"),
                                start = item.getLong("start"),
                                end = item.getLong("end"),
                                alert = if (item.has("alert")) item.getString("alert") else null,
                                label = item.optString("label"),
                                labels = labels,
                            )
                        )
                    }
                }
                WidgetState(todos, unread, strings)
            } catch (e: Exception) {
                Log.e("TuyJoWidget", "Widget data unreadable: ${e.message}")
                WidgetState(emptyList(), unread, emptyMap())
            }
        }
    }
}
