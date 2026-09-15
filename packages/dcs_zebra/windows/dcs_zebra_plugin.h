#ifndef FLUTTER_PLUGIN_DCS_ZEBRA_PLUGIN_H_
#define FLUTTER_PLUGIN_DCS_ZEBRA_PLUGIN_H_

#include <flutter/method_channel.h>
#include <flutter/plugin_registrar_windows.h>

#include <memory>

namespace dcs_zebra {

class DcsZebraPlugin : public flutter::Plugin {
 public:
  static void RegisterWithRegistrar(flutter::PluginRegistrarWindows *registrar);

  DcsZebraPlugin();
  virtual ~DcsZebraPlugin();

  DcsZebraPlugin(const DcsZebraPlugin&) = delete;
  DcsZebraPlugin& operator=(const DcsZebraPlugin&) = delete;

 private:
  void HandleMethodCall(
      const flutter::MethodCall<flutter::EncodableValue> &method_call,
      std::unique_ptr<flutter::MethodResult<flutter::EncodableValue>> result);
};

}  // namespace dcs_zebra

#endif
