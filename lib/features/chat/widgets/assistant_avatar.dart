import 'package:hatchaudit/localized_material.dart';

import '../../../widgets/chick_mark_logo.dart';

class AssistantAvatar extends StatelessWidget {
  const AssistantAvatar({super.key, required this.size, this.semanticLabel});

  static const assetPath = 'assets/branding/chickmark-agent-avatar.png';

  final double size;
  final String? semanticLabel;

  @override
  Widget build(BuildContext context) {
    final image = ClipOval(
      child: Image.asset(
        assetPath,
        key: const ValueKey('assistant-avatar-image'),
        width: size,
        height: size,
        fit: BoxFit.cover,
        filterQuality: FilterQuality.high,
        errorBuilder: (context, error, stackTrace) => Image.asset(
          ChickMarkLogo.assetPath,
          width: size,
          height: size,
          fit: BoxFit.contain,
          filterQuality: FilterQuality.high,
        ),
      ),
    );
    final label = semanticLabel;
    if (label == null) return ExcludeSemantics(child: image);
    return Semantics(
      label: context.tr(label),
      image: true,
      child: ExcludeSemantics(child: image),
    );
  }
}
