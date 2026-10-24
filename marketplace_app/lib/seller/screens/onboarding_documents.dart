import 'package:flutter/material.dart';

import '../../data/api_client.dart';
import '../../design/components.dart';
import '../../design/theme.dart';
import '../../design/tokens.g.dart';
import '../document_picker.dart';
import '../seller_api.dart';
import '../seller_format.dart';
import '../seller_models.dart';

/// Step 4: the documents that back the details.
///
/// Which ones are required depends on the answers so far — a GST certificate
/// only once a GSTIN was entered, a certificate of incorporation only for
/// registered entities — so a sole trader is never asked for paperwork they
/// cannot have. The server's checklist decides what is actually missing.
class DocumentsStep extends StatefulWidget {
  final SellerApi api;
  final DocumentPicker picker;
  final Onboarding onboarding;
  final ValueChanged<Onboarding> onChanged;

  const DocumentsStep({
    super.key,
    required this.api,
    required this.picker,
    required this.onboarding,
    required this.onChanged,
  });

  @override
  State<DocumentsStep> createState() => _DocumentsStepState();
}

class _DocumentsStepState extends State<DocumentsStep> {
  final Set<String> _busyKinds = {};
  final Map<String, String> _problems = {};

  Onboarding get _ob => widget.onboarding;

  /// Kinds to show, in a sensible order, restricted to what the API accepts.
  List<String> get _kinds {
    const order = ['PAN_CARD', 'CANCELLED_CHEQUE', 'GST_CERTIFICATE', 'INCORPORATION_CERT', 'ADDRESS_PROOF'];
    final accepted = _ob.documentKinds.isEmpty ? order : _ob.documentKinds;
    return order.where(accepted.contains).toList();
  }

  /// Mirrors the server's rule; anything the server lists as missing is
  /// required whatever this says.
  bool _isRequired(String kind) =>
      _ob.checklist.missingDocuments.contains(kind) ||
      kind == 'PAN_CARD' ||
      kind == 'CANCELLED_CHEQUE' ||
      (kind == 'GST_CERTIFICATE' && _ob.kyc.hasGstin) ||
      (kind == 'INCORPORATION_CERT' && _ob.kyc.isRegisteredEntity);

  Future<void> _upload(String kind) async {
    setState(() => _problems.remove(kind));

    final PickedDocument? file;
    try {
      file = await widget.picker.pick();
    } catch (_) {
      if (mounted) setState(() => _problems[kind] = 'Could not open the file picker.');
      return;
    }
    if (file == null || !mounted) return; // backed out

    final problem = DocumentRules.problemWith(file);
    if (problem != null) {
      setState(() => _problems[kind] = problem);
      return;
    }

    setState(() => _busyKinds.add(kind));
    try {
      final ob = await widget.api.uploadDocument(kind, file);
      if (!mounted) return;
      widget.onChanged(ob);
    } on ApiException catch (e) {
      if (mounted) setState(() => _problems[kind] = e.fieldError('file') ?? e.message);
    } catch (_) {
      if (mounted) setState(() => _problems[kind] = 'Upload failed. Check your connection and try again.');
    } finally {
      if (mounted) setState(() => _busyKinds.remove(kind));
    }
  }

  Future<void> _remove(KycDocument doc) async {
    setState(() {
      _busyKinds.add(doc.kind);
      _problems.remove(doc.kind);
    });
    try {
      final ob = await widget.api.deleteDocument(doc.id);
      if (!mounted) return;
      widget.onChanged(ob);
    } on ApiException catch (e) {
      if (mounted) setState(() => _problems[doc.kind] = e.message);
    } catch (_) {
      if (mounted) setState(() => _problems[doc.kind] = 'Could not remove that file. Try again.');
    } finally {
      if (mounted) setState(() => _busyKinds.remove(doc.kind));
    }
  }

  @override
  Widget build(BuildContext context) {
    final c = context.ds;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text('Upload your documents',
            style: TextStyle(fontSize: DsText.xl, fontWeight: DsWeight.black, color: c.ink)),
        const SizedBox(height: DsSpace.s1),
        Text(
          'JPG, PNG, WebP or PDF, up to 5 MB each. Only our verification team can see these.',
          style: TextStyle(fontSize: DsText.base, color: c.inkMuted),
        ),
        const SizedBox(height: DsSpace.s4),
        for (final kind in _kinds) ...[
          _DocumentCard(
            kind: kind,
            required: _isRequired(kind),
            document: _ob.documentOfKind(kind),
            busy: _busyKinds.contains(kind),
            problem: _problems[kind],
            onUpload: () => _upload(kind),
            onRemove: _remove,
          ),
          const SizedBox(height: DsSpace.s3),
        ],
      ],
    );
  }
}

class _DocumentCard extends StatelessWidget {
  final String kind;
  final bool required;
  final KycDocument? document;
  final bool busy;
  final String? problem;
  final VoidCallback onUpload;
  final ValueChanged<KycDocument> onRemove;

  const _DocumentCard({
    required this.kind,
    required this.required,
    required this.document,
    required this.busy,
    required this.problem,
    required this.onUpload,
    required this.onRemove,
  });

  @override
  Widget build(BuildContext context) {
    final c = context.ds;
    final doc = document;

    return BxCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Expanded(
                child: Text(
                  SellerFormat.documentKind(kind),
                  style: TextStyle(fontSize: DsText.md, fontWeight: DsWeight.black, color: c.ink),
                ),
              ),
              if (doc != null)
                const BxBadge('Uploaded', tone: BxTone.success, icon: Icons.check)
              else if (required)
                const BxBadge('Required', tone: BxTone.warning)
              else
                const BxBadge('Optional'),
            ],
          ),
          const SizedBox(height: DsSpace.s1),
          Text(SellerFormat.documentHint(kind), style: TextStyle(fontSize: DsText.sm, color: c.inkMuted)),
          if (doc != null) ...[
            const SizedBox(height: DsSpace.s3),
            Row(
              children: [
                Icon(Icons.description_outlined, size: 18, color: c.inkMuted),
                const SizedBox(width: DsSpace.s2),
                Expanded(
                  child: Text(
                    '${doc.originalName} · ${SellerFormat.size(doc.sizeBytes)}',
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(fontSize: DsText.sm, color: c.ink),
                  ),
                ),
              ],
            ),
          ],
          if (problem != null) ...[
            const SizedBox(height: DsSpace.s3),
            BxAlert(problem!, tone: BxTone.danger),
          ],
          const SizedBox(height: DsSpace.s3),
          Row(
            children: [
              BxButton(
                label: doc == null ? 'Choose file' : 'Replace',
                leadingIcon: Icons.upload_file,
                variant: doc == null ? BxButtonVariant.primary : BxButtonVariant.secondary,
                size: BxButtonSize.sm,
                loading: busy,
                onPressed: busy ? null : onUpload,
              ),
              if (doc != null) ...[
                const SizedBox(width: DsSpace.s2),
                BxButton(
                  label: 'Remove',
                  variant: BxButtonVariant.ghost,
                  size: BxButtonSize.sm,
                  onPressed: busy ? null : () => onRemove(doc),
                ),
              ],
            ],
          ),
        ],
      ),
    );
  }
}
