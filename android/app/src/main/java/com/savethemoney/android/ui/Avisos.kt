package com.savethemoney.android.ui

import android.app.AlarmManager
import android.app.Notification
import android.app.NotificationChannel
import android.app.NotificationManager
import android.app.PendingIntent
import android.content.BroadcastReceiver
import android.content.Context
import android.content.Intent
import android.net.Uri
import com.savethemoney.android.MainActivity
import com.savethemoney.android.R
import com.savethemoney.android.data.BudgetAlert
import com.savethemoney.android.data.Notifier
import com.savethemoney.android.data.PlannedReminder
import kotlinx.serialization.encodeToString
import kotlinx.serialization.json.Json
import java.time.LocalDate
import java.time.ZoneId

/**
 * Avisos locales con AlarmManager. Lo pendiente se guarda porque Android no deja listar
 * las alarmas ni las conserva al reiniciar. Sin permiso de notificaciones, no se ve nada.
 */
class LocalNotifier(private val context: Context) : Notifier {
    private val prefs get() = context.getSharedPreferences("avisos", Context.MODE_PRIVATE)
    private val alarms get() = context.getSystemService(AlarmManager::class.java)

    override var enabled: Boolean
        get() = prefs.getBoolean(KEY_ENABLED, true)
        set(value) = prefs.edit().putBoolean(KEY_ENABLED, value).apply()

    override fun replaceReminders(reminders: List<PlannedReminder>, prefix: String) {
        val (old, others) = pending().partition { !enabled || it.id.startsWith(prefix) }
        old.forEach { alarms.cancel(alarm(it)) }
        prefs.edit().putString(KEY_PENDING, Json.encodeToString(if (enabled) others + reminders else emptyList())).apply()
        arm()
    }

    /** Programa lo guardado; al reiniciar el teléfono lo llama [AvisosReceiver]. */
    fun arm() {
        val now = System.currentTimeMillis()
        for (reminder in pending()) {
            val at = LocalDate.parse(reminder.fireOn).atTime(reminder.hour, 0).atZone(ZoneId.systemDefault()).toInstant().toEpochMilli()
            // Inexacta a propósito: un aviso a las 9:00 no necesita el permiso de alarma exacta.
            if (at > now) alarms.setAndAllowWhileIdle(AlarmManager.RTC_WAKEUP, at, alarm(reminder))
        }
    }

    override fun budgetAlerts(alerts: List<BudgetAlert>) {
        if (!enabled) return
        val sent = prefs.getStringSet(KEY_SENT, emptySet()).orEmpty().toMutableSet()
        val fresh = alerts.filter { it.id !in sent }
        if (fresh.isEmpty()) return
        fresh.forEach {
            show(it.id, it.title, it.body)
            sent += it.id
        }
        // Sólo los últimos, para que la lista no crezca sin fin.
        prefs.edit().putStringSet(KEY_SENT, sent.sorted().takeLast(300).toSet()).apply()
    }

    fun show(id: String, title: String, body: String) {
        val manager = context.getSystemService(NotificationManager::class.java)
        manager.createNotificationChannel(NotificationChannel(CHANNEL, "Avisos", NotificationManager.IMPORTANCE_DEFAULT))
        val open = PendingIntent.getActivity(
            context, 0, Intent(context, MainActivity::class.java), PendingIntent.FLAG_IMMUTABLE or PendingIntent.FLAG_UPDATE_CURRENT,
        )
        manager.notify(
            id.hashCode(),
            Notification.Builder(context, CHANNEL).setSmallIcon(R.drawable.ic_launcher_foreground).setContentTitle(title)
                .setContentText(body).setStyle(Notification.BigTextStyle().bigText(body)).setContentIntent(open).setAutoCancel(true).build(),
        )
    }

    private fun pending(): List<PlannedReminder> =
        prefs.getString(KEY_PENDING, null)?.let { runCatching { Json.decodeFromString<List<PlannedReminder>>(it) }.getOrNull() }.orEmpty()

    private fun alarm(reminder: PlannedReminder): PendingIntent {
        val intent = Intent(context, AvisosReceiver::class.java).setData(Uri.fromParts("aviso", reminder.id, null))
            .putExtra(EXTRA_TITLE, reminder.title).putExtra(EXTRA_BODY, reminder.body)
        return PendingIntent.getBroadcast(context, 0, intent, PendingIntent.FLAG_IMMUTABLE or PendingIntent.FLAG_UPDATE_CURRENT)
    }

    companion object {
        private const val CHANNEL = "avisos"
        private const val KEY_ENABLED = "activos"
        private const val KEY_PENDING = "pendientes"
        private const val KEY_SENT = "enviados"
        const val EXTRA_TITLE = "titulo"
        const val EXTRA_BODY = "cuerpo"
    }
}

class AvisosReceiver : BroadcastReceiver() {
    override fun onReceive(context: Context, intent: Intent) {
        val notifier = LocalNotifier(context)
        if (intent.action == Intent.ACTION_BOOT_COMPLETED) {
            notifier.arm()
        } else {
            notifier.show(intent.data?.schemeSpecificPart.orEmpty(), intent.getStringExtra(LocalNotifier.EXTRA_TITLE).orEmpty(), intent.getStringExtra(LocalNotifier.EXTRA_BODY).orEmpty())
        }
    }
}
