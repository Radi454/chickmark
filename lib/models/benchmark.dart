/// A single benchmark value for a given breed, flock age, and parameter.
///
/// Valid parameter names (used as keys throughout the app):
///   'Hatchability', 'Fertility', 'HOF', 'Infertile', 'EarlyDead', 'LateDead'
class Benchmark {
  final String id;
  final String breed;
  final int ageWeeks;
  final String parameter;
  final double value;

  const Benchmark({
    required this.id,
    required this.breed,
    required this.ageWeeks,
    required this.parameter,
    required this.value,
  });

  Map<String, dynamic> toMap() => {
        'id': id,
        'breed': breed,
        'age_weeks': ageWeeks,
        'parameter': parameter,
        'value': value,
      };

  factory Benchmark.fromMap(Map<String, dynamic> m) => Benchmark(
        id: m['id'] as String,
        breed: m['breed'] as String,
        ageWeeks: (m['age_weeks'] as num).toInt(),
        parameter: m['parameter'] as String,
        value: (m['value'] as num).toDouble(),
      );

  @override
  String toString() =>
      'Benchmark(breed: $breed, age: ${ageWeeks}w, $parameter: $value)';
}
