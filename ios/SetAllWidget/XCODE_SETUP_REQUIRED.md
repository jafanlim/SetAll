# 5-Minute Manual Setup — SetAll Widget

1. Open ios/Runner.xcworkspace in Xcode
2. File -> New -> Target -> Widget Extension
   Name: SetAllWidget | Bundle ID: com.jafa.setall.app.SetAllWidget
   Uncheck "Include Configuration Intent" -> Finish -> Activate
3. Delete the generated Swift file, replace with ios/SetAllWidget/SetAllWidget.swift
4. Runner target -> Signing -> + App Groups -> group.com.jafa.setall.app.widget
5. SetAllWidget target -> Signing -> + App Groups -> group.com.jafa.setall.app.widget
6. Build and run on device -> long-press home -> + -> search SetAll
