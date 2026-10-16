import 'dart:ffi';
import 'dart:io';
import 'dart:math';

import 'package:ffi/ffi.dart';
import 'package:grpc/grpc.dart';
import 'package:hiddify/core/model/directories.dart';
import 'package:hiddify/gen/hiddify_core_generated_bindings.dart';
import 'package:hiddify/hiddifycore/core_interface/core_interface.dart';
import 'package:hiddify/hiddifycore/core_interface/responsive_core_client.dart';
import 'package:hiddify/hiddifycore/generated/v2/hcommon/common.pb.dart';
import 'package:hiddify/hiddifycore/generated/v2/hcore/hcore.pb.dart';
import 'package:hiddify/hiddifycore/generated/v2/hcore/hcore_service.pbgrpc.dart';
import 'package:hiddify/hiddifycore/generated/v2/hello/hello.pb.dart';
import 'package:hiddify/hiddifycore/generated/v2/hello/hello_service.pbgrpc.dart';
import 'package:hiddify/utils/custom_loggers.dart';
import 'package:path/path.dart' as p;

final _logger = infraLogger('HiddifyCoreFFI');
typedef StopFunc = Pointer<Utf8> Function();
typedef StopFuncDart = Pointer<Utf8> Function();

class CoreInterfaceDesktop extends CoreInterface with InfraLogger {
  static final HiddifyCoreNativeLibrary _box = _gen();

  static HiddifyCoreNativeLibrary _gen() {
    String fullPath = "";
    if (Platform.environment.containsKey('FLUTTER_TEST')) {
      fullPath = "hiddify-core";
    }
    if (Platform.isWindows) {
      fullPath = p.join(fullPath, "hiddify-core.dll");
    } else if (Platform.isMacOS) {
      fullPath = p.join(fullPath, "hiddify-core.dylib");
    } else {
      fullPath = p.join(fullPath, "hiddify-core.so");
    }

    _logger.debug('hiddify-core native libs path: "$fullPath"');
    final lib = DynamicLibrary.open(fullPath);
    // final stopFunc = lib.lookup<NativeFunction<StopFunc>>('stop').asFunction<StopFunc>();
    // final errPtr2 = stopFunc();
    // final err = errPtr2.cast<Utf8>().toDartString();

    return HiddifyCoreNativeLibrary(lib);
  }

  Future<bool> isMusl() async {
    try {
      final result = await Process.run('ldd', ['--version']);
      return result.stdout.toString().toLowerCase().contains('musl');
    } catch (_) {
      return false;
    }
  }

  final port = 17078;

  @override
  Future<CoreInfoResponse> readFreshStatus() async {
    // Do not reuse the HTTP/2 connection whose Stop reply was lost.
    final channel = ClientChannel(
      '127.0.0.1',
      port: _windowsPort ?? port,
      options: const ChannelOptions(credentials: ChannelCredentials.insecure()),
    );
    try {
      return await CoreClient(channel)
          .coreInfoListener(Empty(), options: CallOptions(timeout: const Duration(seconds: 2)))
          .first;
    } finally {
      await channel.shutdown();
    }
  }

  int? _windowsPort;
  Future<String>? _windowsSetup;
  static String generateRandomPassword(int length) {
    const characters = 'abcdefghijklmnopqrstuvwxyzABCDEFGHIJKLMNOPQRSTUVWXYZ0123456789';
    final random = Random();
    return List.generate(length, (_) => characters[random.nextInt(characters.length)]).join();
  }

  static final String secret = generateRandomPassword(100);

  @override
  Future<String> setup(Directories directories, bool debug, int mode) async {
    if (Platform.isWindows) {
      return _windowsSetup ??= _setupWindows(directories, debug).then(
        (error) {
          if (error.isNotEmpty) _windowsSetup = null;
          return error;
        },
        onError: (Object error, StackTrace stack) {
          _windowsSetup = null;
          Error.throwWithStackTrace(error, stack);
        },
      );
    }
    // Generate a random password for the grpc service
    // final errPtr2 = _box.stop();
    // final err = errPtr2.cast<Utf8>().toDartString();
    // throw Exception('stop: $err');
    const channelOption = ChannelCredentials.insecure();
    final helloClient = HelloClient(
      ClientChannel(
        '127.0.0.1',
        port: port,
        options: const ChannelOptions(credentials: channelOption),
      ),
    );

    try {
      await helloClient.sayHello(HelloRequest(name: "test"));
      loggy.info("core is already started!");
    } catch (e) {
      //core is not started yet

      final errPtr = _box.setup(
        directories.baseDir.path.toNativeUtf8().cast(),
        directories.workingDir.path.toNativeUtf8().cast(),
        directories.tempDir.path.toNativeUtf8().cast(),
        SetupMode.GRPC_NORMAL_INSECURE.value,
        "127.0.0.1:$port".toNativeUtf8().cast(),
        secret.toNativeUtf8().cast(),
        0,
        debug ? 1 : 0,
      );
      final err = errPtr.cast<Utf8>().toDartString();

      if (err.isNotEmpty) {
        return err;
      }
      final res = await helloClient.sayHello(HelloRequest(name: "test"));
      loggy.info(res.toString());
    }
    bgClient = fgClient = ResponsiveCoreClient(
      // Subscription and statistics streams can remain paused off screen.
      // Control RPCs need their own connection throughout the session.
      ClientChannel(
        'localhost',
        port: port,
        options: const ChannelOptions(
          credentials: ChannelCredentials.insecure(),
          // credentials: ChannelCredentials.secure(
          //   password: secret,
          //   onBadCertificate: (certificate, host) => true,
          // ),
        ),
      ),
      controlChannel: ClientChannel(
        '127.0.0.1',
        port: port,
        options: const ChannelOptions(credentials: ChannelCredentials.insecure()),
      ),
    );

    return "";
  }

  Future<String> _setupWindows(Directories directories, bool debug) async {
    // A separate process must never reuse another application's foreground
    // core simply because it answers on Hiddify's default port.
    if (_windowsPort == null) {
      final reservation = await ServerSocket.bind(InternetAddress.loopbackIPv4, 0);
      _windowsPort = reservation.port;
      await reservation.close();
    }
    final errorPointer = _box.setup(
      directories.baseDir.path.toNativeUtf8().cast(),
      directories.workingDir.path.toNativeUtf8().cast(),
      directories.tempDir.path.toNativeUtf8().cast(),
      SetupMode.GRPC_NORMAL_INSECURE.value,
      '127.0.0.1:$_windowsPort'.toNativeUtf8().cast(),
      secret.toNativeUtf8().cast(),
      0,
      debug ? 1 : 0,
    );
    final error = errorPointer.cast<Utf8>().toDartString();
    if (error.isNotEmpty) return error;
    final channel = ClientChannel(
      '127.0.0.1',
      port: _windowsPort!,
      options: const ChannelOptions(credentials: ChannelCredentials.insecure()),
    );
    try {
      await HelloClient(channel).sayHello(HelloRequest(name: 'ProxyYou')).timeout(const Duration(seconds: 10));
      bgClient = fgClient = ResponsiveCoreClient(
        channel,
        controlChannel: ClientChannel(
          '127.0.0.1',
          port: _windowsPort!,
          options: const ChannelOptions(credentials: ChannelCredentials.insecure()),
        ),
      );
      return '';
    } catch (_) {
      await channel.shutdown();
      rethrow;
    }
  }

  @override
  Future<bool> restart(String path, String name) async {
    return false;
  }

  @override
  Future<bool> stop() async {
    return false;
  }
}
