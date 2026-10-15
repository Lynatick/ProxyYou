import 'dart:async';
import 'dart:io';

import 'package:path/path.dart' as p;

final _replacementGates = <String, Future<void>>{};

Future<void> _replace(File stagingFile, File destination) async {
  if (!Platform.isWindows) {
    await stagingFile.rename(destination.path);
    return;
  }
  // Concurrent MoveFileEx calls can deny each other's access to the same file.
  // Validation stays parallel; only the final replacement is serialized.
  final key = p.normalize(destination.absolute.path).toLowerCase();
  final previous = _replacementGates[key];
  final completed = Completer<void>();
  _replacementGates[key] = completed.future;
  if (previous != null) await previous;
  try {
    await stagingFile.rename(destination.path);
  } finally {
    completed.complete();
    if (identical(_replacementGates[key], completed.future)) _replacementGates.remove(key);
  }
}

/// Validate a new file before atomically replacing the saved configuration.
/// Replacement needs write access to the directory, even if an older app
/// created the destination as root. Failed validation keeps that file intact.
Future<String?> validateAndReplaceConfig(String path, Future<String?> Function(String stagingPath) validate) async {
  final destination = File(path);
  final stagingDirectory = await destination.parent.createTemp('.profile-');
  final stagingFile = File('${stagingDirectory.path}/config.json');
  try {
    final error = await validate(stagingFile.path);
    if (error != null) return error;
    await _replace(stagingFile, destination);
    return null;
  } finally {
    await stagingDirectory.delete(recursive: true);
  }
}
