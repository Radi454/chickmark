
import 'dart:convert';

class HatchResultsTray {
  final String trayId;
  final String position;
  final int traySize;
  final int infertile;

  HatchResultsTray({
    required this.trayId,
    required this.position,
    required this.traySize,
    required this.infertile,
  });

  // Calculate fertility percentage
  double get fertilityPct {
    if (traySize == 0) return 0.0;
    return ((traySize - infertile) / traySize) * 100;
  }

  factory HatchResultsTray.fromMap(Map<String, dynamic> map) {
    return HatchResultsTray(
      trayId: map['trayId'] as String,
      position: map['position'] as String,
      traySize: map['traySize'] as int,
      infertile: map['infertile'] as int,
    );
  }

  Map<String, dynamic> toMap() {
    return {
      'trayId': trayId,
      'position': position,
      'traySize': traySize,
      'infertile': infertile,
    };
  }

  factory HatchResultsTray.fromJson(String source) =>
      HatchResultsTray.fromMap(jsonDecode(source) as Map<String, dynamic>);

  String toJson() => jsonEncode(toMap());
}

class EggBreakoutTray {
  final String trayId;
  final String position;
  final Map<String, int> parameters; // parameterId -> count

  EggBreakoutTray({
    required this.trayId,
    required this.position,
    required this.parameters,
  });

  factory EggBreakoutTray.fromMap(Map<String, dynamic> map) {
    return EggBreakoutTray(
      trayId: map['trayId'] as String,
      position: map['position'] as String,
      parameters: Map<String, int>.from(
        (map['parameters'] as Map<String, dynamic>).map(
          (key, value) => MapEntry(key, value as int),
        ),
      ),
    );
  }

  Map<String, dynamic> toMap() {
    return {
      'trayId': trayId,
      'position': position,
      'parameters': parameters,
    };
  }

  factory EggBreakoutTray.fromJson(String source) =>
      EggBreakoutTray.fromMap(jsonDecode(source) as Map<String, dynamic>);

  String toJson() => jsonEncode(toMap());
}
