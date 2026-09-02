/// Dart port of `legal_metrology_ml/layer4_rulebook_engine/engine.py` +
/// `layer5_aggregation/scorer.py` (deterministic branch used by
/// `run_barcode_pipeline`).
library;

import 'models.dart';
import 'rules.dart';

ComplianceDiff evaluate(PackageData pkg, {List<RuleResult> extra = const []}) {
  final passed = <RuleResult>[];
  final failed = <RuleResult>[];
  final warnings = <RuleResult>[];
  final na = <RuleResult>[];
  final inconclusive = <RuleResult>[];

  final results = <RuleResult>[];
  for (final rule in allRules) {
    try {
      results.add(rule(pkg));
    } catch (e) {
      results.add(RuleResult(
        ruleId: 'RULE_ERROR',
        ruleName: 'Rule error',
        status: 'INCONCLUSIVE',
        severity: 'MINOR',
        detail: 'Rule raised: $e',
        weight: 0.0,
      ));
    }
  }
  results.addAll(extra);

  for (final r in results) {
    switch (r.status) {
      case 'PASS':
        passed.add(r);
      case 'FAIL':
        failed.add(r);
      case 'WARNING':
        warnings.add(r);
      case 'NOT_APPLICABLE':
        na.add(r);
      default:
        inconclusive.add(r);
    }
  }

  return ComplianceDiff(
    passed: passed,
    failed: failed,
    warnings: warnings,
    notApplicable: na,
    inconclusive: inconclusive,
  );
}

({int rating, String label}) starRating(double score) {
  if (score >= 0.95) return (rating: 5, label: 'Fully Compliant');
  if (score >= 0.80) return (rating: 4, label: 'Mostly Compliant');
  if (score >= 0.60) return (rating: 3, label: 'Partially Compliant');
  if (score >= 0.40) return (rating: 2, label: 'Largely Non-Compliant');
  return (rating: 1, label: 'Critically Non-Compliant');
}

/// Deterministic score: confirmed-compliant weight over
/// (confirmed + failed + warning + unverified-mandatory) weight — matching
/// `run_barcode_pipeline` in the Python backend.
ComplianceScore scoreDiff(ComplianceDiff diff, {bool countUnverified = true}) {
  double w(Iterable<RuleResult> rs) => rs.fold(0.0, (s, r) => s + r.weight);

  final passedW = w(diff.passed);
  final failedW = w(diff.failed);
  final warnW = w(diff.warnings);
  final unverifiedW = countUnverified
      ? w(diff.inconclusive.where((r) => r.severity == 'CRITICAL' || r.severity == 'MAJOR'))
      : 0.0;

  final applicable = passedW + failedW + warnW + unverifiedW;
  final prob = applicable > 0 ? passedW / applicable : 1.0;
  final sr = starRating(prob);

  final unverifiedMandatory = diff.inconclusive
      .where((r) => r.severity == 'CRITICAL' || r.severity == 'MAJOR')
      .toList();
  var label = sr.label;
  if (countUnverified && unverifiedMandatory.isNotEmpty) {
    label = '${sr.label} — ${unverifiedMandatory.length} mandatory declarations unverified';
  }

  return ComplianceScore(
    finalScore: double.parse(prob.toStringAsFixed(3)),
    starRating: sr.rating,
    starLabel: label,
    totalApplicableRules: diff.passed.length +
        diff.failed.length +
        diff.warnings.length +
        unverifiedMandatory.length,
    passedRules: diff.passed.length,
    failedRules: diff.failed.length,
    criticalFailures: diff.failed.where((r) => r.severity == 'CRITICAL').length,
    majorFailures: diff.failed.where((r) => r.severity == 'MAJOR').length,
    minorFailures: diff.failed.where((r) => r.severity == 'MINOR').length,
  );
}

List<String> generateRecommendations(ComplianceDiff diff) {
  final recs = <String>[];
  for (final r in diff.failed) {
    final ref = r.legalReference != null ? ' (Ref: ${r.legalReference})' : '';
    final ev = r.evidence != null ? ' Found: ${r.evidence}' : '';
    recs.add('[${r.severity}] ${r.ruleName}$ref: ${r.detail}.$ev');
  }
  for (final r in diff.warnings) {
    recs.add('[WARNING] ${r.ruleName}: ${r.detail}.');
  }
  final unverified = diff.inconclusive
      .where((r) => r.severity == 'CRITICAL' || r.severity == 'MAJOR')
      .map((r) => r.ruleName)
      .toSet()
      .toList()
    ..sort();
  if (unverified.isNotEmpty) {
    recs.insert(0,
        '[ACTION] Physically inspect the pack for these unverified declarations: ${unverified.join(', ')}.');
  }
  if (recs.isEmpty) {
    recs.add('No compliance issues found. Maintain current packaging standards.');
  }
  return recs;
}
