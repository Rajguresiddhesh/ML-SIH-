/// Dart port of `legal_metrology_ml/data_sources/product_lookup.py`.
///
/// Online-optional: returns an empty [ProductRecord] immediately when the
/// device is offline, so the audit still runs from the GTIN alone.
library;

import 'dart:async';
import 'dart:convert';

import 'package:connectivity_plus/connectivity_plus.dart';
import 'package:http/http.dart' as http;

import 'product_record.dart';

const _ua = {'User-Agent': 'LegalMetrologyChecker/1.0 (compliance-audit)'};
const _timeout = Duration(seconds: 6);
const _deadline = Duration(seconds: 12);

const sourceGs1India = 'gs1_india_datakart';
const sourceOff = 'open_food_facts';
const sourceObf = 'open_beauty_facts';
const sourceOpf = 'open_products_facts';
const sourceUpc = 'upcitemdb';
const sourceWikidata = 'wikidata';

const _priority = [
  sourceGs1India,
  sourceOff,
  sourceObf,
  sourceOpf,
  sourceUpc,
  sourceWikidata,
];

final _qtyRe = RegExp(
  r'(\d+(?:[.,]\d+)?)\s*'
  r'(kg|kgs|g|gm|gms|gram|grams|mg|l|lt|ltr|litre|liter|liters|ml|cl|pcs|pc|piece|pieces|n|nos|units?|u|m|cm|mm)\b',
  caseSensitive: false,
);
final _mrpRe = RegExp(r'(?:₹|rs\.?|inr|mrp)\s*[:\-]?\s*(\d+(?:\.\d{1,2})?)',
    caseSensitive: false);

const _unitCanon = {
  'kg': 'kg', 'kgs': 'kg',
  'g': 'g', 'gm': 'g', 'gms': 'g', 'gram': 'g', 'grams': 'g',
  'mg': 'mg',
  'l': 'l', 'lt': 'l', 'ltr': 'l', 'litre': 'l', 'liter': 'l', 'liters': 'l',
  'ml': 'ml', 'cl': 'cl',
  'pcs': 'U', 'pc': 'U', 'piece': 'U', 'pieces': 'U', 'u': 'U',
  'n': 'N', 'nos': 'N', 'unit': 'U', 'units': 'U',
  'm': 'm', 'cm': 'cm', 'mm': 'mm',
};

({double? value, String? unit, String? raw}) parseQuantity(String? text) {
  if (text == null || text.isEmpty) return (value: null, unit: null, raw: null);
  final m = _qtyRe.firstMatch(text);
  if (m == null) return (value: null, unit: null, raw: text.trim());
  final v = double.tryParse(m.group(1)!.replaceAll(',', '.'));
  if (v == null) return (value: null, unit: null, raw: m.group(0));
  final u = _unitCanon[m.group(2)!.toLowerCase()] ?? m.group(2)!.toLowerCase();
  return (value: v, unit: u, raw: m.group(0));
}

double? parseMrp(List<String?> texts) {
  for (final t in texts) {
    if (t == null) continue;
    final m = _mrpRe.firstMatch(t);
    if (m != null) return double.tryParse(m.group(1)!);
  }
  return null;
}

String? _clean(Object? s) {
  if (s == null) return null;
  final v = s.toString().trim().replaceAll(RegExp(r',$'), '').trim();
  return v.isEmpty ? null : v;
}

/// Configure GS1 India / DataKart access (from settings). When [gs1IndiaKey]
/// is null the licensed source is skipped.
class LookupConfig {
  final String? gs1IndiaKey;
  final String gs1IndiaUrlTemplate;
  const LookupConfig({
    this.gs1IndiaKey,
    this.gs1IndiaUrlTemplate =
        'https://datakartapigateway.gs1india.org/api/v1/product/gtin/{gtin}',
  });
}

Future<Map<String, dynamic>> _getJson(Uri url, {Map<String, String>? headers}) async {
  final resp = await http.get(url, headers: {..._ua, ...?headers}).timeout(_timeout);
  if (resp.statusCode != 200) return {};
  final body = jsonDecode(resp.body);
  return body is Map<String, dynamic> ? body : {};
}

Future<Map<String, Object?>> _openfacts(String gtin, String host, String source) async {
  try {
    final data = await _getJson(Uri.parse('https://$host/api/v2/product/$gtin.json'));
    final status = data['status'];
    if (status != 1 && status != 'success' && status != 'success_with_warnings') return {};
    final p = (data['product'] as Map?)?.cast<String, dynamic>() ?? {};
    if (p.isEmpty) return {};
    final q = parseQuantity(p['quantity']?.toString());
    final labels = '${(p['labels_tags'] as List?)?.join(' ') ?? ''} '
        '${(p['ingredients_analysis_tags'] as List?)?.join(' ') ?? ''}';
    String? veg;
    if (labels.contains('non-vegetarian')) {
      veg = 'NON_VEG';
    } else if (labels.contains('vegetarian') || labels.contains('vegan')) veg = 'VEG';
    return {
      '_source': source,
      'product_name': _clean(p['product_name'] ?? p['product_name_en'] ?? p['generic_name']),
      'brand': _clean((p['brands']?.toString() ?? '').split(',').first),
      'manufacturer_name': _clean(p['manufacturer'] ?? (p['brands']?.toString() ?? '').split(',').first),
      'manufacturer_address': _clean(p['manufacturing_places'] ?? p['emb_codes']),
      'country_of_origin': _clean(p['origin']),
      'net_quantity_raw': q.raw,
      'net_quantity_value': q.value,
      'net_quantity_unit': q.unit,
      'veg_non_veg': veg,
      'consumer_care': _clean(p['customer_service']),
      'categories': [
        for (final c in (p['categories']?.toString() ?? '').split(','))
          if (c.trim().isNotEmpty) c.trim()
      ].take(6).toList(),
    };
  } catch (_) {
    return {};
  }
}

Future<Map<String, Object?>> _upcitemdb(String gtin) async {
  try {
    final data = await _getJson(Uri.parse('https://api.upcitemdb.com/prod/trial/lookup?upc=$gtin'));
    final items = (data['items'] as List?) ?? [];
    if (items.isEmpty) return {};
    final it = (items.first as Map).cast<String, dynamic>();
    final q = parseQuantity((it['size'] ?? it['weight'] ?? it['dimension'])?.toString());
    return {
      '_source': sourceUpc,
      'product_name': _clean(it['title']),
      'brand': _clean(it['brand']),
      'manufacturer_name': _clean(it['manufacturer'] ?? it['brand']),
      'net_quantity_raw': q.raw,
      'net_quantity_value': q.value,
      'net_quantity_unit': q.unit,
    };
  } catch (_) {
    return {};
  }
}

Future<Map<String, Object?>> _wikidata(String gtin) async {
  final forms = {gtin, gtin.replaceFirst(RegExp(r'^0+'), ''), gtin.padLeft(13, '0')}
      .where((f) => f.isNotEmpty);
  final values = forms.map((f) => '"$f"').join(' ');
  final query = '''
SELECT ?itemLabel ?brandLabel ?manufacturerLabel ?countryLabel WHERE {
  VALUES ?gtin { $values }
  ?item wdt:P3962 ?gtin .
  OPTIONAL { ?item wdt:P1716 ?brand. }
  OPTIONAL { ?item wdt:P176 ?manufacturer. }
  OPTIONAL { ?item wdt:P495 ?country. }
  SERVICE wikibase:label { bd:serviceParam wikibase:language "en". }
} LIMIT 1''';
  try {
    final data = await _getJson(Uri.parse(
        'https://query.wikidata.org/sparql?format=json&query=${Uri.encodeComponent(query)}'));
    final rows = (data['results']?['bindings'] as List?) ?? [];
    if (rows.isEmpty) return {};
    final r = (rows.first as Map).cast<String, dynamic>();
    String? g(String k) => _clean((r[k] as Map?)?['value']);
    return {
      '_source': sourceWikidata,
      'product_name': g('itemLabel'),
      'brand': g('brandLabel'),
      'manufacturer_name': g('manufacturerLabel'),
      'country_of_origin': g('countryLabel'),
    };
  } catch (_) {
    return {};
  }
}

Future<Map<String, Object?>> _gs1India(String gtin, LookupConfig cfg) async {
  final key = cfg.gs1IndiaKey;
  if (key == null || key.isEmpty) return {};
  final url = Uri.parse(cfg.gs1IndiaUrlTemplate.replaceAll('{gtin}', gtin));
  try {
    final data = await _getJson(url, headers: {'Authorization': 'Bearer $key', 'APIKey': key});
    final products = data['products'];
    final firstProduct =
        (products is List && products.isNotEmpty) ? products.first : null;
    final p = ((data['product'] ?? firstProduct ?? data['data'] ?? data) as Map?)
            ?.cast<String, dynamic>() ??
        {};
    if (p.isEmpty) return {};
    final q = parseQuantity(
        (p['netContent'] ?? p['netQuantity'] ?? p['quantity'])?.toString());
    return {
      '_source': sourceGs1India,
      'product_name': _clean(p['productName'] ?? p['productDescription']),
      'brand': _clean(p['brandName'] ?? p['brand']),
      'manufacturer_name': _clean(p['manufacturedBy'] ?? p['manufacturer'] ?? p['companyName']),
      'manufacturer_address': _clean(p['manufacturedByAddress'] ?? p['companyAddress']),
      'packer_name': _clean(p['packedBy'] ?? p['marketedBy']),
      'importer_name': _clean(p['importedBy']),
      'country_of_origin': _clean(p['countryOfOrigin'] ?? 'India'),
      'net_quantity_raw': q.raw,
      'net_quantity_value': q.value,
      'net_quantity_unit': q.unit,
      'mrp_value': parseMrp([p['mrp']?.toString(), p['MRP']?.toString()]),
      'mrp_currency': 'INR',
      'manufacture_date': _clean(p['manufacturingDate'] ?? p['packagingDate']),
      'best_before': _clean(p['bestBefore']),
      'fssai_license': _clean(p['fssaiLicenseNo'] ?? p['fssai']),
      'consumer_care_phone': _clean(p['customerCareNumber']),
      'consumer_care_email': _clean(p['customerCareEmail']),
    };
  } catch (_) {
    return {};
  }
}

const _mergeableFields = [
  'product_name', 'brand', 'manufacturer_name', 'manufacturer_address',
  'packer_name', 'importer_name', 'importer_address', 'country_of_origin',
  'net_quantity_raw', 'net_quantity_value', 'net_quantity_unit', 'mrp_value',
  'mrp_currency', 'manufacture_date', 'best_before', 'fssai_license',
  'veg_non_veg', 'consumer_care', 'consumer_care_phone', 'consumer_care_email',
];

Future<ProductRecord> lookupProduct(
  String gtin, {
  LookupConfig config = const LookupConfig(),
}) async {
  final digits = gtin.split('').where((c) => '0123456789'.contains(c)).join();
  final record = ProductRecord(digits.isNotEmpty ? digits : gtin);
  if (digits.isEmpty) return record;

  final conn = await Connectivity().checkConnectivity();
  if (conn.contains(ConnectivityResult.none) && conn.length == 1) {
    return record; // offline — GTIN structural checks only
  }

  final adapters = <Future<Map<String, Object?>>>[
    _gs1India(digits, config),
    _openfacts(digits, 'world.openfoodfacts.org', sourceOff),
    _openfacts(digits, 'world.openbeautyfacts.org', sourceObf),
    _openfacts(digits, 'world.openproductsfacts.org', sourceOpf),
    _upcitemdb(digits),
    _wikidata(digits),
  ];

  var payloads = <Map<String, Object?>>[];
  try {
    payloads = (await Future.wait(adapters).timeout(_deadline))
        .where((m) => m.isNotEmpty)
        .toList();
  } on TimeoutException {
    // use whatever resolved
  }

  payloads.sort((a, b) {
    final ia = _priority.indexOf(a['_source'] as String? ?? '');
    final ib = _priority.indexOf(b['_source'] as String? ?? '');
    return (ia < 0 ? 99 : ia).compareTo(ib < 0 ? 99 : ib);
  });

  for (final payload in payloads) {
    final source = payload['_source'] as String? ?? 'unknown';
    record.sources.add(source);
    for (final f in _mergeableFields) {
      record.set(f, payload[f], source);
    }
    for (final c in (payload['categories'] as List?)?.cast<String>() ?? const []) {
      if (!record.categories.contains(c)) record.categories.add(c);
    }
  }

  if (record.netQuantityRaw != null && record.netQuantityValue == null) {
    final q = parseQuantity(record.netQuantityRaw);
    record.netQuantityValue = q.value;
    record.netQuantityUnit ??= q.unit;
  }
  return record;
}
