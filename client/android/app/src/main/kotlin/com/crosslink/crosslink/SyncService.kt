package com.crosslink.crosslink

import android.app.*
import android.content.Context
import android.content.Intent
import android.content.pm.ServiceInfo
import android.os.Build
import android.os.IBinder
import android.security.keystore.KeyGenParameterSpec
import android.security.keystore.KeyProperties
import android.util.AtomicFile
import android.util.Base64
import androidx.core.app.NotificationCompat
import okhttp3.OkHttpClient
import org.json.JSONArray
import org.json.JSONObject
import java.io.File
import java.security.KeyStore
import java.security.cert.CertificateFactory
import java.security.cert.X509Certificate
import javax.crypto.Cipher
import javax.crypto.KeyGenerator
import javax.crypto.SecretKey
import javax.crypto.spec.GCMParameterSpec
import javax.net.ssl.*

/** Credentials survive process recreation, but cannot be copied out of the Android keystore. */
object SessionStore {
 private const val alias = "crosslink-background-session"
 private fun key(): SecretKey {
  val keys = KeyStore.getInstance("AndroidKeyStore").apply { load(null) }
  if (keys.containsAlias(alias)) return keys.getKey(alias, null) as SecretKey
  return KeyGenerator.getInstance(KeyProperties.KEY_ALGORITHM_AES, "AndroidKeyStore").apply {
   init(KeyGenParameterSpec.Builder(alias, KeyProperties.PURPOSE_ENCRYPT or KeyProperties.PURPOSE_DECRYPT)
    .setBlockModes(KeyProperties.BLOCK_MODE_GCM).setEncryptionPaddings(KeyProperties.ENCRYPTION_PADDING_NONE).build())
  }.generateKey()
 }
 private fun file(ctx: Context) = AtomicFile(File(ctx.noBackupFilesDir, "crosslink-session"))
 @Synchronized fun save(ctx: Context, session: JSONObject) {
  val cipher = Cipher.getInstance("AES/GCM/NoPadding")
  cipher.init(Cipher.ENCRYPT_MODE, key())
  val data = JSONObject().put("iv", Base64.encodeToString(cipher.iv, Base64.NO_WRAP))
   .put("data", Base64.encodeToString(cipher.doFinal(session.toString().toByteArray(Charsets.UTF_8)), Base64.NO_WRAP))
  val f = file(ctx); val output = f.startWrite()
  try { output.write(data.toString().toByteArray(Charsets.UTF_8)); f.finishWrite(output) }
  catch (e: Exception) { f.failWrite(output); throw e }
 }
 @Synchronized fun read(ctx: Context): JSONObject? {
  if (!file(ctx).baseFile.exists()) return null
  val data = JSONObject(file(ctx).readFully().toString(Charsets.UTF_8))
  val cipher = Cipher.getInstance("AES/GCM/NoPadding")
  cipher.init(Cipher.DECRYPT_MODE, key(), GCMParameterSpec(128, Base64.decode(data.getString("iv"), Base64.NO_WRAP)))
  return JSONObject(cipher.doFinal(Base64.decode(data.getString("data"), Base64.NO_WRAP)).toString(Charsets.UTF_8))
 }
 @Synchronized fun saveOwned(ctx: Context, session: JSONObject, owner: String) {
  val current = read(ctx) ?: throw java.io.IOException("Session stopped")
  if (current.optString("owner") != owner) throw java.io.IOException("Session replaced")
  save(ctx, session)
 }
 @Synchronized fun clear(ctx: Context) { file(ctx).delete(); AtomicFile(File(ctx.noBackupFilesDir, "crosslink-inbox")).delete() }
 @Synchronized fun persistMessage(ctx: Context, message: JSONObject, owner: String): Boolean {
  if (read(ctx)?.optString("owner") != owner) throw java.io.IOException("Session stopped")
  val f = AtomicFile(File(ctx.noBackupFilesDir, "crosslink-inbox"))
  val list = if (f.baseFile.exists()) JSONArray(f.readFully().toString(Charsets.UTF_8)) else JSONArray()
  val id = message.getString("id")
  for (i in 0 until list.length()) if (list.getJSONObject(i).optString("id") == id) return false
  val next = JSONArray().put(message)
  for (i in 0 until minOf(99, list.length())) next.put(list.getJSONObject(i))
  val output = f.startWrite()
  try { output.write(next.toString().toByteArray(Charsets.UTF_8)); f.finishWrite(output) }
  catch (e: Exception) { f.failWrite(output); throw e }
  return true
 }
}

class SyncService : Service() {
 companion object {
  @Volatile var client: SyncClient? = null
  @Volatile var listener: ((JSONObject) -> Unit)? = null
  private const val ongoingId = 1
  fun emit(value: JSONObject) { listener?.invoke(value) }
 }
 private var http: OkHttpClient? = null
 private var epoch = 0
 private fun launchIntent(): PendingIntent = PendingIntent.getActivity(this, 0,
  Intent(this, MainActivity::class.java).addFlags(Intent.FLAG_ACTIVITY_SINGLE_TOP),
  PendingIntent.FLAG_IMMUTABLE or PendingIntent.FLAG_UPDATE_CURRENT)
 override fun onCreate() {
  super.onCreate()
  val manager = getSystemService(NOTIFICATION_SERVICE) as NotificationManager
  if (Build.VERSION.SDK_INT >= 26) {
   manager.createNotificationChannel(NotificationChannel("crosslink-sync", "CrossLink 后台连接", NotificationManager.IMPORTANCE_LOW))
   manager.createNotificationChannel(NotificationChannel("crosslink", "CrossLink 消息", NotificationManager.IMPORTANCE_DEFAULT))
  }
  val notification = NotificationCompat.Builder(this, "crosslink-sync").setSmallIcon(R.mipmap.ic_launcher)
   .setContentTitle("CrossLink").setContentText("同账号设备同步已启用").setContentIntent(launchIntent()).setOngoing(true).build()
  if (Build.VERSION.SDK_INT >= 34) startForeground(ongoingId, notification, ServiceInfo.FOREGROUND_SERVICE_TYPE_REMOTE_MESSAGING)
  else startForeground(ongoingId, notification)
 }
 private fun trustedHttp(): OkHttpClient {
  val certificate = assets.open("flutter_assets/assets/platform_ca.pem").use {
   CertificateFactory.getInstance("X.509").generateCertificate(it) as X509Certificate
  }
  val roots = KeyStore.getInstance(KeyStore.getDefaultType()).apply { load(null); setCertificateEntry("platform", certificate) }
  val factory = TrustManagerFactory.getInstance(TrustManagerFactory.getDefaultAlgorithm()).apply { init(roots) }
  val trust = factory.trustManagers.filterIsInstance<X509TrustManager>().single()
  val tls = SSLContext.getInstance("TLS").apply { init(null, arrayOf(trust), null) }
  // The normal hostname verifier is retained: the IP must match the certificate SAN.
  return OkHttpClient.Builder().sslSocketFactory(tls.socketFactory, trust)
   .connectTimeout(15, java.util.concurrent.TimeUnit.SECONDS)
   .readTimeout(30, java.util.concurrent.TimeUnit.SECONDS).build()
 }
 override fun onStartCommand(intent: Intent?, flags: Int, startId: Int): Int {
  if (client != null && intent?.getBooleanExtra("replace", false) != true) return START_STICKY
  client?.stop()
  client = null
  http?.dispatcher?.cancelAll()
  val currentEpoch = ++epoch
  try {
   val session = SessionStore.read(this) ?: run { stopSelf(); return START_NOT_STICKY }
   val endpoint = session.getString("endpoint")
   val owner = session.getString("owner")
   session.put("owner", owner)
   session.getJSONObject("tokens").put("_native_owner", owner)
   SessionStore.saveOwned(this, session, owner)
   require(endpoint.startsWith("https://"))
   http = trustedHttp()
   val worker = SyncClient(endpoint, session.getJSONObject("tokens"), http!!,
    { tokens -> if (currentEpoch == epoch) SessionStore.saveOwned(this, JSONObject().put("endpoint", endpoint).put("tokens", tokens).put("owner", owner), owner) },
    { message -> if (currentEpoch == epoch && SessionStore.persistMessage(this, message, owner)) notifyMessage(message) },
    { value -> if (currentEpoch == epoch) emit(value.put("owner", owner)) },
    { if (currentEpoch == epoch) { SessionStore.clear(this); emit(JSONObject().put("type", "session.revoked").put("owner", owner)); stopSelf() } })
   client = worker
   worker.start()
  } catch (_: Exception) {
   emit(JSONObject().put("type", "offline"))
   stopSelf()
  }
  return START_STICKY
 }
 private fun notifyMessage(message: JSONObject) {
  try {
   val payload = message.optJSONObject("payload") ?: JSONObject()
   val content = payload.optString("content", payload.optString("name", "收到新内容"))
   val notification = NotificationCompat.Builder(this, "crosslink").setSmallIcon(R.mipmap.ic_launcher)
    .setContentTitle(payload.optString("title", "CrossLink 收到新内容")).setContentText(content.take(200))
    .setStyle(NotificationCompat.BigTextStyle().bigText(content.take(1000))).setContentIntent(launchIntent()).setAutoCancel(true).build()
   val id = message.getString("id").hashCode().and(0x7fffffff).let { if (it == ongoingId) 2 else it }
   (getSystemService(NOTIFICATION_SERVICE) as NotificationManager).notify(id, notification)
  } catch (_: SecurityException) { /* Delivery still persists when notification permission is denied. */ }
 }
 override fun onDestroy() {
  ++epoch
  client?.stop(); client = null
  http?.dispatcher?.cancelAll(); http?.connectionPool?.evictAll(); http = null
  super.onDestroy()
 }
 override fun onBind(intent: Intent?): IBinder? = null
}
