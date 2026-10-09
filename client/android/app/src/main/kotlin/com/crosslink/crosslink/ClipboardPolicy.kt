package com.crosslink.crosslink

/** Identity of a platform clipboard update; independent of the Android framework. */
class ClipboardPolicy {
 data class Observation(val sequence:Long,val ownWrite:Boolean)
 var sequence=0L
  private set
 private var fingerprint:String?=null
 private var marker:String?=null
 private var writtenAt=-1L
 fun markWritten(value:String,stamp:Long){marker=value;writtenAt=stamp}
 fun observe(hash:String,stamp:Long,value:String?):Observation {
  val current="$hash|$stamp|$value"
  if(fingerprint!=current){fingerprint=current;sequence++}
  return Observation(sequence,value!=null&&value==marker&&(writtenAt<0||writtenAt==stamp))
 }
 fun reset(){sequence=0;fingerprint=null;marker=null;writtenAt=-1}
}
