/// What the app knows about the store it talks to, as the server states it.
///
/// This is a single-business app: one store, selling its own goods. The server
/// tells the app its name and the public Google client id the owner set in Settings.
class StoreConfig {
  final String storeName;

  /// The Web OAuth client id "Continue with Google" needs, or empty when the owner
  /// has not set Google sign-in up (the button is then not shown).
  final String googleServerClientId;

  const StoreConfig({this.storeName = '', this.googleServerClientId = ''});

  /// Used until the server answers, and when it cannot.
  static const fallback = StoreConfig();

  factory StoreConfig.fromJson(Map<String, dynamic> j) => StoreConfig(
        storeName: '${j['store_name'] ?? ''}',
        googleServerClientId: '${j['google_server_client_id'] ?? ''}',
      );

  Map<String, dynamic> toJson() => {
        'store_name': storeName,
        'google_server_client_id': googleServerClientId,
      };
}
