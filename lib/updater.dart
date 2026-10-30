import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:open_filex/open_filex.dart';
import 'package:path_provider/path_provider.dart';
import 'package:permission_handler/permission_handler.dart';

/// Téléphones 64 bits : petit APK arm64. Anciens téléphones 32 bits : arm32.
/// Vrai pour l'APK Lite (sans appels) : il se met à jour avec l'APK Lite.
const isLite = bool.fromEnvironment('LITE');
final String _apkName = (Platform.version.contains('arm64') || Platform.version.contains('x64'))
    ? (isLite ? 'chat-elvidio-lite.apk' : 'chat-elvidio.apk')
    : (isLite ? 'chat-elvidio-lite-arm32.apk' : 'chat-elvidio-arm32.apk');

/// Numéro de version de cette installation (donné par le build GitHub).
const currentBuild = int.fromEnvironment('BUILD_NUMBER', defaultValue: 0);

const _releaseApi =
    'https://api.github.com/repos/elvidioo/chat-elvidio-app/releases/latest';

class UpdateInfo {
  const UpdateInfo({required this.build, required this.url, required this.size});

  final int build;
  final String url;
  final int size;

  String get sizeLabel =>
      size > 0 ? ' (${(size / 1024 / 1024).toStringAsFixed(0)} Mo)' : '';
}

/// Renvoie la mise à jour disponible, ou null si l'app est à jour.
/// Lance une exception si la vérification échoue (pas d'internet...).
Future<UpdateInfo?> checkForUpdate() async {
  final client = HttpClient()..connectionTimeout = const Duration(seconds: 10);
  try {
    final req = await client.getUrl(Uri.parse(_releaseApi));
    req.headers.set('Accept', 'application/vnd.github+json');
    req.headers.set('User-Agent', 'chat-elvidio-app');
    final res = await req.close().timeout(const Duration(seconds: 15));
    if (res.statusCode != 200) throw HttpException('HTTP ${res.statusCode}');
    final data =
        jsonDecode(await res.transform(utf8.decoder).join()) as Map<String, dynamic>;

    final build =
        int.tryParse(data['tag_name'].toString().replaceFirst('build-', ''));
    if (build == null || build <= currentBuild) return null;

    for (final asset in (data['assets'] as List)) {
      if (asset['name'] == _apkName) {
        return UpdateInfo(
          build: build,
          url: asset['browser_download_url'].toString(),
          size: (asset['size'] as num?)?.toInt() ?? 0,
        );
      }
    }
    return null;
  } finally {
    client.close();
  }
}

Future<String> downloadApk(
  UpdateInfo info,
  void Function(double progress) onProgress,
) async {
  final dir = await getTemporaryDirectory();
  final file = File('${dir.path}/chat-elvidio-${info.build}.apk');
  if (await file.exists()) await file.delete();

  final client = HttpClient()..connectionTimeout = const Duration(seconds: 15);
  try {
    final req = await client.getUrl(Uri.parse(info.url));
    req.headers.set('User-Agent', 'chat-elvidio-app');
    final res = await req.close();
    if (res.statusCode != 200) throw HttpException('HTTP ${res.statusCode}');

    final total = res.contentLength > 0 ? res.contentLength : info.size;
    var received = 0;
    final sink = file.openWrite();
    try {
      await for (final chunk in res) {
        sink.add(chunk);
        received += chunk.length;
        if (total > 0) onProgress(received / total);
      }
    } finally {
      await sink.close();
    }
    if (info.size > 0 && await file.length() != info.size) {
      throw const HttpException('Téléchargement incomplet');
    }
    return file.path;
  } finally {
    client.close();
  }
}

Future<void> installApk(String path) async {
  var status = await Permission.requestInstallPackages.status;
  if (!status.isGranted) {
    status = await Permission.requestInstallPackages.request();
  }
  if (!status.isGranted) {
    throw const HttpException(
        'Autorise l\'installation d\'applications pour Veyra, puis réessaie.');
  }
  final result = await OpenFilex.open(
    path,
    type: 'application/vnd.android.package-archive',
  );
  if (result.type != ResultType.done) {
    throw Exception(result.message);
  }
}

void _toast(BuildContext context, String text) {
  if (!context.mounted) return;
  ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(text)));
}

Future<void> _downloadAndInstall(BuildContext context, UpdateInfo info) async {
  final progress = ValueNotifier<double>(0);
  var dialogOpen = true;

  showDialog<void>(
    context: context,
    barrierDismissible: false,
    builder: (_) => PopScope(
      canPop: false,
      child: AlertDialog(
        title: const Text('Téléchargement...'),
        content: ValueListenableBuilder<double>(
          valueListenable: progress,
          builder: (_, value, __) => Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              LinearProgressIndicator(value: value > 0 ? value : null),
              const SizedBox(height: 10),
              Text('${(value * 100).toInt()} %'),
            ],
          ),
        ),
      ),
    ),
  );

  void closeDialog() {
    if (dialogOpen && context.mounted) {
      dialogOpen = false;
      Navigator.of(context, rootNavigator: true).pop();
    }
  }

  try {
    final path = await downloadApk(info, (v) => progress.value = v);
    closeDialog();
    await installApk(path);
  } on HttpException catch (e) {
    closeDialog();
    _toast(context, e.message);
  } catch (_) {
    closeDialog();
    _toast(context, 'Mise à jour impossible. Réessaie plus tard.');
  }
}

Future<void> promptUpdate(BuildContext context, UpdateInfo info) async {
  final go = await showDialog<bool>(
    context: context,
    builder: (dialogContext) => AlertDialog(
      title: const Text('Mise à jour disponible'),
      content: Text(
        'Une nouvelle version de Veyra${info.sizeLabel} est prête. '
        'Elle s\'installe par-dessus l\'app, tes messages sont conservés.',
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(dialogContext, false),
          child: const Text('Plus tard'),
        ),
        TextButton(
          onPressed: () => Navigator.pop(dialogContext, true),
          child: const Text(
            'Mettre à jour',
            style: TextStyle(fontWeight: FontWeight.w700),
          ),
        ),
      ],
    ),
  );
  if (go != true || !context.mounted) return;
  await _downloadAndInstall(context, info);
}

/// Vérifie s'il y a une nouvelle version et propose de l'installer.
/// En mode silencieux (au démarrage), n'affiche rien s'il n'y a pas de mise à jour.
Future<void> checkAndPrompt(BuildContext context, {bool silent = false}) async {
  try {
    final info = await checkForUpdate();
    if (!context.mounted) return;
    if (info == null) {
      if (!silent) _toast(context, 'Tu as la dernière version.');
      return;
    }
    await promptUpdate(context, info);
  } catch (_) {
    if (!silent) _toast(context, 'Impossible de vérifier. Vérifie ta connexion.');
  }
}
