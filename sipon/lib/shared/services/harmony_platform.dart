import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';

bool get isHarmonyOS => !kIsWeb && defaultTargetPlatform.name == 'ohos';

const harmonyServices = MethodChannel('sipon/harmony');
