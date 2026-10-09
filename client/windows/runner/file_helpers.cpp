#include "file_helpers.h"
#include "startup_helpers.h"
#include <shlobj.h>
#include <shobjidl.h>
#include <wrl/client.h>
#include <filesystem>
#include <vector>
namespace {
std::wstring Wide(const std::string& text){
 const int size=MultiByteToWideChar(CP_UTF8,MB_ERR_INVALID_CHARS,text.data(),static_cast<int>(text.size()),nullptr,0);
 if(size<=0)return {};std::wstring value(size,L'\0');
 MultiByteToWideChar(CP_UTF8,MB_ERR_INVALID_CHARS,text.data(),static_cast<int>(text.size()),value.data(),size);return value;
}
std::string Utf8(const std::wstring& text){
 const int size=WideCharToMultiByte(CP_UTF8,0,text.data(),static_cast<int>(text.size()),nullptr,0,nullptr,nullptr);
 if(size<=0)return {};std::string value(size,'\0');
 WideCharToMultiByte(CP_UTF8,0,text.data(),static_cast<int>(text.size()),value.data(),size,nullptr,nullptr);return value;
}
}
namespace crosslink {
std::optional<std::string> TransferDirectory(){
 PWSTR local=nullptr;if(FAILED(SHGetKnownFolderPath(FOLDERID_LocalAppData,0,nullptr,&local)))return std::nullopt;
 const auto directory=std::filesystem::path(local)/L"CrossLink"/InstanceIdentity()/L"transfers";CoTaskMemFree(local);
 std::error_code error;std::filesystem::create_directories(directory,error);if(error)return std::nullopt;
 return Utf8(directory.wstring());
}
std::optional<std::string> ChooseSavePath(HWND window,const std::string& name,HRESULT& error){
 Microsoft::WRL::ComPtr<IFileSaveDialog> dialog;
 error=CoCreateInstance(CLSID_FileSaveDialog,nullptr,CLSCTX_INPROC_SERVER,IID_PPV_ARGS(&dialog));if(FAILED(error))return std::nullopt;
 DWORD options=0;error=dialog->GetOptions(&options);if(FAILED(error))return std::nullopt;
 error=dialog->SetOptions(options|FOS_FORCEFILESYSTEM|FOS_OVERWRITEPROMPT|FOS_PATHMUSTEXIST);if(FAILED(error))return std::nullopt;
 const auto fileName=Wide(name);error=dialog->SetFileName(fileName.empty()?L"file":fileName.c_str());if(FAILED(error))return std::nullopt;
 error=dialog->SetTitle(L"保存收到的文件");if(FAILED(error))return std::nullopt;
 error=dialog->Show(window);if(FAILED(error))return std::nullopt;
 Microsoft::WRL::ComPtr<IShellItem> item;error=dialog->GetResult(&item);if(FAILED(error))return std::nullopt;
 PWSTR path=nullptr;error=item->GetDisplayName(SIGDN_FILESYSPATH,&path);if(FAILED(error))return std::nullopt;
 const auto result=Utf8(path);CoTaskMemFree(path);return result;
}
}
