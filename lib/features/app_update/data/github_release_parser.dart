import 'package:dartx/dartx.dart';
import 'package:hiddify/core/model/constants.dart';
import 'package:hiddify/core/model/environment.dart';
import 'package:hiddify/features/app_update/model/remote_version_entity.dart';
import 'package:version/version.dart';

abstract class GithubReleaseParser {
  /// Select the newest usable package for this platform, independent of GitHub
  /// publication order. A bad entry must not hide the remaining valid releases.
  static RemoteVersionEntity? latest(
    List<dynamic> releases, {
    required String operatingSystem,
    bool includePreReleases = false,
    bool macOSIntel = false,
  }) {
    RemoteVersionEntity? latest;
    Version? highest;
    for (final raw in releases) {
      if (raw is! Map<String, dynamic> || raw['draft'] == true || (!includePreReleases && raw['prerelease'] != false)) {
        continue;
      }
      try {
        final remote = parse(raw);
        if (remote.flavor != Environment.prod) continue;
        final uri = Uri.parse(remote.url);
        final repositoryPath = Uri.parse(Constants.githubUrl).path.toLowerCase();
        if (uri.scheme != 'https' ||
            uri.host != 'github.com' ||
            uri.userInfo.isNotEmpty ||
            !uri.path.toLowerCase().startsWith('$repositoryPath/releases/tag/')) {
          continue;
        }
        final pattern = switch (operatingSystem) {
          'android' => 'ProxyYou-Android-${remote.version}.apk',
          'macos' => 'ProxyYou-macOS-${macOSIntel ? 'Intel' : 'AppleSilicon'}-${remote.version}.zip',
          'windows' => 'ProxyYou-Windows-x64-${remote.version}-Setup.exe',
          'ios' => 'ProxyYou-iOS-${remote.version}.ipa',
          _ => null,
        };
        final assets = raw['assets'];
        if (pattern == null ||
            assets is! List ||
            !assets.any(
              (asset) => asset is Map && asset['name'] == pattern && asset['size'] is num && (asset['size'] as num) > 0,
            )) {
          continue;
        }
        final candidate = Version.parse(remote.version);
        if (highest == null || candidate > highest) {
          highest = candidate;
          latest = remote;
        }
      } catch (_) {
        // Drafts, missing timestamps and malformed tags are not update offers.
      }
    }
    return latest;
  }

  static RemoteVersionEntity parse(Map<String, dynamic> json) {
    final fullTag = json['tag_name'] as String;
    final fullVersion = fullTag.removePrefix("v").split("-").first.split("+");
    var version = fullVersion.first;
    var buildNumber = fullVersion.elementAtOrElse(1, (index) => "");
    var flavor = Environment.prod;
    for (final env in Environment.values) {
      final suffix = ".${env.name}";
      if (version.endsWith(suffix)) {
        version = version.removeSuffix(suffix);
        flavor = env;
        break;
      } else if (buildNumber.endsWith(suffix)) {
        buildNumber = buildNumber.removeSuffix(suffix);
        flavor = env;
        break;
      }
    }
    final preRelease = json["prerelease"] as bool;
    final publishedAt = DateTime.parse(json["published_at"] as String);
    return RemoteVersionEntity(
      version: version,
      buildNumber: buildNumber,
      releaseTag: fullTag,
      preRelease: preRelease,
      url: json["html_url"] as String,
      publishedAt: publishedAt,
      flavor: flavor,
    );
  }
}
