import 'package:flutter_test/flutter_test.dart';
import 'package:hatchaudit/core/theme/app_text_styles.dart';

void main() {
  test('uses a compact operational type scale', () {
    expect(AppTextStyles.heading.fontSize, lessThanOrEqualTo(20));
    expect(AppTextStyles.sectionTitle.fontSize, lessThanOrEqualTo(17));
    expect(AppTextStyles.title.fontSize, lessThanOrEqualTo(15));
    expect(AppTextStyles.body.fontSize, lessThanOrEqualTo(14));
    expect(AppTextStyles.subtitle.fontSize, lessThanOrEqualTo(13));
    expect(AppTextStyles.metricLarge.fontSize, lessThanOrEqualTo(24));

    final textTheme = AppTextStyles.textTheme;
    expect(textTheme.displayLarge?.fontSize, lessThanOrEqualTo(28));
    expect(textTheme.displayMedium?.fontSize, lessThanOrEqualTo(24));
    expect(textTheme.displaySmall?.fontSize, lessThanOrEqualTo(22));
    expect(textTheme.headlineLarge?.fontSize, lessThanOrEqualTo(22));
  });
}
