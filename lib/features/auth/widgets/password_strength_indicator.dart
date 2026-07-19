import 'package:hatchaudit/localized_material.dart';
import '../../../core/security/password_policy.dart';

class PasswordStrengthIndicator extends StatelessWidget {
  final String password;

  const PasswordStrengthIndicator({super.key, required this.password});

  @override
  Widget build(BuildContext context) {
    final strength = _calculateStrength(password);

    return Row(
      children: [
        _buildBar(strength >= 1, Colors.red),
        const SizedBox(width: 4),
        _buildBar(strength >= 2, Colors.orange),
        const SizedBox(width: 4),
        _buildBar(strength >= 3, Colors.lightGreen),
        const SizedBox(width: 4),
        _buildBar(strength >= 4, Colors.green),
      ],
    );
  }

  Widget _buildBar(bool isActive, Color color) {
    return Expanded(
      child: Container(
        height: 4,
        decoration: BoxDecoration(
          color: isActive ? color : Colors.grey[300],
          borderRadius: BorderRadius.circular(2),
        ),
      ),
    );
  }

  int _calculateStrength(String password) {
    return PasswordPolicy.strengthScore(password);
  }
}
