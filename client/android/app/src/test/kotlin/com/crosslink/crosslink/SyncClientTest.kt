package com.crosslink.crosslink

import okhttp3.*
import okhttp3.mockwebserver.*
import org.json.JSONObject
import org.junit.Assert.*
import org.junit.Test
import java.util.concurrent.CountDownLatch
import java.util.concurrent.TimeUnit

class SyncClientTest {
 @Test fun pausedSessionRetainsCredentialsAndResumeGetsFreshOwner() {
  val original=JSONObject("""{"endpoint":"https://platform","owner":"old","tokens":{"access_token":"access","refresh_token":"refresh","device_id":"phone","_native_owner":"old"}}""")
  val paused=BackgroundSession.pause(original)
  assertTrue(paused.getBoolean("paused"))
  assertFalse(BackgroundSession.mayStart(paused))
  assertEquals("refresh",paused.getJSONObject("tokens").getString("refresh_token"))
  assertFalse(original.has("paused"))
  val resumed=BackgroundSession.resume(paused,"new")
  assertTrue(BackgroundSession.mayStart(resumed))
  assertEquals("new",resumed.getString("owner"))
  assertEquals("new",resumed.getJSONObject("tokens").getString("_native_owner"))
  assertEquals("phone",resumed.getJSONObject("tokens").getString("device_id"))
  assertEquals("refresh",resumed.getJSONObject("tokens").getString("refresh_token"))
 }

 @Test fun backgroundSocketAuthenticatesPersistsAndAcknowledges() {
  val server=MockWebServer(); val delivered=CountDownLatch(1);val acknowledged=CountDownLatch(1)
  server.dispatcher=object:okhttp3.mockwebserver.Dispatcher() {
   override fun dispatch(req:RecordedRequest):MockResponse {
    if(req.path=="/ws") return MockResponse().withWebSocketUpgrade(object:WebSocketListener(){
     override fun onMessage(ws:WebSocket,text:String){
      val data=JSONObject(text)
      if(data.optString("type")=="auth") {
       assertEquals("access",data.getString("token"))
       ws.send("{\"type\":\"auth_ok\",\"device_id\":\"phone\"}")
       ws.send("{\"event\":\"message.created\",\"event_id\":\"event\",\"timestamp\":1,\"data\":{\"id\":\"message\",\"type\":\"text\",\"payload\":{\"content\":\"hello phone\"}}}")
      }
     }
    })
    if(req.path?.startsWith("/api/v1/messages/pending") == true) return MockResponse().setBody("[]")
    if(req.path=="/api/v1/messages/message/ack") { assertEquals("Bearer access",req.getHeader("Authorization"));acknowledged.countDown();return MockResponse().setBody("{\"status\":\"delivered\"}") }
    return MockResponse().setResponseCode(404)
   }
  }
  server.start()
  val c=SyncClient(server.url("/").toString().trimEnd('/'),JSONObject("{\"access_token\":\"access\",\"refresh_token\":\"refresh\",\"device_id\":\"phone\"}"),OkHttpClient(),{},
   {m->assertEquals("hello phone",m.getJSONObject("payload").getString("content"));delivered.countDown()},{},{fail("Unexpected revocation")})
  try { c.start();assertTrue(delivered.await(8,TimeUnit.SECONDS));assertTrue(acknowledged.await(8,TimeUnit.SECONDS)) } finally { c.stop();server.shutdown() }
 }
 @Test fun duplicateStaleAccessRefreshUsesOneRotation() {
  val server=MockWebServer();server.enqueue(MockResponse().setBody("{\"access_token\":\"new-access\",\"refresh_token\":\"rotated-refresh\",\"device_id\":\"phone\"}"));server.start()
  var persisted:JSONObject?=null
  val c=SyncClient(server.url("/").toString().trimEnd('/'),JSONObject("{\"access_token\":\"old-access\",\"refresh_token\":\"old-refresh\",\"device_id\":\"phone\"}"),OkHttpClient(),{persisted=it},{},{},{fail("Unexpected revocation")})
  try {
   assertEquals("new-access",c.refresh("old-access").getString("access_token"))
   assertEquals("new-access",c.refresh("old-access").getString("access_token"))
   assertEquals(1,server.requestCount);assertEquals("rotated-refresh",persisted!!.getString("refresh_token"))
  } finally { c.stop();server.shutdown() }
 }

 @Test fun closeBeforeAuthenticationRefreshesAndReconnects() {
  val server=MockWebServer();val connected=CountDownLatch(1);var sockets=0
  server.dispatcher=object:okhttp3.mockwebserver.Dispatcher() {
   override fun dispatch(req:RecordedRequest):MockResponse {
    if(req.path=="/api/v1/auth/refresh") return MockResponse().setBody("""{"access_token":"valid","refresh_token":"rotated","device_id":"phone"}""")
    if(req.path?.startsWith("/api/v1/messages/pending")==true) return MockResponse().setBody("[]")
    if(req.path=="/ws") {
     val first=++sockets==1
     return MockResponse().withWebSocketUpgrade(object:WebSocketListener() {
      override fun onMessage(ws:WebSocket,text:String) {
       if(first) ws.close(4001,"Expired")
       else {
        assertEquals("valid",JSONObject(text).getString("token"))
        ws.send("""{"type":"auth_ok"}""")
       }
      }
      override fun onClosing(ws:WebSocket,code:Int,reason:String) { ws.close(code,null) }
     })
    }
    return MockResponse().setResponseCode(404)
   }
  };server.start()
  val c=SyncClient(server.url("/").toString().trimEnd('/'),JSONObject("""{"access_token":"expired","refresh_token":"refresh","device_id":"phone"}"""),OkHttpClient(),{},{},
   {if(it.optString("type")=="auth_ok")connected.countDown()},{fail("Unexpected revocation")})
  try { c.start();assertTrue("Closed before auth must recover",connected.await(8,TimeUnit.SECONDS));assertTrue(sockets>=2) } finally {c.stop();server.shutdown()}
 }
 @Test fun drainsOfflineInboxBeyondWebsocketPage() {
  val server=MockWebServer();val done=CountDownLatch(501);var pages=0
  server.dispatcher=object:okhttp3.mockwebserver.Dispatcher() {
   override fun dispatch(req:RecordedRequest):MockResponse {
    if(req.path=="/ws")return MockResponse().withWebSocketUpgrade(object:WebSocketListener() {
     override fun onMessage(ws:WebSocket,text:String){ ws.send("""{"type":"auth_ok"}""") }
    })
    if(req.path?.startsWith("/api/v1/messages/pending")==true){
     val start=if(pages++==0)0 else 500
     val end=if(start==0)500 else 501
     val data=org.json.JSONArray()
     for(i in start until end)data.put(JSONObject().put("id","m$i").put("type","text").put("payload",JSONObject().put("content","$i")))
     return MockResponse().setBody(data.toString())
    }
    if(req.path?.endsWith("/ack")==true){done.countDown();return MockResponse().setBody("{}")}
    return MockResponse().setResponseCode(404)
   }
  };server.start()
  val c=SyncClient(server.url("/").toString().trimEnd('/'),JSONObject("""{"access_token":"access","refresh_token":"refresh","device_id":"phone"}"""),OkHttpClient(),{},{},{},{fail("Unexpected revocation")})
  try { c.start();assertTrue("All 501 receipts must be acknowledged",done.await(60,TimeUnit.SECONDS));assertEquals(2,pages) } finally {c.stop();server.shutdown()}
 }
 @Test fun revokedRefreshCannotResurrectSession() {
  val server=MockWebServer();server.enqueue(MockResponse().setResponseCode(401));server.start()
  var revoked=false;var saved=false
  val c=SyncClient(server.url("/").toString().trimEnd('/'),JSONObject("""{"access_token":"access","refresh_token":"refresh"}"""),OkHttpClient(),{saved=true},{},{},{revoked=true})
  try {
   try {c.refresh("access");fail("Revoked session must fail")}catch(_:SessionRevoked){}
   assertTrue(revoked);assertFalse(saved)
   try {c.refresh("access");fail("Stopped owner must stay stopped")}catch(_:java.io.IOException){}
   assertEquals(1,server.requestCount)
  }finally{c.stop();server.shutdown()}
 }
 @Test fun logoutWaitsForInFlightDurableRotationBeforeClearing() {
  val server=MockWebServer();server.enqueue(MockResponse().setBody("""{"access_token":"new","refresh_token":"rotated"}"""));server.start()
  val entered=CountDownLatch(1);val allow=CountDownLatch(1);val cleared=CountDownLatch(1)
  var persisted=false;var published=false
  val c=SyncClient(server.url("/").toString().trimEnd('/'),JSONObject("""{"access_token":"old","refresh_token":"refresh"}"""),OkHttpClient(),
   {entered.countDown();allow.await(5,TimeUnit.SECONDS);persisted=true},{},{if(it.optString("type")=="session.updated")published=true},{})
  val refresh=Thread {try{c.refresh("old")}catch(_:java.io.IOException){}}
  try {
   refresh.start();assertTrue(entered.await(5,TimeUnit.SECONDS));c.stop()
   val logout=Thread {c.awaitStopped();persisted=false;cleared.countDown()};logout.start()
   assertFalse("Clear must wait for pending write",cleared.await(100,TimeUnit.MILLISECONDS))
   allow.countDown();assertTrue(cleared.await(5,TimeUnit.SECONDS))
   refresh.join();logout.join();assertFalse(persisted);assertFalse(published)
  }finally{allow.countDown();c.stop();server.shutdown()}
 }
 @Test fun slowAcknowledgementDoesNotBlockHeartbeats() {
  val server=MockWebServer();val ackStarted=CountDownLatch(1);val ping=CountDownLatch(1)
  server.dispatcher=object:okhttp3.mockwebserver.Dispatcher(){
   override fun dispatch(req:RecordedRequest):MockResponse{
    if(req.path=="/ws")return MockResponse().withWebSocketUpgrade(object:WebSocketListener(){
     override fun onMessage(ws:WebSocket,text:String){
      if(JSONObject(text).optString("type")=="ping"){ping.countDown();ws.send("""{"type":"pong"}""")}
      else {
       ws.send("""{"type":"auth_ok"}""")
       ws.send("""{"event":"message.created","data":{"id":"slow","type":"text","payload":{"content":"slow ack"}}}""")
      }
     }
    })
    if(req.path?.endsWith("/ack")==true){
     ackStarted.countDown()
     return MockResponse().setBody("{}").setHeadersDelay(2,TimeUnit.SECONDS)
    }
    if(req.path?.startsWith("/api/v1/messages/pending")==true)return MockResponse().setBody("[]")
    return MockResponse().setResponseCode(404)
   }
  };server.start()
  val c=SyncClient(server.url("/").toString().trimEnd('/'),JSONObject("""{"access_token":"access","refresh_token":"refresh"}"""),
   OkHttpClient(),{},{},{},{fail("Unexpected revocation")},heartbeatIntervalMillis=100)
  try{
   c.start();assertTrue(ackStarted.await(5,TimeUnit.SECONDS))
   assertTrue("ACK latency must not stall the socket heartbeat",ping.await(1,TimeUnit.SECONDS))
  }finally{c.stop();server.shutdown()}
 }

 @Test fun connectionStateTracksAuthenticationReconnectAndStop() {
  val server=MockWebServer();val auth=CountDownLatch(1);val online=CountDownLatch(1);val offline=CountDownLatch(1)
  var remote:WebSocket?=null
  server.dispatcher=object:okhttp3.mockwebserver.Dispatcher(){
   override fun dispatch(req:RecordedRequest):MockResponse {
    if(req.path=="/ws")return MockResponse().withWebSocketUpgrade(object:WebSocketListener(){
     override fun onMessage(ws:WebSocket,text:String){remote=ws;auth.countDown()}
     override fun onClosing(ws:WebSocket,code:Int,reason:String){ws.close(code,null)}
    })
    if(req.path?.startsWith("/api/v1/messages/pending")==true)return MockResponse().setBody("[]")
    return MockResponse().setResponseCode(503)
   }
  };server.start()
  val c=SyncClient(server.url("/").toString().trimEnd('/'),JSONObject("""{"access_token":"a","refresh_token":"r","device_id":"phone"}"""),OkHttpClient(),{},{},
   {if(it.optString("type")=="connection.state"){if(it.optString("state")=="connected")online.countDown();if(it.optString("state")=="reconnecting")offline.countDown()}},{fail("Unexpected revocation")})
  try {
   assertEquals("stopped",c.connectionSnapshot().getString("state"))
   c.start();assertTrue(auth.await(8,TimeUnit.SECONDS));assertEquals("connecting",c.connectionSnapshot().getString("state"))
   val starting=c.connectionSnapshot().getLong("revision")
   remote!!.send("""{"type":"auth_ok"}""");assertTrue(online.await(8,TimeUnit.SECONDS))
   assertEquals("connected",c.connectionSnapshot().getString("state"));assertTrue(c.connectionSnapshot().getLong("revision")>starting)
   remote!!.close(1000,"test reconnect");assertTrue(offline.await(8,TimeUnit.SECONDS));assertEquals("reconnecting",c.connectionSnapshot().getString("state"))
   c.stop();assertEquals("stopped",c.connectionSnapshot().getString("state"))
  }finally{c.stop();server.shutdown()}
 }

 @Test fun clipboardPolicySuppressesOwnDuplicatesButAllowsUserRecopy() {
  val policy=ClipboardPolicy()
  val initial=policy.observe("initial",1,null)
  policy.markWritten("owner-write",2)
  val own=policy.observe("remote",2,"owner-write")
  val duplicate=policy.observe("remote",2,"owner-write")
  assertTrue(own.ownWrite);assertTrue(duplicate.ownWrite);assertEquals(own.sequence,duplicate.sequence)
  val user=policy.observe("remote",3,null)
  assertFalse(user.ownWrite);assertTrue(user.sequence>own.sequence);assertTrue(own.sequence>initial.sequence)
 }
 @Test fun clipboardPolicyResetsOldOwnerMarkers() {
  val policy=ClipboardPolicy();policy.markWritten("old",7);assertTrue(policy.observe("text",7,"old").ownWrite)
  policy.reset();assertFalse(policy.observe("text",7,"old").ownWrite)
 }
}
