#include <windows.h>
#include <cstring>
#include <iostream>
#include <string>
#include <vector>
#include "clipboard_helpers.h"
static int updates=0;
LRESULT CALLBACK TestProc(HWND hwnd,UINT message,WPARAM w,LPARAM l){if(message==WM_CLIPBOARDUPDATE){updates++;return 0;}return DefWindowProcW(hwnd,message,w,l);}
class ClipboardBackup {
 struct Entry{UINT format;HGLOBAL memory;};
 std::vector<Entry> entries_;HWND owner_=nullptr;DWORD expected_=0;bool modified_=false;
 public:
 ~ClipboardBackup(){if(modified_)Restore();for(auto& entry:entries_)if(entry.memory)GlobalFree(entry.memory);}
 bool Capture(HWND owner){
  owner_=owner;if(!OpenClipboard(owner))return false;
  size_t total=0;UINT format=0;bool ok=true;
  while((format=EnumClipboardFormats(format))!=0){
   HANDLE source=GetClipboardData(format);const SIZE_T size=source?GlobalSize(source):0;
   if(size==0||size>16*1024*1024||entries_.size()>=256||total+size>16*1024*1024){ok=false;break;}
   HGLOBAL copy=GlobalAlloc(GMEM_MOVEABLE,size);void* data=GlobalLock(source);void* output=copy?GlobalLock(copy):nullptr;
   if(!data||!output){if(data)GlobalUnlock(source);if(output)GlobalUnlock(copy);if(copy)GlobalFree(copy);ok=false;break;}
   std::memcpy(output,data,size);GlobalUnlock(source);GlobalUnlock(copy);entries_.push_back({format,copy});total+=size;
  }
  expected_=GetClipboardSequenceNumber();CloseClipboard();return ok;
 }
 void Mark(DWORD sequence){expected_=sequence;modified_=true;}
 bool Unchanged()const{return GetClipboardSequenceNumber()==expected_;}
 bool Restore(){
  bool opened=false;for(int attempt=0;attempt<20&&!opened;attempt++){opened=OpenClipboard(owner_)!=FALSE;if(!opened)Sleep(10);}
  if(!opened){std::cerr<<"Could not restore clipboard; code "<<GetLastError()<<"\n";return false;}
  if(GetClipboardSequenceNumber()!=expected_&&GetClipboardOwner()!=owner_){CloseClipboard();modified_=false;return true;} // Never replace a new user copy.
  if(!EmptyClipboard()){CloseClipboard();return false;}
  bool ok=true;for(auto& entry:entries_){if(SetClipboardData(entry.format,entry.memory))entry.memory=nullptr;else ok=false;}
  CloseClipboard();modified_=false;return ok;
 }
};
#define REQUIRE(expr) do {if(!(expr)){std::cerr<<"failed line "<<__LINE__<<" code "<<GetLastError()<<"\n";return 1;}}while(0)
int main(){
 WNDCLASSW cls={};cls.lpfnWndProc=TestProc;cls.hInstance=GetModuleHandleW(nullptr);cls.lpszClassName=L"CrossLinkClipboardTests";
 REQUIRE(RegisterClassW(&cls));HWND window=CreateWindowExW(0,cls.lpszClassName,L"",0,0,0,0,0,HWND_MESSAGE,nullptr,cls.hInstance,nullptr);REQUIRE(window);
 ClipboardBackup backup;
 if(!backup.Capture(window)){std::cerr<<"Current clipboard formats cannot be safely backed up; no test writes performed\n";DestroyWindow(window);return 2;}
 REQUIRE(AddClipboardFormatListener(window));REQUIRE(backup.Unchanged());
 const std::string text=u8"你好\nhttps://example.com 😀\t ";DWORD first=0,second=0;
 REQUIRE(crosslink::WriteClipboardText(window,text,first));backup.Mark(first);
 auto value=crosslink::ReadClipboardText(window);std::cerr<<"read available="<<value.available<<" matches="<<(value.text&&*value.text==text)<<" seq="<<value.sequence<<" writeSeq="<<first<<" reason="<<value.reason<<"\n";REQUIRE(value.available&&value.text&&*value.text==text);REQUIRE(value.sequence==first);REQUIRE(backup.Unchanged());
 REQUIRE(crosslink::WriteClipboardText(window,text,second));backup.Mark(second);REQUIRE(second!=first);
 auto before=crosslink::ReadClipboardText(window);DWORD rejected=0;REQUIRE(!crosslink::WriteClipboardText(window,std::string(102401,'x'),rejected));REQUIRE(crosslink::ReadClipboardText(window).text==before.text);
 REQUIRE(backup.Unchanged());DWORD newer=0;REQUIRE(crosslink::WriteClipboardText(window,"new local",newer));backup.Mark(newer);
 DWORD ignored=0;REQUIRE(!crosslink::WriteClipboardText(window,"stale remote",ignored,second));REQUIRE(*crosslink::ReadClipboardText(window).text=="new local");
 DWORD maximum=0;REQUIRE(crosslink::WriteClipboardText(window,std::string(102400,'x'),maximum));backup.Mark(maximum);REQUIRE(crosslink::ReadClipboardText(window).text->size()==102400);
 REQUIRE(backup.Unchanged());DWORD blank=0;REQUIRE(crosslink::WriteClipboardText(window," \t\r\n",blank));backup.Mark(blank);REQUIRE(*crosslink::ReadClipboardText(window).text==" \t\r\n");
 const auto deadline=GetTickCount64()+1000;MSG message;
 while(GetTickCount64()<deadline&&updates==0){while(PeekMessageW(&message,nullptr,0,0,PM_REMOVE)){TranslateMessage(&message);DispatchMessageW(&message);}Sleep(5);}
 REQUIRE(updates>0);REQUIRE(backup.Unchanged());REQUIRE(OpenClipboard(window));REQUIRE(EmptyClipboard());HGLOBAL memory=GlobalAlloc(GMEM_MOVEABLE,4);REQUIRE(memory);REQUIRE(SetClipboardData(RegisterClipboardFormatW(L"CrossLink.TestNonText"),memory));backup.Mark(GetClipboardSequenceNumber());CloseClipboard();
 auto unsupported=crosslink::ReadClipboardText(window);REQUIRE(!unsupported.available&&unsupported.reason=="unsupported");REQUIRE(backup.Restore());
 RemoveClipboardFormatListener(window);DestroyWindow(window);UnregisterClassW(cls.lpszClassName,cls.hInstance);
 std::cout<<"PASS: real Windows clipboard Unicode/whitespace, notifications, recopy sequence, size and format guards; original formats restored\n";return 0;
}
