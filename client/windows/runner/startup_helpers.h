#ifndef CROSSLINK_STARTUP_HELPERS_H_
#define CROSSLINK_STARTUP_HELPERS_H_
#include <windows.h>
#include <string>
namespace crosslink {
struct StartupSettings { bool enabled = false; bool minimized = false; };
std::wstring RunCommand(const std::wstring& path, bool minimized);
std::wstring InstanceIdentity();
StartupSettings ReadStartup();
bool WriteStartup(bool enabled, bool minimized);
UINT ActivationMessage();
void ActivateExisting(const std::wstring& identity);
}
#endif
