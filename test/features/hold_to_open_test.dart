import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:bolo/features/parent/hold_to_open.dart';

void main() {
  Widget wrap(Widget w) => MaterialApp(home: Scaffold(body: Center(child: w)));

  testWidgets('fires onOpen after the full hold', (tester) async {
    var opened = false;
    await tester.pumpWidget(wrap(HoldToOpen(
      holdDuration: const Duration(milliseconds: 300),
      onOpen: () => opened = true,
      child: const SizedBox(width: 48, height: 48),
    )));
    final gesture = await tester.startGesture(
        tester.getCenter(find.byType(HoldToOpen)));
    await tester.pump(const Duration(milliseconds: 350));
    await gesture.up();
    await tester.pump();
    expect(opened, isTrue);
  });

  testWidgets('releasing early does nothing', (tester) async {
    var opened = false;
    await tester.pumpWidget(wrap(HoldToOpen(
      holdDuration: const Duration(milliseconds: 300),
      onOpen: () => opened = true,
      child: const SizedBox(width: 48, height: 48),
    )));
    final gesture = await tester.startGesture(
        tester.getCenter(find.byType(HoldToOpen)));
    await tester.pump(const Duration(milliseconds: 100));
    await gesture.up();
    await tester.pump(const Duration(milliseconds: 400));
    expect(opened, isFalse);
  });
}
