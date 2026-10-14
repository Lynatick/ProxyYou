import 'dart:io';
import 'dart:isolate';

import 'package:crypto/crypto.dart';

const subscriptionSourceHash = 'proxyyou-source-sha256';

// Hash before expansion/conversion, in an isolate and with bounded memory.
Future<String> subscriptionFingerprint(String path) =>
    Isolate.run(() async => (await sha256.bind(File(path).openRead()).first).toString());
