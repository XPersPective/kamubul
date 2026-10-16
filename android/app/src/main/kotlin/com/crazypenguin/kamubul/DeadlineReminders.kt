package com.crazypenguin.kamubul

import android.Manifest
import android.app.AlarmManager
import android.app.NotificationChannel
import android.app.NotificationManager
import android.app.PendingIntent
import android.content.BroadcastReceiver
import android.content.Context
import android.content.Intent
import android.content.pm.PackageManager
import android.net.Uri
import android.os.Build
import android.util.AtomicFile
import androidx.core.app.NotificationCompat
import org.json.JSONArray
import org.json.JSONObject
import java.io.File
import java.time.Instant
import java.time.ZoneId
import java.time.format.DateTimeFormatter

// Only public listing metadata; no backup, network, profile or FCM token.
object DeadlineReminders {
    const val TAP = "kamubul_deadline_url"
    private const val CHANNEL = "kamubul_deadlines"
    private const val TAG = "kamubul.deadline"
    private val zone = ZoneId.of("Europe/Istanbul")
    private fun file(c: Context) = AtomicFile(File(c.noBackupFilesDir, "deadline-reminders.v1"))
    private fun read(c: Context): JSONObject {
        val f = file(c)
        if (!f.baseFile.exists() && !File(f.baseFile.path + ".bak").exists())
            return JSONObject().put("version", 1).put("enabled", false).put("nextId", 1)
                .put("plans", JSONArray()).put("sent", JSONArray())
        require(f.baseFile.length() <= 1048576 && File(f.baseFile.path + ".bak").length() <= 1048576)
        return JSONObject(String(f.readFully(), Charsets.UTF_8)).also { require(it.getInt("version") == 1) }
    }
    private fun write(c: Context, state: JSONObject) {
        val bytes = state.toString().toByteArray(Charsets.UTF_8)
        require(bytes.size <= 1048576)
        val f = file(c)
        val out = f.startWrite()
        try { out.write(bytes); f.finishWrite(out) }
        catch (e: Exception) { f.failWrite(out); throw e }
    }
    private fun items(a: JSONArray) = (0 until a.length()).map { a.getJSONObject(it) }
    private fun key(p: JSONObject) = p.getString("url") + "|" + p.getLong("expires")
    private fun manager(c: Context) = c.getSystemService(NotificationManager::class.java)
    private fun allowed(c: Context): Boolean =
        (Build.VERSION.SDK_INT < 33 || c.checkSelfPermission(Manifest.permission.POST_NOTIFICATIONS) == PackageManager.PERMISSION_GRANTED) &&
            (Build.VERSION.SDK_INT < 24 || manager(c).areNotificationsEnabled()) &&
            (Build.VERSION.SDK_INT < 26 || manager(c).getNotificationChannel(CHANNEL)?.importance != NotificationManager.IMPORTANCE_NONE)
    private fun intent(c: Context, p: JSONObject) = PendingIntent.getBroadcast(
        c, p.getInt("id"), Intent(c, DeadlineReminderReceiver::class.java)
            .setData(Uri.parse("kamubul://deadline/" + p.getInt("id")))
            .putExtra("id", p.getInt("id")), PendingIntent.FLAG_UPDATE_CURRENT or PendingIntent.FLAG_IMMUTABLE)
    private fun cancel(c: Context, p: JSONObject) {
        c.getSystemService(AlarmManager::class.java).cancel(intent(c, p))
        manager(c).cancel(TAG, p.getInt("id"))
    }
    private fun schedule(c: Context, p: JSONObject, at: Long = p.getLong("at")) {
        if (p.getLong("expires") > System.currentTimeMillis())
            c.getSystemService(AlarmManager::class.java).setAndAllowWhileIdle(
                AlarmManager.RTC_WAKEUP, maxOf(at, System.currentTimeMillis() + 1000), intent(c, p))
    }

    @Synchronized fun sync(c: Context, raw: List<*>, enabled: Boolean?): Boolean {
        // ponytail: platform ceiling is 500 pending alarms; batching is the upgrade path.
        val old = read(c)
        val on = enabled ?: (old.getBoolean("enabled") && allowed(c))
        require(!on || raw.size <= 500) { "too_many_reminders" }
        require(!on || allowed(c)) { "notification_permission_required" }
        val now = System.currentTimeMillis()
        val previous = items(old.getJSONArray("plans"))
        val byKey = previous.associateBy(::key)
        val sent = items(old.getJSONArray("sent")).filter { it.getLong("expires") > now }
        val sentKeys = sent.map(::key).toSet()
        var nextId = old.getInt("nextId")
        val plans = if (!on) emptyList() else raw.map { entry ->
            require(entry is Map<*, *>)
            val url = entry["url"] as? String ?: error("url")
            val title = entry["title"] as? String ?: error("title")
            val at = (entry["at"] as? Number)?.toLong() ?: error("at")
            val expires = (entry["expires"] as? Number)?.toLong() ?: error("expires")
            val uri = Uri.parse(url)
            require(url.length <= 2000 && uri.scheme == "https" && !uri.host.isNullOrBlank() && uri.userInfo == null)
            require(title.isNotBlank() && title.length <= 2000 && at > 0 && expires > at && expires <= now + 3155760000000L)
            JSONObject().put("url", url).put("title", title).put("at", at).put("expires", expires)
        }.filter { it.getLong("expires") > now && key(it) !in sentKeys }.distinctBy(::key).map { p ->
            val existing = byKey[key(p)]
            if (existing != null) p.put("id", existing.getInt("id")).put("at", existing.getLong("at"))
            else { require(nextId in 1 until Int.MAX_VALUE); p.put("id", nextId++) }
            p
        }
        val state = JSONObject().put("version", 1).put("enabled", on).put("nextId", nextId)
            .put("plans", JSONArray(plans)).put("sent", JSONArray(sent))
        // Durable desired state first: a stale alarm cannot pass receiver validation.
        write(c, state)
        previous.forEach { cancel(c, it) }
        if (!on) manager(c).cancelAllOwnReminders()
        plans.forEach { schedule(c, it) }
        return on
    }

    private fun NotificationManager.cancelAllOwnReminders() {
        if (Build.VERSION.SDK_INT >= 23) activeNotifications.filter { it.tag == TAG }.forEach { cancel(TAG, it.id) }
    }
    @Synchronized fun enabled(c: Context) = read(c).getBoolean("enabled")
    @Synchronized fun restore(c: Context) {
        val state = read(c)
        if (state.getBoolean("enabled") && allowed(c)) items(state.getJSONArray("plans")).forEach { schedule(c, it) }
    }
    @Synchronized fun deliver(c: Context, id: Int) {
        val state = read(c)
        if (!state.getBoolean("enabled") || !allowed(c)) return
        val plans = items(state.getJSONArray("plans"))
        val p = plans.find { it.getInt("id") == id } ?: return
        val now = System.currentTimeMillis()
        val expiry = p.getLong("expires")
        if (now < p.getLong("at")) { schedule(c, p); return }
        if (now >= expiry) { cancel(c, p); return }
        val wall = Instant.ofEpochMilli(now).atZone(zone)
        if (wall.hour < 8 || wall.hour >= 22) {
            val next = wall.toLocalDate().plusDays(if (wall.hour >= 22) 1 else 0).atTime(8, 0).atZone(zone).toInstant().toEpochMilli()
            if (next < expiry) schedule(c, p, next) else cancel(c, p)
            return
        }
        // Persist consumption before display; delivery remains best effort on process death.
        state.put("plans", JSONArray(plans.filter { it.getInt("id") != id }))
        state.getJSONArray("sent").put(JSONObject().put("url", p.getString("url")).put("expires", expiry))
        write(c, state)
        if (Build.VERSION.SDK_INT >= 26) manager(c).createNotificationChannel(
            NotificationChannel(CHANNEL, "Son başvuru hatırlatmaları", NotificationManager.IMPORTANCE_DEFAULT))
        val tap = PendingIntent.getActivity(c, id, Intent(c, MainActivity::class.java)
            .setAction("kamubul.DEADLINE").putExtra(TAP, p.getString("url"))
            .addFlags(Intent.FLAG_ACTIVITY_CLEAR_TOP or Intent.FLAG_ACTIVITY_SINGLE_TOP),
            PendingIntent.FLAG_UPDATE_CURRENT or PendingIntent.FLAG_IMMUTABLE)
        val date = Instant.ofEpochMilli(expiry).atZone(zone).format(DateTimeFormatter.ofPattern("dd.MM.yyyy HH:mm"))
        manager(c).notify(TAG, id, NotificationCompat.Builder(c, CHANNEL)
            .setSmallIcon(R.drawable.ic_stat_kamubul).setContentTitle("Son başvuru: $date")
            .setContentText(p.getString("title")).setStyle(NotificationCompat.BigTextStyle().bigText(p.getString("title")))
            .setContentIntent(tap).setAutoCancel(true).setOnlyAlertOnce(true).build())
    }
}

class DeadlineReminderReceiver : BroadcastReceiver() {
    override fun onReceive(context: Context, intent: Intent) {
        try { DeadlineReminders.deliver(context, intent.getIntExtra("id", -1)) }
        catch (_: Exception) { /* Fail closed; next app sync reports durable-state errors. */ }
    }
}
class DeadlineReminderBootReceiver : BroadcastReceiver() {
    override fun onReceive(context: Context, intent: Intent) {
        if (intent.action !in setOf(Intent.ACTION_BOOT_COMPLETED, Intent.ACTION_MY_PACKAGE_REPLACED, Intent.ACTION_TIME_CHANGED, Intent.ACTION_TIMEZONE_CHANGED)) return
        try { DeadlineReminders.restore(context) }
        catch (_: Exception) { /* No notification from unverified state. */ }
    }
}
