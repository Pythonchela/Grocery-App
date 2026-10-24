import 'dart:async';
import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;
import 'package:http_parser/http_parser.dart' show MediaType;

/// Talks to the same Laravel API the web storefront uses.
///
/// Deliberately mirrors `lib/apiClient.js`: same paths, same snake_case ->
/// camelCase normalisation, same 401-clears-the-token behaviour. Anything that
/// diverges here becomes a bug that only reproduces on mobile.
class ApiException implements Exception {
  final int status;
  final String message;

  /// Per-field validation messages from a 422 (`{"errors": {"pan": ["…"]}}`),
  /// so a form can put each message under the field it belongs to instead of
  /// dumping them all in one banner. Null when the response had none.
  final Map<String, List<String>>? errors;

  ApiException(this.status, this.message, {this.errors});

  /// The first message for [field], if the API reported one.
  String? fieldError(String field) {
    final list = errors?[field];
    return (list == null || list.isEmpty) ? null : list.first;
  }

  @override
  String toString() => message;
}

class ApiClient {
  /// All builds use the live backend unless a developer explicitly overrides it.
  /// For a local Android emulator, pass
  /// `--dart-define=API_BASE=http://10.0.2.2:8000/api/v1`.
  static const String baseUrl = String.fromEnvironment(
    'API_BASE',
    defaultValue: 'https://api.rentalmoney.in/api/v1',
  );

  /// Public storefront origin, used to build links shoppers can share.
  static const String webBase = String.fromEnvironment(
    'WEB_BASE',
    defaultValue: 'https://rentalmoney.in',
  );

  /// Called when the API rejects a token we sent — the session is dead and the
  /// app should bounce to sign-in rather than render empty lists as though the
  /// account genuinely had no orders.
  static VoidCallback? onUnauthorized;

  static Future<dynamic> request(
    String path, {
    String method = 'GET',
    Object? body,
    String? token,
    Map<String, String>? query,

    /// Return the whole response body (`data`, `meta`, and any extra keys such
    /// as a ledger's `balance`) instead of just `data`. Paginated lists need it.
    bool envelope = false,
  }) async {
    var uri = Uri.parse('$baseUrl$path');
    if (query != null && query.isNotEmpty) {
      uri = uri.replace(queryParameters: {...uri.queryParameters, ...query});
    }

    final headers = {
      'Content-Type': 'application/json',
      'Accept': 'application/json',
      if (token != null) 'Authorization': 'Bearer $token',
    };

    final encoded = body == null ? null : jsonEncode(body);

    Future<http.Response> send() => switch (method) {
          'POST' => http.post(uri, headers: headers, body: encoded),
          'PUT' => http.put(uri, headers: headers, body: encoded),
          'DELETE' => http.delete(uri, headers: headers, body: encoded),
          _ => http.get(uri, headers: headers),
        };

    http.Response res;
    try {
      res = await _withConnectionErrors(send);
    } on ApiException catch (e) {
      // A read that timed out or never connected is safe to repeat once - the
      // first attempt on a cold phone often stalls on a stale connection while
      // the retry goes straight through. Writes are never repeated: a second
      // attempt could place a second order.
      if (method != 'GET' || e.status != 0) rethrow;
      res = await _withConnectionErrors(send);
    }

    try {
      return _decode(res, token, envelope: envelope);
    } on ApiException catch (e) {
      // A 5xx on a read is usually the server being momentarily overloaded (a
      // database deadlock under a burst of requests, say); the same request a
      // moment later goes through. Reads only - and only once.
      if (method != 'GET' || e.status < 500) rethrow;
      await Future<void>.delayed(const Duration(milliseconds: 600));
      return _decode(await _withConnectionErrors(send), token,
          envelope: envelope);
    }
  }

  /// Multipart upload of one file, plus any text [fields]. Bytes rather than a
  /// path, so it works the same on mobile and web.
  static Future<dynamic> upload(
    String path, {
    required String fileField,
    required List<int> bytes,
    required String filename,
    required String contentType,
    Map<String, String> fields = const {},
    String? token,
  }) async {
    final req = http.MultipartRequest('POST', Uri.parse('$baseUrl$path'))
      ..headers['Accept'] = 'application/json'
      ..fields.addAll(fields)
      ..files.add(http.MultipartFile.fromBytes(
        fileField,
        bytes,
        filename: filename,
        contentType: MediaType.parse(contentType),
      ));
    if (token != null) req.headers['Authorization'] = 'Bearer $token';

    final res = await _withConnectionErrors(
      () async => http.Response.fromStream(await req.send()),
      timeout: const Duration(seconds: 60),
    );
    return _decode(res, token);
  }

  static Future<http.Response> _withConnectionErrors(
    Future<http.Response> Function() send, {
    Duration timeout = const Duration(seconds: 10),
  }) async {
    try {
      return await send().timeout(timeout);
    } on TimeoutException {
      throw ApiException(
          0, 'The store is taking too long to respond. Please try again.');
    } on http.ClientException {
      throw ApiException(0,
          'Could not connect. Check your internet connection and try again.');
    }
  }

  static dynamic _decode(http.Response res, String? token,
      {bool envelope = false}) {
    Map<String, dynamic> data = {};
    if (res.body.isNotEmpty) {
      try {
        final decoded = jsonDecode(res.body);
        if (decoded is Map<String, dynamic>) data = decoded;
      } catch (_) {
        // Non-JSON body (an HTML error page, say) — fall through to the status.
      }
    }

    if (res.statusCode >= 400) {
      if (res.statusCode == 401 && token != null) onUnauthorized?.call();

      // 429 is a real outcome now that the API is rate limited, and "Request
      // failed (429)" tells the user nothing actionable.
      if (res.statusCode == 429) {
        throw ApiException(
            429, 'Too many attempts. Please wait a minute and try again.');
      }

      final errors = data['errors'];
      final message = errors is Map
          ? errors.values.expand((v) => v is List ? v : [v]).join(' ')
          : (data['message'] as String?) ??
              'Request failed (${res.statusCode})';

      Map<String, List<String>>? byField;
      if (errors is Map) {
        byField = {
          for (final e in errors.entries)
            e.key.toString(): (e.value is List ? e.value as List : [e.value])
                .map((m) => m.toString())
                .toList(),
        };
      }
      throw ApiException(res.statusCode, message, errors: byField);
    }

    return envelope ? data : (data['data'] ?? data);
  }
}
