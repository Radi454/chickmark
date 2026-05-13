import '../../core/utils/calculation_utils.dart';

class YfbmEntry {
  final double? chickWeight;
  final double? yolkWeight;

  YfbmEntry({this.chickWeight, this.yolkWeight});

  // Calculate yolk percentage
  double? get yolkPct {
    return CalculationUtils.percentOf(yolkWeight, chickWeight);
  }

  factory YfbmEntry.fromMap(Map<String, dynamic> map) {
    return YfbmEntry(
      chickWeight: map['chickWeight']?.toDouble(),
      yolkWeight: map['yolkWeight']?.toDouble(),
    );
  }

  Map<String, dynamic> toMap() {
    return {'chickWeight': chickWeight, 'yolkWeight': yolkWeight};
  }
}
