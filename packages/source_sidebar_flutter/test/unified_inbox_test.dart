import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:source_sidebar_flutter/source_sidebar_flutter.dart';

SourceSidebarItem email(String id) => SourceSidebarItem(
  id: id,
  title: 'Email $id',
  authorOrPublisher: 'Expéditeur',
  summary: 'Résumé',
  publishedAt: DateTime(2026, 9, 8),
  sourceType: 'email',
  content: 'Contenu $id',
);
const sections = {
  'sources': 'Sources',
  'support': 'Service client',
  'diffusion': 'Diffusion',
};

void main() {
  testWidgets(
    'one grouped inbox retains source rows and eager section anchors',
    (tester) async {
      final sources = List.generate(40, (index) => email('source$index'));
      final supportKey = GlobalKey();
      await tester.pumpWidget(
        MaterialApp(
          home: SourceSidebar(
            items: [...sources, email('support'), email('campaign')],
            onSelected: (_) {},
            sectionLabels: sections,
            itemSectionIds: {'support': 'support', 'campaign': 'diffusion'},
            sectionKeys: {'support': supportKey},
          ),
        ),
      );
      await tester.pumpAndSettle();
      expect(find.byType(CustomScrollView), findsOneWidget);
      expect(find.byType(Viewport), findsOneWidget);
      expect(find.text('Email source0'), findsOneWidget);
      expect(supportKey.currentContext, isNotNull);
      await Scrollable.ensureVisible(supportKey.currentContext!);
      await tester.pumpAndSettle();
      expect(find.text('Email support'), findsOneWidget);
      expect(tester.takeException(), isNull);
    },
  );
  testWidgets(
    'empty and loading sources retain all sections and host messages',
    (tester) async {
      await tester.pumpWidget(
        MaterialApp(
          home: SourceSidebar(
            items: const [],
            onSelected: (_) {},
            isLoading: true,
            sectionLabels: sections,
            sectionEmptyMessages: const {
              'sources': 'Readwise à connecter',
              'support': 'Gmail à connecter',
              'diffusion': 'Aucune campagne',
            },
          ),
        ),
      );
      await tester.pump();
      expect(find.byType(CustomScrollView), findsOneWidget);
      expect(find.text('Readwise à connecter'), findsOneWidget);
      expect(find.text('Gmail à connecter'), findsOneWidget);
      expect(find.text('Aucune campagne'), findsOneWidget);
      expect(tester.takeException(), isNull);
    },
  );
  testWidgets('all providers open the same reader with contextual footer', (
    tester,
  ) async {
    String? selected;
    await tester.pumpWidget(
      MaterialApp(
        home: StatefulBuilder(
          builder: (context, update) => SourceSidebar(
            title: 'ShipGlows Email Engine',
            items: [email('support')],
            selectedId: selected,
            onSelected: (id) => update(() => selected = id),
            sectionLabels: sections,
            itemSectionIds: const {'support': 'support'},
            readerFooter: const Text('Répondre via Gmail'),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();
    await tester.ensureVisible(find.text('Email support'));
    await tester.tap(find.text('Email support'));
    await tester.pumpAndSettle();
    expect(find.text('Contenu support'), findsOneWidget);
    expect(find.text('Répondre via Gmail'), findsOneWidget);
    expect(find.byType(SingleChildScrollView), findsOneWidget);
    expect(tester.takeException(), isNull);
  });
  testWidgets('navigation header precedes existing desktop filters', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(1200, 900);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    await tester.pumpWidget(
      MaterialApp(
        home: SourceSidebar(
          items: const [],
          onSelected: (_) {},
          navigationHeader: const Text('Navigation moteur'),
        ),
      ),
    );
    await tester.pumpAndSettle();
    expect(
      tester.getTopLeft(find.text('Navigation moteur')).dy,
      lessThan(tester.getTopLeft(find.text('Inbox').first).dy),
    );
    expect(tester.takeException(), isNull);
  });
}
