#include "startup_helpers.h"
#include <cwctype>
#include <cstdint>
#include <sstream>
#include <vector>
namespace {
std::wstring Executable() {
 std::vector<wchar_t> buffer(32768);
 DWORD size=GetModuleFileNameW(nullptr,buffer.data(),static_cast<DWORD>(buffer.size()));
 if(size==0||size>=buffer.size())return {};
 return std::wstring(buffer.data(),size);
}
std::wstring SettingsPath(){return L"Software\\CrossLink\\Instances\\"+crosslink::InstanceIdentity();}
constexpr wchar_t kRunKey[]=L"Software\\Microsoft\\Windows\\CurrentVersion\\Run";
std::wstring ReadString(HKEY key,const std::wstring& name){
 DWORD type=0,size=0;
 if(RegQueryValueExW(key,name.c_str(),nullptr,&type,nullptr,&size)!=ERROR_SUCCESS||type!=REG_SZ||size>65536)return {};
 std::vector<wchar_t> value(size/sizeof(wchar_t)+1,L'\0');
 if(RegQueryValueExW(key,name.c_str(),nullptr,&type,reinterpret_cast<BYTE*>(value.data()),&size)!=ERROR_SUCCESS)return {};
 return std::wstring(value.data());
}
struct FindContext{const std::wstring* identity;HWND window=nullptr;};
BOOL CALLBACK FindWindowForInstance(HWND window,LPARAM data){
 auto* state=reinterpret_cast<FindContext*>(data);
 if(GetPropW(window,state->identity->c_str())!=nullptr){state->window=window;return FALSE;}return TRUE;
}
}
namespace crosslink {
std::wstring RunCommand(const std::wstring& path,bool minimized){
 if(path.empty()||path.find(L'"')!=std::wstring::npos)return {};
 const std::wstring command=L"\""+path+L"\""+(minimized?L" --tray":L"");
 return command.size()<=260?command:std::wstring();
}
std::wstring InstanceIdentity(){
 const auto path=Executable();uint64_t hash=14695981039346656037ULL;
 for(wchar_t ch:path){hash^=static_cast<uint16_t>(towlower(ch));hash*=1099511628211ULL;}
 std::wostringstream output;output<<L"CrossLink-"<<std::hex<<hash;return output.str();
}
StartupSettings ReadStartup(){
 StartupSettings settings;HKEY key=nullptr;
 if(RegOpenKeyExW(HKEY_CURRENT_USER,SettingsPath().c_str(),0,KEY_READ,&key)==ERROR_SUCCESS){
  DWORD value=0,size=sizeof(value),type=0;
  if(RegQueryValueExW(key,L"Minimized",nullptr,&type,reinterpret_cast<BYTE*>(&value),&size)==ERROR_SUCCESS&&type==REG_DWORD)settings.minimized=value!=0;
  RegCloseKey(key);
 }
 if(RegOpenKeyExW(HKEY_CURRENT_USER,kRunKey,0,KEY_READ,&key)==ERROR_SUCCESS){
  const auto command=ReadString(key,InstanceIdentity());
  settings.enabled=!command.empty()&&command==RunCommand(Executable(),settings.minimized);
  RegCloseKey(key);
 }
 return settings;
}
bool WriteStartup(bool enabled,bool minimized){
 const auto command=RunCommand(Executable(),minimized);if(enabled&&command.empty())return false;
 HKEY key=nullptr;
 if(RegCreateKeyExW(HKEY_CURRENT_USER,kRunKey,0,nullptr,0,KEY_SET_VALUE,nullptr,&key,nullptr)!=ERROR_SUCCESS)return false;
 const auto identity=InstanceIdentity();
 LSTATUS status=enabled?RegSetValueExW(key,identity.c_str(),0,REG_SZ,reinterpret_cast<const BYTE*>(command.c_str()),static_cast<DWORD>((command.size()+1)*sizeof(wchar_t))):RegDeleteValueW(key,identity.c_str());
 RegCloseKey(key);if(status!=ERROR_SUCCESS&&!(status==ERROR_FILE_NOT_FOUND&&!enabled))return false;
 if(RegCreateKeyExW(HKEY_CURRENT_USER,SettingsPath().c_str(),0,nullptr,0,KEY_SET_VALUE,nullptr,&key,nullptr)!=ERROR_SUCCESS)return false;
 const DWORD value=minimized?1:0;
 status=RegSetValueExW(key,L"Minimized",0,REG_DWORD,reinterpret_cast<const BYTE*>(&value),sizeof(value));
 RegCloseKey(key);return status==ERROR_SUCCESS;
}
UINT ActivationMessage(){static const UINT value=RegisterWindowMessageW(L"CrossLink.Activate.v1");return value;}
void ActivateExisting(const std::wstring& identity){
 FindContext state{&identity,nullptr};
 for(int i=0;i<20&&state.window==nullptr;i++){EnumWindows(FindWindowForInstance,reinterpret_cast<LPARAM>(&state));if(state.window==nullptr)Sleep(100);}
 if(state.window!=nullptr){DWORD_PTR result=0;SendMessageTimeoutW(state.window,ActivationMessage(),0,0,SMTO_ABORTIFHUNG,1000,&result);}
}
}
