import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

/// Comptes Premium (soutien) : badge doré et avantages.
class Premium {
  Premium._();
  static final Premium I = Premium._();

  /// Identifiants des comptes dont le Premium est en cours.
  final ValueNotifier<Set<String>> ids = ValueNotifier<Set<String>>({});
  final ValueNotifier<DateTime?> myUntil = ValueNotifier<DateTime?>(null);
  final ValueNotifier<bool> isAdmin = ValueNotifier<bool>(false);
  StreamSubscription<List<Map<String, dynamic>>>? _sub;

  SupabaseClient get _db => Supabase.instance.client;

  bool get mePremium {
    final u = myUntil.value;
    return u != null && u.isAfter(DateTime.now());
  }

  Future<void> start() async {
    final me = _db.auth.currentUser?.id;
    if (me == null) return;
    await _sub?.cancel();
    try {
      _sub = _db.from('premium').stream(primaryKey: ['user_id']).listen(_apply, onError: (_) {});
    } catch (_) {}
    try {
      final a = await _db.from('admins').select('user_id').eq('user_id', me);
      isAdmin.value = (a as List).isNotEmpty;
    } catch (_) {}
  }

  void _apply(List<Map<String, dynamic>> rows) {
    final me = _db.auth.currentUser?.id;
    final now = DateTime.now();
    final s = <String>{};
    DateTime? mine;
    for (final r in rows) {
      final until = DateTime.tryParse(r['until']?.toString() ?? '')?.toLocal();
      if (until == null || !until.isAfter(now)) continue;
      final id = r['user_id'].toString();
      s.add(id);
      if (id == me) mine = until;
    }
    ids.value = s;
    myUntil.value = mine;
  }

  void stop() {
    _sub?.cancel();
    _sub = null;
    ids.value = {};
    myUntil.value = null;
    isAdmin.value = false;
  }
}
