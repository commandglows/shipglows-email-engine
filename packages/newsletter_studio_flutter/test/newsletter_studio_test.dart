import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:newsletter_studio_flutter/newsletter_studio_flutter.dart';

void main() {
  void useExpandedViewport(WidgetTester tester) {
    tester.view.physicalSize = const Size(1280, 900);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
  }

  final source = NewsletterSourceReference(
    id: 'source-one',
    title: 'A useful source',
    publisher: 'Synthetic publisher',
    excerpt: 'A sanitized excerpt.',
    canonicalUrl: Uri.https('example.test', '/source'),
  );

  NewsletterDraft draft({List<NewsletterSourceReference> sources = const []}) {
    return NewsletterDraft(
      id: 'draft-one',
      revision: 3,
      title: 'Weekly draft',
      subject: 'A useful subject',
      preheader: 'A useful preheader',
      sources: sources,
      blocks: const [
        NewsletterBlock(
          id: 'opening',
          type: NewsletterBlockType.text,
          text: 'Draft body.',
        ),
      ],
    );
  }

  testWidgets('J reclaims source focus and X attaches the selected source', (
    tester,
  ) async {
    useExpandedViewport(tester);
    NewsletterDraft? changed;
    await tester.pumpWidget(
      _Harness(
        draft: draft(),
        sources: [source],
        onDraftChanged: (value) => changed = value,
      ),
    );
    await tester.pump();

    await tester.sendKeyEvent(LogicalKeyboardKey.tab);
    final previousFocus = FocusManager.instance.primaryFocus;
    await tester.sendKeyEvent(LogicalKeyboardKey.keyJ);
    await tester.pump();

    final row = tester.widget<InkWell>(
      find
          .ancestor(
            of: find.text('A useful source'),
            matching: find.byType(InkWell),
          )
          .first,
    );
    expect(row.focusNode?.hasPrimaryFocus, isTrue);
    expect(FocusManager.instance.primaryFocus, isNot(same(previousFocus)));

    await tester.sendKeyEvent(LogicalKeyboardKey.keyX);
    await tester.pump();
    expect(changed?.sources.single.id, 'source-one');
  });

  testWidgets('send requires review and explicit confirmation', (tester) async {
    useExpandedViewport(tester);
    var sent = false;
    await tester.pumpWidget(
      _Harness(
        draft: draft(),
        sources: [source],
        audience: const NewsletterAudienceSummary(
          id: 'audience',
          label: 'Eligible readers',
          eligibleCount: 12,
        ),
        sender: const NewsletterSenderSummary(
          name: 'Verified sender',
          address: 'sender@example.test',
          replyTo: 'reply@example.test',
          isVerified: true,
        ),
        capabilities: const NewsletterStudioCapabilities(canSend: true),
        onSend: (value) async {
          sent = true;
          return NewsletterOperationReceipt(
            operationId: 'send-one',
            draftRevision: value.revision,
            message: 'Accepted.',
          );
        },
      ),
    );
    await tester.pump();

    await tester.sendKeyDownEvent(LogicalKeyboardKey.controlLeft);
    await tester.sendKeyEvent(LogicalKeyboardKey.enter);
    await tester.sendKeyUpEvent(LogicalKeyboardKey.controlLeft);
    await tester.pumpAndSettle();
    expect(find.text('Vérifier'), findsWidgets);
    expect(sent, isFalse);

    await tester.tap(find.text('Envoyer maintenant'));
    await tester.pumpAndSettle();
    expect(find.text('Envoyer cette newsletter maintenant ?'), findsOneWidget);
    expect(sent, isFalse);

    await tester.tap(find.text('Confirmer l’envoi'));
    await tester.pumpAndSettle();
    expect(sent, isTrue);
  });

  testWidgets('Ctrl+wheel zooms the complete studio and Ctrl+0 resets it', (
    tester,
  ) async {
    useExpandedViewport(tester);
    await tester.pumpWidget(_Harness(draft: draft(), sources: [source]));
    await tester.pump();

    double workspaceScale() {
      final viewport = tester.getSize(
        find.byKey(const ValueKey('newsletter-studio-zoom')),
      );
      final content = tester.getSize(
        find.byKey(const ValueKey('newsletter-studio-zoom-content')),
      );
      return viewport.width / content.width;
    }

    expect(workspaceScale(), 1);
    await tester.sendKeyDownEvent(LogicalKeyboardKey.controlLeft);
    await tester.sendEventToBinding(
      const PointerScrollEvent(
        position: Offset(600, 400),
        scrollDelta: Offset(0, -100),
      ),
    );
    await tester.sendKeyUpEvent(LogicalKeyboardKey.controlLeft);
    await tester.pump();
    expect(workspaceScale(), greaterThan(1));

    await tester.sendKeyDownEvent(LogicalKeyboardKey.controlLeft);
    await tester.sendKeyEvent(LogicalKeyboardKey.digit0);
    await tester.sendKeyUpEvent(LogicalKeyboardKey.controlLeft);
    await tester.pump();
    expect(workspaceScale(), 1);
  });
}

class _Harness extends StatelessWidget {
  const _Harness({
    required this.draft,
    required this.sources,
    this.onDraftChanged,
    this.audience,
    this.sender,
    this.capabilities = const NewsletterStudioCapabilities(),
    this.onSend,
  });

  final NewsletterDraft draft;
  final List<NewsletterSourceReference> sources;
  final ValueChanged<NewsletterDraft>? onDraftChanged;
  final NewsletterAudienceSummary? audience;
  final NewsletterSenderSummary? sender;
  final NewsletterStudioCapabilities capabilities;
  final NewsletterSender? onSend;

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      theme: ThemeData(splashFactory: InkRipple.splashFactory),
      home: SizedBox(
        width: 1280,
        height: 900,
        child: NewsletterStudio(
          draft: draft,
          availableSources: sources,
          audience: audience,
          sender: sender,
          capabilities: capabilities,
          onDraftChanged: onDraftChanged ?? (_) {},
          onSend: onSend,
        ),
      ),
    );
  }
}
