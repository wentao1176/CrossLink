#include "clipboard_helpers.h"
#include <cstring>
namespace crosslink {
namespace {
constexpr size_t kMaxBytes=102400;
class ClipboardLock {
 public:
  explicit ClipboardLock(HWND owner):opened_(OpenClipboard(owner)!=FALSE){}
  ~ClipboardLock(){if(opened_)CloseClipboard();}
  bool opened()const{return opened_;}
  void Close(){if(opened_){CloseClipboard();opened_=false;}}
 private:
  bool opened_;
};
}
ClipboardText ReadClipboardText(HWND owner){
 ClipboardText result;
 ClipboardLock lock(owner);
 if(!lock.opened()){result.reason="busy";return result;}
 result.sequence=GetClipboardSequenceNumber();
 if(!IsClipboardFormatAvailable(CF_UNICODETEXT)){
  result.available=CountClipboardFormats()==0;
  if(!result.available)result.reason="unsupported";
  return result;
 }
 HANDLE memory=GetClipboardData(CF_UNICODETEXT);
 if(!memory){result.reason="busy";return result;}
 const SIZE_T bytes=GlobalSize(memory);
 if(bytes>(kMaxBytes+1)*sizeof(wchar_t)){result.reason="too_large";return result;}
 const auto* value=static_cast<const wchar_t*>(GlobalLock(memory));
 if(!value){result.reason="busy";return result;}
 const size_t capacity=bytes/sizeof(wchar_t);
 size_t length=0;while(length<capacity&&value[length]!=0)length++;
 if(length==capacity){GlobalUnlock(memory);result.reason="unsupported";return result;}
 const int count=static_cast<int>(length);
 const int output=count==0?0:WideCharToMultiByte(CP_UTF8,WC_ERR_INVALID_CHARS,value,count,nullptr,0,nullptr,nullptr);
 if((count>0&&output<=0)||output>static_cast<int>(kMaxBytes)){
  GlobalUnlock(memory);result.reason=output>static_cast<int>(kMaxBytes)?"too_large":"unsupported";return result;
 }
 std::string text(static_cast<size_t>(output),'\0');
 if(output>0)WideCharToMultiByte(CP_UTF8,WC_ERR_INVALID_CHARS,value,count,text.data(),output,nullptr,nullptr);
 GlobalUnlock(memory);result.available=true;result.text=std::move(text);return result;
}
bool WriteClipboardText(HWND owner,const std::string& text,DWORD& sequence,std::optional<DWORD> expected){
 if(text.size()>kMaxBytes||text.find('\0')!=std::string::npos)return false;
 const int count=text.empty()?0:MultiByteToWideChar(CP_UTF8,MB_ERR_INVALID_CHARS,text.data(),static_cast<int>(text.size()),nullptr,0);
 if(!text.empty()&&count<=0)return false;
 std::wstring wide(static_cast<size_t>(count),L'\0');
 if(count>0)MultiByteToWideChar(CP_UTF8,MB_ERR_INVALID_CHARS,text.data(),static_cast<int>(text.size()),wide.data(),count);
 HGLOBAL memory=GlobalAlloc(GMEM_MOVEABLE,(wide.size()+1)*sizeof(wchar_t));
 if(!memory)return false;
 auto* output=static_cast<wchar_t*>(GlobalLock(memory));
 if(!output){GlobalFree(memory);return false;}
 if(!wide.empty())std::memcpy(output,wide.data(),wide.size()*sizeof(wchar_t));
 output[wide.size()]=0;GlobalUnlock(memory);
 ClipboardLock lock(owner);
 if(!lock.opened()||(expected&&GetClipboardSequenceNumber()!=*expected)||!EmptyClipboard()){GlobalFree(memory);return false;}
 if(!SetClipboardData(CF_UNICODETEXT,memory)){GlobalFree(memory);return false;}
 lock.Close();
 sequence=GetClipboardOwner()==owner?GetClipboardSequenceNumber():0;return true;
}
}
