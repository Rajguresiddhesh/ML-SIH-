// Parity check: the Dart rulebook port must agree with the Python backend on
// every rule it implements. Fixtures are produced by
// `python tools/gen_dart_fixtures.py`.

import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:legal_metrology_checker/src/compliance/audit.dart';
import 'package:legal_metrology_checker/src/compliance/barcode_rules.dart';
import 'package:legal_metrology_checker/src/compliance/gs1.dart';
import 'package:legal_metrology_checker/src/compliance/rulebook_engine.dart';
import 'package:legal_metrology_checker/src/data/product_record.dart';

ProductRecord _recordFromJson(String gtin, Map<String, dynamic> j) {
  final r = ProductRecord(gtin);
  void s(String k, void Function(dynamic) set) {
    if (j[k] != null) set(j[k]);
  }

  s('product_name', (v) => r.productName = v as String);
  s('brand', (v) => r.brand = v as String);
  s('manufacturer_name', (v) => r.manufacturerName = v as String);
  s('manufacturer_address', (v) => r.manufacturerAddress = v as String);
  s('country_of_origin', (v) => r.countryOfOrigin = v as String);
  s('net_quantity_raw', (v) => r.netQuantityRaw = v as String);
  s('net_quantity_value', (v) => r.netQuantityValue = (v as num).toDouble());
  s('net_quantity_unit', (v) => r.netQuantityUnit = v as String);
  s('mrp_value', (v) => r.mrpValue = (v as num).toDouble());
  s('manufacture_date', (v) => r.manufactureDate = v as String);
  s('consumer_care_phone', (v) => r.consumerCarePhone = v as String);
  s('consumer_care_email', (v) => r.consumerCareEmail = v as String);
  s('fssai_license', (v) => r.fssaiLicense = v as String);
  s('sources', (v) => r.sources.addAll((v as List).cast<String>()));
  return r;
}

void main() {
  final file = File('assets/fixtures/rulebook_cases.json');

  test('fixtures exist (run tools/gen_dart_fixtures.py)', () {
    expect(file.existsSync(), isTrue);
  });

  if (!file.existsSync()) return;

  final cases = (jsonDecode(file.readAsStringSync()) as List).cast<Map<String, dynamic>>();

  for (final c in cases) {
    test('parity: ${c['name']}', () {
      final gtin = classifyGtin(c['gtin'] as String);
      final rec = _recordFromJson(c['gtin'] as String, c['record'] as Map<String, dynamic>);
      final pkg = packageFromRecord(rec, gtin);
      final diff = evaluate(pkg, extra: evaluateBarcodeRules(pkg, gtin));

      final dartStatus = <String, String>{};
      for (final r in diff.all) {
        dartStatus[r.ruleId] = r.status;
      }

      final expected = (c['expected'] as Map<String, dynamic>).cast<String, String>();
      // Only compare rules the Dart port implements.
      for (final entry in dartStatus.entries) {
        if (expected.containsKey(entry.key)) {
          expect(entry.value, expected[entry.key],
              reason: 'rule ${entry.key} disagreed with Python backend');
        }
      }
      // Every barcode rule must be present and matching.
      for (final id in [
        'B01_GTIN_STRUCT',
        'B02_GTIN_CHECKSUM',
        'B03_GTIN_SCOPE',
        'B04_GS1_AUTHORITY',
        'B05_REGISTRY_ID',
        'B06_ORIGIN_CONSISTENCY',
      ]) {
        expect(dartStatus[id], expected[id], reason: '$id parity');
      }
    });
  }

  test('deterministic score matches run_barcode_pipeline shape', () {
    final gtin = classifyGtin('9781234567897');
    final rec = ProductRecord('9781234567897');
    final pkg = packageFromRecord(rec, gtin);
    final diff = evaluate(pkg, extra: evaluateBarcodeRules(pkg, gtin));
    final score = scoreDiff(diff);
    expect(score.finalScore, lessThan(0.3)); // unknown product -> very low
    expect(score.starRating, 1);
  });
}
