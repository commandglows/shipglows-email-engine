import 'package:flutter/material.dart';
import 'package:newsletter_studio_flutter/newsletter_studio_flutter.dart';

import 'campaign_repository.dart';
import 'central_email_api.dart';
import 'session_client.dart';
import 'engine_theme.dart';
import 'source_workspace.dart';

void main() {
  final client = createSessionClient();
  runApp(
    EmailEngineApp(
      api: CentralEmailApi(origin: Uri.parse(Uri.base.origin), client: client),
    ),
  );
}

/// The real operator application has no demo fallbacks or credential inputs.
class EmailEngineApp extends StatefulWidget {
  const EmailEngineApp({super.key, required this.api});
  final CentralEmailApi api;
  @override
  State<EmailEngineApp> createState() => _EmailEngineAppState();
}

class _EmailEngineAppState extends State<EmailEngineApp> {
  bool _dark = false;
  @override
  Widget build(BuildContext context) => MaterialApp(
    title: 'ShipGlows · Email Engine',
    debugShowCheckedModeBanner: false,
    theme: EngineTheme.create(Brightness.light),
    darkTheme: EngineTheme.create(Brightness.dark),
    themeMode: _dark ? ThemeMode.dark : ThemeMode.light,
    home: Builder(
      builder: (context) => ReaderSourceWorkspace(
        api: widget.api,
        darkMode: _dark,
        onToggleTheme: () => setState(() => _dark = !_dark),
        onOpenCampaign: (session) => Navigator.of(context).push<void>(
          MaterialPageRoute(builder: (_) => _CampaignEditor(session: session)),
        ),
      ),
    ),
  );
}

class _CampaignEditor extends StatefulWidget {
  const _CampaignEditor({required this.session});
  final CampaignEditorSession session;
  @override
  State<_CampaignEditor> createState() => _CampaignEditorState();
}

class _CampaignEditorState extends State<_CampaignEditor> {
  late NewsletterDraft _draft;
  NewsletterAudienceSummary? _audience;
  NewsletterSchedule? _schedule;
  NewsletterTestReceipt? _test;
  bool _busy = false;
  bool _saved = true;
  bool _allowPop = false;
  @override
  void initState() {
    super.initState();
    _draft = widget.session.draft;
    final scheduled = widget.session.record['scheduled_at'];
    if (scheduled is String) {
      _schedule = NewsletterSchedule(
        sendAt: DateTime.parse(scheduled),
        timezoneLabel: 'Heure locale',
      );
    }
    _audience = NewsletterAudienceSummary(
      id: widget.session.audienceId,
      label: widget.session.audienceId,
      eligibleCount: 0,
      isResolved: false,
    );
  }

  void _error(Object error) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(
          error is EmailApiException
              ? error.message
              : 'L’action n’a pas abouti. Votre brouillon reste ouvert.',
        ),
      ),
    );
  }

  Future<NewsletterDraft> _save(NewsletterDraft draft) async {
    try {
      final saved = await widget.session.save(draft);
      return saved;
    } on EmailApiException catch (error) {
      _error(error);
      if (const [
        'version_conflict',
        'stale_version',
        'conflict',
      ].contains(error.code)) {
        throw const NewsletterSaveConflict();
      }
      rethrow;
    }
  }

  Future<void> _back() async {
    if (_busy) return;
    setState(() => _busy = true);
    try {
      if (!_saved && widget.session.state == 'draft') {
        if (_draft.saveState == NewsletterSaveState.conflict) {
          final discard = await showDialog<bool>(
            context: context,
            builder: (context) => AlertDialog(
              title: const Text('Conflit de versions'),
              content: const Text(
                'Copiez vos modifications avant de quitter. La version enregistrée sur le serveur sera conservée.',
              ),
              actions: [
                TextButton(
                  onPressed: () => Navigator.pop(context, false),
                  child: const Text('Rester dans le brouillon'),
                ),
                TextButton(
                  onPressed: () => Navigator.pop(context, true),
                  child: const Text('Quitter sans enregistrer'),
                ),
              ],
            ),
          );
          if (discard != true || !mounted) return;
        } else {
          // The session serializes this latest snapshot behind pending writes.
          // Never infer saved state from equal revisions: keystrokes may share it.
          await _save(_draft);
        }
      }
      if (mounted) {
        setState(() {
          _allowPop = true;
          _busy = false;
        });
        WidgetsBinding.instance.addPostFrameCallback((_) {
          if (mounted) Navigator.of(context).pop();
        });
      }
    } catch (error) {
      _error(error);
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<NewsletterTestReceipt> _sendTest(NewsletterDraft draft) async {
    final recipients = widget.session.business.testRecipients;
    final recipient = await showDialog<String>(
      context: context,
      builder: (context) => SimpleDialog(
        title: const Text('Recevoir un email test'),
        children: [
          for (final address in recipients)
            SimpleDialogOption(
              onPressed: () => Navigator.pop(context, address),
              child: Text(address),
            ),
        ],
      ),
    );
    if (recipient == null) throw const NewsletterActionCancelled();
    final receipt = await widget.session.test(draft, recipient);
    if (mounted) setState(() => _test = receipt);
    return receipt;
  }

  @override
  Widget build(BuildContext context) {
    final session = widget.session;
    final business = session.business;
    final editable = session.state == 'draft' && !_busy;
    return PopScope(
      canPop: _allowPop,
      onPopInvokedWithResult: (didPop, result) {
        if (!didPop && !_busy) _back();
      },
      child: NewsletterStudio(
        key: ValueKey(session.id),
        draft: _draft,
        onDraftChanged: (draft) => setState(() {
          _draft = draft;
          if (draft.saveState == NewsletterSaveState.dirty) _test = null;
          _saved =
              draft.saveState == NewsletterSaveState.saved ||
              draft.saveState == NewsletterSaveState.clean;
        }),
        audience: _audience,
        availableAudiences: business.audiences
            .map(
              (a) => NewsletterAudienceSummary(
                id: a['id'] as String,
                label: a['id'] as String,
                eligibleCount: 0,
                isResolved: false,
              ),
            )
            .toList(),
        onAudienceChanged: (audience) async {
          if (_busy) return;
          setState(() => _busy = true);
          try {
            await session.selectAudience(audience.id, _draft);
            if (mounted) {
              setState(() {
                _audience = audience;
                _test = null;
              });
            }
          } catch (error) {
            _error(error);
          } finally {
            if (mounted) setState(() => _busy = false);
          }
        },
        sender: NewsletterSenderSummary(
          name: business.brand,
          address: business.from,
          replyTo: business.from,
          isVerified: business.canApprove,
        ),
        design: NewsletterDesignSummary(
          templateName: 'Éditorial',
          brandName: business.brand,
        ),
        schedule: _schedule,
        onScheduleChanged: (value) => setState(() => _schedule = value),
        testReceipt: _test,
        capabilities: NewsletterStudioCapabilities(
          canEdit: editable,
          canPreview: !_busy,
          canTest:
              editable &&
              business.canTest &&
              business.testRecipients.isNotEmpty,
          canSchedule: editable && business.canApprove,
          canSend: editable && business.canApprove,
          canUnschedule:
              !_busy &&
              const ['scheduled', 'queued', 'sending'].contains(session.state),
          canViewDeliveryStatus: true,
        ),
        onSaveDraft: _save,
        onResolveAudience: (draft) async {
          final audience = await session.resolve(draft);
          if (mounted) setState(() => _audience = audience);
          return audience;
        },
        // The studio adopts onResolveAudience before checking blockers.
        onValidateDraft: (draft, audience) async => [],
        onRenderPreview: session.preview,
        onSendTest: _sendTest,
        onSend: (draft) async {
          final receipt = await session.approve(draft);
          if (mounted) setState(() {});
          return receipt;
        },
        onSchedule: (draft, schedule) async {
          final receipt = await session.approve(draft, schedule);
          if (mounted) setState(() {});
          return receipt;
        },
        onUnschedule: (_) async {
          await session.cancel();
          if (mounted) setState(() {});
        },
        onLoadDeliveryStatus: (_) async {
          final status = await session.delivery();
          if (mounted) setState(() {});
          return status;
        },
        onBack: _back,
      ),
    );
  }
}
