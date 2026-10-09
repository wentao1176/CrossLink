package com.crosslink.crosslink

import android.app.Activity
import android.content.ClipData
import android.content.ClipboardManager
import android.content.Context
import android.os.Build
import android.os.PersistableBundle
import java.security.MessageDigest
import java.util.UUID

class NativeClipboardBridge(private val activity:Activity,private val emit:(String,Map<String,Any?>)->Unit) {
 private val manager=activity.getSystemService(Context.CLIPBOARD_SERVICE) as ClipboardManager
 private val policy=ClipboardPolicy()
 private var watching=false
 private var owner=""
 private var lastObservation:ClipboardPolicy.Observation?=null
 private val listener=ClipboardManager.OnPrimaryClipChangedListener {
  if(watching&&activity.hasWindowFocus()) {
   val value=snapshot(owner)
   if(lastObservation?.ownWrite!=true)emit("clipboardChanged",value+mapOf("owner" to owner))
  }
 }
 fun watch(enabled:Boolean,tag:String):Boolean {
  require(tag.isNotEmpty())
  if(enabled){
   if(!watching){manager.addPrimaryClipChangedListener(listener)}
   if(owner!=tag||!watching)policy.reset()
   owner=tag;watching=true
  }else if(owner==tag){
   if(watching)manager.removePrimaryClipChangedListener(listener)
   watching=false;policy.reset()
  }
  return true
 }
 private fun hash(value:String)=MessageDigest.getInstance("SHA-256").digest(value.toByteArray(Charsets.UTF_8)).joinToString(""){"%02x".format(it)}
 fun snapshot(tag:String):Map<String,Any?> {
  if(!watching||tag!=owner)return mapOf("available" to false,"reason" to "session","sequence" to policy.sequence)
  if(!activity.hasWindowFocus())return mapOf("available" to false,"reason" to "focus","sequence" to policy.sequence)
  try {
   val clip=manager.primaryClip
   val stamp=if(Build.VERSION.SDK_INT>=26)clip?.description?.timestamp?:0L else 0L
   val marker=clip?.description?.extras?.getString("crosslink_write")
   var value:String?=null;var reason=""
   if(clip!=null&&clip.itemCount>0){
    if(clip.itemCount!=1)reason="unsupported"
    else {
     val item=clip.getItemAt(0);val raw=item.text
     if(raw!=null){
      if(raw.length>102400)reason="too_large" else value=raw.toString()
     }else if(item.uri?.scheme in listOf("http","https"))value=item.uri.toString()
     else reason="unsupported"
    }
   }
   if(value!=null&&value.toByteArray(Charsets.UTF_8).size>102400){value=null;reason="too_large"}
   val observation=policy.observe(value?.let(::hash)?:"empty:$reason",stamp,marker)
   lastObservation=observation
   return mapOf("available" to reason.isEmpty(),"text" to value,"sequence" to observation.sequence,"reason" to reason)
  }catch(_:Exception){return mapOf("available" to false,"reason" to "busy","sequence" to policy.sequence)}
 }
 fun write(tag:String,text:String,expected:Long):Boolean {
  if(!watching||owner!=tag||!activity.hasWindowFocus()||text.toByteArray(Charsets.UTF_8).size>102400)return false
  val current=snapshot(tag)
  if(current["available"]!=true||current["sequence"]!=expected)return false
  return try {
   val marker=UUID.randomUUID().toString()
   val clip=ClipData.newPlainText("CrossLink",text)
   clip.description.extras=PersistableBundle().apply{putString("crosslink_write",marker)}
   policy.markWritten(marker,-1)
   manager.setPrimaryClip(clip)
   val stamp=if(Build.VERSION.SDK_INT>=26)manager.primaryClip?.description?.timestamp?:0L else 0L
   policy.markWritten(marker,stamp);policy.observe(hash(text),stamp,marker)
   true
  }catch(_:Exception){false}
 }
 fun focus(hasFocus:Boolean){if(watching)emit("clipboardFocus",mapOf("owner" to owner,"focused" to hasFocus))}
 fun dispose(){if(watching)manager.removePrimaryClipChangedListener(listener);watching=false;policy.reset()}
}
