import 'package:flutter/material.dart';

import '../data/api_client.dart';
import '../design/components.dart';
import '../design/theme.dart';
import '../design/tokens.g.dart';
import '../state/app_state.dart';

/// Customer questions and answers for one product.
///
/// Questions are moderated server-side, so a freshly asked question is
/// acknowledged but not shown until approved.
class ProductQuestions extends StatefulWidget {
  final String productId;
  const ProductQuestions({super.key, required this.productId});

  @override
  State<ProductQuestions> createState() => _ProductQuestionsState();
}

class _ProductQuestionsState extends State<ProductQuestions> {
  List<Map<String, dynamic>> _questions = [];
  bool _loading = true;
  String? _error;
  bool _showAll = false;

  static const _collapsed = 3;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    try {
      final data =
          await ApiClient.request('/products/${widget.productId}/questions');
      if (!mounted) return;
      setState(() {
        _questions = (data as List).cast<Map<String, dynamic>>();
        _loading = false;
        _error = null;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _error = e.toString();
        _loading = false;
      });
    }
  }

  bool _requireSignIn() {
    if (AppState.instance.isSignedIn) return true;
    ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
        content: Text('Sign in from the Account tab to join the conversation')));
    return false;
  }

  Future<void> _ask() async {
    if (!_requireSignIn()) return;
    final done = await showBxSheet<bool>(
      context: context,
      title: 'Ask a question',
      child: _TextForm(
        hint: 'What would you like to know about this product?',
        submitLabel: 'Submit question',
        onSubmit: (text) => ApiClient.request(
          '/products/${widget.productId}/questions',
          method: 'POST',
          token: AppState.instance.token,
          body: {'body': text},
        ),
      ),
    );
    if (done == true && mounted) {
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
          content: Text('Question submitted — it will appear once approved.')));
    }
  }

  Future<void> _answer(Map<String, dynamic> question) async {
    if (!_requireSignIn()) return;
    final done = await showBxSheet<bool>(
      context: context,
      title: 'Answer this question',
      child: _TextForm(
        heading: '${question['body']}',
        hint: 'Share what you know',
        submitLabel: 'Post answer',
        onSubmit: (text) => ApiClient.request(
          '/questions/${question['id']}/answer',
          method: 'POST',
          token: AppState.instance.token,
          body: {'body': text},
        ),
      ),
    );
    if (done == true) _load();
  }

  Future<void> _helpful(Map<String, dynamic> answer) async {
    if (!_requireSignIn()) return;
    try {
      await ApiClient.request('/answers/${answer['id']}/helpful',
          method: 'POST', token: AppState.instance.token);
      _load();
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context)
            .showSnackBar(SnackBar(content: Text('$e')));
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final c = context.ds;
    final visible =
        _showAll ? _questions : _questions.take(_collapsed).toList();

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            Expanded(
              child: Text('Questions & answers',
                  style: TextStyle(
                      fontSize: DsText.lg,
                      fontWeight: DsWeight.black,
                      color: c.ink)),
            ),
            BxButton(
              label: 'Ask',
              size: BxButtonSize.sm,
              variant: BxButtonVariant.secondary,
              leadingIcon: Icons.help_outline,
              onPressed: _ask,
            ),
          ],
        ),
        const SizedBox(height: DsSpace.s3),
        if (_loading)
          const BxSkeleton(height: 80, radius: DsRadius.cardAll)
        else if (_error != null)
          BxAlert(_error!, tone: BxTone.danger)
        else if (_questions.isEmpty)
          BxCard(
            child: Text('No questions yet. Be the first to ask.',
                style: TextStyle(fontSize: DsText.base, color: c.inkMuted)),
          )
        else ...[
          ...visible.map((q) => Padding(
                padding: const EdgeInsets.only(bottom: DsSpace.s3),
                child: _QuestionTile(
                  question: q,
                  onAnswer: () => _answer(q),
                  onHelpful: _helpful,
                ),
              )),
          if (_questions.length > _collapsed)
            Center(
              child: BxButton(
                label: _showAll
                    ? 'Show fewer'
                    : 'Show all ${_questions.length} questions',
                variant: BxButtonVariant.link,
                size: BxButtonSize.sm,
                onPressed: () => setState(() => _showAll = !_showAll),
              ),
            ),
        ],
      ],
    );
  }
}

class _QuestionTile extends StatelessWidget {
  final Map<String, dynamic> question;
  final VoidCallback onAnswer;
  final void Function(Map<String, dynamic>) onHelpful;

  const _QuestionTile(
      {required this.question, required this.onAnswer, required this.onHelpful});

  @override
  Widget build(BuildContext context) {
    final c = context.ds;
    final answers =
        (question['answers'] as List? ?? []).cast<Map<String, dynamic>>();
    final asker = question['user'];

    return BxCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text('Q  ',
                  style: TextStyle(
                      fontWeight: DsWeight.black, color: c.accent)),
              Expanded(
                child: Text('${question['body']}',
                    style: TextStyle(
                        fontSize: DsText.base,
                        fontWeight: DsWeight.bold,
                        color: c.ink)),
              ),
            ],
          ),
          if (asker is Map)
            Padding(
              padding: const EdgeInsets.only(left: 22, top: 2),
              child: Text('Asked by ${asker['name']}',
                  style: TextStyle(fontSize: DsText.xs, color: c.inkSubtle)),
            ),
          const SizedBox(height: DsSpace.s2),
          if (answers.isEmpty)
            Padding(
              padding: const EdgeInsets.only(left: 22),
              child: Text('No answers yet.',
                  style: TextStyle(fontSize: DsText.sm, color: c.inkMuted)),
            )
          else
            ...answers.take(2).map((a) {
              final user = a['user'];
              return Padding(
                padding: const EdgeInsets.only(left: 22, bottom: DsSpace.s2),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text('${a['body']}',
                        style: TextStyle(
                            fontSize: DsText.base,
                            height: DsText.baseHeight,
                            color: c.inkMuted)),
                    const SizedBox(height: 2),
                    Wrap(
                      spacing: DsSpace.s2,
                      crossAxisAlignment: WrapCrossAlignment.center,
                      children: [
                        if (a['is_official'] == true)
                          const BxBadge('Official', tone: BxTone.accent),
                        if (a['is_verified_buyer'] == true)
                          const BxBadge('Verified buyer',
                              tone: BxTone.success),
                        if (user is Map)
                          Text('— ${user['name']}',
                              style: TextStyle(
                                  fontSize: DsText.xs, color: c.inkSubtle)),
                        InkWell(
                          onTap: () => onHelpful(a),
                          child: Padding(
                            padding: const EdgeInsets.symmetric(vertical: 4),
                            child: Text(
                              'Helpful (${a['helpful_count'] ?? 0})',
                              style: TextStyle(
                                  fontSize: DsText.xs,
                                  fontWeight: DsWeight.bold,
                                  color: c.accent),
                            ),
                          ),
                        ),
                      ],
                    ),
                  ],
                ),
              );
            }),
          Align(
            alignment: Alignment.centerLeft,
            child: BxButton(
              label: 'Answer',
              variant: BxButtonVariant.link,
              size: BxButtonSize.sm,
              onPressed: onAnswer,
            ),
          ),
        ],
      ),
    );
  }
}

class _TextForm extends StatefulWidget {
  final String? heading;
  final String hint;
  final String submitLabel;
  final Future<dynamic> Function(String text) onSubmit;

  const _TextForm({
    this.heading,
    required this.hint,
    required this.submitLabel,
    required this.onSubmit,
  });

  @override
  State<_TextForm> createState() => _TextFormState();
}

class _TextFormState extends State<_TextForm> {
  final _controller = TextEditingController();
  bool _saving = false;
  String? _error;

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  Future<void> _submit() async {
    final text = _controller.text.trim();
    if (text.isEmpty) {
      setState(() => _error = 'Please write something first.');
      return;
    }
    setState(() {
      _saving = true;
      _error = null;
    });
    try {
      await widget.onSubmit(text);
      if (mounted) Navigator.of(context).pop(true);
    } catch (e) {
      if (mounted) {
        setState(() {
          _error = e.toString();
          _saving = false;
        });
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final c = context.ds;
    return Padding(
      padding:
          EdgeInsets.only(bottom: MediaQuery.of(context).viewInsets.bottom),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisSize: MainAxisSize.min,
        children: [
          if (widget.heading != null) ...[
            Text(widget.heading!,
                style: TextStyle(
                    fontSize: DsText.base,
                    fontWeight: DsWeight.bold,
                    color: c.ink)),
            const SizedBox(height: DsSpace.s3),
          ],
          if (_error != null) ...[
            BxAlert(_error!, tone: BxTone.danger),
            const SizedBox(height: DsSpace.s3),
          ],
          BxField(
            label: 'Your message',
            hint: widget.hint,
            controller: _controller,
            maxLines: 4,
          ),
          const SizedBox(height: DsSpace.s4),
          BxButton(
            label: widget.submitLabel,
            fullWidth: true,
            loading: _saving,
            onPressed: _saving ? null : _submit,
          ),
        ],
      ),
    );
  }
}
