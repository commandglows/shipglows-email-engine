import 'package:flutter/material.dart';
import 'package:newsletter_studio_flutter/newsletter_studio_flutter.dart';
import 'package:source_sidebar_flutter/source_sidebar_flutter.dart';

import 'preview_theme.dart';
import 'campaign_demo_repository.dart';
import 'support_demo_repository.dart';

void main() => runApp(const SourceSidebarPreviewApp());

class SourceSidebarPreviewApp extends StatefulWidget {
  const SourceSidebarPreviewApp({super.key, this.showCockpit = true});
  final bool showCockpit;

  @override
  State<SourceSidebarPreviewApp> createState() =>
      _SourceSidebarPreviewAppState();
}

class _SourceSidebarPreviewAppState extends State<SourceSidebarPreviewApp> {
  ThemeMode _themeMode = ThemeMode.light;
  final _campaigns = CampaignDemoRepository();
  final _support = DemoSupportRepository();

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      debugShowCheckedModeBanner: false,
      title: 'ShipGlows · Email Engine',
      theme: PreviewTheme.light(),
      darkTheme: PreviewTheme.dark(),
      themeMode: _themeMode,
      home: widget.showCockpit
          ? EmailCockpit(
              demonstration: true,
              initialSection: Uri.base.queryParameters.containsKey('campaigns')
                  ? EmailSection.diffusion
                  : EmailSection.overview,
              darkMode: _themeMode == ThemeMode.dark,
              onToggleTheme: () => setState(
                () => _themeMode = _themeMode == ThemeMode.dark
                    ? ThemeMode.light
                    : ThemeMode.dark,
              ),
              builder: (context, section) => switch (section) {
                EmailSection.support => SupportWorkspace(repository: _support),
                EmailSection.sources ||
                EmailSection.diffusion => SourceLibraryDemo(
                  key: ValueKey(section),
                  campaignsOnly: section == EmailSection.diffusion,
                  campaigns: _campaigns,
                  darkMode: _themeMode == ThemeMode.dark,
                  onThemeChanged: (dark) => setState(
                    () => _themeMode = dark ? ThemeMode.dark : ThemeMode.light,
                  ),
                ),
                EmailSection.overview => const SizedBox.shrink(),
              },
            )
          : SourceLibraryDemo(
              darkMode: _themeMode == ThemeMode.dark,
              onThemeChanged: (darkMode) => setState(
                () => _themeMode = darkMode ? ThemeMode.dark : ThemeMode.light,
              ),
            ),
    );
  }
}

class SourceLibraryDemo extends StatefulWidget {
  const SourceLibraryDemo({
    required this.darkMode,
    required this.onThemeChanged,
    this.campaignsOnly = false,
    this.campaigns,
    super.key,
  });

  final bool darkMode;
  final ValueChanged<bool> onThemeChanged;
  final bool campaignsOnly;
  final CampaignDemoRepository? campaigns;

  @override
  State<SourceLibraryDemo> createState() => _SourceLibraryDemoState();
}

class _SourceLibraryDemoState extends State<SourceLibraryDemo> {
  static const _moveDestinations = [
    SourceMoveDestination(id: 'later', label: 'Later'),
    SourceMoveDestination(id: 'reference', label: 'Reference'),
    SourceMoveDestination(id: 'archive', label: 'Archived'),
  ];
  static const _accounts = [
    SourceAccount(id: 'work', label: 'Work account'),
    SourceAccount(id: 'research', label: 'Research account'),
  ];
  static const _projects = [
    SourceProjectDestination(id: 'shipglows', label: 'ShipGlows'),
    SourceProjectDestination(id: 'contentglows', label: 'ContentGlows'),
    SourceProjectDestination(id: 'newsletter', label: 'Health newsletter'),
  ];

  late List<SourceSidebarItem> _items;
  late NewsletterDraft _newsletterDraft;
  late List<NewsletterSourceReference> _newsletterSources;
  late NewsletterSchedule? _newsletterSchedule;
  String? _selectedId;
  String _accountId = 'work';
  bool _loading = false;
  _DemoWorkspace _workspace = _DemoWorkspace.sources;
  NewsletterAudienceSummary? _audience;
  NewsletterTestReceipt? _testReceipt;
  late final _campaigns = widget.campaigns ?? CampaignDemoRepository();
  bool _fromCampaigns = false;

  @override
  void initState() {
    super.initState();
    if (widget.campaignsOnly) {
      _workspace = _DemoWorkspace.campaigns;
    }
    _items = _previewSources();
    _newsletterSources = _items
        .where((item) => item.location != 'archive')
        .map(_newsletterSourceFromItem)
        .toList(growable: false);
    _newsletterDraft = _previewNewsletter(_newsletterSources);
    _newsletterSchedule = NewsletterSchedule(
      sendAt: DateTime.now().add(const Duration(days: 1)),
      timezoneLabel: 'Europe/Paris',
    );
    _audience = const NewsletterAudienceSummary(
      id: 'contentglows-health-readers',
      label: 'Health project · engaged readers',
      eligibleCount: 1284,
      excludedCount: 37,
    );
  }

  Future<void> _refresh() async {
    setState(() => _loading = true);
    await Future<void>.delayed(PreviewTheme.simulatedActionDelay);
    if (!mounted) return;
    setState(() {
      _items = _previewSources();
      _selectedId = null;
      _loading = false;
    });
    _notify('Demo library refreshed.');
  }

  Future<void> _ingest(SourceSidebarItem item) async {
    _replace(item, processingState: SourceProcessingState.processing);
    await Future<void>.delayed(PreviewTheme.simulatedActionDelay);
    if (!mounted) return;
    _replace(
      item,
      processingState: SourceProcessingState.processed,
      tags: {...item.tags, 'demo-processed'}.toList(),
    );
    _notify('Sent to the selected project (simulated).');
  }

  Future<void> _selectAccount(SourceAccount account) async {
    setState(() {
      _accountId = account.id;
      _selectedId = null;
    });
    _notify('Switched to ${account.label} (simulated).');
  }

  Future<void> _summarize(SourceSidebarItem item) async {
    await Future<void>.delayed(PreviewTheme.simulatedActionDelay);
    if (!mounted) return;
    _replace(item, tags: {...item.tags, 'synthetic-summary'}.toList());
    _notify('Synthetic summary ready: ${item.summary}');
  }

  Future<void> _distribute(
    SourceSidebarItem item,
    List<SourceProjectDestination> projects,
  ) async {
    await Future<void>.delayed(PreviewTheme.simulatedActionDelay);
    if (!mounted) return;
    _replace(
      item,
      processingState: SourceProcessingState.processed,
      tags: {...item.tags, ...projects.map((project) => project.id)}.toList(),
    );
    _notify(
      'Sent to ${projects.map((project) => project.label).join(', ')} (simulated).',
    );
  }

  Future<void> _markSeen(SourceSidebarItem item) async {
    _replace(item, seen: true);
    _notify('Marked as seen in this demo.');
  }

  Future<void> _archive(SourceSidebarItem item) async {
    _replace(item, location: 'archive');
    setState(() => _selectedId = null);
    _notify('Moved to Archived in this demo.');
  }

  Future<void> _move(
    SourceSidebarItem item,
    SourceMoveDestination destination,
  ) async {
    _replace(item, location: destination.id);
    setState(() => _selectedId = null);
    _notify('Moved to ${destination.label} in this demo.');
  }

  Future<void> _delete(SourceSidebarItem item) async {
    setState(() {
      _items = _items.where((candidate) => candidate.id != item.id).toList();
      _selectedId = null;
    });
    _notify('Deleted from this demo. Refresh to restore it.');
  }

  Future<void> _openExternal(SourceSidebarItem item) async {
    _notify('External Reader links are disabled in the public demo.');
  }

  Future<void> _openLibrary() async {
    _notify('Readwise is disconnected from this synthetic public demo.');
  }

  void _replace(
    SourceSidebarItem source, {
    bool? seen,
    String? location,
    List<String>? tags,
    SourceProcessingState? processingState,
  }) {
    setState(() {
      _items = _items
          .map(
            (item) => item.id == source.id
                ? SourceSidebarItem(
                    id: item.id,
                    title: item.title,
                    authorOrPublisher: item.authorOrPublisher,
                    summary: item.summary,
                    publishedAt: item.publishedAt,
                    sourceType: item.sourceType,
                    content: item.content,
                    tags: tags ?? item.tags,
                    seen: seen ?? item.seen,
                    location: location ?? item.location,
                    processingState: processingState ?? item.processingState,
                    canonicalExternalUrl: item.canonicalExternalUrl,
                  )
                : item,
          )
          .toList(growable: false);
    });
  }

  void _notify(String message) {
    ScaffoldMessenger.of(context)
      ..hideCurrentSnackBar()
      ..showSnackBar(SnackBar(content: Text(message)));
  }

  Future<NewsletterDraft> _saveNewsletter(NewsletterDraft draft) async {
    await Future<void>.delayed(PreviewTheme.simulatedActionDelay);
    _campaigns.save(draft);
    return draft.copyWith(
      revision: draft.revision + 1,
      saveState: NewsletterSaveState.saved,
    );
  }

  Future<NewsletterAudienceSummary> _resolveNewsletterAudience(
    NewsletterDraft draft,
  ) async {
    await Future<void>.delayed(PreviewTheme.simulatedActionDelay);
    return _audience!;
  }

  Future<List<NewsletterValidationIssue>> _validateNewsletter(
    NewsletterDraft draft,
    NewsletterAudienceSummary? audience,
  ) async {
    await Future<void>.delayed(PreviewTheme.simulatedActionDelay);
    return const [
      NewsletterValidationIssue(
        id: 'dark-mode-review',
        severity: NewsletterIssueSeverity.warning,
        title: 'Dark-mode inbox proof deferred',
        message:
            'The synthetic preview cannot prove received-client rendering.',
        target: 'design',
      ),
    ];
  }

  Future<NewsletterPreview> _renderNewsletterPreview(
    NewsletterDraft draft,
    NewsletterPreviewViewport viewport,
  ) async {
    await Future<void>.delayed(PreviewTheme.simulatedActionDelay);
    return NewsletterPreview(
      revision: draft.revision,
      viewport: viewport,
      subject: draft.subject,
      preheader: draft.preheader,
      plainText: draft.blocks
          .where((block) => block.type != NewsletterBlockType.divider)
          .map((block) => block.text)
          .join('\n\n'),
    );
  }

  Future<NewsletterTestReceipt> _sendNewsletterTest(
    NewsletterDraft draft,
  ) async {
    await Future<void>.delayed(PreviewTheme.simulatedActionDelay);
    final receipt = NewsletterTestReceipt(
      operationId: 'demo-test-${draft.revision}',
      draftRevision: draft.revision,
      message: 'Synthetic test completed.',
      recipientLabel: 'Diane · demo inbox',
      sentAt: DateTime.now(),
    );
    setState(() => _testReceipt = receipt);
    _notify('Synthetic test completed. No email was sent.');
    return receipt;
  }

  Future<NewsletterOperationReceipt> _scheduleNewsletter(
    NewsletterDraft draft,
    NewsletterSchedule schedule,
  ) async {
    await Future<void>.delayed(PreviewTheme.simulatedActionDelay);
    if (mounted) {
      setState(() => _newsletterSchedule = schedule);
      _notify('Schedule accepted by the synthetic demo only.');
    }
    return NewsletterOperationReceipt(
      operationId: 'demo-schedule-${draft.revision}',
      draftRevision: draft.revision,
      message: 'Synthetic schedule accepted.',
    );
  }

  Future<void> _unscheduleNewsletter(String draftId) async {
    await Future<void>.delayed(PreviewTheme.simulatedActionDelay);
    if (!mounted) return;
    setState(() => _newsletterSchedule = null);
    _notify('Synthetic schedule removed. No provider was contacted.');
  }

  Future<NewsletterDeliveryStatus> _loadNewsletterDeliveryStatus(
    String draftId,
  ) async {
    await Future<void>.delayed(PreviewTheme.simulatedActionDelay);
    return NewsletterDeliveryStatus(
      state: _newsletterSchedule == null
          ? NewsletterDeliveryState.draft
          : NewsletterDeliveryState.scheduled,
      message: _newsletterSchedule == null
          ? 'Synthetic draft has no active delivery.'
          : 'Synthetic schedule is ready for host reconciliation.',
      updatedAt: DateTime.now(),
      operationId: 'demo-status-${_newsletterDraft.revision}',
    );
  }

  Future<Map<String, num>> _loadNewsletterAnalytics(String draftId) async {
    await Future<void>.delayed(PreviewTheme.simulatedActionDelay);
    return const {'Delivered': 0, 'Unique opens': 0, 'Unique clicks': 0};
  }

  Future<NewsletterOperationReceipt> _sendNewsletter(
    NewsletterDraft draft,
  ) async {
    await Future<void>.delayed(PreviewTheme.simulatedActionDelay);
    _notify('Send accepted by the synthetic demo. No email was sent.');
    return NewsletterOperationReceipt(
      operationId: 'demo-send-${draft.revision}',
      draftRevision: draft.revision,
      message: 'Synthetic send accepted.',
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: SafeArea(
        child: switch (_workspace) {
          _DemoWorkspace.campaigns => CampaignWorkspace(
            repository: _campaigns,
            style: PreviewTheme.newsletterStyle(widget.darkMode),
            businessLabel: 'ShipGlows · démonstration',
            disabledReason:
                'Données fictives · aucun email réel ne sera envoyé.',
            onOpenCampaign: (campaign) async {
              final sample = _previewNewsletter(_newsletterSources);
              setState(() {
                _newsletterDraft =
                    _campaigns.drafts[campaign.id] ??
                    NewsletterDraft(
                      id: campaign.id,
                      revision: campaign.revision,
                      title: campaign.title,
                      subject: campaign.subject,
                      preheader: 'Le carnet de bord des projets ShipGlows.',
                      blocks: sample.blocks,
                      sources: sample.sources,
                    );
                _fromCampaigns = true;
                _workspace = _DemoWorkspace.newsletter;
              });
            },
          ),
          _DemoWorkspace.sources => SourceSidebar(
            title: 'Sources',
            items: _items,
            selectedId: _selectedId,
            isLoading: _loading,
            style: PreviewTheme.sidebarStyle(widget.darkMode),
            categories: PreviewTheme.categories(widget.darkMode),
            topBarActions: [
              IconButton(
                tooltip: 'Campagnes',
                onPressed: () =>
                    setState(() => _workspace = _DemoWorkspace.campaigns),
                icon: const Icon(Icons.campaign_outlined),
              ),
              IconButton(
                tooltip: 'Open Newsletter Studio',
                onPressed: () {
                  setState(() => _workspace = _DemoWorkspace.newsletter);
                },
                icon: const Icon(Icons.edit_note_outlined),
              ),
              IconButton(
                tooltip: widget.darkMode ? 'Use light theme' : 'Use dark theme',
                onPressed: () => widget.onThemeChanged(!widget.darkMode),
                icon: Icon(
                  widget.darkMode
                      ? Icons.light_mode_outlined
                      : Icons.dark_mode_outlined,
                ),
              ),
              const Padding(
                padding: EdgeInsets.symmetric(horizontal: 8),
                child: CircleAvatar(radius: 16, child: Text('D')),
              ),
            ],
            onSelected: (id) => setState(() => _selectedId = id),
            onRefresh: _refresh,
            onOpenLibrary: _openLibrary,
            onIngest: _ingest,
            onMarkSeen: _markSeen,
            onArchive: _archive,
            onDelete: _delete,
            onOpenExternal: _openExternal,
            moveDestinations: _moveDestinations,
            laterDestinationId: 'later',
            onMove: _move,
            accounts: _accounts,
            currentAccountId: _accountId,
            onAccountSelected: _selectAccount,
            onSummarize: _summarize,
            projectDestinations: _projects,
            onDistribute: _distribute,
            onActionError: (error) => _notify('Action failed: $error'),
          ),
          _DemoWorkspace.newsletter => NewsletterStudio(
            draft: _newsletterDraft,
            availableSources: _newsletterSources,
            audience: _audience,
            sender: const NewsletterSenderSummary(
              name: 'ContentGlows Health',
              address: 'newsletter@example.test',
              replyTo: 'hello@example.test',
              isVerified: true,
            ),
            design: const NewsletterDesignSummary(
              templateName: 'Editorial focus',
              brandName: 'Synthetic ContentGlows',
            ),
            schedule: _newsletterSchedule,
            testReceipt: _testReceipt,
            capabilities: const NewsletterStudioCapabilities(
              canTest: true,
              canSchedule: true,
              canSend: true,
              canUnschedule: true,
              canViewDeliveryStatus: true,
              canViewAnalytics: true,
            ),
            style: PreviewTheme.newsletterStyle(widget.darkMode),
            onDraftChanged: (draft) {
              setState(() => _newsletterDraft = draft);
            },
            onSaveDraft: _saveNewsletter,
            onResolveAudience: _resolveNewsletterAudience,
            onValidateDraft: _validateNewsletter,
            onRenderPreview: _renderNewsletterPreview,
            onSendTest: _sendNewsletterTest,
            onSchedule: _scheduleNewsletter,
            onSend: _sendNewsletter,
            onUnschedule: _unscheduleNewsletter,
            onLoadDeliveryStatus: _loadNewsletterDeliveryStatus,
            onLoadAnalytics: _loadNewsletterAnalytics,
            onOpenSource: (sourceId) async {
              final source = _newsletterSources.firstWhere(
                (candidate) => candidate.id == sourceId,
              );
              _notify('Opened ${source.title} in the synthetic source tray.');
            },
            onBack: () {
              setState(
                () => _workspace = _fromCampaigns
                    ? _DemoWorkspace.campaigns
                    : _DemoWorkspace.sources,
              );
            },
            topBarActions: [
              IconButton(
                tooltip: widget.darkMode ? 'Use light theme' : 'Use dark theme',
                onPressed: () => widget.onThemeChanged(!widget.darkMode),
                icon: Icon(
                  widget.darkMode
                      ? Icons.light_mode_outlined
                      : Icons.dark_mode_outlined,
                ),
              ),
            ],
          ),
        },
      ),
    );
  }
}

enum _DemoWorkspace { sources, newsletter, campaigns }

NewsletterSourceReference _newsletterSourceFromItem(SourceSidebarItem item) {
  return NewsletterSourceReference(
    id: item.id,
    title: item.title,
    publisher: item.authorOrPublisher,
    excerpt: item.summary,
    canonicalUrl: item.canonicalExternalUrl,
  );
}

NewsletterDraft _previewNewsletter(List<NewsletterSourceReference> sources) {
  final selectedSources = sources.take(3).toList(growable: false);
  return NewsletterDraft(
    id: 'demo-health-weekly',
    revision: 1,
    title: 'Health Signals · Weekly draft',
    subject: 'Three health stories worth understanding this week',
    preheader: 'Evidence-led ideas, with every source kept in reach.',
    sources: selectedSources,
    blocks: [
      const NewsletterBlock(
        id: 'heading-opening',
        type: NewsletterBlockType.heading,
        text: 'A calmer way to read this week’s health signals',
        isProtected: true,
      ),
      const NewsletterBlock(
        id: 'text-opening',
        type: NewsletterBlockType.text,
        text:
            'This synthetic draft demonstrates how sources, writing, audience checks and delivery review can stay in one focused workspace.',
      ),
      if (selectedSources.isNotEmpty)
        NewsletterBlock(
          id: 'source-${selectedSources.first.id}',
          type: NewsletterBlockType.source,
          text: selectedSources.first.excerpt,
          label: selectedSources.first.title,
          sourceId: selectedSources.first.id,
        ),
      const NewsletterBlock(
        id: 'divider-one',
        type: NewsletterBlockType.divider,
      ),
      const NewsletterBlock(
        id: 'text-close',
        type: NewsletterBlockType.text,
        text:
            'The public demo never contacts a provider. ContentGlows will own persistence, consent, rendering and delivery.',
      ),
    ],
  );
}

List<SourceSidebarItem> _previewSources() => [
  _source(
    id: 'flutter-architecture',
    publisher: 'Flutter Engineering Weekly',
    title: 'Designing resilient Flutter application boundaries',
    summary: 'Keep product decisions separate from provider adapters.',
    day: 25,
    tags: const ['shipglows-ready', 'flutter'],
    content:
        '''A resilient Flutter application keeps presentation, domain decisions, and external providers behind clear boundaries.

This synthetic article demonstrates the long-form reading state. Select text, search the library, switch themes, and send the source to a project to evaluate the complete interaction.''',
  ),
  _source(
    id: 'security-roundup',
    publisher: 'Practical AppSec Dispatch',
    title: 'Security signals worth tracking this week',
    summary: 'Authentication, provenance, and prompt-injection boundaries.',
    day: 24,
    tags: const ['shipglows-ready', 'security'],
  ),
  _source(
    id: 'content-systems',
    publisher: 'Editorial Systems',
    title: 'Repurposing research without losing provenance',
    summary: 'One source library can feed distinct project workflows.',
    day: 23,
    tags: const ['contentglows-ready', 'workflow'],
    seen: true,
  ),
  _source(
    id: 'dependency-health',
    publisher: 'Dependency Health',
    title: 'The maintenance signals hidden in release notes',
    summary: 'What to extract before an upgrade becomes urgent.',
    day: 22,
    tags: const ['shipglows-ready', 'maintenance'],
  ),
  _source(
    id: 'reader-workflow',
    publisher: 'Knowledge Ops Notes',
    title: 'A calmer workflow for newsletter research',
    summary: 'Capture once, review deliberately, distribute when useful.',
    day: 21,
    tags: const ['research', 'reader'],
    seen: true,
  ),
  _source(
    id: 'health-storytelling',
    publisher: 'Health Narrative Lab',
    title: 'Turning expert interviews into trustworthy stories',
    summary: 'A provenance-first framework for health content.',
    day: 20,
    tags: const ['contentglows-ready', 'health'],
    seen: true,
  ),
  _source(
    id: 'browser-security',
    publisher: 'Browser Security Brief',
    title: 'Passkeys, sessions, and safer recovery flows',
    summary: 'Practical implementation notes from production teams.',
    day: 19,
    tags: const ['shipglows-ready', 'security'],
  ),
  _source(
    id: 'editorial-angles',
    publisher: 'The Editorial Operator',
    title: 'Seven ways to find a sharper content angle',
    summary: 'Move from collected sources to defensible points of view.',
    day: 18,
    tags: const ['contentglows-ready', 'research'],
    processed: true,
  ),
  _source(
    id: 'flutter-performance',
    publisher: 'Flutter Performance Notes',
    title: 'Frame budgets for dense information interfaces',
    summary: 'Keep scrolling smooth without flattening the experience.',
    day: 17,
    tags: const ['shipglows-ready', 'flutter'],
    seen: true,
  ),
  _source(
    id: 'business-models',
    publisher: 'Independent Business Review',
    title: 'Where small software products gain leverage',
    summary: 'Distribution and workflow advantages worth studying.',
    day: 16,
    tags: const ['contentglows-ready', 'business'],
  ),
  _source(
    id: 'supply-chain',
    publisher: 'Secure Supply Chain',
    title: 'A field checklist for package provenance',
    summary: 'Attestations, lockfiles, and the controls between them.',
    day: 15,
    tags: const ['shipglows-ready', 'security'],
    processed: true,
    seen: true,
  ),
  _source(
    id: 'archived-example',
    publisher: 'Product Systems Archive',
    title: 'A source already reviewed and archived',
    summary: 'Synthetic data for testing the archive navigation state.',
    day: 14,
    tags: const ['workflow'],
    location: 'archive',
    seen: true,
  ),
];

SourceSidebarItem _source({
  required String id,
  required String publisher,
  required String title,
  required String summary,
  required int day,
  required List<String> tags,
  String? content,
  bool seen = false,
  bool processed = false,
  String location = 'new',
}) {
  return SourceSidebarItem(
    id: id,
    title: title,
    authorOrPublisher: publisher,
    summary: summary,
    publishedAt: DateTime.utc(2026, 8, day),
    sourceType: 'newsletter',
    content:
        content ??
        '''This synthetic newsletter entry is included to test the density, reading rhythm, and project handoff of the shared Flutter source interface.

Production applications provide sanitized content and decide what “Send to project” means. The shared package remains independent from Readwise and from either product architecture.''',
    tags: tags,
    seen: seen,
    location: location,
    processingState: processed
        ? SourceProcessingState.processed
        : SourceProcessingState.idle,
    canonicalExternalUrl: Uri.https('readwise.io', '/reader'),
  );
}
