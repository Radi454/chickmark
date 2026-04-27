import 'package:flutter_test/flutter_test.dart';
import 'package:hatchaudit/features/dashboard/utils/pasgar_interpretation.dart';

void main() {
  test('Pasgar final score interpretation uses approved bands', () {
    expect(
      PasgarScoreInterpretation.fromScore(9.5).band,
      PasgarInterpretationBand.excellent,
    );
    expect(
      PasgarScoreInterpretation.fromScore(9.0).band,
      PasgarInterpretationBand.acceptable,
    );
    expect(
      PasgarScoreInterpretation.fromScore(8.99).band,
      PasgarInterpretationBand.investigate,
    );
  });
}
