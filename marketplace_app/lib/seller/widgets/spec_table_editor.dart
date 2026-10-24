import 'package:flutter/material.dart';

import '../../design/components.dart';
import '../../design/theme.dart';
import '../../design/tokens.g.dart';
import '../seller_models.dart';

/// Holds what a seller has typed into the specification table.
///
/// The screen owns one of these, so it can read the rows at save time and
/// dispose every text field it created.
class SpecTableController extends ChangeNotifier {
  final List<SpecGroupDraft> _groups;

  SpecTableController([List<SellerSpecGroup> initial = const []])
      : _groups = [
          for (final g in initial)
            SpecGroupDraft(g.title, [for (final r in g.rows) SpecRowDraft(r.label, r.value)]),
        ];

  bool get isEmpty => _groups.isEmpty;

  /// The table as the API takes it. Rows missing a name or a value are left out
  /// by the server, so a half-typed row costs nothing.
  List<Map<String, dynamic>> toJson() => [
        for (final g in _groups)
          {
            'title': g.title.text.trim(),
            'rows': [
              for (final r in g.rows)
                {'label': r.label.text.trim(), 'value': r.value.text.trim()},
            ],
          },
      ];

  void addGroup() {
    _groups.add(SpecGroupDraft(_groups.isEmpty ? 'General' : '', [SpecRowDraft('', '')]));
    notifyListeners();
  }

  void removeGroup(SpecGroupDraft g) {
    _groups.remove(g);
    g.dispose();
    notifyListeners();
  }

  void addRow(SpecGroupDraft g) {
    g.rows.add(SpecRowDraft('', ''));
    notifyListeners();
  }

  void removeRow(SpecGroupDraft g, SpecRowDraft r) {
    g.rows.remove(r);
    r.dispose();
    notifyListeners();
  }

  @override
  void dispose() {
    for (final g in _groups) {
      g.dispose();
    }
    super.dispose();
  }
}

class SpecGroupDraft {
  final TextEditingController title;
  final List<SpecRowDraft> rows;

  SpecGroupDraft(String title, this.rows) : title = TextEditingController(text: title);

  void dispose() {
    title.dispose();
    for (final r in rows) {
      r.dispose();
    }
  }
}

class SpecRowDraft {
  final TextEditingController label;
  final TextEditingController value;

  SpecRowDraft(String label, String value)
      : label = TextEditingController(text: label),
        value = TextEditingController(text: value);

  void dispose() {
    label.dispose();
    value.dispose();
  }
}

/// The specification table as a seller edits it: sections, each a list of
/// "name / value" rows (Fabric / Cotton). Shoppers see it under "All details".
class SpecTableEditor extends StatelessWidget {
  final SpecTableController controller;
  final bool enabled;

  const SpecTableEditor({super.key, required this.controller, this.enabled = true});

  @override
  Widget build(BuildContext context) {
    final c = context.ds;

    return ListenableBuilder(
      listenable: controller,
      builder: (context, _) {
        final groups = controller._groups;

        return Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            if (groups.isEmpty)
              Padding(
                padding: const EdgeInsets.only(bottom: DsSpace.s3),
                child: Text(
                  'Nothing yet. Add rows like Fabric, Fit or Warranty so shoppers can compare.',
                  style: TextStyle(fontSize: DsText.sm, color: c.inkMuted),
                ),
              ),
            for (final g in groups) ...[
              Container(
                padding: const EdgeInsets.all(DsSpace.s3),
                margin: const EdgeInsets.only(bottom: DsSpace.s3),
                decoration: BoxDecoration(
                  color: c.surfaceSunken,
                  borderRadius: DsRadius.controlAll,
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        Expanded(
                          child: BxField(
                            label: 'Section heading',
                            hint: 'e.g. General',
                            controller: g.title,
                            enabled: enabled,
                          ),
                        ),
                        IconButton(
                          tooltip: 'Remove this section',
                          onPressed: enabled ? () => controller.removeGroup(g) : null,
                          icon: const Icon(Icons.delete_outline),
                        ),
                      ],
                    ),
                    const SizedBox(height: DsSpace.s2),
                    for (final r in g.rows)
                      Padding(
                        padding: const EdgeInsets.only(bottom: DsSpace.s2),
                        child: Row(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Expanded(
                              child: BxField(
                                label: 'Name',
                                hint: 'Fabric',
                                controller: r.label,
                                enabled: enabled,
                              ),
                            ),
                            const SizedBox(width: DsSpace.s2),
                            Expanded(
                              child: BxField(
                                label: 'Value',
                                hint: 'Cotton',
                                controller: r.value,
                                enabled: enabled,
                              ),
                            ),
                            Padding(
                              padding: const EdgeInsets.only(top: 22),
                              child: IconButton(
                                tooltip: 'Remove row',
                                onPressed: enabled ? () => controller.removeRow(g, r) : null,
                                icon: const Icon(Icons.close, size: 20),
                              ),
                            ),
                          ],
                        ),
                      ),
                    Align(
                      alignment: Alignment.centerLeft,
                      child: TextButton.icon(
                        onPressed: enabled ? () => controller.addRow(g) : null,
                        icon: const Icon(Icons.add, size: 18),
                        label: const Text('Add row'),
                      ),
                    ),
                  ],
                ),
              ),
            ],
            OutlinedButton.icon(
              onPressed: enabled ? controller.addGroup : null,
              icon: const Icon(Icons.add, size: 18),
              label: Text(groups.isEmpty ? 'Add specifications' : 'Add another section'),
            ),
          ],
        );
      },
    );
  }
}
