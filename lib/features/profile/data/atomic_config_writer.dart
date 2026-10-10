import 'dart:io';

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
    await stagingFile.rename(destination.path);
    return null;
  } finally {
    await stagingDirectory.delete(recursive: true);
  }
}
