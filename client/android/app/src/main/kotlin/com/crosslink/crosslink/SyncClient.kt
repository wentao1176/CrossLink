package com.crosslink.crosslink

import okhttp3.*
import okhttp3.MediaType.Companion.toMediaType
import okhttp3.RequestBody.Companion.toRequestBody
import org.json.JSONObject
import java.io.IOException
import java.util.concurrent.Executors
import java.util.concurrent.ScheduledFuture
import java.util.concurrent.TimeUnit
import java.util.concurrent.atomic.AtomicBoolean

class SessionRevoked : IOException("Session revoked")

/** One refresh owner and socket for an Android device, including when Flutter is absent. */
class SyncClient(val endpoint: String, initial: JSONObject, val http: OkHttpClient,
 private val saved: (JSONObject) -> Unit, private val message: (JSONObject) -> Unit,
 private val event: (JSONObject) -> Unit, private val revoked: () -> Unit,
 private val heartbeatIntervalMillis: Long = 30000) {
 private val stateLock = Any()
 private var connectionState = "stopped"
 private var stateRevision = 0L
 fun connectionSnapshot(): JSONObject = synchronized(stateLock) {
  JSONObject().put("state", connectionState).put("revision", stateRevision)
 }
 private fun transition(next: String) {
  val value = synchronized(stateLock) {
   if ((stopped.get() && next != "stopped") || connectionState == next) return
   connectionState = next
   stateRevision += 1
   JSONObject().put("type", "connection.state").put("state", next).put("revision", stateRevision)
  }
  event(value)
 }
 private val tokenLock = Any()
 private var tokens = JSONObject(initial.toString())
 private val stopped = AtomicBoolean(false)
 private val executor = Executors.newSingleThreadScheduledExecutor()
 private val delivery = Executors.newSingleThreadExecutor()
 @Volatile private var socket: WebSocket? = null
 private var retry: ScheduledFuture<*>? = null
 private var heartbeat: ScheduledFuture<*>? = null
 private var lastPong = System.currentTimeMillis()
 private var attempts = 0
 @Volatile private var generation = 0

 fun snapshot(): JSONObject = synchronized(tokenLock) { JSONObject(tokens.toString()) }

 fun refresh(staleAccess: String? = null): JSONObject = synchronized(tokenLock) {
  if (stopped.get()) throw IOException("Messaging stopped")
  if (staleAccess != null && tokens.optString("access_token") != staleAccess) return@synchronized snapshot()
  val body = JSONObject().put("refresh_token", tokens.getString("refresh_token")).toString()
  http.newCall(Request.Builder().url("$endpoint/api/v1/auth/refresh")
   .post(body.toRequestBody("application/json".toMediaType())).build()).execute().use { response ->
   if (response.code == 401) {
    stop()
    revoked()
    throw SessionRevoked()
   }
   if (!response.isSuccessful) throw IOException("Platform refresh failed")
   val next = JSONObject(response.body?.string() ?: throw IOException("Empty response"))
   if (tokens.has("_native_owner")) next.put("_native_owner", tokens.getString("_native_owner"))
   require(next.optString("access_token").isNotEmpty() && next.optString("refresh_token").isNotEmpty())
   if (stopped.get()) throw IOException("Messaging stopped")
   // Durable rotation must finish before exposing the new access token to Flutter.
   saved(next)
   if (stopped.get()) throw IOException("Messaging stopped")
   tokens = JSONObject(next.toString())
   event(JSONObject().put("type", "session.updated").put("tokens", snapshot()))
   snapshot()
  }
 }

 private fun execute(action: () -> Unit) {
  if (!stopped.get()) try { executor.execute { if (!stopped.get()) action() } } catch (_: Exception) {}
 }
 private fun deliver(action: () -> Unit) {
  if (!stopped.get()) try { delivery.execute { if (!stopped.get()) action() } } catch (_: Exception) {}
 }
 fun start() = execute { connect(false) }

 private fun connect(rotate: Boolean) {
  if (stopped.get()) return
  try {
   transition(if (rotate) "reconnecting" else "connecting")
   if (rotate) refresh(snapshot().optString("access_token"))
   val epoch = ++generation
   val uri = endpoint.replaceFirst("https://", "wss://").replaceFirst("http://", "ws://") + "/ws"
   socket = http.newWebSocket(Request.Builder().url(uri).build(), object: WebSocketListener() {
    override fun onOpen(ws: WebSocket, response: Response) {
     if (stopped.get() || epoch != generation) { ws.cancel(); return }
     ws.send(JSONObject().put("type", "auth").put("token", snapshot().getString("access_token")).toString())
    }
    override fun onMessage(ws: WebSocket, text: String) = execute {
     if (epoch != generation) return@execute
     try {
      val data = JSONObject(text)
      when (data.optString("type")) {
       "pong" -> lastPong = System.currentTimeMillis()
       "auth_ok" -> {
        transition("connected")
        attempts = 0
        lastPong = System.currentTimeMillis()
        heartbeat?.cancel(false)
        heartbeat = executor.scheduleAtFixedRate({
         if (stopped.get() || epoch != generation) return@scheduleAtFixedRate
         if (System.currentTimeMillis() - lastPong > 90000) { ws.cancel(); reconnect(epoch) }
         else ws.send("{\"type\":\"ping\"}")
        }, heartbeatIntervalMillis, heartbeatIntervalMillis, TimeUnit.MILLISECONDS)
        event(data)
        deliver { drainPending() }
       }
       else -> {
        val kind = data.optString("event")
        if (kind in listOf("message.created", "clipboard.updated", "file.created", "notification.created")) {
         val payload = data.getJSONObject("data")
         // HTTP receipts and a large offline inbox cannot block the socket heartbeat.
         deliver {
          try {
           message(payload) // App-private durable inbox before acknowledging delivery.
           acknowledge(payload.getString("id"))
           event(data)
          } catch (_: SessionRevoked) {} catch (_: Exception) { execute { ws.cancel(); reconnect(epoch) } }
         }
        } else event(data)
       }
      }
     } catch (_: SessionRevoked) {} catch (_: Exception) { ws.cancel(); reconnect(epoch) }
    }
    override fun onClosing(ws: WebSocket, code: Int, reason: String) {
     ws.close(code, null)
     execute { reconnect(epoch) }
    }
    override fun onClosed(ws: WebSocket, code: Int, reason: String) = execute { reconnect(epoch) }
    override fun onFailure(ws: WebSocket, t: Throwable, response: Response?) = execute { reconnect(epoch) }
   })
  } catch (_: SessionRevoked) {} catch (_: Exception) { reconnect(generation) }
 }

 private fun drainPending() {
  if (stopped.get()) return
  try {
   var access = snapshot().getString("access_token")
   fun request(): Response = http.newCall(Request.Builder().url("$endpoint/api/v1/messages/pending?limit=500")
    .header("Authorization", "Bearer $access").build()).execute()
   var response = request()
   if (response.code == 401) {
    response.close()
    access = refresh(access).getString("access_token")
    response = request()
   }
   val pending = response.use {
    if (!it.isSuccessful) throw IOException("Pending delivery unavailable")
    org.json.JSONArray(it.body?.string() ?: "[]")
   }
   for (i in 0 until pending.length()) {
    if (stopped.get()) return
    val payload = pending.getJSONObject(i)
    message(payload)
    acknowledge(payload.getString("id"))
    event(JSONObject().put("event", "message.created").put("data", payload))
   }
   // Yield between pages so a large offline inbox cannot starve socket heartbeats.
   if (pending.length() == 500) deliver { drainPending() }
  } catch (_: SessionRevoked) {} catch (_: Exception) {
   if (!stopped.get()) executor.schedule({ deliver { drainPending() } }, 5, TimeUnit.SECONDS)
  }
 }

 private fun acknowledge(id: String) {
  fun request(access: String): Response = http.newCall(Request.Builder()
   .url("$endpoint/api/v1/messages/$id/ack").header("Authorization", "Bearer $access")
   .post("{}".toRequestBody("application/json".toMediaType())).build()).execute()
  val access = snapshot().getString("access_token")
  request(access).use { response ->
   if (response.isSuccessful) return
   if (response.code != 401) throw IOException("Acknowledgement failed")
  }
  request(refresh(access).getString("access_token")).use { response ->
   if (!response.isSuccessful) throw IOException("Acknowledgement failed")
  }
 }

 private fun reconnect(epoch: Int) {
  if (stopped.get() || epoch != generation || retry?.isDone == false) return
  ++generation // Ignore callbacks from the closed socket.
  heartbeat?.cancel(false)
  transition("reconnecting")
  event(JSONObject().put("type", "offline"))
  val delay = minOf(30L, 1L shl minOf(attempts++, 5))
  retry = executor.schedule({ retry = null; connect(true) }, delay, TimeUnit.SECONDS)
 }

 /** Called off the UI thread after stop(): no rotation can persist after it returns. */
 fun awaitStopped() { synchronized(tokenLock) {} }

 fun stop() {
  if (!stopped.compareAndSet(false, true)) return
  transition("stopped")
  ++generation
  socket?.cancel()
  heartbeat?.cancel(false)
  retry?.cancel(false)
  executor.shutdownNow()
  delivery.shutdownNow()
 }
}
