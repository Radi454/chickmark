import 'package:flutter_test/flutter_test.dart';
import 'package:hatchaudit/features/audits/logic/audit_value_parsing.dart';

void main() {
  test('decodedMaps parses a JSON list of objects and rejects junk', () {
    expect(decodedMaps('[{"a":1},{"b":2}]'), hasLength(2));
    expect(decodedMaps(null), isEmpty);
    expect(decodedMaps('not json'), isEmpty);
    expect(decodedMaps('{"a":1}'), isEmpty); // object, not list
    expect(decodedMaps(''), isEmpty); // blank string
    expect(decodedMaps('   '), isEmpty); // whitespace
  });

  test('decodedListLength returns the count of items in decoded list', () {
    expect(decodedListLength('[{"a":1},{"b":2}]'), 2);
    expect(decodedListLength('[{"a":1}]'), 1);
    expect(decodedListLength(null), 0);
    expect(decodedListLength('not json'), 0);
    expect(decodedListLength('{"a":1}'), 0); // object, not list
  });

  test('decodedMap parses a JSON object and rejects junk', () {
    final map = decodedMap('{"a":1,"b":2}');
    expect(map, isNotNull);
    expect(map, containsPair('a', 1));
    expect(map, containsPair('b', 2));

    expect(decodedMap(null), isNull);
    expect(decodedMap('not json'), isNull);
    expect(decodedMap('[1,2,3]'), isNull); // list, not object
    expect(decodedMap(''), isNull); // blank string
  });

  test('asDouble coerces num and numeric strings, else null', () {
    expect(asDouble(3), 3.0);
    expect(asDouble(3.14), 3.14);
    expect(asDouble('2.5'), 2.5);
    expect(asDouble('3'), 3.0);
    expect(asDouble('x'), isNull);
    expect(asDouble(null), isNull);
    expect(asDouble(''), isNull);
  });

  test('asInt coerces num and numeric strings, rounding floats', () {
    expect(asInt(3), 3);
    expect(asInt(3.14), 3); // rounds
    expect(asInt(3.6), 4); // rounds
    expect(asInt('2'), 2);
    expect(asInt('x'), isNull);
    expect(asInt(null), isNull);
  });

  test('pct divides count by total as percentage, guarding zero and null', () {
    expect(pct(1, 4), 25.0);
    expect(pct(1, 2), 50.0);
    expect(pct(3, 4), 75.0);
    expect(pct(1, 0), isNull); // zero denominator
    expect(pct(null, 4), isNull); // null numerator
    expect(pct(1, null), isNull); // null denominator
    expect(pct(0, 4), 0.0); // zero numerator is valid
    expect(pct('1', '4'), 25.0); // string inputs
  });

  test('compactJson encodes map as JSON, omitting null values', () {
    final result = compactJson({'a': 1, 'b': 'text', 'c': null});
    expect(result, isA<String>());
    expect(result, contains('"a":1'));
    expect(result, contains('"b":"text"'));
    expect(result, isNot(contains('null'))); // null values omitted

    // Test with empty map after removing nulls
    final allNull = compactJson({'a': null, 'b': null});
    expect(allNull, '{}');

    // Test with no null values
    final noNull = compactJson({'x': 1, 'y': 2});
    expect(noNull, contains('"x":1'));
    expect(noNull, contains('"y":2'));
  });

  test('blankToNull trims and nulls empties; hasText mirrors it', () {
    expect(blankToNull('  '), isNull);
    expect(blankToNull(' a '), 'a');
    expect(blankToNull(''), isNull);
    expect(blankToNull(null), isNull);
    expect(blankToNull('text'), 'text');

    expect(hasText(''), isFalse);
    expect(hasText('  '), isFalse);
    expect(hasText('x'), isTrue);
    expect(hasText(' x '), isTrue);
    expect(hasText(null), isFalse);
  });
}
