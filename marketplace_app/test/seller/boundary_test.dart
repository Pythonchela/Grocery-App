import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

/// Selling and shopping are two apps built from one codebase. That only stays true
/// if nothing quietly reaches across, so this test reads the imports and fails the
/// moment something does.
///
///   lib/main.dart          the shopping app     — must not reach lib/seller or lib/vendor
///   lib/main_vendor.dart   the seller app       — must not reach the shopper's screens, widgets or state
///   lib/seller/            the seller area      — imports only itself, the design system, support and the API client
///
/// See lib/seller/README.md for the rules.
void main() {
  final libDir = Directory('lib');

  List<File> dartFiles(Directory d) =>
      d.listSync(recursive: true).whereType<File>().where((f) => f.path.endsWith('.dart')).toList();

  String norm(String path) => path.replaceAll('\\', '/');

  final importPattern = RegExp(r'''^(?:import|export)\s+['"]([^'"]+)['"]''', multiLine: true);

  /// Resolve an import to a path under lib/, or null for dart: and third-party packages.
  String? resolve(String from, String target) {
    if (target.startsWith('dart:')) return null;

    if (target.startsWith('package:marketplace_app/')) {
      return 'lib/${target.substring('package:marketplace_app/'.length)}';
    }
    if (target.startsWith('package:')) return null;

    final parts = [...File(from).parent.path.replaceAll('\\', '/').split('/')];
    for (final seg in target.split('/')) {
      if (seg == '..') {
        parts.removeLast();
      } else if (seg != '.') {
        parts.add(seg);
      }
    }
    return parts.join('/');
  }

  Iterable<String> importsOf(String file) =>
      importPattern.allMatches(File(file).readAsStringSync()).map((m) => resolve(file, m.group(1)!)).whereType<String>();

  /// Every file the app would compile in, starting from its entry point.
  Set<String> reachableFrom(String entry) {
    final seen = <String>{};
    final queue = [entry];
    while (queue.isNotEmpty) {
      final file = queue.removeLast();
      if (!seen.add(file) || !File(file).existsSync()) continue;
      queue.addAll(importsOf(file));
    }
    return seen;
  }

  test('the seller area imports only itself, the design system and the API client', () {
    final offenders = <String>[];

    for (final file in dartFiles(Directory('lib/seller'))) {
      for (final path in importsOf(file.path)) {
        final allowed = path.startsWith('lib/seller/') ||
            path.startsWith('lib/design/') ||
            // Shared with the shopping app on the same terms: it reaches only the API client and the design system.
            path.startsWith('lib/support/') ||
            path == 'lib/data/api_client.dart';

        if (!allowed) offenders.add('${norm(file.path)} imports $path');
      }
    }

    expect(offenders, isEmpty, reason: 'the seller area must not depend on the shopping app:\n${offenders.join('\n')}');
  });

  test('only the seller app imports the seller area, and only through its public file', () {
    final offenders = <String>[];

    for (final file in dartFiles(libDir)) {
      final here = norm(file.path);
      if (here.startsWith('lib/seller/')) continue;

      for (final path in importsOf(file.path)) {
        if (!path.startsWith('lib/seller/')) continue;

        final ok = here.startsWith('lib/vendor/') && path == 'lib/seller/seller.dart';
        if (!ok) offenders.add('$here imports $path');
      }
    }

    expect(offenders, isEmpty, reason: 'unexpected dependencies on the seller area:\n${offenders.join('\n')}');
  });

  test('the shopping app contains no seller code', () {
    final reached = reachableFrom('lib/main.dart');
    final seller = reached.where((p) => p.startsWith('lib/seller/') || p.startsWith('lib/vendor/')).toList()..sort();

    expect(reached, contains('lib/screens/account_screen.dart'), reason: 'the walk should find the shopping app');
    expect(seller, isEmpty, reason: 'the shopping app must not compile in selling:\n${seller.join('\n')}');
  });

  test('the seller app contains no shopping screens, widgets or state', () {
    final reached = reachableFrom('lib/main_vendor.dart');
    final shopper = reached
        .where((p) => p.startsWith('lib/screens/') || p.startsWith('lib/widgets/') || p.startsWith('lib/state/'))
        .toList()
      ..sort();

    expect(reached, contains('lib/seller/screens/seller_dashboard.dart'), reason: 'the walk should find the seller area');
    expect(shopper, isEmpty, reason: 'the seller app must not compile in shopping:\n${shopper.join('\n')}');
  });

  test('the shopping app does not import the seller-only data files', () {
    // The seller app has its own session; nothing in the shopper's state refers to it.
    final offenders = dartFiles(Directory('lib/state'))
        .where((f) => f.readAsStringSync().contains('vendor/') || f.readAsStringSync().contains('seller/'))
        .map((f) => norm(f.path))
        .toList();

    expect(offenders, isEmpty);
  });

  test('the design system does not know about sellers', () {
    final offenders = dartFiles(Directory('lib/design'))
        .where((f) => f.readAsStringSync().contains('seller/'))
        .map((f) => f.path)
        .toList();

    expect(offenders, isEmpty);
  });
}
