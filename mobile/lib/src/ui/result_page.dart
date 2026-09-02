import 'package:flutter/material.dart';

import '../compliance/models.dart';

class ResultPage extends StatelessWidget {
  final ComplianceReport report;
  const ResultPage({super.key, required this.report});

  @override
  Widget build(BuildContext context) {
    final s = report.score;
    final pct = (s.finalScore * 100).round();
    final color = pct >= 70
        ? Colors.green
        : pct >= 40
            ? Colors.orange
            : Colors.red;

    return Scaffold(
      appBar: AppBar(title: const Text('Compliance Report')),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          Card(
            color: color.withOpacity(0.10),
            child: Padding(
              padding: const EdgeInsets.all(16),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text('$pct%',
                      style: Theme.of(context)
                          .textTheme
                          .displaySmall
                          ?.copyWith(color: color, fontWeight: FontWeight.bold)),
                  Text('${'★' * s.starRating}${'☆' * (5 - s.starRating)}  ${s.starLabel}'),
                  const SizedBox(height: 6),
                  Text(report.source,
                      style: Theme.of(context).textTheme.bodySmall),
                  Text(
                    '${s.passedRules} passed · ${s.failedRules} failed · '
                    '${report.diff.warnings.length} warnings · '
                    '${report.diff.inconclusive.length} inconclusive',
                    style: Theme.of(context).textTheme.bodySmall,
                  ),
                ],
              ),
            ),
          ),
          const SizedBox(height: 12),
          _barcodeCard(context),
          const SizedBox(height: 12),
          _group(context, 'Failed', report.diff.failed, Colors.red),
          _group(context, 'Warnings', report.diff.warnings, Colors.orange),
          _group(context, 'Inconclusive — verify on pack', report.diff.inconclusive,
              Colors.blueGrey),
          _group(context, 'Passed', report.diff.passed, Colors.green),
          _group(context, 'Not applicable', report.diff.notApplicable, Colors.grey),
          const SizedBox(height: 16),
          if (report.recommendations.isNotEmpty) ...[
            Text('Recommendations',
                style: Theme.of(context).textTheme.titleMedium),
            const SizedBox(height: 6),
            ...report.recommendations.map((r) => Padding(
                  padding: const EdgeInsets.symmetric(vertical: 3),
                  child: Text('• $r'),
                )),
          ],
        ],
      ),
    );
  }

  Widget _barcodeCard(BuildContext context) {
    final p = report.packageData;
    if (!p.hasBarcode) return const SizedBox.shrink();
    final rows = <String, String>{
      'Bar code': p.barcodeValue ?? '—',
      'GTIN format': p.barcodeGtinFormat ?? 'not a GTIN length',
      'Check digit': p.barcodeChecksumValid == null
          ? '—'
          : (p.barcodeChecksumValid! ? 'valid' : 'INVALID'),
      'GS1 authority': p.barcodeIssuingCountry ??
          (p.barcodeIsGs1India == true ? 'GS1 India' : 'unknown'),
      'GS1 India (890)': p.barcodeIsGs1India == true ? 'yes' : 'no',
      if (p.barcodeIsRestricted == true) 'Restricted prefix': 'yes',
      'Registry match': p.productIdentified
          ? p.productDataSources.join(', ')
          : 'not found in any registry',
      if (p.barcodeRegisteredOwner != null)
        'Brand owner': p.barcodeRegisteredOwner!,
    };
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(14),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text('Bar code / GS1 verification',
                style: Theme.of(context).textTheme.titleSmall),
            const SizedBox(height: 8),
            ...rows.entries.map((e) => Padding(
                  padding: const EdgeInsets.symmetric(vertical: 2),
                  child: Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      SizedBox(
                          width: 130,
                          child: Text(e.key,
                              style: Theme.of(context).textTheme.bodySmall)),
                      Expanded(child: Text(e.value)),
                    ],
                  ),
                )),
          ],
        ),
      ),
    );
  }

  Widget _group(
      BuildContext context, String title, List<RuleResult> rules, Color color) {
    if (rules.isEmpty) return const SizedBox.shrink();
    return ExpansionTile(
      title: Text('$title (${rules.length})',
          style: TextStyle(color: color, fontWeight: FontWeight.w600)),
      initiallyExpanded: title == 'Failed' || title.startsWith('Inconclusive'),
      childrenPadding: const EdgeInsets.only(bottom: 8),
      children: [
        for (final r in rules)
          ListTile(
            dense: true,
            title: Text(r.ruleName),
            subtitle: Text('${r.ruleId} · ${r.severity}\n${r.detail}'
                '${r.legalReference != null ? '\n${r.legalReference}' : ''}'),
            isThreeLine: true,
          ),
      ],
    );
  }
}
