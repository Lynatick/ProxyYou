import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:hiddify/features/profile/data/atomic_config_writer.dart';

void main() {
  late Directory directory;
  late File destination;

  setUp(() async {
    directory = await Directory.systemTemp.createTemp('proxyyou-atomic-test-');
    destination = File('${directory.path}/profile.json');
    await destination.writeAsString('previous valid configuration');
  });

  tearDown(() => directory.delete(recursive: true));

  test('replaces a read-only configuration through its writable directory', () async {
    if (!Platform.isWindows) {
      final result = await Process.run('/bin/chmod', ['444', destination.path]);
      expect(result.exitCode, 0);
    }
    final error = await validateAndReplaceConfig(destination.path, (stagingPath) async {
      expect(await destination.readAsString(), 'previous valid configuration');
      await File(stagingPath).writeAsString('validated replacement');
      return null;
    });
    expect(error, isNull);
    expect(await destination.readAsString(), 'validated replacement');
    expect(await directory.list().length, 1);
  });

  test('failed validation preserves the previous file and removes partial output', () async {
    final error = await validateAndReplaceConfig(destination.path, (stagingPath) async {
      await File(stagingPath).writeAsString('partial invalid configuration');
      return 'FAILED';
    });
    expect(error, 'FAILED');
    expect(await destination.readAsString(), 'previous valid configuration');
    expect(await directory.list().length, 1);
  });

  test('exception preserves the previous file and cleans staging directory', () async {
    await expectLater(
      validateAndReplaceConfig(destination.path, (_) async => throw StateError('connection lost')),
      throwsStateError,
    );
    expect(await destination.readAsString(), 'previous valid configuration');
    expect(await directory.list().length, 1);
  });

  test('successful response without an output file preserves the previous file', () async {
    await expectLater(
      validateAndReplaceConfig(destination.path, (_) async => null),
      throwsA(isA<FileSystemException>()),
    );
    expect(await destination.readAsString(), 'previous valid configuration');
    expect(await directory.list().length, 1);
  });

  test('simultaneous updates have independent staging paths', () async {
    final stagingPaths = <String>{};
    await Future.wait(
      List.generate(20, (index) {
        return validateAndReplaceConfig(destination.path, (stagingPath) async {
          stagingPaths.add(stagingPath);
          await File(stagingPath).writeAsString('validated $index');
          return null;
        });
      }),
    );
    expect(stagingPaths.length, 20);
    expect(await destination.readAsString(), startsWith('validated '));
    expect(await directory.list().length, 1);
  });
}
