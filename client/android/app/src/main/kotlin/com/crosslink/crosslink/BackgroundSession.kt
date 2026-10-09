package com.crosslink.crosslink
import org.json.JSONObject
object BackgroundSession {
 fun mayStart(session:JSONObject?):Boolean = session != null && !session.optBoolean("paused",false)
 fun pause(session:JSONObject):JSONObject = JSONObject(session.toString()).put("paused",true)
 fun resume(session:JSONObject,owner:String):JSONObject {
  require(owner.isNotEmpty())
  val next=JSONObject(session.toString()).put("paused",false).put("owner",owner)
  next.getJSONObject("tokens").put("_native_owner",owner)
  return next
 }
}
