#ifndef WIN32_LEAN_AND_MEAN
#define WIN32_LEAN_AND_MEAN
#endif
#ifndef NOMINMAX
#define NOMINMAX
#endif
// winsock2 must come before windows.h / Flutter headers that pull winsock.h.
#include <winsock2.h>
#include <ws2tcpip.h>
#include <windows.h>
#include <ws2bth.h>
#include <bluetoothapis.h>
#include <setupapi.h>
#include <cfgmgr32.h>
#include <initguid.h>
#include <devguid.h>
#include <usbiodef.h>

#include "dcs_zebra_plugin.h"

#include <flutter/method_channel.h>
#include <flutter/plugin_registrar_windows.h>
#include <flutter/standard_method_codec.h>

#include <algorithm>
#include <cctype>
#include <cstdint>
#include <map>
#include <memory>
#include <mutex>
#include <set>
#include <string>
#include <vector>

#pragma comment(lib, "Bthprops.lib")
#pragma comment(lib, "ws2_32.lib")
#pragma comment(lib, "setupapi.lib")
#pragma comment(lib, "cfgmgr32.lib")

// Serial / COM port device interface GUID.
DEFINE_GUID(GUID_DEVINTERFACE_COMPORT,
            0x86e0d1e0L, 0x8089, 0x11d0,
            0x9c, 0xe4, 0x08, 0x00, 0x3e, 0x30, 0x1f, 0x73);

// USB printer class interface (usbprint.sys) — required for raw ZPL to
// desktop Zebra printers that do not expose a virtual COM port.
DEFINE_GUID(GUID_DEVINTERFACE_USBPRINT,
            0x28d78fadL, 0x5a12, 0x11d1,
            0xae, 0x5b, 0x00, 0x00, 0xf8, 0x03, 0xa8, 0xc2);

namespace dcs_zebra {

namespace {

using flutter::EncodableList;
using flutter::EncodableMap;
using flutter::EncodableValue;

std::mutex g_io_mutex;
std::map<std::string, SOCKET> g_sockets;
std::map<std::string, HANDLE> g_serial_handles;
bool g_wsa_started = false;

std::string Narrow(const std::wstring& input) {
  if (input.empty()) return {};
  int size = WideCharToMultiByte(CP_UTF8, 0, input.c_str(), -1, nullptr, 0,
                                 nullptr, nullptr);
  std::string out(size > 0 ? size - 1 : 0, '\0');
  if (size > 0) {
    WideCharToMultiByte(CP_UTF8, 0, input.c_str(), -1, out.data(), size,
                        nullptr, nullptr);
  }
  return out;
}

std::wstring Widen(const std::string& input) {
  if (input.empty()) return {};
  int size = MultiByteToWideChar(CP_UTF8, 0, input.c_str(), -1, nullptr, 0);
  std::wstring out(size > 0 ? size - 1 : 0, L'\0');
  if (size > 0) {
    MultiByteToWideChar(CP_UTF8, 0, input.c_str(), -1, out.data(), size);
  }
  return out;
}

std::string FormatBtAddress(const BLUETOOTH_ADDRESS& address) {
  char buffer[32];
  sprintf_s(buffer, "%02X:%02X:%02X:%02X:%02X:%02X",
            address.rgBytes[5], address.rgBytes[4], address.rgBytes[3],
            address.rgBytes[2], address.rgBytes[1], address.rgBytes[0]);
  return std::string(buffer);
}

bool ParseBtAddress(const std::string& text, BTH_ADDR* out) {
  unsigned int b[6] = {};
  if (sscanf_s(text.c_str(), "%02x:%02x:%02x:%02x:%02x:%02x",
               &b[0], &b[1], &b[2], &b[3], &b[4], &b[5]) != 6) {
    return false;
  }
  *out = 0;
  for (int i = 0; i < 6; ++i) {
    *out = (*out << 8) | static_cast<BTH_ADDR>(b[i] & 0xFF);
  }
  return true;
}

bool EnsureWsa() {
  if (g_wsa_started) return true;
  WSADATA data;
  if (WSAStartup(MAKEWORD(2, 2), &data) != 0) return false;
  g_wsa_started = true;
  return true;
}

void CloseSocketLocked(const std::string& id) {
  auto it = g_sockets.find(id);
  if (it == g_sockets.end()) return;
  closesocket(it->second);
  g_sockets.erase(it);
}

void CloseSerialLocked(const std::string& id) {
  auto it = g_serial_handles.find(id);
  if (it == g_serial_handles.end()) return;
  CloseHandle(it->second);
  g_serial_handles.erase(it);
}

void CloseAnyLocked(const std::string& id) {
  CloseSocketLocked(id);
  CloseSerialLocked(id);
}

std::string RegistryPropertyString(HDEVINFO info, SP_DEVINFO_DATA* data,
                                   DWORD property) {
  DWORD type = 0;
  DWORD size = 0;
  SetupDiGetDeviceRegistryPropertyW(info, data, property, &type, nullptr, 0,
                                    &size);
  if (size == 0) return {};
  std::vector<BYTE> buffer(size);
  if (!SetupDiGetDeviceRegistryPropertyW(info, data, property, &type,
                                         buffer.data(), size, &size)) {
    return {};
  }
  if (type != REG_SZ && type != REG_MULTI_SZ) return {};
  return Narrow(reinterpret_cast<wchar_t*>(buffer.data()));
}

std::string ToLowerCopy(std::string value) {
  for (auto& c : value) {
    c = static_cast<char>(tolower(static_cast<unsigned char>(c)));
  }
  return value;
}

bool IsGenericManufacturer(const std::string& manufacturer) {
  std::string lower = ToLowerCopy(manufacturer);
  // Trim
  while (!lower.empty() && (lower.front() == ' ' || lower.front() == '\t')) {
    lower.erase(lower.begin());
  }
  while (!lower.empty() && (lower.back() == ' ' || lower.back() == '\t')) {
    lower.pop_back();
  }
  if (lower.empty()) return true;
  // COM "Standard Serial over Bluetooth link" reports Microsoft — Device Manager
  // shows the Bluetooth/USB parent manufacturer instead.
  return lower == "microsoft" || lower == "microsoft corporation" ||
         lower == "(standard system devices)" ||
         lower == "standard system devices" ||
         lower.rfind("(standard ", 0) == 0;
}

std::string DevNodePropertyString(DEVINST inst, ULONG property) {
  WCHAR buffer[512] = {};
  ULONG size = sizeof(buffer);
  ULONG type = 0;
  if (CM_Get_DevNode_Registry_PropertyW(inst, property, &type, buffer, &size,
                                        0) != CR_SUCCESS) {
    return {};
  }
  if (type != REG_SZ && type != REG_MULTI_SZ) return {};
  return Narrow(buffer);
}

/// Prefer a non-generic manufacturer: walk parent chain like Device Manager.
std::string ResolveManufacturer(HDEVINFO info, SP_DEVINFO_DATA* data) {
  std::string mfg = RegistryPropertyString(info, data, SPDRP_MFG);
  if (!IsGenericManufacturer(mfg)) return mfg;

  DEVINST current = data->DevInst;
  for (int depth = 0; depth < 8; ++depth) {
    DEVINST parent = 0;
    if (CM_Get_Parent(&parent, current, 0) != CR_SUCCESS) break;
    std::string parent_mfg = DevNodePropertyString(parent, CM_DRP_MFG);
    if (!IsGenericManufacturer(parent_mfg)) return parent_mfg;
    current = parent;
  }
  // Keep leaf manufacturer only when nothing better was found.
  return IsGenericManufacturer(mfg) ? std::string{} : mfg;
}

std::string ExtractComPort(const std::string& text) {
  // Prefer explicit COMn tokens.
  for (size_t i = 0; i + 3 < text.size(); ++i) {
    if ((text[i] == 'C' || text[i] == 'c') &&
        (text[i + 1] == 'O' || text[i + 1] == 'o') &&
        (text[i + 2] == 'M' || text[i + 2] == 'm') &&
        std::isdigit(static_cast<unsigned char>(text[i + 3]))) {
      size_t end = i + 3;
      while (end < text.size() &&
             std::isdigit(static_cast<unsigned char>(text[end]))) {
        ++end;
      }
      std::string port = text.substr(i, end - i);
      for (auto& c : port) c = static_cast<char>(toupper(static_cast<unsigned char>(c)));
      return port;
    }
  }
  return {};
}

struct UsbIdentity {
  std::string vid;
  std::string pid;
  std::string serial;
};

UsbIdentity ParseUsbIdentity(const std::string& path) {
  UsbIdentity out;
  const std::string lower = ToLowerCopy(path);
  auto vidPos = lower.find("vid_");
  if (vidPos != std::string::npos && vidPos + 8 <= lower.size()) {
    out.vid = lower.substr(vidPos + 4, 4);
  }
  auto pidPos = lower.find("pid_");
  if (pidPos != std::string::npos && pidPos + 8 <= lower.size()) {
    out.pid = lower.substr(pidPos + 4, 4);
  }
  // Path form: \\?\usb#vid_xxxx&pid_yyyy#SERIAL#{guid}
  auto hash1 = lower.find('#');
  if (hash1 != std::string::npos) {
    auto hash2 = lower.find('#', hash1 + 1);
    if (hash2 != std::string::npos) {
      auto hash3 = lower.find('#', hash2 + 1);
      if (hash3 != std::string::npos && hash3 > hash2 + 1) {
        out.serial = lower.substr(hash2 + 1, hash3 - hash2 - 1);
      }
    }
  }
  return out;
}

bool IsUsbPrintGuid(const std::string& path) {
  return ToLowerCopy(path).find("28d78fad-5a12-11d1-ae5b-0000f803a8c2") !=
         std::string::npos;
}

EncodableList EnumerateDeviceInterfaces(const GUID& guid) {
  EncodableList found;
  HDEVINFO info = SetupDiGetClassDevsW(&guid, nullptr, nullptr,
                                       DIGCF_PRESENT | DIGCF_DEVICEINTERFACE);
  if (info == INVALID_HANDLE_VALUE) return found;

  SP_DEVICE_INTERFACE_DATA iface{};
  iface.cbSize = sizeof(iface);
  for (DWORD index = 0;
       SetupDiEnumDeviceInterfaces(info, nullptr, &guid, index, &iface);
       ++index) {
    DWORD required = 0;
    SetupDiGetDeviceInterfaceDetailW(info, &iface, nullptr, 0, &required,
                                     nullptr);
    if (required == 0) continue;
    std::vector<BYTE> detail_buffer(required);
    auto* detail =
        reinterpret_cast<SP_DEVICE_INTERFACE_DETAIL_DATA_W*>(detail_buffer.data());
    detail->cbSize = sizeof(SP_DEVICE_INTERFACE_DETAIL_DATA_W);
    SP_DEVINFO_DATA dev{};
    dev.cbSize = sizeof(dev);
    if (!SetupDiGetDeviceInterfaceDetailW(info, &iface, detail, required,
                                          nullptr, &dev)) {
      continue;
    }

    EncodableMap map;
    map[EncodableValue("path")] = EncodableValue(Narrow(detail->DevicePath));
    map[EncodableValue("friendly")] =
        EncodableValue(RegistryPropertyString(info, &dev, SPDRP_FRIENDLYNAME));
    map[EncodableValue("description")] =
        EncodableValue(RegistryPropertyString(info, &dev, SPDRP_DEVICEDESC));
    map[EncodableValue("hardwareId")] =
        EncodableValue(RegistryPropertyString(info, &dev, SPDRP_HARDWAREID));
    map[EncodableValue("manufacturer")] =
        EncodableValue(ResolveManufacturer(info, &dev));
    found.push_back(EncodableValue(map));
  }
  SetupDiDestroyDeviceInfoList(info);
  return found;
}

std::string FindUsbPrintPathForIdentity(const UsbIdentity& identity) {
  if (identity.vid.empty() || identity.pid.empty()) return {};
  auto printers = EnumerateDeviceInterfaces(GUID_DEVINTERFACE_USBPRINT);
  for (const auto& item : printers) {
    const auto* map = std::get_if<EncodableMap>(&item);
    if (map == nullptr) continue;
    auto pathIt = map->find(EncodableValue("path"));
    if (pathIt == map->end()) continue;
    const auto* path = std::get_if<std::string>(&pathIt->second);
    if (path == nullptr || path->empty()) continue;
    const UsbIdentity other = ParseUsbIdentity(*path);
    if (other.vid != identity.vid || other.pid != identity.pid) continue;
    if (!identity.serial.empty() && !other.serial.empty() &&
        other.serial != identity.serial) {
      continue;
    }
    return *path;
  }
  // Fall back to first matching VID/PID even without serial match.
  for (const auto& item : printers) {
    const auto* map = std::get_if<EncodableMap>(&item);
    if (map == nullptr) continue;
    auto pathIt = map->find(EncodableValue("path"));
    if (pathIt == map->end()) continue;
    const auto* path = std::get_if<std::string>(&pathIt->second);
    if (path == nullptr || path->empty()) continue;
    const UsbIdentity other = ParseUsbIdentity(*path);
    if (other.vid == identity.vid && other.pid == identity.pid) {
      return *path;
    }
  }
  return {};
}

std::string ResolveUsbOpenPath(const std::string& address) {
  if (address.empty()) return {};
  if (IsUsbPrintGuid(address)) return address;
  if (ToLowerCopy(address).rfind("com", 0) == 0) return {};

  // Generic USB_DEVICE path → locate matching usbprint.sys interface.
  const UsbIdentity identity = ParseUsbIdentity(address);
  std::string print_path = FindUsbPrintPathForIdentity(identity);
  if (!print_path.empty()) return print_path;

  // Last resort: try the given path directly (some stacks accept it).
  return address;
}

std::string ConnectSerial(const std::string& id, const std::string& address);

EncodableList DiscoverBluetooth() {
  EncodableList found;
  BLUETOOTH_DEVICE_SEARCH_PARAMS search{};
  search.dwSize = sizeof(search);
  search.fReturnAuthenticated = TRUE;
  search.fReturnRemembered = TRUE;
  search.fReturnUnknown = TRUE;
  search.fReturnConnected = TRUE;
  search.fIssueInquiry = TRUE;
  search.cTimeoutMultiplier = 2;
  search.hRadio = nullptr;

  BLUETOOTH_DEVICE_INFO info{};
  info.dwSize = sizeof(info);

  HBLUETOOTH_DEVICE_FIND find = BluetoothFindFirstDevice(&search, &info);
  if (find == nullptr) {
    return found;
  }

  do {
    std::string name = Narrow(info.szName);
    std::string address = FormatBtAddress(info.Address);
    EncodableMap map;
    map[EncodableValue("id")] = EncodableValue("bluetooth:" + address);
    map[EncodableValue("address")] = EncodableValue(address);
    map[EncodableValue("connectionType")] = EncodableValue("bluetooth");
    map[EncodableValue("name")] = EncodableValue(name);
    map[EncodableValue("paired")] =
        EncodableValue(info.fAuthenticated || info.fRemembered);
    found.push_back(EncodableValue(map));
  } while (BluetoothFindNextDevice(find, &info));

  BluetoothFindDeviceClose(find);
  return found;
}

EncodableList DiscoverComPorts() {
  EncodableList found;
  std::set<std::string> seen;

  HDEVINFO info = SetupDiGetClassDevsW(&GUID_DEVINTERFACE_COMPORT, nullptr,
                                       nullptr,
                                       DIGCF_PRESENT | DIGCF_DEVICEINTERFACE);
  if (info != INVALID_HANDLE_VALUE) {
    SP_DEVICE_INTERFACE_DATA iface{};
    iface.cbSize = sizeof(iface);
    for (DWORD index = 0;
         SetupDiEnumDeviceInterfaces(info, nullptr, &GUID_DEVINTERFACE_COMPORT,
                                     index, &iface);
         ++index) {
      DWORD required = 0;
      SetupDiGetDeviceInterfaceDetailW(info, &iface, nullptr, 0, &required,
                                       nullptr);
      if (required == 0) continue;
      std::vector<BYTE> detail_buffer(required);
      auto* detail =
          reinterpret_cast<SP_DEVICE_INTERFACE_DETAIL_DATA_W*>(detail_buffer.data());
      detail->cbSize = sizeof(SP_DEVICE_INTERFACE_DETAIL_DATA_W);
      SP_DEVINFO_DATA dev{};
      dev.cbSize = sizeof(dev);
      if (!SetupDiGetDeviceInterfaceDetailW(info, &iface, detail, required,
                                            nullptr, &dev)) {
        continue;
      }

      std::string friendly =
          RegistryPropertyString(info, &dev, SPDRP_FRIENDLYNAME);
      std::string description =
          RegistryPropertyString(info, &dev, SPDRP_DEVICEDESC);
      std::string manufacturer = ResolveManufacturer(info, &dev);
      std::string port = ExtractComPort(friendly);
      if (port.empty()) port = ExtractComPort(description);
      if (port.empty()) {
        // Fallback: parse \\.\COMn from device path.
        port = ExtractComPort(Narrow(detail->DevicePath));
      }
      if (port.empty()) continue;
      if (!seen.insert(port).second) continue;

      std::string name = friendly.empty() ? description : friendly;
      if (name.empty()) name = port;

      EncodableMap map;
      map[EncodableValue("id")] = EncodableValue("serial:" + port);
      map[EncodableValue("address")] = EncodableValue(port);
      map[EncodableValue("connectionType")] = EncodableValue("serial");
      map[EncodableValue("name")] = EncodableValue(name);
      map[EncodableValue("model")] = EncodableValue(description);
      if (!manufacturer.empty()) {
        map[EncodableValue("manufacturer")] = EncodableValue(manufacturer);
      }
      found.push_back(EncodableValue(map));
    }
    SetupDiDestroyDeviceInfoList(info);
  }

  // Also include DOS device names (covers ports SetupAPI may miss).
  char buffer[65536] = {};
  DWORD n = QueryDosDeviceA(nullptr, buffer, static_cast<DWORD>(sizeof(buffer)));
  if (n != 0) {
    for (const char* p = buffer; *p; p += strlen(p) + 1) {
      std::string name = p;
      if (name.size() < 4) continue;
      if (!(name[0] == 'C' || name[0] == 'c')) continue;
      if (!(name[1] == 'O' || name[1] == 'o')) continue;
      if (!(name[2] == 'M' || name[2] == 'm')) continue;
      if (!std::isdigit(static_cast<unsigned char>(name[3]))) continue;
      for (auto& c : name) {
        c = static_cast<char>(toupper(static_cast<unsigned char>(c)));
      }
      if (!seen.insert(name).second) continue;
      EncodableMap map;
      map[EncodableValue("id")] = EncodableValue("serial:" + name);
      map[EncodableValue("address")] = EncodableValue(name);
      map[EncodableValue("connectionType")] = EncodableValue("serial");
      map[EncodableValue("name")] = EncodableValue(name);
      found.push_back(EncodableValue(map));
    }
  }

  return found;
}

EncodableList DiscoverUsb() {
  EncodableList found;
  std::set<std::string> seen_ids;

  auto pushUsb = [&](const std::string& open_path, const std::string& name,
                     const std::string& description, const std::string& serial,
                     const std::string& manufacturer) {
    if (open_path.empty()) return;
    const std::string id = "usb:" + open_path;
    if (!seen_ids.insert(id).second) return;
    EncodableMap map;
    map[EncodableValue("id")] = EncodableValue(id);
    map[EncodableValue("address")] = EncodableValue(open_path);
    map[EncodableValue("connectionType")] = EncodableValue("usb");
    map[EncodableValue("name")] = EncodableValue(name.empty() ? open_path : name);
    map[EncodableValue("model")] = EncodableValue(description);
    if (!serial.empty()) {
      map[EncodableValue("serialNumber")] = EncodableValue(serial);
    }
    if (!manufacturer.empty()) {
      map[EncodableValue("manufacturer")] = EncodableValue(manufacturer);
    }
    found.push_back(EncodableValue(map));
  };

  // Prefer usbprint.sys interfaces — these are openable for raw ZPL.
  for (const auto& item : EnumerateDeviceInterfaces(GUID_DEVINTERFACE_USBPRINT)) {
    const auto* map = std::get_if<EncodableMap>(&item);
    if (map == nullptr) continue;
    auto pathIt = map->find(EncodableValue("path"));
    auto friendlyIt = map->find(EncodableValue("friendly"));
    auto descIt = map->find(EncodableValue("description"));
    auto mfgIt = map->find(EncodableValue("manufacturer"));
    const auto* path = pathIt == map->end()
                           ? nullptr
                           : std::get_if<std::string>(&pathIt->second);
    if (path == nullptr || path->empty()) continue;
    std::string friendly;
    std::string description;
    std::string manufacturer;
    if (friendlyIt != map->end()) {
      if (const auto* s = std::get_if<std::string>(&friendlyIt->second)) {
        friendly = *s;
      }
    }
    if (descIt != map->end()) {
      if (const auto* s = std::get_if<std::string>(&descIt->second)) {
        description = *s;
      }
    }
    if (mfgIt != map->end()) {
      if (const auto* s = std::get_if<std::string>(&mfgIt->second)) {
        manufacturer = *s;
      }
    }
    const UsbIdentity identity = ParseUsbIdentity(*path);
    std::string name = friendly.empty() ? description : friendly;
    pushUsb(*path, name, description, identity.serial, manufacturer);
  }

  // Also surface generic USB devices (e.g. Zebra VID 0a5f), remapping to
  // usbprint path when available so Connect works from the listed address.
  for (const auto& item :
       EnumerateDeviceInterfaces(GUID_DEVINTERFACE_USB_DEVICE)) {
    const auto* map = std::get_if<EncodableMap>(&item);
    if (map == nullptr) continue;
    auto pathIt = map->find(EncodableValue("path"));
    auto friendlyIt = map->find(EncodableValue("friendly"));
    auto descIt = map->find(EncodableValue("description"));
    auto mfgIt = map->find(EncodableValue("manufacturer"));
    const auto* path = pathIt == map->end()
                           ? nullptr
                           : std::get_if<std::string>(&pathIt->second);
    if (path == nullptr || path->empty()) continue;

    std::string friendly;
    std::string description;
    std::string manufacturer;
    if (friendlyIt != map->end()) {
      if (const auto* s = std::get_if<std::string>(&friendlyIt->second)) {
        friendly = *s;
      }
    }
    if (descIt != map->end()) {
      if (const auto* s = std::get_if<std::string>(&descIt->second)) {
        description = *s;
      }
    }
    if (mfgIt != map->end()) {
      if (const auto* s = std::get_if<std::string>(&mfgIt->second)) {
        manufacturer = *s;
      }
    }

    // Skip non-printer noise unless it looks like Zebra / already has a COM.
    const UsbIdentity identity = ParseUsbIdentity(*path);
    const std::string hay = ToLowerCopy(friendly + " " + description + " " +
                                        manufacturer + " " + *path);
    const bool zebra_vid = identity.vid == "0a5f";
    const bool name_hint =
        hay.find("zebra") != std::string::npos ||
        hay.find("zdesigner") != std::string::npos ||
        hay.find("printer") != std::string::npos;
    std::string com = ExtractComPort(friendly);
    if (com.empty()) com = ExtractComPort(description);
    if (!zebra_vid && !name_hint && com.empty()) continue;

    if (!com.empty()) {
      const std::string id = "serial:" + com;
      if (!seen_ids.insert(id).second) continue;
      EncodableMap entry;
      entry[EncodableValue("id")] = EncodableValue(id);
      entry[EncodableValue("address")] = EncodableValue(com);
      entry[EncodableValue("connectionType")] = EncodableValue("serial");
      entry[EncodableValue("name")] =
          EncodableValue((friendly.empty() ? description : friendly) + " (" +
                         com + ")");
      entry[EncodableValue("model")] = EncodableValue(description);
      if (!manufacturer.empty()) {
        entry[EncodableValue("manufacturer")] = EncodableValue(manufacturer);
      }
      found.push_back(EncodableValue(entry));
      continue;
    }

    std::string open_path = FindUsbPrintPathForIdentity(identity);
    if (open_path.empty()) open_path = *path;
    std::string name = friendly.empty() ? description : friendly;
    pushUsb(open_path, name, description, identity.serial, manufacturer);
  }

  return found;
}

std::string ConnectUsb(const std::string& id, const std::string& address) {
  std::string upper = address;
  for (auto& c : upper) {
    c = static_cast<char>(toupper(static_cast<unsigned char>(c)));
  }
  if (upper.rfind("COM", 0) == 0) {
    return ConnectSerial(id, upper);
  }

  const std::string open_path = ResolveUsbOpenPath(address);
  if (open_path.empty()) {
    return "Could not resolve a USB printer interface for this device.";
  }

  // usbprint.sys typically wants GENERIC_WRITE + FILE_SHARE_READ + OPEN_ALWAYS
  // (or OPEN_EXISTING). Try a few combinations for driver quirks.
  HANDLE handle = INVALID_HANDLE_VALUE;
  const DWORD accesses[] = {
      GENERIC_READ | GENERIC_WRITE,
      GENERIC_WRITE,
  };
  const DWORD shares[] = {
      FILE_SHARE_READ | FILE_SHARE_WRITE,
      FILE_SHARE_READ,
      0,
  };
  const DWORD dispositions[] = {OPEN_EXISTING, OPEN_ALWAYS};

  DWORD last_error = 0;
  const std::wstring wide_path = Widen(open_path);
  for (DWORD access : accesses) {
    for (DWORD share : shares) {
      for (DWORD disposition : dispositions) {
        handle = CreateFileW(wide_path.c_str(), access, share, nullptr,
                             disposition,
                             FILE_ATTRIBUTE_NORMAL | FILE_FLAG_SEQUENTIAL_SCAN,
                             nullptr);
        if (handle != INVALID_HANDLE_VALUE) break;
        last_error = GetLastError();
      }
      if (handle != INVALID_HANDLE_VALUE) break;
    }
    if (handle != INVALID_HANDLE_VALUE) break;
  }

  if (handle == INVALID_HANDLE_VALUE) {
    return "Failed to open USB printer (Win32 " + std::to_string(last_error) +
           "). Path: " + open_path +
           ". Close Windows print jobs / other apps using the printer and retry.";
  }

  {
    std::lock_guard<std::mutex> lock(g_io_mutex);
    CloseAnyLocked(id);
    g_serial_handles[id] = handle;
  }
  return {};
}

std::string ConnectBluetooth(const std::string& id, const std::string& address) {
  if (!EnsureWsa()) {
    return "WSAStartup failed";
  }
  BTH_ADDR btAddr = 0;
  if (!ParseBtAddress(address, &btAddr)) {
    return "Invalid Bluetooth address";
  }

  SOCKET sock = socket(AF_BTH, SOCK_STREAM, BTHPROTO_RFCOMM);
  if (sock == INVALID_SOCKET) {
    return "Failed to create RFCOMM socket";
  }

  SOCKADDR_BTH sa{};
  sa.addressFamily = AF_BTH;
  sa.btAddr = btAddr;
  // Standard Serial Port Profile UUID used by Zebra classic Bluetooth printers.
  sa.serviceClassId = SerialPortServiceClass_UUID;
  sa.port = BT_PORT_ANY;

  if (connect(sock, reinterpret_cast<SOCKADDR*>(&sa), sizeof(sa)) == SOCKET_ERROR) {
    const int err = WSAGetLastError();
    closesocket(sock);
    return "RFCOMM connect failed (WSA " + std::to_string(err) +
           "). Pair the Zebra printer in Windows Settings first.";
  }

  {
    std::lock_guard<std::mutex> lock(g_io_mutex);
    CloseAnyLocked(id);
    g_sockets[id] = sock;
  }
  return {};
}

std::string ConnectSerial(const std::string& id, const std::string& address) {
  std::string port = address;
  for (auto& c : port) {
    c = static_cast<char>(toupper(static_cast<unsigned char>(c)));
  }
  if (port.rfind("COM", 0) != 0) {
    return "Invalid COM port address (expected COMn)";
  }

  // COM10+ requires the \\.\ prefix.
  std::string path = "\\\\.\\" + port;
  HANDLE handle = CreateFileA(path.c_str(), GENERIC_READ | GENERIC_WRITE, 0,
                              nullptr, OPEN_EXISTING, 0, nullptr);
  if (handle == INVALID_HANDLE_VALUE) {
    return "Failed to open " + port + " (Win32 " +
           std::to_string(GetLastError()) +
           "). Close other apps using this port and retry.";
  }

  DCB dcb{};
  dcb.DCBlength = sizeof(dcb);
  if (!GetCommState(handle, &dcb)) {
    CloseHandle(handle);
    return "GetCommState failed for " + port;
  }
  // Link-OS USB/serial printers commonly use 115200 8N1.
  dcb.BaudRate = CBR_115200;
  dcb.ByteSize = 8;
  dcb.Parity = NOPARITY;
  dcb.StopBits = ONESTOPBIT;
  dcb.fBinary = TRUE;
  dcb.fDtrControl = DTR_CONTROL_ENABLE;
  dcb.fRtsControl = RTS_CONTROL_ENABLE;
  if (!SetCommState(handle, &dcb)) {
    CloseHandle(handle);
    return "SetCommState failed for " + port;
  }

  COMMTIMEOUTS timeouts{};
  timeouts.ReadIntervalTimeout = 50;
  timeouts.ReadTotalTimeoutConstant = 2000;
  timeouts.ReadTotalTimeoutMultiplier = 10;
  timeouts.WriteTotalTimeoutConstant = 2000;
  timeouts.WriteTotalTimeoutMultiplier = 10;
  SetCommTimeouts(handle, &timeouts);
  SetupComm(handle, 8192, 8192);
  PurgeComm(handle, PURGE_RXCLEAR | PURGE_TXCLEAR);

  {
    std::lock_guard<std::mutex> lock(g_io_mutex);
    CloseAnyLocked(id);
    g_serial_handles[id] = handle;
  }
  return {};
}

std::string WriteBytes(const std::string& id, const std::vector<uint8_t>& bytes) {
  std::lock_guard<std::mutex> lock(g_io_mutex);
  auto serial = g_serial_handles.find(id);
  if (serial != g_serial_handles.end()) {
    DWORD written = 0;
    if (!WriteFile(serial->second, bytes.data(),
                   static_cast<DWORD>(bytes.size()), &written, nullptr)) {
      return "Serial write failed (Win32 " + std::to_string(GetLastError()) + ")";
    }
    return {};
  }
  auto it = g_sockets.find(id);
  if (it == g_sockets.end()) return "Not connected";
  int sent = send(it->second, reinterpret_cast<const char*>(bytes.data()),
                  static_cast<int>(bytes.size()), 0);
  if (sent == SOCKET_ERROR) {
    return "Write failed (WSA " + std::to_string(WSAGetLastError()) + ")";
  }
  return {};
}

std::vector<uint8_t> ReadBytes(const std::string& id, int timeoutMs) {
  HANDLE serial = INVALID_HANDLE_VALUE;
  SOCKET sock = INVALID_SOCKET;
  {
    std::lock_guard<std::mutex> lock(g_io_mutex);
    auto sit = g_serial_handles.find(id);
    if (sit != g_serial_handles.end()) {
      serial = sit->second;
    } else {
      auto it = g_sockets.find(id);
      if (it == g_sockets.end()) return {};
      sock = it->second;
    }
  }

  if (serial != INVALID_HANDLE_VALUE) {
    COMMTIMEOUTS timeouts{};
    timeouts.ReadIntervalTimeout = 50;
    timeouts.ReadTotalTimeoutConstant = static_cast<DWORD>((std::max)(timeoutMs, 1));
    timeouts.ReadTotalTimeoutMultiplier = 0;
    timeouts.WriteTotalTimeoutConstant = 2000;
    timeouts.WriteTotalTimeoutMultiplier = 10;
    SetCommTimeouts(serial, &timeouts);
    char buffer[4096];
    DWORD n = 0;
    if (!ReadFile(serial, buffer, sizeof(buffer), &n, nullptr) || n == 0) {
      return {};
    }
    return std::vector<uint8_t>(buffer, buffer + n);
  }

  DWORD timeout = static_cast<DWORD>((std::max)(timeoutMs, 1));
  setsockopt(sock, SOL_SOCKET, SO_RCVTIMEO, reinterpret_cast<const char*>(&timeout),
             sizeof(timeout));
  char buffer[4096];
  int n = recv(sock, buffer, sizeof(buffer), 0);
  if (n <= 0) return {};
  return std::vector<uint8_t>(buffer, buffer + n);
}

bool Wants(const std::vector<std::string>& types, const char* value) {
  if (types.empty()) return true;
  return std::find(types.begin(), types.end(), value) != types.end();
}

}  // namespace

void DcsZebraPlugin::RegisterWithRegistrar(
    flutter::PluginRegistrarWindows* registrar) {
  auto channel =
      std::make_unique<flutter::MethodChannel<flutter::EncodableValue>>(
          registrar->messenger(), "dcs_zebra",
          &flutter::StandardMethodCodec::GetInstance());

  auto plugin = std::make_unique<DcsZebraPlugin>();

  channel->SetMethodCallHandler(
      [plugin_pointer = plugin.get()](const auto& call, auto result) {
        plugin_pointer->HandleMethodCall(call, std::move(result));
      });

  registrar->AddPlugin(std::move(plugin));
}

DcsZebraPlugin::DcsZebraPlugin() {}

DcsZebraPlugin::~DcsZebraPlugin() {
  std::lock_guard<std::mutex> lock(g_io_mutex);
  for (auto& entry : g_sockets) {
    closesocket(entry.second);
  }
  g_sockets.clear();
  for (auto& entry : g_serial_handles) {
    CloseHandle(entry.second);
  }
  g_serial_handles.clear();
}

void DcsZebraPlugin::HandleMethodCall(
    const flutter::MethodCall<flutter::EncodableValue>& method_call,
    std::unique_ptr<flutter::MethodResult<flutter::EncodableValue>> result) {
  const auto& method = method_call.method_name();

  if (method == "capabilities") {
    EncodableMap map;
    map[EncodableValue("tcp")] = EncodableValue(true);
    map[EncodableValue("bluetooth")] = EncodableValue(true);
    map[EncodableValue("bluetoothLe")] = EncodableValue(false);
    map[EncodableValue("usb")] = EncodableValue(true);
    map[EncodableValue("serial")] = EncodableValue(true);
    result->Success(EncodableValue(map));
    return;
  }

  if (method == "startDiscover") {
    // No EventChannel on Windows yet — Dart falls back to one-shot discover.
    result->NotImplemented();
    return;
  }

  if (method == "cancelDiscover") {
    result->Success();
    return;
  }

  if (method == "pair" || method == "unpair") {
    result->Success(EncodableValue("unsupported"));
    return;
  }

  if (method == "bondedPrinters" || method == "pairedAccessories") {
    EncodableList bonded;
    for (const auto& item : DiscoverBluetooth()) {
      const auto* map = std::get_if<EncodableMap>(&item);
      if (map == nullptr) continue;
      auto pairedIt = map->find(EncodableValue("paired"));
      bool paired = false;
      if (pairedIt != map->end()) {
        if (const auto* b = std::get_if<bool>(&pairedIt->second)) paired = *b;
      }
      if (paired) bonded.push_back(item);
    }
    result->Success(EncodableValue(bonded));
    return;
  }

  if (method == "ensureBluetoothPermissions") {
    result->Success(EncodableValue("granted"));
    return;
  }

  if (method == "discover") {
    EncodableList found;
    std::set<std::string> seen_ids;
    const auto* args = std::get_if<EncodableMap>(method_call.arguments());
    std::vector<std::string> types;
    if (args != nullptr) {
      auto it = args->find(EncodableValue("types"));
      if (it != args->end()) {
        if (const auto* list = std::get_if<EncodableList>(&it->second)) {
          for (const auto& item : *list) {
            if (const auto* s = std::get_if<std::string>(&item)) {
              types.push_back(*s);
            }
          }
        }
      }
    }
    auto appendUnique = [&](EncodableList items) {
      for (const auto& item : items) {
        const auto* map = std::get_if<EncodableMap>(&item);
        if (map == nullptr) continue;
        auto idIt = map->find(EncodableValue("id"));
        std::string id;
        if (idIt != map->end()) {
          if (const auto* s = std::get_if<std::string>(&idIt->second)) {
            id = *s;
          }
        }
        if (!id.empty() && !seen_ids.insert(id).second) continue;
        found.push_back(item);
      }
    };
    if (Wants(types, "bluetooth")) {
      appendUnique(DiscoverBluetooth());
    }
    if (Wants(types, "serial") || Wants(types, "usb")) {
      appendUnique(DiscoverComPorts());
    }
    if (Wants(types, "usb")) {
      appendUnique(DiscoverUsb());
    }
    result->Success(EncodableValue(found));
    return;
  }

  if (method == "connect") {
    const auto* args = std::get_if<EncodableMap>(method_call.arguments());
    if (args == nullptr) {
      result->Error("bad_args", "Missing arguments");
      return;
    }
    auto idIt = args->find(EncodableValue("id"));
    auto addressIt = args->find(EncodableValue("address"));
    auto typeIt = args->find(EncodableValue("connectionType"));
    if (idIt == args->end() || addressIt == args->end()) {
      result->Error("bad_args", "id/address required");
      return;
    }
    const auto* id = std::get_if<std::string>(&idIt->second);
    const auto* address = std::get_if<std::string>(&addressIt->second);
    std::string type = "bluetooth";
    if (typeIt != args->end()) {
      if (const auto* t = std::get_if<std::string>(&typeIt->second)) type = *t;
    }
    if (id == nullptr || address == nullptr) {
      result->Error("bad_args", "id/address required");
      return;
    }

    std::string error;
    if (type == "bluetooth") {
      error = ConnectBluetooth(*id, *address);
    } else if (type == "serial") {
      error = ConnectSerial(*id, *address);
    } else if (type == "usb") {
      error = ConnectUsb(*id, *address);
    } else {
      result->Error(
          "unsupported",
          "Windows native plugin supports Bluetooth RFCOMM, COM/serial, and "
          "USB printers (usbprint). Use Dart TCP for network printers.");
      return;
    }
    if (!error.empty()) {
      result->Error("connect_failed", error);
      return;
    }
    result->Success();
    return;
  }

  if (method == "disconnect") {
    const auto* args = std::get_if<EncodableMap>(method_call.arguments());
    if (args != nullptr) {
      auto idIt = args->find(EncodableValue("id"));
      if (idIt != args->end()) {
        if (const auto* id = std::get_if<std::string>(&idIt->second)) {
          std::lock_guard<std::mutex> lock(g_io_mutex);
          CloseAnyLocked(*id);
        }
      }
    }
    result->Success();
    return;
  }

  if (method == "write") {
    const auto* args = std::get_if<EncodableMap>(method_call.arguments());
    if (args == nullptr) {
      result->Error("bad_args", "Missing arguments");
      return;
    }
    auto idIt = args->find(EncodableValue("id"));
    auto bytesIt = args->find(EncodableValue("bytes"));
    if (idIt == args->end() || bytesIt == args->end()) {
      result->Error("bad_args", "id/bytes required");
      return;
    }
    const auto* id = std::get_if<std::string>(&idIt->second);
    const auto* bytes = std::get_if<std::vector<uint8_t>>(&bytesIt->second);
    if (id == nullptr || bytes == nullptr) {
      result->Error("bad_args", "id/bytes required");
      return;
    }
    const std::string error = WriteBytes(*id, *bytes);
    if (!error.empty()) {
      result->Error("write_failed", error);
      return;
    }
    result->Success();
    return;
  }

  if (method == "read") {
    const auto* args = std::get_if<EncodableMap>(method_call.arguments());
    std::string id;
    int timeoutMs = 2000;
    if (args != nullptr) {
      auto idIt = args->find(EncodableValue("id"));
      if (idIt != args->end()) {
        if (const auto* value = std::get_if<std::string>(&idIt->second)) {
          id = *value;
        }
      }
      auto timeoutIt = args->find(EncodableValue("timeoutMs"));
      if (timeoutIt != args->end()) {
        if (const auto* value = std::get_if<int32_t>(&timeoutIt->second)) {
          timeoutMs = *value;
        }
      }
    }
    auto data = ReadBytes(id, timeoutMs);
    if (data.empty()) {
      result->Success();
      return;
    }
    result->Success(EncodableValue(data));
    return;
  }

  if (method == "getStatus") {
    // Host status over RFCOMM/serial is handled by Dart ~HS after connect.
    result->Success();
    return;
  }

  result->NotImplemented();
}

}  // namespace dcs_zebra
