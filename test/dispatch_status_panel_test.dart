import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:roadsos/models/dispatch_channel_status.dart';
import 'package:roadsos/ui/dispatch_status_panel.dart';

void main() {
  testWidgets('DispatchStatusPanel shows channel titles and lifecycle detail', (
    tester,
  ) async {
    const channels = [
      DispatchChannelRow(
        id: 'sms',
        title: 'Emergency SMS',
        lifecycle: DispatchChannelLifecycle.success,
        detail: 'Relay accepted.',
      ),
      DispatchChannelRow(
        id: 'mesh',
        title: 'Nearby mesh',
        lifecycle: DispatchChannelLifecycle.failed,
        detail: 'No peers in range.',
      ),
    ];

    await tester.pumpWidget(
      MaterialApp(
        theme: ThemeData(
          useMaterial3: true,
          colorScheme: ColorScheme.fromSeed(seedColor: Colors.teal),
        ),
        home: const Scaffold(body: DispatchStatusPanel(channels: channels)),
      ),
    );

    expect(find.text('DISPATCH STATUS'), findsOneWidget);
    expect(find.text('Emergency SMS'), findsOneWidget);
    expect(find.text('Relay accepted.'), findsOneWidget);
    expect(find.text('Nearby mesh'), findsOneWidget);
    expect(find.text('No peers in range.'), findsOneWidget);
  });

  testWidgets('DispatchStatusPanel renders nothing for empty channels', (
    tester,
  ) async {
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(body: DispatchStatusPanel(channels: const [])),
      ),
    );

    expect(find.text('DISPATCH STATUS'), findsNothing);
  });
}
