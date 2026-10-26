import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../premium.dart';
import '../theme.dart';

/// Soutenir Chat Elvidio : Premium payé par Mobile Money, validé par l'administrateur.
class PremiumScreen extends StatefulWidget {
  const PremiumScreen({super.key});

  @override
  State<PremiumScreen> createState() => _PremiumScreenState();
}

class _PremiumScreenState extends State<PremiumScreen> {
  final _db = Supabase.instance.client;
  final _ref = TextEditingController();
  String _info = '';
  String _price = '';
  Map<String, dynamic>? _last;
  bool _loading = true;
  bool _sending = false;

  @override
  void initState() {
    super.initState();
    _load();
  }

  @override
  void dispose() {
    _ref.dispose();
    super.dispose();
  }

  Future<void> _load() async {
    try {
      final c = await _db.from('app_config').select('key, value');
      for (final r in c) {
        if (r['key'] == 'payment_info') _info = r['value'].toString();
        if (r['key'] == 'premium_price') _price = r['value'].toString();
      }
      final l = await _db
          .from('premium_requests')
          .select('id, reference, status, created_at')
          .eq('user_id', _db.auth.currentUser!.id)
          .order('created_at', ascending: false)
          .limit(1);
      _last = (l as List).isEmpty ? null : Map<String, dynamic>.from(l.first);
    } catch (_) {}
    if (mounted) setState(() => _loading = false);
  }

  Future<void> _send() async {
    final r = _ref.text.trim();
    if (r.length < 3) return;
    setState(() => _sending = true);
    try {
      await _db.from('premium_requests').insert({'reference': r});
      _ref.clear();
      await _load();
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
            content: Text('Demande envoyée. Elle sera validée après vérification du paiement.')));
      }
    } catch (_) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
            content: Text('Envoi impossible (trop de demandes ou pas de connexion).')));
      }
    }
    if (mounted) setState(() => _sending = false);
  }

  Widget _perk(IconData i, String t) => Padding(
        padding: const EdgeInsets.symmetric(vertical: 5),
        child: Row(children: [
          Icon(i, color: AppColors.gold),
          const SizedBox(width: 12),
          Expanded(child: Text(t)),
        ]),
      );

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Premium')),
      body: _loading
          ? const Center(child: CircularProgressIndicator())
          : ListView(
              padding: const EdgeInsets.all(16),
              children: [
                Container(
                  padding: const EdgeInsets.all(18),
                  decoration: BoxDecoration(
                    gradient: AppColors.gradient,
                    borderRadius: BorderRadius.circular(18),
                  ),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      const Icon(Icons.star_rounded, color: AppColors.gold, size: 36),
                      const SizedBox(height: 8),
                      const Text('Chat Elvidio Premium',
                          style: TextStyle(
                              color: Colors.white, fontSize: 22, fontWeight: FontWeight.w800)),
                      const SizedBox(height: 4),
                      Text(
                        Premium.I.mePremium
                            ? 'Actif jusqu\'au ${Premium.I.myUntil.value!.day.toString().padLeft(2, '0')}/${Premium.I.myUntil.value!.month.toString().padLeft(2, '0')}/${Premium.I.myUntil.value!.year}'
                            : 'Soutiens l\'app et débloque les avantages.',
                        style: const TextStyle(color: Colors.white70),
                      ),
                    ],
                  ),
                ),
                const SizedBox(height: 16),
                _perk(Icons.verified_outlined, 'Badge doré ★ sur ta photo, visible partout'),
                _perk(Icons.history_toggle_off, 'Tes stories restent 72 h au lieu de 24 h'),
                _perk(Icons.favorite_border, 'Tu finances les serveurs et les nouveautés'),
                const SizedBox(height: 16),
                if (_price.isNotEmpty)
                  Text('Prix : $_price',
                      style: const TextStyle(fontSize: 18, fontWeight: FontWeight.w800)),
                const SizedBox(height: 8),
                Container(
                  padding: const EdgeInsets.all(14),
                  decoration: BoxDecoration(
                    color: AppColors.surface,
                    borderRadius: BorderRadius.circular(14),
                  ),
                  child: Text(
                    _info.isEmpty
                        ? 'Les moyens de paiement seront bientôt indiqués ici.'
                        : _info,
                    style: const TextStyle(height: 1.4),
                  ),
                ),
                const SizedBox(height: 16),
                Text('Après le paiement, écris ici la référence de la transaction (ou le numéro qui a payé) :',
                    style: TextStyle(color: AppColors.muted)),
                const SizedBox(height: 8),
                TextField(
                  controller: _ref,
                  maxLength: 80,
                  decoration: const InputDecoration(hintText: 'Référence ou numéro'),
                ),
                FilledButton(
                  onPressed: _sending || _info.isEmpty ? null : _send,
                  child: const Text('J\'ai payé, valider'),
                ),
                if (_last != null) ...[
                  const SizedBox(height: 16),
                  Text(
                    'Dernière demande (${_last!['reference']}) : ${const {
                      'pending': 'en attente de vérification',
                      'approved': 'validée',
                      'rejected': 'refusée',
                    }[_last!['status']] ?? ''}',
                    style: TextStyle(color: AppColors.muted),
                  ),
                ],
              ],
            ),
    );
  }
}
