import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hatchaudit/features/audits/widgets/audit_scope_dialogs.dart';

void main() {
  testWidgets('scope identity dialog returns trimmed required values', (
    tester,
  ) async {
    Map<String, String>? result;
    await _pumpDialogHost(
      tester,
      onPressed: (context) async {
        result = await showAuditScopeIdentityDialog(
          context,
          scopeLabel: 'House',
          fields: const [AuditScopeIdentityField(key: 'house', label: 'House')],
        );
      },
    );

    await tester.tap(find.text('Open'));
    await tester.pumpAndSettle();

    expect(find.text('Add House scope'), findsOneWidget);
    final addButton = tester.widget<FilledButton>(
      find.byKey(const ValueKey('scope-identity-add')),
    );
    expect(addButton.onPressed, isNull);

    await tester.enterText(
      find.byKey(const ValueKey('scope-identity-house')),
      ' 12 ',
    );
    await tester.pump();
    await tester.tap(find.byKey(const ValueKey('scope-identity-add')));
    await tester.pumpAndSettle();

    expect(result, {'house': '12'});
  });

  testWidgets('scope identity dialog keeps duplicate validation in dialog', (
    tester,
  ) async {
    Map<String, String>? result;
    await _pumpDialogHost(
      tester,
      onPressed: (context) async {
        result = await showAuditScopeIdentityDialog(
          context,
          scopeLabel: 'Machine',
          fields: const [
            AuditScopeIdentityField(key: 'setter', label: 'Setter'),
            AuditScopeIdentityField(key: 'hatcher', label: 'Hatcher'),
          ],
          validator: (values) =>
              values['setter'] == '1' && values['hatcher'] == '2'
              ? 'This Machine scope already exists.'
              : null,
        );
      },
    );

    await tester.tap(find.text('Open'));
    await tester.pumpAndSettle();
    await tester.enterText(
      find.byKey(const ValueKey('scope-identity-setter')),
      '1',
    );
    await tester.enterText(
      find.byKey(const ValueKey('scope-identity-hatcher')),
      '2',
    );
    await tester.pump();
    await tester.tap(find.byKey(const ValueKey('scope-identity-add')));
    await tester.pumpAndSettle();

    expect(result, isNull);
    expect(find.text('This Machine scope already exists.'), findsOneWidget);

    await tester.enterText(
      find.byKey(const ValueKey('scope-identity-hatcher')),
      '3',
    );
    await tester.pump();
    await tester.tap(find.byKey(const ValueKey('scope-identity-add')));
    await tester.pumpAndSettle();

    expect(result, {'setter': '1', 'hatcher': '3'});
  });

  testWidgets('cancelling scope identity dialog returns null', (tester) async {
    Map<String, String>? result = const {'unexpected': 'value'};
    await _pumpDialogHost(
      tester,
      onPressed: (context) async {
        result = await showAuditScopeIdentityDialog(
          context,
          scopeLabel: 'Tray',
          fields: const [AuditScopeIdentityField(key: 'tray', label: 'Tray')],
        );
      },
    );

    await tester.tap(find.text('Open'));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const ValueKey('scope-identity-cancel')));
    await tester.pumpAndSettle();

    expect(result, isNull);
  });

  testWidgets('empty scope removal proceeds without opening a dialog', (
    tester,
  ) async {
    bool? result;
    await _pumpDialogHost(
      tester,
      onPressed: (context) async {
        result = await confirmAuditScopeRemoval(
          context,
          hasEnteredResults: false,
        );
      },
    );

    await tester.tap(find.text('Open'));
    await tester.pump();

    expect(result, isTrue);
    expect(find.text('Remove scope?'), findsNothing);
  });

  testWidgets('result-bearing scope removal requires explicit confirmation', (
    tester,
  ) async {
    bool? result;
    await _pumpDialogHost(
      tester,
      onPressed: (context) async {
        result = await confirmAuditScopeRemoval(
          context,
          hasEnteredResults: true,
        );
      },
    );

    await tester.tap(find.text('Open'));
    await tester.pumpAndSettle();

    expect(find.text('Remove scope?'), findsOneWidget);
    expect(
      find.text(
        'This scope contains entered results. Removing it will permanently '
        'discard those results.',
      ),
      findsOneWidget,
    );

    await tester.tap(find.byKey(const ValueKey('scope-removal-cancel')));
    await tester.pumpAndSettle();
    expect(result, isFalse);

    await tester.tap(find.text('Open'));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const ValueKey('scope-removal-confirm')));
    await tester.pumpAndSettle();
    expect(result, isTrue);
  });

  test('normalizes optional scope prefixes and casing', () {
    expect(normalizeAuditScopeIdentity(' H12 ', prefix: 'H'), '12');
    expect(normalizeAuditScopeIdentity('sA-2', prefix: 'S'), 'a-2');
    expect(normalizeAuditScopeIdentity('  North House '), 'north house');
  });
}

Future<void> _pumpDialogHost(
  WidgetTester tester, {
  required Future<void> Function(BuildContext context) onPressed,
}) async {
  await tester.pumpWidget(
    MaterialApp(
      home: Scaffold(
        body: Builder(
          builder: (context) => TextButton(
            onPressed: () => onPressed(context),
            child: const Text('Open'),
          ),
        ),
      ),
    ),
  );
}
