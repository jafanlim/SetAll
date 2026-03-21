// HOTFIX-04: speech_to_text_windows 1.0.0+beta.8 pubspec.yaml declares
// pluginClass: SpeechToTextWindows which causes Flutter tools to generate
// a call to SpeechToTextWindowsRegisterWithRegistrar in generated_plugin_registrant.cc.
// However the compiled DLL exports SpeechToTextWindowsPluginRegisterWithRegistrar.
// This shim bridges the two by forwarding the legacy symbol to the actual export.
#include "include/speech_to_text_windows/speech_to_text_windows.h"

extern "C" {

__declspec(dllexport) void SpeechToTextWindowsRegisterWithRegistrar(
    FlutterDesktopPluginRegistrarRef registrar) {
  SpeechToTextWindowsPluginRegisterWithRegistrar(registrar);
}

}  // extern "C"
