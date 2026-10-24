import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:marketplace_app/data/api_client.dart';

import 'support.dart';

/// A read that fails to connect is repeated once; a write never is - a second
/// attempt at "place order" could place a second order.
void main() {
  test('a read that fails once is retried and succeeds', () async {
    var calls = 0;
    final client = MockClient((request) async {
      calls++;
      if (calls == 1) throw http.ClientException('connection reset');
      return response([1, 2, 3]);
    });

    final data = await http.runWithClient(() => ApiClient.request('/categories'), () => client);

    expect(data, [1, 2, 3]);
    expect(calls, 2);
  });

  test('a read that keeps failing gives up after the one retry', () async {
    var calls = 0;
    final client = MockClient((request) async {
      calls++;
      throw http.ClientException('offline');
    });

    await expectLater(
      http.runWithClient(() => ApiClient.request('/categories'), () => client),
      throwsA(isA<ApiException>()),
    );
    expect(calls, 2);
  });

  test('a write is never repeated', () async {
    var calls = 0;
    final client = MockClient((request) async {
      calls++;
      throw http.ClientException('offline');
    });

    await expectLater(
      http.runWithClient(
          () => ApiClient.request('/orders/checkout', method: 'POST', body: {'a': 1}),
          () => client),
      throwsA(isA<ApiException>()),
    );
    expect(calls, 1);
  });

  test('a server error on a read is retried once and can recover', () async {
    var calls = 0;
    final client = MockClient((request) async {
      calls++;
      return calls == 1
          ? http.Response('{"message":"Server Error"}', 500)
          : response([1]);
    });

    final data = await http.runWithClient(() => ApiClient.request('/categories'), () => client);

    expect(data, [1]);
    expect(calls, 2);
  });

  test('a server error that persists is reported after the one retry', () async {
    var calls = 0;
    final client = MockClient((request) async {
      calls++;
      return http.Response('{"message":"Server Error"}', 500);
    });

    await expectLater(
      http.runWithClient(() => ApiClient.request('/categories'), () => client),
      throwsA(isA<ApiException>()),
    );
    expect(calls, 2);
  });

  test('a client error is never retried', () async {
    var calls = 0;
    final client = MockClient((request) async {
      calls++;
      return http.Response('{"message":"nope"}', 404);
    });

    await expectLater(
      http.runWithClient(() => ApiClient.request('/categories'), () => client),
      throwsA(isA<ApiException>()),
    );
    expect(calls, 1);
  });

  test('a server error on a write is never retried', () async {
    var calls = 0;
    final client = MockClient((request) async {
      calls++;
      return http.Response('{"message":"Server Error"}', 500);
    });

    await expectLater(
      http.runWithClient(
          () => ApiClient.request('/orders/checkout', method: 'POST', body: {'a': 1}),
          () => client),
      throwsA(isA<ApiException>()),
    );
    expect(calls, 1);
  });
}
