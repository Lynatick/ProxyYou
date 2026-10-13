import 'dart:ffi';
import 'dart:io';

import 'package:fpdart/fpdart.dart';
import 'package:hiddify/core/http_client/dio_http_client.dart';
import 'package:hiddify/core/model/constants.dart';
import 'package:hiddify/core/model/environment.dart';
import 'package:hiddify/core/utils/exception_handler.dart';
import 'package:hiddify/features/app_update/data/github_release_parser.dart';
import 'package:hiddify/features/app_update/model/app_update_failure.dart';
import 'package:hiddify/features/app_update/model/remote_version_entity.dart';
import 'package:hiddify/utils/utils.dart';

abstract interface class AppUpdateRepository {
  TaskEither<AppUpdateFailure, RemoteVersionEntity> getLatestVersion({
    bool includePreReleases = false,
    Release release = Release.general,
  });
}

class AppUpdateRepositoryImpl with ExceptionHandler, InfraLogger implements AppUpdateRepository {
  AppUpdateRepositoryImpl({required this.httpClient});

  final DioHttpClient httpClient;

  @override
  TaskEither<AppUpdateFailure, RemoteVersionEntity> getLatestVersion({
    bool includePreReleases = false,
    Release release = Release.general,
  }) {
    return exceptionHandler(() async {
      if (!release.allowCustomUpdateChecker) {
        throw Exception("custom update checkers are not supported");
      }
      final response = await httpClient.get<List>('${Constants.githubReleasesApiUrl}?per_page=30');
      if (response.statusCode != 200 || response.data == null) {
        return left(const AppUpdateFailure.unexpected());
      }
      final latest = GithubReleaseParser.latest(
        response.data!,
        operatingSystem: Platform.operatingSystem,
        includePreReleases: includePreReleases,
        macOSIntel: Platform.isMacOS && Abi.current() == Abi.macosX64,
      );
      if (latest == null) return left(const AppUpdateFailure.unexpected());
      return right(latest);
    }, AppUpdateFailure.unexpected);
  }
}
