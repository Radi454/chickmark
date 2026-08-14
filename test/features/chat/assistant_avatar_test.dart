import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hatchaudit/features/chat/widgets/assistant_avatar.dart';

void main() {
  testWidgets('renders the dedicated circular assistant identity asset', (
    tester,
  ) async {
    await tester.pumpWidget(
      const MaterialApp(
        home: Scaffold(
          body: AssistantAvatar(size: 48, semanticLabel: 'ChickMark logo'),
        ),
      ),
    );

    expect(find.byType(ClipOval), findsOneWidget);
    final image = tester.widget<Image>(
      find.byKey(const ValueKey('assistant-avatar-image')),
    );
    expect((image.image as AssetImage).assetName, AssistantAvatar.assetPath);
    expect(image.width, 48);
    expect(image.height, 48);
    expect(find.bySemanticsLabel('ChickMark logo'), findsOneWidget);
  });
}
