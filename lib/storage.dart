import 'dart:convert';
import 'dart:io';

import 'package:path_provider/path_provider.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

// Stockage de la session dans de simples fichiers de l'app, sans passer par
// le plugin shared_preferences (qui plante au démarrage sur certains builds).

Future<File> _file(String name) async {
  final dir = await getApplicationSupportDirectory();
  await dir.create(recursive: true);
  return File('${dir.path}/$name');
}

class FileLocalStorage extends LocalStorage {
  const FileLocalStorage();

  @override
  Future<void> initialize() async {}

  @override
  Future<bool> hasAccessToken() async {
    final f = await _file('supabase_session.json');
    return f.exists();
  }

  @override
  Future<String?> accessToken() async {
    final f = await _file('supabase_session.json');
    return await f.exists() ? f.readAsString() : null;
  }

  @override
  Future<void> removePersistedSession() async {
    final f = await _file('supabase_session.json');
    if (await f.exists()) await f.delete();
  }

  @override
  Future<void> persistSession(String persistSessionString) async {
    final f = await _file('supabase_session.json');
    await f.writeAsString(persistSessionString);
  }
}

class FileAsyncStorage extends GotrueAsyncStorage {
  const FileAsyncStorage();

  Future<Map<String, dynamic>> _load() async {
    try {
      final f = await _file('supabase_pkce.json');
      if (!await f.exists()) return {};
      return Map<String, dynamic>.from(jsonDecode(await f.readAsString()));
    } catch (_) {
      return {};
    }
  }

  Future<void> _store(Map<String, dynamic> data) async {
    final f = await _file('supabase_pkce.json');
    await f.writeAsString(jsonEncode(data));
  }

  @override
  Future<String?> getItem({required String key}) async {
    final data = await _load();
    return data[key]?.toString();
  }

  @override
  Future<void> setItem({required String key, required String value}) async {
    final data = await _load();
    data[key] = value;
    await _store(data);
  }

  @override
  Future<void> removeItem({required String key}) async {
    final data = await _load();
    data.remove(key);
    await _store(data);
  }
}
