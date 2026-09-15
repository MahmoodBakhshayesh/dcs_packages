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
#include <string>
#include <vector>

#ifndef WIN32_LEAN_AND_MEAN
#define WIN32_LEAN_AND_MEAN
#endif
#include <windows.h>
#include <winsock2.h>
#include <ws2bth.h>
#include <bluetoothapis.h>

#pragma comment(lib, "Bthprops.lib")
#pragma comment(lib, "ws2_32.lib")

namespace dcs_zebra {

namespace {

using flutter::EncodableList;
using flutter::EncodableMap;
using flutter::EncodableValue;

std::mutex g_socket_mutex;
std::map<std::string, SOCKET> g_sockets;
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

std::string ToLower(std::string value) {
  for (auto& c : value) c = static_cast<char>(tolower(static_cast<unsigned char>(c)));
  return value;
}

bool LooksLikeZebra(const std::string& name) {
  const std::string lower = ToLower(name);
  if (lower.empty()) return false;
  // Reject common non-printer Bluetooth accessories.
  const char* negatives[] = {
      "buds", "airpods", "headset", "headphone", "earbud", "speaker",
      "watch", "phone", "mouse", "keyboard", "gamepad", "controller",
      "beats", "audio", "tv"};
  for (const char* token : negatives) {
    if (lower.find(token) != std::string::npos) return false;
  }
  const char* positives[] = {
      "zebra", "zq", "zd", "zt", "zr", "ql", "gc", "gk", "gx",
      "imz", "mz", "printer", "tln", "tlg"};
  for (const char* token : positives) {
    if (lower.find(token) != std::string::npos) return true;
  }
  return false;
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
    if (!LooksLikeZebra(name)) {
      continue;
    }
    std::string address = FormatBtAddress(info.Address);
    EncodableMap map;
    map[EncodableValue("id")] = EncodableValue("bluetooth:" + address);
    map[EncodableValue("address")] = EncodableValue(address);
    map[EncodableValue("connectionType")] = EncodableValue("bluetooth");
    map[EncodableValue("name")] = EncodableValue(name);
    found.push_back(EncodableValue(map));
  } while (BluetoothFindNextDevice(find, &info));

  BluetoothFindDeviceClose(find);
  return found;
}

EncodableList DiscoverUsb() { return EncodableList(); }

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
    std::lock_guard<std::mutex> lock(g_socket_mutex);
    CloseSocketLocked(id);
    g_sockets[id] = sock;
  }
  return {};
}

std::string WriteBytes(const std::string& id, const std::vector<uint8_t>& bytes) {
  std::lock_guard<std::mutex> lock(g_socket_mutex);
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
  SOCKET sock = INVALID_SOCKET;
  {
    std::lock_guard<std::mutex> lock(g_socket_mutex);
    auto it = g_sockets.find(id);
    if (it == g_sockets.end()) return {};
    sock = it->second;
  }
  DWORD timeout = static_cast<DWORD>(std::max(timeoutMs, 1));
  setsockopt(sock, SOL_SOCKET, SO_RCVTIMEO, reinterpret_cast<const char*>(&timeout),
             sizeof(timeout));
  char buffer[4096];
  int n = recv(sock, buffer, sizeof(buffer), 0);
  if (n <= 0) return {};
  return std::vector<uint8_t>(buffer, buffer + n);
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
  std::lock_guard<std::mutex> lock(g_socket_mutex);
  for (auto& entry : g_sockets) {
    closesocket(entry.second);
  }
  g_sockets.clear();
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
    map[EncodableValue("usb")] = EncodableValue(false);
    result->Success(EncodableValue(map));
    return;
  }

  if (method == "discover") {
    EncodableList found;
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
    if (types.empty() ||
        std::find(types.begin(), types.end(), "bluetooth") != types.end()) {
      auto bt = DiscoverBluetooth();
      found.insert(found.end(), bt.begin(), bt.end());
    }
    if (std::find(types.begin(), types.end(), "usb") != types.end()) {
      auto usb = DiscoverUsb();
      found.insert(found.end(), usb.begin(), usb.end());
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
    if (type != "bluetooth") {
      result->Error(
          "unsupported",
          "Windows native plugin currently supports Bluetooth Classic RFCOMM. "
          "Use Dart TCP for network printers.");
      return;
    }
    const std::string error = ConnectBluetooth(*id, *address);
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
          std::lock_guard<std::mutex> lock(g_socket_mutex);
          CloseSocketLocked(*id);
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
    // Host status over RFCOMM is handled by Dart ~HS after connect.
    result->Success();
    return;
  }

  result->NotImplemented();
}

}  // namespace dcs_zebra
