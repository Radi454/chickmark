import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hatchaudit/core/navigation/modal_route_visibility_observer.dart';

void main() {
  testWidgets('tracks popup routes without flagging normal page routes', (
    tester,
  ) async {
    final hasModalRoute = ValueNotifier<bool>(false);
    final observer = ModalRouteVisibilityObserver(hasModalRoute);

    await tester.pumpWidget(
      MaterialApp(
        navigatorObservers: [observer],
        home: Builder(
          builder: (context) {
            return Scaffold(
              body: Column(
                children: [
                  ElevatedButton(
                    onPressed: () {
                      Navigator.of(context).push(
                        MaterialPageRoute<void>(
                          builder: (_) =>
                              const Scaffold(body: Text('Normal page')),
                        ),
                      );
                    },
                    child: const Text('Open page'),
                  ),
                  ElevatedButton(
                    onPressed: () {
                      showModalBottomSheet<void>(
                        context: context,
                        builder: (_) => const SizedBox(
                          height: 120,
                          child: Text('Modal sheet'),
                        ),
                      );
                    },
                    child: const Text('Open sheet'),
                  ),
                ],
              ),
            );
          },
        ),
      ),
    );

    expect(hasModalRoute.value, isFalse);

    await tester.tap(find.text('Open page'));
    await tester.pumpAndSettle();

    expect(find.text('Normal page'), findsOneWidget);
    expect(hasModalRoute.value, isFalse);

    Navigator.of(tester.element(find.text('Normal page'))).pop();
    await tester.pumpAndSettle();

    await tester.tap(find.text('Open sheet'));
    await tester.pumpAndSettle();

    expect(find.text('Modal sheet'), findsOneWidget);
    expect(hasModalRoute.value, isTrue);

    Navigator.of(tester.element(find.text('Modal sheet'))).pop();
    await tester.pumpAndSettle();

    expect(hasModalRoute.value, isFalse);
  });
}
