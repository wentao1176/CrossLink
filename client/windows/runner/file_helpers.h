#ifndef CROSSLINK_FILE_HELPERS_H_
#define CROSSLINK_FILE_HELPERS_H_
#include <windows.h>
#include <string>
#include <optional>
namespace crosslink {
std::optional<std::string> TransferDirectory();
std::optional<std::string> ChooseSavePath(HWND window,const std::string& name,HRESULT& error);
}
#endif
