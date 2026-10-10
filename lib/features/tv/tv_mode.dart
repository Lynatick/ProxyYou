import 'package:flutter/services.dart';
import 'package:hiddify/utils/platform_utils.dart';
import 'package:hooks_riverpod/hooks_riverpod.dart';

final televisionProvider = FutureProvider<bool>((ref) async {
  if (!PlatformUtils.isAndroid) return false;
  try {
    return await const MethodChannel('dev.proxyyou/device').invokeMethod<bool>('isTelevision') ?? false;
  } on PlatformException {
    return false;
  } on MissingPluginException {
    return false;
  }
});
