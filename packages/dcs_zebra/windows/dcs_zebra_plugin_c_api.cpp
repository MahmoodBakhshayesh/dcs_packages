#include "include/dcs_zebra/dcs_zebra_plugin_c_api.h"

#include <flutter/plugin_registrar_windows.h>

#include "dcs_zebra_plugin.h"

void DcsZebraPluginCApiRegisterWithRegistrar(
    FlutterDesktopPluginRegistrarRef registrar) {
  dcs_zebra::DcsZebraPlugin::RegisterWithRegistrar(
      flutter::PluginRegistrarManager::GetInstance()
          ->GetRegistrar<flutter::PluginRegistrarWindows>(registrar));
}
