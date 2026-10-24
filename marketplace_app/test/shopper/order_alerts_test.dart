import 'package:flutter_test/flutter_test.dart';
import 'package:marketplace_app/data/local_notifications.dart';
import 'package:marketplace_app/data/order_alerts.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// The watcher decides what the shopper is told about their orders, and when.
/// Its promise is: every update announced once, nothing repeated, and a fresh
/// install does not bury anyone in old news.
void main() {
  late SharedPreferences prefs;
  late List<String> unreadIds;
  late List<String> shown;

  AlertItem item(String id) =>
      AlertItem(id: id, type: 'ORDER_UPDATE', title: 'Update $id', data: {'order_id': 'o-$id'});

  NotificationWatcher watcher({int maxIndividual = 3}) => NotificationWatcher(
        prefs: prefs,
        maxIndividual: maxIndividual,
        fetch: (_) async => unreadIds.map(item).toList(),
        show: (alert, {bool summary = false, int more = 0}) async =>
            shown.add(summary ? 'summary:$more' : alert.id),
      );

  setUp(() async {
    SharedPreferences.setMockInitialValues({});
    prefs = await SharedPreferences.getInstance();
    unreadIds = [];
    shown = [];
  });

  test('the first check on a phone records history without announcing it', () async {
    unreadIds = ['1', '2', '3'];

    final raised = await watcher().check('t');

    expect(raised, 0);
    expect(shown, isEmpty);
  });

  test('after that, a new update is announced exactly once', () async {
    await watcher().check('t'); // prime with nothing

    unreadIds = ['1'];
    expect(await watcher().check('t'), 1);
    expect(shown, ['1']);

    // The same update is still unread on the next check; it must not repeat.
    expect(await watcher().check('t'), 0);
    expect(shown, ['1']);
  });

  test('history from before the first check never fires later', () async {
    unreadIds = ['old1', 'old2'];
    await watcher().check('t');

    unreadIds = ['new', 'old1', 'old2'];
    await watcher().check('t');

    expect(shown, ['new']);
  });

  test('a burst is announced oldest first, with the rest folded into one line', () async {
    await watcher().check('t');

    // API order is newest first.
    unreadIds = ['5', '4', '3', '2', '1'];
    final raised = await watcher().check('t');

    expect(shown.first, 'summary:2');
    expect(shown.sublist(1), ['3', '4', '5']);
    expect(raised, 4);
  });

  test('reading everything and then getting news announces just the news', () async {
    await watcher().check('t');
    unreadIds = ['1'];
    await watcher().check('t');

    unreadIds = [];
    await watcher().check('t');

    unreadIds = ['2'];
    await watcher().check('t');

    expect(shown, ['1', '2']);
  });

  test('the memory of announced updates is bounded', () async {
    await watcher().check('t');
    unreadIds = List.generate(400, (i) => 'n$i');
    await watcher(maxIndividual: 1).check('t');

    expect(prefs.getStringList(NotificationWatcher.alertedKey)!.length, lessThanOrEqualTo(300));
  });

  group('parsing', () {
    test('keeps well-formed notifications and drops the rest', () {
      final items = NotificationWatcher.parse([
        {'id': 'a', 'type': 'REFUND', 'title': 'Refunded', 'body': '₹499', 'data': {'order_id': 'o1'}},
        {'type': 'REFUND', 'title': 'No id'},
        'garbage',
        {'id': 'b', 'title': 'Plain'},
      ]);

      expect(items.map((i) => i.id), ['a', 'b']);
      expect(items.first.data['order_id'], 'o1');
      expect(items.last.data, isEmpty);
    });

    test('anything that is not a list yields nothing', () {
      expect(NotificationWatcher.parse(null), isEmpty);
      expect(NotificationWatcher.parse({'oops': 1}), isEmpty);
    });
  });

  group('notification ids', () {
    test('the same key always gives the same id, so an alert replaces itself', () {
      expect(LocalNotifications.stableId('n:42'), LocalNotifications.stableId('n:42'));
      expect(LocalNotifications.stableId('n:42'), isNot(LocalNotifications.stableId('n:43')));
    });

    test('ids are positive and fit in 31 bits', () {
      for (final key in ['a', 'n:1', 'review_reminder_xyz', '', 'summary']) {
        final id = LocalNotifications.stableId(key);
        expect(id, greaterThan(0));
        expect(id, lessThanOrEqualTo(0x7fffffff));
      }
    });
  });
}
