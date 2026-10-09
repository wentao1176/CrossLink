#include "clipboard_bridge.h"
#include "clipboard_helpers.h"
#include "startup_helpers.h"
#include <flutter/standard_method_codec.h>
#include <cstdint>
namespace {
const flutter::EncodableValue* Arg(const flutter::EncodableValue* raw,const char* name){
 if(!raw)return nullptr;const auto* map=std::get_if<flutter::EncodableMap>(raw);if(!map)return nullptr;
 auto value=map->find(flutter::EncodableValue(name));return value==map->end()?nullptr:&value->second;
}
std::string StringArg(const flutter::EncodableValue* raw,const char* name){auto* value=Arg(raw,name);if(!value)return {};auto* text=std::get_if<std::string>(value);return text?*text:std::string();}
int64_t IntegerArg(const flutter::EncodableValue* raw,const char* name){auto* value=Arg(raw,name);if(!value)return -1;if(auto* v=std::get_if<int64_t>(value))return *v;if(auto* v=std::get_if<int32_t>(value))return *v;return -1;}
}
ClipboardBridge::ClipboardBridge(flutter::BinaryMessenger* messenger,HWND window):window_(window){
 channel_=std::make_unique<flutter::MethodChannel<flutter::EncodableValue>>(messenger,"crosslink/native",&flutter::StandardMethodCodec::GetInstance());
 channel_->SetMethodCallHandler([this](const flutter::MethodCall<flutter::EncodableValue>& call,std::unique_ptr<flutter::MethodResult<flutter::EncodableValue>> result){
  const auto* args=call.arguments();const std::string tag=StringArg(args,"owner");
  if(call.method_name()=="startupRead"){
   const auto settings=crosslink::ReadStartup();
   result->Success(flutter::EncodableValue(flutter::EncodableMap{
    {flutter::EncodableValue("enabled"),flutter::EncodableValue(settings.enabled)},
    {flutter::EncodableValue("minimized"),flutter::EncodableValue(settings.minimized)}}));return;
  }
  if(call.method_name()=="startupWrite"){
   const auto* rawEnabled=Arg(args,"enabled");const auto* rawMinimized=Arg(args,"minimized");
   const auto* enabled=rawEnabled?std::get_if<bool>(rawEnabled):nullptr;const auto* minimized=rawMinimized?std::get_if<bool>(rawMinimized):nullptr;
   if(!enabled||!minimized||!crosslink::WriteStartup(*enabled,*minimized)){result->Error("STARTUP_FAILED","Unable to update current-user startup");return;}
   result->Success();return;
  }
  if(call.method_name()=="showWindow"){ShowWindow(window_,SW_SHOW);SetForegroundWindow(window_);result->Success();return;}
  if(call.method_name()=="clipboardWatch"){
   const auto* raw=Arg(args,"enabled");const auto* enabled=raw?std::get_if<bool>(raw):nullptr;
   if(!enabled||tag.empty()){result->Error("INVALID_CLIPBOARD_ARGUMENT","Invalid clipboard session");return;}
   if(*enabled){
    if(!watching_&&!AddClipboardFormatListener(window_)){result->Success(flutter::EncodableValue(false));return;}
    watching_=true;owner_=tag;attempts_=0;
   }else if(owner_==tag){
    if(watching_)RemoveClipboardFormatListener(window_);watching_=false;KillTimer(window_,kRetryTimer);
   }
   result->Success(flutter::EncodableValue(true));return;
  }
  if(call.method_name()=="clipboardRead"){
   crosslink::ClipboardText value;
   if(watching_&&owner_==tag)value=crosslink::ReadClipboardText(window_);
   else value.reason="session";
   result->Success(flutter::EncodableValue(flutter::EncodableMap{
    {flutter::EncodableValue("available"),flutter::EncodableValue(value.available)},
    {flutter::EncodableValue("sequence"),flutter::EncodableValue(static_cast<int64_t>(value.sequence))},
    {flutter::EncodableValue("text"),value.text?flutter::EncodableValue(*value.text):flutter::EncodableValue()},
    {flutter::EncodableValue("reason"),flutter::EncodableValue(value.reason)}}));return;
  }
  if(call.method_name()=="clipboardWrite"){
   const auto* raw=Arg(args,"text");const auto* text=raw?std::get_if<std::string>(raw):nullptr;const int64_t expected=IntegerArg(args,"expected_sequence");
   const bool valid=watching_&&owner_==tag&&text&&expected>=0&&static_cast<uint64_t>(expected)<=UINT32_MAX;
   const bool written=valid&&crosslink::WriteClipboardText(window_,*text,written_sequence_,static_cast<DWORD>(expected));
   result->Success(flutter::EncodableValue(written));return;
  }
  result->NotImplemented();
 });
}
ClipboardBridge::~ClipboardBridge(){if(watching_)RemoveClipboardFormatListener(window_);KillTimer(window_,kRetryTimer);channel_->SetMethodCallHandler(nullptr);}
void ClipboardBridge::Changed(){
 if(!watching_)return;
 auto value=crosslink::ReadClipboardText(window_);
 if(value.reason=="busy"&&attempts_<3){attempts_++;SetTimer(window_,kRetryTimer,30,nullptr);return;}
 attempts_=0;KillTimer(window_,kRetryTimer);
 if(value.sequence==written_sequence_&&written_sequence_!=0)return;
 channel_->InvokeMethod("clipboardChanged",std::make_unique<flutter::EncodableValue>(flutter::EncodableMap{
  {flutter::EncodableValue("owner"),flutter::EncodableValue(owner_)},
  {flutter::EncodableValue("available"),flutter::EncodableValue(value.available)},
  {flutter::EncodableValue("sequence"),flutter::EncodableValue(static_cast<int64_t>(value.sequence))},
  {flutter::EncodableValue("text"),value.text?flutter::EncodableValue(*value.text):flutter::EncodableValue()},
  {flutter::EncodableValue("reason"),flutter::EncodableValue(value.reason)}}));
}
bool ClipboardBridge::HandleMessage(UINT message,WPARAM wparam){
 if(message==crosslink::ActivationMessage()){ShowWindow(window_,SW_RESTORE);SetForegroundWindow(window_);return true;}
 if(message==WM_CLIPBOARDUPDATE||(message==WM_TIMER&&wparam==kRetryTimer)){Changed();return true;}return false;
}
