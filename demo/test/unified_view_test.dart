import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:source_sidebar_flutter/source_sidebar_flutter.dart';
import 'package:source_sidebar_preview/main.dart';

void main() {
  testWidgets('one inbox opens support and campaigns in the shared reader', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(1440, 1000);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    await tester.pumpWidget(const SourceSidebarPreviewApp());
    await tester.pumpAndSettle();
    expect(find.byType(SourceSidebar), findsOneWidget);
    expect(find.text('Vue d’ensemble'), findsNothing);
    await tester.tap(find.widgetWithText(ListTile, 'Service client'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Accès à mon espace ContentGlows').first);
    await tester.pumpAndSettle();
    expect(find.byType(SourceSidebar), findsOneWidget);
    expect(find.text('Votre réponse'), findsOneWidget);
    await tester.tap(find.widgetWithText(ListTile, 'Diffusion'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Les nouvelles de la semaine').first);
    await tester.pumpAndSettle();
    expect(find.byType(SourceSidebar), findsOneWidget);
    expect(find.text('Ouvrir l’éditeur'), findsOneWidget);
  });
}
