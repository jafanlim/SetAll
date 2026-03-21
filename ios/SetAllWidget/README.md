# SetAll Widget — Xcode Setup

This folder was created by FEAT-10. The Swift files are ready.
You must add the Widget Extension target in Xcode manually:

1. Open ios/Runner.xcworkspace in Xcode
2. File → New → Target → Widget Extension
3. Name: SetAllWidget
4. Bundle ID: com.jafa.setall.app.SetAllWidget
5. Uncheck "Include Configuration Intent"
6. Replace the generated Swift files with ios/SetAllWidget/SetAllWidget.swift
7. In the Widget target → Signing & Capabilities → + Capability → App Groups
   Add: group.com.jafa.setall.app.widget
8. In the Runner target → Signing & Capabilities → App Groups
   Add the same group: group.com.jafa.setall.app.widget
9. Build and run on a physical device
10. Long-press the home screen → + → search "SetAll" → add widget

NOTE: SharedPreferences on Flutter writes to NSUserDefaults with the standard suite.
For the App Group to work, the Flutter side must also use the App Group suite.
If SharedPreferences does not support App Groups directly, replace _writeWidgetData
with a platform channel call or use the shared_preferences_foundation package
with the groupId parameter.
