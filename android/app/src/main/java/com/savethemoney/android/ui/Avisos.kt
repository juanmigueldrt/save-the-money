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
import androidx.core.content.edit
import com.savethemoney.android.MainActivity
import com.savethemoney.android.R
import com.savethemoney.android.data.BudgetAlert
import com.savethemoney.android.data.HabitReminderPlanner
import com.savethemoney.android.data.HabitSettings
import com.savethemoney.android.data.Notifier
import com.savethemoney.android.data.PlannedReminder
import kotlinx.serialization.encodeToString
import kotlinx.serialization.json.Json
import java.time.LocalDate
import java.time.LocalDateTime
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

    // Antes había un solo interruptor: si estaba apagado, los límites también empiezan apagados.
    override var budgetAlertsEnabled: Boolean
        get() = prefs.getBoolean(KEY_BUDGET, prefs.getBoolean(KEY_ENABLED, true))
        set(value) = prefs.edit().putBoolean(KEY_BUDGET, value).apply()

    override var habits: HabitSettings
        get() = HabitSettings(
            HabitSettings.LogReminder.entries.firstOrNull { it.name == prefs.getString(KEY_LOG, null) } ?: HabitSettings.LogReminder.Off,
            prefs.getInt(KEY_LOG_HOUR, 21), prefs.getBoolean(KEY_WEEKLY, true),
        )
        set(value) = prefs.edit().putString(KEY_LOG, value.logReminder.name).putInt(KEY_LOG_HOUR, value.logHour)
            .putBoolean(KEY_WEEKLY, value.weeklySummary).apply()

    override fun replaceReminders(reminders: List<PlannedReminder>, prefix: String) {
        // Los de hábito tienen sus propios interruptores; el resto, el de «Avisos de pagos fijos».
        val habit = prefix == HabitReminderPlanner.PREFIX
        val (old, others) = pending().partition {
            it.id.startsWith(prefix) || (!enabled && !habit && !it.id.startsWith(HabitReminderPlanner.PREFIX))
        }
        old.forEach { alarms.cancel(alarm(it)) }
        prefs.edit().putString(KEY_PENDING, Json.encodeToString(others + if (enabled || habit) reminders else emptyList())).apply()
        arm()
    }

    /**
     * Programa lo guardado y muestra ya lo de hoy cuya hora ha pasado. [AvisosReceiver] lo llama al reiniciar
     * el teléfono, al actualizar la app y al cambiar la hora o la zona horaria.
     */
    fun arm() {
        val (due, later) = split(pending(), shown(), LocalDateTime.now())
        for (reminder in later) {
            val at = reminder.at().atZone(ZoneId.systemDefault()).toInstant().toEpochMilli()
            // Inexacta a propósito: un aviso a las 9:00 no necesita el permiso de alarma exacta.
            alarms.setAndAllowWhileIdle(AlarmManager.RTC_WAKEUP, at, alarm(reminder))
        }
        due.forEach { showReminder(it.id, it.title, it.body) }
    }

    /** Muestra un aviso programado una sola vez; si Android no deja mostrarlo, sigue pendiente para el próximo [arm]. */
    fun showReminder(id: String, title: String, body: String) {
        if (id in shown() || !show(id, title, body)) return
        // Sólo los que siguen pendientes, para que la lista no crezca sin fin.
        val ids = pending().mapTo(mutableSetOf()) { it.id }
        prefs.edit { putStringSet(KEY_SHOWN, (shown() + id).filterTo(mutableSetOf()) { it in ids }) }
    }

    override fun budgetAlerts(alerts: List<BudgetAlert>) {
        if (!budgetAlertsEnabled) return
        val sent = prefs.getStringSet(KEY_SENT, emptySet()).orEmpty()
        val updated = sendAlerts(alerts, sent) { show(it.id, it.title, it.body) }
        if (updated == sent) return
        // Sólo los últimos, para que la lista no crezca sin fin.
        prefs.edit { putStringSet(KEY_SENT, updated.sorted().takeLast(300).toSet()) }
    }

    /** Sin permiso de notificaciones (Android 13+) o con los avisos de la app apagados en Ajustes, no se ve nada. */
    val canShow: Boolean
        get() = context.getSystemService(NotificationManager::class.java).let {
            it.areNotificationsEnabled() && it.getNotificationChannel(CHANNEL)?.importance != NotificationManager.IMPORTANCE_NONE
        }

    /** Devuelve false si Android no deja mostrarla. */
    fun show(id: String, title: String, body: String): Boolean {
        val manager = context.getSystemService(NotificationManager::class.java)
        manager.createNotificationChannel(NotificationChannel(CHANNEL, "Avisos", NotificationManager.IMPORTANCE_DEFAULT))
        if (!canShow) return false
        val open = PendingIntent.getActivity(
            context, 0, Intent(context, MainActivity::class.java), PendingIntent.FLAG_IMMUTABLE or PendingIntent.FLAG_UPDATE_CURRENT,
        )
        manager.notify(
            id.hashCode(),
            Notification.Builder(context, CHANNEL).setSmallIcon(R.drawable.ic_launcher_foreground).setContentTitle(title)
                .setContentText(body).setStyle(Notification.BigTextStyle().bigText(body)).setContentIntent(open).setAutoCancel(true).build(),
        )
        return true
    }

    private fun shown(): Set<String> = prefs.getStringSet(KEY_SHOWN, emptySet()).orEmpty()

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
        private const val KEY_BUDGET = "limites"
        private const val KEY_PENDING = "pendientes"
        private const val KEY_SENT = "enviados"
        private const val KEY_SHOWN = "mostrados"
        private const val KEY_LOG = "habito_apuntar"
        private const val KEY_LOG_HOUR = "habito_hora"
        private const val KEY_WEEKLY = "habito_semanal"
        const val EXTRA_TITLE = "titulo"
        const val EXTRA_BODY = "cuerpo"

        /**
         * Separa lo pendiente en lo que hay que mostrar ya (hoy, con la hora pasada) y lo que hay que programar.
         * Lo ya mostrado y lo de días anteriores se descarta: Android no avisa de lo que se perdió con el teléfono apagado.
         */
        internal fun split(
            pending: List<PlannedReminder>,
            shown: Set<String>,
            now: LocalDateTime,
        ): Pair<List<PlannedReminder>, List<PlannedReminder>> = pending
            .filter { it.id !in shown && !LocalDate.parse(it.fireOn).isBefore(now.toLocalDate()) }
            .partition { !it.at().isAfter(now) }

        /** Devuelve los ids enviados más los de las alertas que [show] ha podido mostrar; las demás se reintentan. */
        internal fun sendAlerts(alerts: List<BudgetAlert>, sent: Set<String>, show: (BudgetAlert) -> Boolean): Set<String> =
            sent + alerts.filter { it.id !in sent && show(it) }.map { it.id }

        private fun PlannedReminder.at(): LocalDateTime = LocalDate.parse(fireOn).atTime(hour, 0)
    }
}

class AvisosReceiver : BroadcastReceiver() {
    override fun onReceive(context: Context, intent: Intent) {
        val notifier = LocalNotifier(context)
        when (intent.action) {
            // Android borra las alarmas al reiniciar; al actualizar la app o cambiar la zona, la hora local se recalcula.
            Intent.ACTION_BOOT_COMPLETED, Intent.ACTION_MY_PACKAGE_REPLACED, Intent.ACTION_TIMEZONE_CHANGED, Intent.ACTION_TIME_CHANGED ->
                notifier.arm()
            else -> notifier.showReminder(intent.data?.schemeSpecificPart.orEmpty(), intent.getStringExtra(LocalNotifier.EXTRA_TITLE).orEmpty(), intent.getStringExtra(LocalNotifier.EXTRA_BODY).orEmpty())
        }
    }
}
