enum PasgarInterpretationBand { excellent, acceptable, investigate }

class PasgarScoreInterpretation {
  final PasgarInterpretationBand band;
  final String label;
  final String message;

  const PasgarScoreInterpretation({
    required this.band,
    required this.label,
    required this.message,
  });

  factory PasgarScoreInterpretation.fromScore(double score) {
    if (score >= 9.5) {
      return const PasgarScoreInterpretation(
        band: PasgarInterpretationBand.excellent,
        label: 'Excellent',
        message: 'Excellent chick quality. Maintain current hatchery process.',
      );
    }
    if (score >= 9.0) {
      return const PasgarScoreInterpretation(
        band: PasgarInterpretationBand.acceptable,
        label: 'Acceptable',
        message: 'Acceptable chick quality. Monitor trends and defect mix.',
      );
    }
    return const PasgarScoreInterpretation(
      band: PasgarInterpretationBand.investigate,
      label: 'Investigate',
      message:
          'Below 9.0. Review incubation, hatch window, holding, and handling.',
    );
  }
}
