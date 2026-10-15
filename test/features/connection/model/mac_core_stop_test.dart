import 'dart:async';

import 'package:flutter_test/flutter_test.dart';
import 'package:grpc/grpc.dart';
import 'package:hiddify/features/connection/model/connection_operations.dart';
import 'package:hiddify/hiddifycore/core_interface/mac_core_stop.dart';
import 'package:hiddify/hiddifycore/generated/v2/hcore/hcore.pb.dart';

CoreInfoResponse stopped() => CoreInfoResponse(coreState: CoreStates.STOPPED);

void main() {
  for (final type in [MessageType.EMPTY, MessageType.ALREADY_STOPPED]) {
    test('accepts confirmed stop $type without another status query', () async {
      await stopMacCore(
        requestStop: () async => stopped()..messageType = type,
        readFreshStatus: () async => throw StateError('must not query'),
      );
    });
  }

  for (final error in [
    TimeoutException('reply lost'),
    const GrpcError.deadlineExceeded('reply lost'),
    const GrpcError.unavailable('connection closed'),
    const GrpcError.unknown('HTTP/2 error: connection terminated'),
  ]) {
    test('fresh STOPPED recovers a lost reply: $error', () async {
      var queries = 0;
      Object? recovered;
      await stopMacCore(
        requestStop: () async => throw error,
        readFreshStatus: () async {
          queries++;
          return stopped();
        },
        onRecoveredReply: (error) => recovered = error,
      );
      expect(queries, 1);
      expect(recovered, same(error));
    });
  }

  for (final status in [CoreStates.STARTED, CoreStates.STOPPING]) {
    test('does not report success while fresh state is $status', () async {
      const error = GrpcError.deadlineExceeded('stop not confirmed');
      await expectLater(
        stopMacCore(
          requestStop: () async => throw error,
          readFreshStatus: () async => CoreInfoResponse(coreState: status),
        ),
        throwsA(same(error)),
      );
    });
  }

  test('keeps the original transport error when the status query fails', () async {
    const error = GrpcError.deadlineExceeded('original');
    await expectLater(
      stopMacCore(
        requestStop: () async => throw error,
        readFreshStatus: () async => throw const GrpcError.unavailable('query failed'),
      ),
      throwsA(same(error)),
    );
  });

  test('does not hide an explicit stop failure behind a STOPPED snapshot', () async {
    await expectLater(
      stopMacCore(
        requestStop: () async => stopped()..messageType = MessageType.UNEXPECTED_ERROR,
        readFreshStatus: () async => throw StateError('must not query'),
      ),
      throwsStateError,
    );
  });

  test('does not treat a server application error as a lost response', () async {
    const error = GrpcError.unknown('cleanup failed');
    await expectLater(
      stopMacCore(
        requestStop: () async => throw error,
        readFreshStatus: () async => throw StateError('must not query'),
      ),
      throwsA(same(error)),
    );
  });

  test('never sends stop or status requests after restoration fails', () async {
    var requests = 0;
    await expectLater(
      MacDisconnectController().run(
        restoreProxy: () async => throw StateError('restore failed'),
        stopCore: () => stopMacCore(
          requestStop: () async {
            requests++;
            return stopped();
          },
          readFreshStatus: () async {
            requests++;
            return stopped();
          },
        ),
      ),
      throwsStateError,
    );
    expect(requests, 0);
  });
}
