package com.crosslink.crosslink

import android.Manifest
import android.app.NotificationChannel
import android.app.NotificationManager
import android.app.PendingIntent
import android.content.Intent
import android.content.pm.PackageManager
import android.net.Uri
import android.os.Build
import android.provider.OpenableColumns
import androidx.core.app.NotificationCompat
import io.flutter.embedding.android.FlutterActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.MethodChannel
import java.io.File
import java.util.UUID
import java.util.concurrent.Executors

class MainActivity : FlutterActivity() {
    private var channel: MethodChannel? = null
    private var pendingShare: Map<String, Any>? = null
    private val worker = Executors.newSingleThreadExecutor()
    override fun configureFlutterEngine(engine: FlutterEngine) {
        super.configureFlutterEngine(engine)
        channel = MethodChannel(engine.dartExecutor.binaryMessenger, "crosslink/native")
        channel!!.setMethodCallHandler { call, result ->
            when (call.method) {
                "getInitialShare" -> { result.success(pendingShare); pendingShare = null }
                "clearShares" -> { File(cacheDir, "crosslink-shares").listFiles()?.forEach { it.delete() }; result.success(null) }
                "requestNotifications" -> {
                    if (Build.VERSION.SDK_INT >= 33 && checkSelfPermission(Manifest.permission.POST_NOTIFICATIONS) != PackageManager.PERMISSION_GRANTED) {
                        requestPermissions(arrayOf(Manifest.permission.POST_NOTIFICATIONS), 102)
                    }
                    result.success(null)
                }
                "notify" -> {
                    try { notifyUser(call.argument<String>("title") ?: "CrossLink", call.argument<String>("content") ?: "收到新内容"); result.success(null) }
                    catch (e: Exception) { result.error("NOTIFICATION_FAILED", "Unable to display notification", null) }
                }
                "openFile" -> {
                    try {
                        val value = call.argument<String>("path") ?: ""
                        val uri = Uri.parse(value)
                        startActivity(Intent(Intent.ACTION_VIEW).setDataAndType(uri, contentResolver.getType(uri) ?: "application/octet-stream").addFlags(Intent.FLAG_GRANT_READ_URI_PERMISSION))
                        result.success(true)
                    } catch(e: Exception) { result.success(false) }
                }
                else -> result.notImplemented()
            }
        }
        receiveShare(intent)
    }
    override fun onNewIntent(intent: Intent) { super.onNewIntent(intent); setIntent(intent); receiveShare(intent) }
    @Suppress("DEPRECATION")
    private fun receiveShare(intent: Intent) {
        if (intent.action != Intent.ACTION_SEND && intent.action != Intent.ACTION_SEND_MULTIPLE) return
        val text = intent.getCharSequenceExtra(Intent.EXTRA_TEXT)?.toString()
        val uris = if (intent.action == Intent.ACTION_SEND_MULTIPLE) intent.getParcelableArrayListExtra<Uri>(Intent.EXTRA_STREAM) ?: arrayListOf()
                   else arrayListOf<Uri>().also { intent.getParcelableExtra<Uri>(Intent.EXTRA_STREAM)?.let(it::add) }
        worker.execute {
            try {
                require(uris.size <= 20)
                val directory = File(cacheDir, "crosslink-shares"); directory.mkdirs()
                directory.listFiles()?.filter { it.lastModified() < System.currentTimeMillis() - 86400000 }?.forEach { it.delete() }
                val files = uris.map { uri ->
                    var name = "shared-file"
                    contentResolver.query(uri, arrayOf(OpenableColumns.DISPLAY_NAME), null, null, null)?.use { cursor ->
                        if (cursor.moveToFirst()) name = cursor.getString(0) ?: name
                    }
                    val local = File(directory, UUID.randomUUID().toString())
                    try {
                        contentResolver.openInputStream(uri)?.use { input ->
                            local.outputStream().use { output ->
                                val buffer = ByteArray(65536); var total = 0L
                                while (true) { val count = input.read(buffer); if (count < 0) break; total += count; require(total <= 104857600); output.write(buffer, 0, count) }
                            }
                        } ?: throw IllegalArgumentException("Unreadable shared file")
                    } catch (e: Exception) { local.delete(); throw e }
                    mapOf("path" to local.absolutePath, "name" to name)
                }
                val share = mutableMapOf<String, Any>("files" to files)
                if (text != null) share["text"] = text
                runOnUiThread { pendingShare = share; channel?.invokeMethod("share", share) }
            } catch (e: Exception) {
                runOnUiThread { channel?.invokeMethod("share", mapOf("error" to "分享文件读取失败：单个文件最大 100 MB，最多 20 个文件")) }
            }
        }
    }
    private fun notifyUser(title: String, content: String) {
        val manager = getSystemService(NOTIFICATION_SERVICE) as NotificationManager
        if (Build.VERSION.SDK_INT >= 26) manager.createNotificationChannel(NotificationChannel("crosslink", "CrossLink 消息", NotificationManager.IMPORTANCE_DEFAULT))
        val launch = PendingIntent.getActivity(this, 0, Intent(this, MainActivity::class.java).addFlags(Intent.FLAG_ACTIVITY_SINGLE_TOP), PendingIntent.FLAG_IMMUTABLE or PendingIntent.FLAG_UPDATE_CURRENT)
        val notification = NotificationCompat.Builder(this, "crosslink").setSmallIcon(R.mipmap.ic_launcher).setContentTitle(title).setContentText(content.take(200)).setStyle(NotificationCompat.BigTextStyle().bigText(content.take(1000))).setContentIntent(launch).setAutoCancel(true).build()
        manager.notify((System.currentTimeMillis() % Int.MAX_VALUE).toInt(), notification)
    }
}
