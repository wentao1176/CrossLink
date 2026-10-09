#ifndef CROSSLINK_CLIPBOARD_BRIDGE_H_
#define CROSSLINK_CLIPBOARD_BRIDGE_H_
#include <windows.h>
#include <flutter/method_channel.h>
#include <flutter/encodable_value.h>
#include <memory>
#include <string>
class ClipboardBridge {
 public:
  ClipboardBridge(flutter::BinaryMessenger* messenger,HWND window);
  ~ClipboardBridge();
  bool HandleMessage(UINT message,WPARAM wparam);
 private:
  void Changed();
  HWND window_;bool watching_=false;DWORD written_sequence_=0;
  UINT attempts_=0;std::string owner_;
  std::unique_ptr<flutter::MethodChannel<flutter::EncodableValue>> channel_;
  static constexpr UINT_PTR kRetryTimer=0x43524C11;
};
#endif
