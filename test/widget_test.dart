import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mowr/main.dart';

void main() {
  testWidgets('app renders without error', (WidgetTester tester) async {
    await tester.pumpWidget(const ProviderScope(child: MowrApp()));
    await tester.pumpAndSettle();
    expect(find.text('MOWR'), findsOneWidget);
  });
}
