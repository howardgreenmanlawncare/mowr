import 'package:flutter_test/flutter_test.dart';
import 'package:mowr/features/booking/domain/booking_draft.dart';
import 'package:mowr/features/booking/domain/discount.dart';
import 'package:mowr/features/booking/domain/lawn_area_model.dart';
import 'package:mowr/features/booking/domain/pricing.dart';

DiscountRule rule({
  String id = 'r',
  double pct = 20,
  bool active = true,
  bool recurringOnly = true,
  int minOccurrence = 3,
  bool ongoing = false,
}) =>
    DiscountRule(
      id: id,
      name: 'Test',
      percentOff: pct,
      active: active,
      recurringOnly: recurringOnly,
      minOccurrence: minOccurrence,
      ongoing: ongoing,
    );

void main() {
  group('rule matching', () {
    test('"3rd mow" one-off reward applies only at occurrence 3', () {
      final r = rule(minOccurrence: 3, ongoing: false);
      expect(r.appliesTo(isRecurring: true, occurrence: 2), isFalse);
      expect(r.appliesTo(isRecurring: true, occurrence: 3), isTrue);
      expect(r.appliesTo(isRecurring: true, occurrence: 4), isFalse);
    });

    test('ongoing rule applies from its occurrence onward', () {
      final r = rule(minOccurrence: 3, ongoing: true);
      expect(r.appliesTo(isRecurring: true, occurrence: 2), isFalse);
      expect(r.appliesTo(isRecurring: true, occurrence: 3), isTrue);
      expect(r.appliesTo(isRecurring: true, occurrence: 9), isTrue);
    });

    test('recurring-only rule never applies to a one-off', () {
      final r = rule(recurringOnly: true, minOccurrence: 1, ongoing: true);
      expect(r.appliesTo(isRecurring: false, occurrence: 1), isFalse);
      expect(r.appliesTo(isRecurring: true, occurrence: 1), isTrue);
    });

    test('inactive rule never applies', () {
      final r = rule(active: false, minOccurrence: 1, ongoing: true);
      expect(r.appliesTo(isRecurring: true, occurrence: 5), isFalse);
    });
  });

  group('best discount', () {
    test('picks the largest applicable percentage', () {
      final rules = [
        rule(id: 'a', pct: 10, minOccurrence: 1, ongoing: true),
        rule(id: 'b', pct: 20, minOccurrence: 3, ongoing: false),
      ];
      final at3 = bestDiscount(
          rules, const DiscountContext(isRecurring: true, occurrence: 3));
      expect(at3?.id, 'b'); // 20% beats 10%
      final at2 = bestDiscount(
          rules, const DiscountContext(isRecurring: true, occurrence: 2));
      expect(at2?.id, 'a'); // only the ongoing 10% applies at #2
    });

    test('nothing applies to a one-off', () {
      final rules = [rule(minOccurrence: 1, ongoing: true)];
      expect(bestDiscount(rules, DiscountContext.oneOff), isNull);
    });
  });

  group('engine applies discount to the quote', () {
    final lawn = LawnArea(
      id: 'l1',
      name: 'Back',
      areaSqM: 200,
      perimeter: 0,
      source: LawnMeasurementSource.manual,
    );
    final engine = PricingEngine(
      const PricingRules(),
      discountRules: [rule(id: 'b', pct: 20, minOccurrence: 3, ongoing: false)],
    );

    BookingQuote quoteAt(DiscountContext? ctx) => engine.quote(
          lawns: [lawn],
          heights: const {'l1': GrassLength.medium},
          edgedLawnIds: const {},
          discount: ctx,
        );

    test('no discount on the first mow', () {
      final q = quoteAt(const DiscountContext(isRecurring: true, occurrence: 1));
      expect(q.hasDiscount, isFalse);
      expect(q.total, q.subtotal);
    });

    test('20% comes off the 3rd mow', () {
      final q = quoteAt(const DiscountContext(isRecurring: true, occurrence: 3));
      expect(q.discountPercent, 20);
      expect(q.total, closeTo(q.subtotal * 0.8, 0.001));
      expect(q.discountLabel, 'Test');
    });

    test('no discount context means full price', () {
      final q = quoteAt(null);
      expect(q.hasDiscount, isFalse);
    });
  });
}
