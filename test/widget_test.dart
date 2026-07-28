import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mowr/main.dart';

void main() {
  testWidgets('app renders and reaches the welcome screen', (tester) async {
    await tester.pumpWidget(const ProviderScope(child: MowrApp()));
    // Splash animation.
    await tester.pumpAndSettle();
    // The splash hands off to welcome after a short delay; fire it, then let
    // the route transition settle.
    await tester.pump(const Duration(milliseconds: 400));
    await tester.pumpAndSettle();

    expect(find.text('Book a MOWR'), findsOneWidget);
  });
}
