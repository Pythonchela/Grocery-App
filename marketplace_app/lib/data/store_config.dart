/// What the app knows about the store it talks to, as the server states it.
///
/// This is a single-business app: one store, selling its own goods. The only
/// thing the server tells the app about it is its name.
class StoreConfig {
  final String storeName;

  const StoreConfig({this.storeName = ''});

  /// Used until the server answers, and when it cannot.
  static const fallback = StoreConfig();

  factory StoreConfig.fromJson(Map<String, dynamic> j) => StoreConfig(storeName: '${j['store_name'] ?? ''}');

  Map<String, dynamic> toJson() => {'store_name': storeName};
}
