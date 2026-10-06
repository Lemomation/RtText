import 'dart:convert';
import 'dart:io';

import 'package:http/http.dart' as http;
import 'package:open_filex/open_filex.dart';
import 'package:package_info_plus/package_info_plus.dart';
import 'package:path_provider/path_provider.dart';

/// In-app updater: checks GitHub Releases for a newer APK, downloads it,
/// and hands it off to the Android package installer.
///
/// The repo is public, so the releases API is called anonymously; only the
/// network errors surface as exceptions, for the caller to catch.
class UpdaterService {
  UpdaterService({http.Client? client}) : _client = client ?? http.Client();

  final http.Client _client;

  static const _latestReleaseUrl =
      'https://api.github.com/repos/Lemomation/RtText/releases/latest';
  static const _apkAssetName = 'app-release.apk';

  /// Checks the latest GitHub release against the installed version.
  ///
  /// Returns [UpdateStatus.upToDate] when there is no newer release (or none
  /// exists yet); [UpdateStatus.updateAvailable] with the download details
  /// otherwise.
  Future<UpdateInfo> check() async {
    final installed = await PackageInfo.fromPlatform();
    final response = await _client.get(
      Uri.parse(_latestReleaseUrl),
      headers: {'Accept': 'application/vnd.github+json'},
    );
    if (response.statusCode == 404) {
      // No releases published yet.
      return UpdateInfo(
        status: UpdateStatus.upToDate,
        installedVersion: installed.version,
        latestVersion: installed.version,
      );
    }
    if (response.statusCode != 200) {
      throw Exception('Release check failed (HTTP ${response.statusCode})');
    }
    final release = jsonDecode(response.body) as Map<String, dynamic>;
    final latestVersion = _stripTag(release['tag_name'] as String? ?? '');
    final notes = (release['body'] as String?)?.trim();
    final assets =
        (release['assets'] as List? ?? const []).cast<Map<String, dynamic>>();
    final apk = assets.where((a) => a['name'] == _apkAssetName).toList();
    if (apk.isEmpty) {
      throw Exception('Latest release has no $_apkAssetName asset');
    }
    final downloadUrl = apk.first['browser_download_url'] as String;
    final apkSize = (apk.first['size'] as num).toInt();
    if (!_isNewer(latestVersion, installed.version)) {
      return UpdateInfo(
        status: UpdateStatus.upToDate,
        installedVersion: installed.version,
        latestVersion: latestVersion,
      );
    }
    return UpdateInfo(
      status: UpdateStatus.updateAvailable,
      installedVersion: installed.version,
      latestVersion: latestVersion,
      downloadUrl: downloadUrl,
      apkSize: apkSize,
      notes: notes,
    );
  }

  /// Streams the APK at [url] into a temp file, reporting progress as
  /// (bytes received, total bytes) when known. Returns the written file.
  Future<File> download(
    String url, {
    void Function(int received, int total)? onProgress,
  }) async {
    final response = await _client.send(http.Request('GET', Uri.parse(url)));
    if (response.statusCode != 200) {
      throw Exception('APK download failed (HTTP ${response.statusCode})');
    }
    final total = response.contentLength ?? 0;
    final dir = await getTemporaryDirectory();
    final file = File(
      '${dir.path}${Platform.pathSeparator}rttext-update.apk',
    );
    final sink = file.openWrite();
    var received = 0;
    try {
      await for (final chunk in response.stream) {
        received += chunk.length;
        sink.add(chunk);
        if (onProgress != null) onProgress(received, total);
      }
      await sink.flush();
    } finally {
      await sink.close();
    }
    return file;
  }

  /// Hands the downloaded [apk] to the Android package installer.
  Future<void> install(File apk) async {
    final result = await OpenFilex.open(
      apk.path,
      type: 'application/vnd.android.package-archive',
    );
    if (result.type != ResultType.done) {
      throw Exception('Install handoff failed: ${result.message}');
    }
  }

  /// 'v1.2.3' / '1.2.3+4' -> '1.2.3'.
  String _stripTag(String tag) {
    var version = tag.trim();
    if (version.startsWith('v')) version = version.substring(1);
    final plus = version.indexOf('+');
    if (plus >= 0) version = version.substring(0, plus);
    return version;
  }

  /// Numeric, part-by-part semver comparison ('1.10.0' > '1.9.0').
  bool _isNewer(String latest, String installed) {
    final latestParts = latest.split('.').map(_partValue).toList();
    final installedParts = installed.split('.').map(_partValue).toList();
    final length =
        latestParts.length > installedParts.length
            ? latestParts.length
            : installedParts.length;
    for (var i = 0; i < length; i++) {
      final l = i < latestParts.length ? latestParts[i] : 0;
      final r = i < installedParts.length ? installedParts[i] : 0;
      if (l != r) return l > r;
    }
    return false;
  }

  int _partValue(String part) => int.tryParse(part.trim()) ?? 0;
}

/// Whether an update is available, plus the details the caller needs to
/// download and install it.
enum UpdateStatus { upToDate, updateAvailable }

class UpdateInfo {
  const UpdateInfo({
    required this.status,
    required this.installedVersion,
    required this.latestVersion,
    this.downloadUrl,
    this.apkSize,
    this.notes,
  });

  final UpdateStatus status;

  /// Version currently installed on the device (from PackageInfo).
  final String installedVersion;

  /// Latest release version, leading 'v' and build suffix stripped.
  final String latestVersion;

  /// Asset download URL; null when up to date.
  final String? downloadUrl;

  /// APK size in bytes; null when unknown or up to date.
  final int? apkSize;

  /// Release notes body from GitHub; null when empty.
  final String? notes;
}
