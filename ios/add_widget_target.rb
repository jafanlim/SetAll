require 'xcodeproj'
project = Xcodeproj::Project.open('Runner.xcodeproj')
if project.targets.find { |t| t.name == 'SetAllWidget' }
  puts "SetAllWidget target already exists — skipping"; exit 0
end
t = project.new_target(:app_extension, 'SetAllWidget', :ios, '16.0')
t.build_configurations.each do |c|
  c.build_settings['PRODUCT_BUNDLE_IDENTIFIER'] = 'com.jafa.setall.app.SetAllWidget'
  c.build_settings['SWIFT_VERSION'] = '5.0'
  c.build_settings['IPHONEOS_DEPLOYMENT_TARGET'] = '16.0'
  c.build_settings['TARGETED_DEVICE_FAMILY'] = '1,2'
end
g = project.main_group['SetAllWidget'] || project.main_group.new_group('SetAllWidget','SetAllWidget')
t.add_file_references([g.new_file('SetAllWidget/SetAllWidget.swift')])
t.add_system_framework('WidgetKit')
t.add_system_framework('SwiftUI')
project.save
puts "SetAllWidget target added successfully"
