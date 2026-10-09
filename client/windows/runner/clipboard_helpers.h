#ifndef CROSSLINK_CLIPBOARD_HELPERS_H_
#define CROSSLINK_CLIPBOARD_HELPERS_H_
#include <windows.h>
#include <optional>
#include <string>
namespace crosslink {
struct ClipboardText {
  bool available=false;
  std::optional<std::string> text;
  DWORD sequence=0;
  std::string reason;
};
ClipboardText ReadClipboardText(HWND owner);
bool WriteClipboardText(HWND owner,const std::string& text,DWORD& sequence,std::optional<DWORD> expected=std::nullopt);
}
#endif
