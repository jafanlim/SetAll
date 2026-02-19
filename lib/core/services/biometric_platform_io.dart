import 'dart:io';

import 'package:flutter/foundation.dart' show kIsWeb;

bool get kBiometricPlatformMobile =>
    !kIsWeb && (Platform.isIOS || Platform.isAndroid);
