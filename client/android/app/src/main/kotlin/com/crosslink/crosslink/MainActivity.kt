package com.crosslink.crosslink

import android.Manifest
import android.app.NotificationChannel
import android.app.NotificationManager
import android.app.PendingIntent
import android.content.Intent
import android.content.pm.PackageManager
import android.net.Uri
import android.os.Build
import androidx.core.content.ContextCompat
import org.json.JSONObject
import android.provider.OpenableColumns
import androidx.core.app.NotificationCompat
import io.flutter.embedding.android.FlutterActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.MethodChannel
import java.io.File
import java.util.UUID
import java.util.concurrent.Executors

class MainActivity : FlutterActivity() {
    private var clipboardBridge: NativeClipboardBridge? = null
    private var eventListener: ((JSONObject) -> Unit)? = null
    private var channel: MethodChannel? = null
    private var pendingShare: Map<String, Any>? = null
    private var saveResult: MethodChannel.Result? = null
    private var saveInput: File? = null
    private val worker = Executors.newSingleThreadExecutor()
    override fun configureFlutterEngine(engine: FlutterEngine) {
        super.configureFlutterEngine(engine)
        channel = MethodChannel(engine.dartExecutor.binaryMessenger, "crosslink/native")
        clipboardBridge = NativeClipboardBridge(this) { method, value -> channel?.invokeMethod(method, value) }
        eventListener = { value -> runOnUiThread { channel?.invokeMethod("backgroundEvent", value.toString()) } }
        SyncService.listener = eventListener
        channel!!.setMethodCallHandler { call, result ->
            when (call.method) {
                "clipboardWatch" -> result.success(clipboardBridge?.watch(call.argument<Boolean>("enabled") ?: false, call.argument<String>("owner") ?: ""))
                "clipboardRead" -> result.success(clipboardBridge?.snapshot(call.argument<String>("owner") ?: ""))
                "clipboardWrite" -> result.success(clipboardBridge?.write(call.argument<String>("owner") ?: "", call.argument<String>("text") ?: "", call.argument<Number>("expected_sequence")?.toLong() ?: -1) ?: false)
                "backgroundSnapshot" -> {
                    worker.execute {
                        try {
                            val snapshot = SyncService.client?.let { client ->
                                val persisted = SessionStore.read(this)
                                persisted?.put("tokens", client.snapshot())?.put("connection", client.connectionSnapshot())
                            } ?: SessionStore.read(this)?.put("connection", JSONObject().put("state", "stopped").put("revision", 0))
                            runOnUiThread { result.success(snapshot?.toString()) }
                        } catch (_: Exception) { runOnUiThread { result.error("SESSION_STORAGE", "Session storage unavailable", null) } }
                    }
                }
                "backgroundStart" -> {
                    val endpoint = call.argument<String>("endpoint") ?: ""
                    val tokens = call.argument<String>("tokens") ?: ""
                    worker.execute {
                        try {
                            require(endpoint.startsWith("https://"))
                            val existing = SyncService.client
                            val persisted = SessionStore.read(this)
                            if (persisted?.optBoolean("paused",false) == true) {
                                val current=JSONObject(persisted.toString()).put("connection",JSONObject().put("state","paused").put("revision",0))
                                runOnUiThread { result.success(current.toString()) };return@execute
                            }
                            if (existing != null && persisted?.optString("endpoint") == endpoint &&
                                existing.snapshot().optString("device_id") == JSONObject(tokens).optString("device_id")) {
                                val current = JSONObject(persisted!!.toString()).put("tokens", existing.snapshot()).put("connection", existing.connectionSnapshot()).toString()
                                runOnUiThread { result.success(current) }
                                return@execute
                            }
                            val owner = UUID.randomUUID().toString()
                            val next=BackgroundSession.resume(JSONObject().put("endpoint",endpoint).put("tokens",JSONObject(tokens)),owner)
                            val owned=next.getJSONObject("tokens")
                            SessionStore.save(this,next)
                            runOnUiThread {
                                try {
                                    ContextCompat.startForegroundService(this, Intent(this, SyncService::class.java).putExtra("replace", true))
                                    result.success(JSONObject().put("endpoint", endpoint).put("owner", owner).put("tokens", owned).put("connection", JSONObject().put("state", "connecting").put("revision", 0)).toString())
                                } catch (_: Exception) { result.error("BACKGROUND_START", "Background messaging unavailable", null) }
                            }
                        } catch (_: Exception) { runOnUiThread { result.error("SESSION_STORAGE", "Session storage unavailable", null) } }
                    }
                }
                "backgroundRefresh" -> {
                    val stale = call.argument<String>("access_token")
                    worker.execute {
                        try {
                            for (i in 0 until 80) {
                                if (SyncService.client != null) break
                                Thread.sleep(25)
                            }
                            val client = SyncService.client ?: throw IllegalStateException("Background messaging unavailable")
                            val tokens = client.refresh(stale)
                            runOnUiThread { result.success(tokens.toString()) }
                        } catch (_: SessionRevoked) { runOnUiThread { result.error("SESSION_REVOKED", "Session revoked", null) } }
                        catch (_: Exception) { runOnUiThread { result.error("BACKGROUND_REFRESH", "Platform unavailable", null) } }
                    }
                }
                "backgroundPause" -> {
                    val stopping=SyncService.client
                    stopping?.stop()
                    stopService(Intent(this,SyncService::class.java))
                    worker.execute {
                        try {
                            stopping?.awaitStopped()
                            val session=SessionStore.read(this)
                            if(session!=null) SessionStore.saveOwned(this,BackgroundSession.pause(session),session.getString("owner"))
                            runOnUiThread { result.success(null) }
                        } catch(_:Exception) { runOnUiThread { result.error("SESSION_STORAGE","Unable to pause session",null) } }
                    }
                }
                "backgroundResume" -> {
                    worker.execute {
                        try {
                            val session=SessionStore.read(this)
                            if(session!=null) SessionStore.saveOwned(this,session.put("paused",false),session.getString("owner"))
                            runOnUiThread { result.success(null) }
                        } catch(_:Exception) { runOnUiThread { result.error("SESSION_STORAGE","Unable to resume session",null) } }
                    }
                }
                "notificationsEnabled" -> result.success(Build.VERSION.SDK_INT < 33 || checkSelfPermission(Manifest.permission.POST_NOTIFICATIONS) == PackageManager.PERMISSION_GRANTED)
                "backgroundStop" -> {
                    // Stop the refresh owner before clearing durable credentials.
                    val stopping = SyncService.client
                    stopping?.stop()
                    stopService(Intent(this, SyncService::class.java))
                    worker.execute {
                        stopping?.awaitStopped()
                        SessionStore.clear(this)
                        runOnUiThread { result.success(null) }
                    }
                }
                "deviceName" -> result.success("${Build.MANUFACTURER} ${Build.MODEL}")
                "getInitialShare" -> { result.success(pendingShare); pendingShare = null }
                "clearShares" -> {
                    val directory=File(cacheDir,"crosslink-shares").canonicalFile
                    call.argument<List<String>>("paths")?.forEach { path ->
                        val file=File(path).canonicalFile
                        if(file.parentFile==directory && file.name.matches(Regex("[a-f0-9-]{36}")))file.delete()
                    }
                    result.success(null)
                }
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
                "transferDirectory" -> {
                    val directory=File(cacheDir,"crosslink-transfers")
                    if(directory.exists() || directory.mkdirs()) result.success(directory.absolutePath)
                    else result.error("TEMP_DIRECTORY","Unable to create temporary directory",null)
                }
                "saveFile" -> {
                    if (saveResult != null) { result.error("SAVE_BUSY", "A save dialog is already open", null) }
                    else {
                        saveResult = result
                        try {
                            val input=File(call.argument<String>("path") ?: "").canonicalFile
                            val directory=File(cacheDir,"crosslink-transfers").canonicalFile
                            require(input.parentFile==directory && input.name.matches(Regex("crosslink-[a-f0-9-]{36}\\.part")) && input.isFile && input.length()<=104857600)
                            saveInput=input
                            val save = Intent(Intent.ACTION_CREATE_DOCUMENT).addCategory(Intent.CATEGORY_OPENABLE).setType(call.argument<String>("mime_type") ?: "application/octet-stream").putExtra(Intent.EXTRA_TITLE, call.argument<String>("name") ?: "file")
                            startActivityForResult(save, 4102)
                        } catch (e: Exception) { saveResult = null; saveInput = null; result.error("SAVE_FAILED", "Unable to open save dialog", null) }
                    }
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
    override fun onWindowFocusChanged(hasFocus: Boolean) { super.onWindowFocusChanged(hasFocus); clipboardBridge?.focus(hasFocus) }
    override fun onDestroy() {
        clipboardBridge?.dispose(); clipboardBridge = null
        saveResult?.error("SAVE_CANCELLED","Activity closed before save completed",null)
        saveResult=null;saveInput=null
        if (SyncService.listener === eventListener) SyncService.listener = null
        channel?.setMethodCallHandler(null)
        channel = null
        worker.shutdown()
        super.onDestroy()
    }
    @Suppress("DEPRECATION")
    override fun onActivityResult(requestCode: Int, resultCode: Int, data: Intent?) {
        if (requestCode != 4102) { super.onActivityResult(requestCode, resultCode, data); return }
        val result = saveResult ?: return
        val input = saveInput
        saveResult = null; saveInput = null
        val uri = data?.data
        if (resultCode != android.app.Activity.RESULT_OK || uri == null || input == null) { result.success(null); return }
        worker.execute {
            try {
                contentResolver.openOutputStream(uri,"w")?.use { output ->
                    input.inputStream().use { source ->
                        val buffer=ByteArray(65536);var total=0L
                        while(true){val count=source.read(buffer);if(count<0)break;total+=count;require(total<=104857600);output.write(buffer,0,count)}
                    }
                } ?: throw IllegalArgumentException("Unable to write selected file")
                try { contentResolver.takePersistableUriPermission(uri,(data?.flags ?: 0) and (Intent.FLAG_GRANT_READ_URI_PERMISSION or Intent.FLAG_GRANT_WRITE_URI_PERMISSION)) } catch(_:SecurityException) {}
                runOnUiThread { result.success(uri.toString()) }
            } catch (e: Exception) {
                try { android.provider.DocumentsContract.deleteDocument(contentResolver,uri) } catch(_:Exception) {}
                runOnUiThread { result.error("SAVE_FAILED", "Unable to save selected file", null) }
            }
        }
    }
    override fun onNewIntent(intent: Intent) { super.onNewIntent(intent); setIntent(intent); receiveShare(intent) }
    @Suppress("DEPRECATION")
    private fun receiveShare(intent: Intent) {
        if (intent.action != Intent.ACTION_SEND && intent.action != Intent.ACTION_SEND_MULTIPLE) return
        val text = intent.getCharSequenceExtra(Intent.EXTRA_TEXT)?.toString()
        val uris = if (intent.action == Intent.ACTION_SEND_MULTIPLE) intent.getParcelableArrayListExtra<Uri>(Intent.EXTRA_STREAM) ?: arrayListOf()
                   else arrayListOf<Uri>().also { intent.getParcelableExtra<Uri>(Intent.EXTRA_STREAM)?.let(it::add) }
        worker.execute {
            val created=mutableListOf<File>()
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
                    created.add(local)
                    mapOf("path" to local.absolutePath, "name" to name)
                }
                val share = mutableMapOf<String, Any>("files" to files)
                if (text != null) share["text"] = text
                runOnUiThread { pendingShare = share; channel?.invokeMethod("share", share) }
            } catch (e: Exception) {
                created.forEach { it.delete() }
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
