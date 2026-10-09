#include "startup_helpers.h"
#include <cassert>
#include <iostream>
int main() {
  assert(crosslink::RunCommand(L"D:\\Apps with spaces\\CrossLink\\crosslink.exe", false) == L"\"D:\\Apps with spaces\\CrossLink\\crosslink.exe\"");
  assert(crosslink::RunCommand(L"D:\\Apps with spaces\\CrossLink\\crosslink.exe", true) == L"\"D:\\Apps with spaces\\CrossLink\\crosslink.exe\" --tray");
  assert(crosslink::RunCommand(L"", false).empty());
  assert(crosslink::RunCommand(L"bad\"path", false).empty());
  assert(crosslink::RunCommand(std::wstring(260,L'x'), false).empty());
  std::cout << "Startup command quoting and limits passed\n";
}
