# Sécurité — état honnête

- **Chiffrement de bout en bout : NON implémenté.** Les messages sont protégés en transit (HTTPS) et par RLS côté serveur, mais lisibles par le serveur. Ne pas présenter l'app comme « E2EE ». Une vraie implémentation demande un protocole éprouvé (Signal/MLS), pas du chiffrement maison.
- Mode proche (Elvidio Relay) : paquets non chiffrés, expéditeur non authentifié, livraison au mieux, sans garantie hors de portée.
- RLS activée sur toutes les tables ; fonctions d'aide dans le schéma `private` ; aucune clé `service_role` dans l'app.
- Secrets : jamais dans le dépôt (secret push à remplacer dans les migrations ; compte de service Firebase uniquement dans Supabase).
- Le bucket `media` est privé (migrations 20261025*) : lecture limitée aux participants via `private.can_read_media`, liens signés d'1 h côté app.
- Signature APK : si les secrets GitHub `KEYSTORE_B64` et `KEYSTORE_PASSWORD` existent, la clé privée est utilisée ; sinon retour à la clé publique du dépôt (`ci/debug.keystore`, non sûre).
- Signalements enregistrés dans `reports` (aucune modération automatique).
