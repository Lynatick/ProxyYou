import 'dart:async';

import 'package:grpc/grpc.dart';
import 'package:hiddify/hiddifycore/generated/v2/hcore/hcore.pb.dart';

bool _confirmed(CoreInfoResponse response) =>
    response.coreState == CoreStates.STOPPED &&
    (response.messageType == MessageType.EMPTY || response.messageType == MessageType.ALREADY_STOPPED);

/// A transport timeout can lose the reply after the engine has already stopped.
/// Only a fresh status query can resolve it; an old UI status is not evidence.
Future<void> stopMacCore({
  required Future<CoreInfoResponse> Function() requestStop,
  required Future<CoreInfoResponse> Function() readFreshStatus,
  void Function(Object error)? onRecoveredReply,
}) async {
  late final Object transportError;
  late final StackTrace transportStack;
  try {
    final response = await requestStop();
    if (!_confirmed(response)) {
      throw StateError(
        'Stop: ${response.coreState}/${response.messageType}'
        '${response.message.isEmpty ? '' : ': ${response.message}'}',
      );
    }
    return;
  } on TimeoutException catch (error, stack) {
    transportError = error;
    transportStack = stack;
  } on GrpcError catch (error, stack) {
    final ambiguous =
        error.code == StatusCode.deadlineExceeded ||
        error.code == StatusCode.unavailable ||
        (error.code == StatusCode.unknown && (error.message?.contains('HTTP/2') ?? false));
    if (!ambiguous) rethrow;
    transportError = error;
    transportStack = stack;
  }

  try {
    final status = await readFreshStatus().timeout(const Duration(seconds: 2));
    if (_confirmed(status)) {
      onRecoveredReply?.call(transportError);
      return;
    }
  } catch (_) {
    // Preserve the original failure when the independent query also fails.
  }
  Error.throwWithStackTrace(transportError, transportStack);
}
