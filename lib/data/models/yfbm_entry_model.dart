class YfbmEntry {
  final double? chickWeight;
  final double? yolkWeight;

  YfbmEntry({this.chickWeight, this.yolkWeight});

  // Calculate yolk percentage
  double? get yolkPct {
    if (chickWeight == null || chickWeight == 0 || yolkWeight == null) {
      return null;
    }
    return (yolkWeight! / chickWeight!) * 100;
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
