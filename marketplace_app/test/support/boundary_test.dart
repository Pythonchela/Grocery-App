import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

/// lib/support is used by both the shopper app and the seller area, so it may
/// depend on neither: only itself, the design system and the API client. That keeps
/// the seller area movable into its own app (it takes lib/support with it).
void main() {
  test('the shared support module imports only itself, the design system and the API client', () {
    final importPattern = RegExp(r'''^(?:import|export)\s+['"]([^'"]+)['"]''', multiLine: true);
    final offenders = <String>[];

    String resolve(File from, String target) {
      if (target.startsWith('package:marketplace_app/')) {
        return 'lib/${target.substring('package:marketplace_app/'.length)}';
      }
      final parts = from.parent.path.replaceAll(r'\', '/').split('/');
      for (final seg in target.split('/')) {
        if (seg == '..') {
          parts.removeLast();
        } else if (seg != '.') {
          parts.add(seg);
        }
      }
      return parts.join('/');
    }

    final files = Directory('lib/support').listSync(recursive: true).whereType<File>().where((f) => f.path.endsWith('.dart'));
    for (final file in files) {
      for (final m in importPattern.allMatches(file.readAsStringSync())) {
        final target = m.group(1)!;
        if (target.startsWith('dart:')) continue;
        if (target.startsWith('package:') && !target.startsWith('package:marketplace_app/')) continue;

        final path = resolve(file, target);
        final allowed = path.startsWith('lib/support/') || path.startsWith('lib/design/') || path == 'lib/data/api_client.dart';
        if (!allowed) offenders.add('${file.path.replaceAll(r'\', '/')} imports $path');
      }
    }

    expect(offenders, isEmpty, reason: offenders.join('\n'));
  });
}
