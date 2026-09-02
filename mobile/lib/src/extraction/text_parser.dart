/// Dart port of `legal_metrology_ml/layer1_feature_extraction/text_parser.py`.
///
/// Regex extraction of the mandatory declarations from OCR text. Kept close to
/// the Python patterns so behaviour matches the backend.
library;

import '../compliance/models.dart';
import 'label_ocr.dart';

class ParsedDeclarations {
  double? mrpValue;
  bool mrpIncludesTax = false;
  double? netQuantityValue;
  String? netQuantityUnit;
  String? fssaiLicense;
  String? manufactureDate;
  String? expiryDate;
  String? bestBefore;
  String? manufacturerName;
  String? manufacturerAddress;
  String? importerName;
  String? importerAddress;
  String? consumerCarePhone;
  String? consumerCareEmail;
  String? commodityName;
  bool hasHindi = false;
  bool hasEnglish = false;
}

final _devanagariDigits = {
  '०': '0', '१': '1', '२': '2', '३': '3', '४': '4',
  '५': '5', '६': '6', '७': '7', '८': '8', '९': '9',
};

final _mrpRe = RegExp(
  r'(?:(?:M\.?\s*R\.?\s*P\.?[a-z\d]?|MAX(?:IMUM)?\s*RETAIL\s*PRICE)'
  r'[\s\S]{0,80}?(?:[:.?\-₹z|]+|\bRs\.?|\bINR)?\s*'
  r'(\d+(?:[.,]\d{1,2})?)(?!\s*(?:mg|g|gm|kg|ml|ltr|tabs?|tablets?|caps?))'
  r'|(?:₹|Rs\.?|INR)\s*(\d+(?:[.,]\d{1,2})?)(?!\s*(?:mg|g|gm|kg|ml|ltr|tabs?|tablets?|caps?|\d{3,})))',
  caseSensitive: false,
);

final _netQtyRe = RegExp(
  r'(?:NET\s*(?:WT|WEIGHT|QTY|QUANTITY|CONTENT|CONTENTS?|VOLUME|VOL)?[\s:.\-|]*)'
  r'(\d+(?:\.\d+)?)\s*'
  r'(g|gm|gms|grams?|kg|kgs|ml|l|ltr|litre|litres|liter|liters|cm|m|mm|nos|units?|pieces?|pcs|N|tablets?|capsules?|sachets?|strips?)\b'
  r'|(\d+)\s*[xX×]\s*(\d+)\s*(tablets?|capsules?|sachets?|strips?|pcs|pieces?)'
  r'|\b(\d+(?:\.\d+)?)\s*(g|gm|gms|grams?|kg|kgs|ml|l|ltr|litre|litres|liter|liters)\b',
  caseSensitive: false,
);

final _fssaiRe = RegExp(
    r'(?:FSSAI|Lic\.?\s*(?:No\.?)?|Licence?\s*No\.?)\s*[,:.\-]?\s*([0-9]{14})',
    caseSensitive: false);
final _fssai14 = RegExp(r'\b(\d{14})\b');

final _mfgRe = RegExp(
  r'(?:MFD|PKD|MFG|PACKED|MANUFACTURED|DATE\s*OF\s*(?:MFG|MANUFACTURE|PACKING))'
  r'[\s:.\-]*'
  r'(\d{1,2}[/\-.][A-Za-z0-9]{3,9}[/\-.]\d{2,4}|\d{1,2}[/\-.]\d{1,2}[/\-.]\d{2,4}|\d{1,2}[/\-.]\d{2,4}|[A-Za-z]{3,9}\.?\s*[/\-.]?\s*\d{2,4})',
  caseSensitive: false,
);
final _expRe = RegExp(
  r'(?:EXP(?:IRY)?|USE\s*BY|BEST\s*BEFORE|BB|USE\s*BEFORE|EXPIRY\s*DATE)'
  r'[\s:.\-]*'
  r'(\d{1,2}[/\-.][A-Za-z0-9]{3,9}[/\-.]\d{2,4}|\d{1,2}[/\-.]\d{1,2}[/\-.]\d{2,4}|\d{1,2}[/\-.]\d{2,4}|[A-Za-z]{3,9}\.?\s*[/\-.]?\s*\d{2,4}|\d+\s*(?:months?|days?|years?))',
  caseSensitive: false,
);

final _phoneRe = RegExp(
    r'(?:1800[\s\-]?\d{3}[\s\-]?\d{3,4}|\+?91[\s\-]?[6-9]\d{9}|[6-9]\d{9})');
final _emailRe = RegExp(r'[\w.+\-]+@[\w\-]+\.[\w.]+', caseSensitive: false);

final _mfrKeywords = <(RegExp, String)>[
  (RegExp(r'(?:Mfd\.?\s*by|Manufactured\s*by|Manufacturer)\s*[:.\-]?\s*', caseSensitive: false), 'manufacturer'),
  (RegExp(r'(?:Packed\s*by|Packer|Pkd\.?\s*by)\s*[:.\-]?\s*', caseSensitive: false), 'packer'),
  (RegExp(r'(?:Imported\s*by|Importer)\s*[:.\-]?\s*', caseSensitive: false), 'importer'),
  (RegExp(r'(?:Mktd\.?\s*by|Marketed\s*by)\s*[:.\-]?\s*', caseSensitive: false), 'marketer'),
];

const _unitMap = {
  'g': 'g', 'gm': 'g', 'gms': 'g', 'gram': 'g', 'grams': 'g',
  'kg': 'kg', 'kgs': 'kg', 'ml': 'ml',
  'l': 'l', 'ltr': 'l', 'litre': 'l', 'litres': 'l', 'liter': 'l', 'liters': 'l',
  'cm': 'cm', 'm': 'm', 'mm': 'mm',
  'nos': 'nos', 'unit': 'nos', 'units': 'nos', 'piece': 'nos', 'pieces': 'nos',
  'pcs': 'nos', 'n': 'nos',
  'tablet': 'tablets', 'tablets': 'tablets',
  'capsule': 'capsules', 'capsules': 'capsules',
};

String _normUnit(String u) => _unitMap[u.toLowerCase()] ?? u.toLowerCase();

ParsedDeclarations parseOcr(OcrResult ocr) {
  var text = ocr.fullText;
  _devanagariDigits.forEach((k, v) => text = text.replaceAll(k, v));
  text = text.replaceAllMapped(RegExp(r'(\d+)O([a-zA-Z]+)'), (m) => '${m[1]}0${m[2]}');

  final d = ParsedDeclarations();
  d.hasHindi = ocr.hasDevanagari;
  d.hasEnglish = ocr.hasLatin;

  // MRP
  final mrpM = _mrpRe.firstMatch(text);
  if (mrpM != null) {
    final vs = (mrpM.group(1) ?? mrpM.group(2) ?? '').replaceAll(',', '.');
    d.mrpValue = double.tryParse(vs);
    final ctx = mrpM.group(0)!.toLowerCase();
    d.mrpIncludesTax = ctx.contains('incl') || ctx.contains('all tax');
  }
  if (d.mrpValue == null) {
    final decimals = RegExp(r'\b(\d{2,5}\.\d{2})\b')
        .allMatches(text)
        .map((m) => double.parse(m.group(1)!))
        .where((c) => c >= 10 && c <= 99999)
        .toList();
    if (decimals.isNotEmpty) d.mrpValue = decimals.reduce((a, b) => a > b ? a : b);
  }
  if (!d.mrpIncludesTax) {
    final lower = text.toLowerCase();
    d.mrpIncludesTax = lower.contains('inclusive of all tax') ||
        lower.contains('incl. of all tax') ||
        lower.contains('incl of all tax');
  }

  // Net quantity
  final nqM = _netQtyRe.firstMatch(text);
  if (nqM != null) {
    if (nqM.group(1) != null) {
      d.netQuantityValue = double.tryParse(nqM.group(1)!);
      d.netQuantityUnit = _normUnit(nqM.group(2)!);
    } else if (nqM.group(3) != null) {
      d.netQuantityValue =
          double.parse(nqM.group(3)!) * double.parse(nqM.group(4)!);
      d.netQuantityUnit = _normUnit(nqM.group(5)!);
    } else if (nqM.group(6) != null) {
      d.netQuantityValue = double.tryParse(nqM.group(6)!);
      d.netQuantityUnit = _normUnit(nqM.group(7)!);
    }
  }

  // FSSAI
  d.fssaiLicense = _fssaiRe.firstMatch(text)?.group(1);
  if (d.fssaiLicense == null) {
    final idx = text.toUpperCase().indexOf('FSSAI');
    if (idx >= 0) {
      final near = text.substring(
          (idx - 20).clamp(0, text.length).toInt(),
          (idx + 60).clamp(0, text.length).toInt());
      d.fssaiLicense = _fssai14.firstMatch(near)?.group(1);
    }
  }

  // Dates
  d.manufactureDate = _mfgRe.firstMatch(text)?.group(1)?.trim();
  final expM = _expRe.firstMatch(text);
  if (expM != null) {
    final dt = expM.group(1)!.trim();
    if (RegExp(r'\d+\s*(?:months?|days?|years?)', caseSensitive: false).hasMatch(dt)) {
      d.bestBefore = dt;
    } else {
      d.expiryDate = dt;
    }
  }

  // Manufacturer / packer / importer
  for (final (re, role) in _mfrKeywords) {
    final m = re.firstMatch(text);
    if (m == null) continue;
    var rest = text.substring(m.end, (m.end + 200).clamp(0, text.length).toInt());
    final endM = RegExp(
      r'(?:Mfd\.?\s*by|Packed\s*by|Imported\s*by|Mktd\.?\s*by|Net\s*(?:Wt|Qty|Weight)|MRP|FSSAI|Customer\s*Care|Consumer\s*(?:Care|Complaint))',
      caseSensitive: false,
    ).firstMatch(rest);
    if (endM != null) rest = rest.substring(0, endM.start);
    final lines = rest.split('\n').map((e) => e.trim()).where((e) => e.isNotEmpty).toList();
    if (lines.isEmpty) continue;
    final name = lines.first;
    final addr = lines.length > 1 ? lines.sublist(1).join(', ') : null;
    switch (role) {
      case 'manufacturer':
        d.manufacturerName = name;
        d.manufacturerAddress = addr;
      case 'importer':
        d.importerName = name;
        d.importerAddress = addr;
      case 'marketer':
        d.manufacturerName ??= name;
        d.manufacturerAddress ??= addr;
    }
  }

  // Consumer care
  final careIdx = RegExp(
    r'(?:consumer|customer)\s*(?:care|complaint|helpline|service)',
    caseSensitive: false,
  ).firstMatch(text);
  final region = careIdx != null
      ? text.substring(
          careIdx.start, (careIdx.start + 200).clamp(0, text.length).toInt())
      : text;
  d.consumerCarePhone = _phoneRe.firstMatch(region)?.group(0)?.trim() ??
      _phoneRe.firstMatch(text)?.group(0)?.trim();
  d.consumerCareEmail = _emailRe.firstMatch(region)?.group(0)?.trim() ??
      _emailRe.firstMatch(text)?.group(0)?.trim();

  // Commodity name — largest line in the top half
  if (ocr.lines.isNotEmpty) {
    final maxY = ocr.lines.map((l) => l.top).reduce((a, b) => a > b ? a : b);
    var upper = ocr.lines.where((l) => l.top < maxY * 0.5).toList();
    if (upper.isEmpty) upper = ocr.lines;
    upper.sort((a, b) => b.height.compareTo(a.height));
    final skip = RegExp(
      r'^(?:\d+|MRP|M\.R\.P|Rs|NET|FSSAI|Mfd|Pkg|Exp|Best|Before|ingredients?|nutrition|contains?)$',
      caseSensitive: false,
    );
    for (final l in upper) {
      final t = l.text.trim();
      if (t.length > 2 && !skip.hasMatch(t)) {
        d.commodityName = t;
        break;
      }
    }
  }

  return d;
}

/// Fold parsed declarations into a [PackageData] (label pipeline, Layer 2).
PackageData toPackageData(ParsedDeclarations d, {double avgOcrConfidence = 0.5}) {
  final p = PackageData()
    ..analysisSource = AnalysisSource.image
    ..commodityName = d.commodityName
    ..manufacturerName = d.manufacturerName
    ..manufacturerAddress = d.manufacturerAddress
    ..importerName = d.importerName
    ..importerAddress = d.importerAddress
    ..mrpValue = d.mrpValue
    ..mrpIncludesTax = d.mrpValue != null ? d.mrpIncludesTax : null
    ..manufactureDate = d.manufactureDate
    ..expiryDate = d.expiryDate
    ..bestBefore = d.bestBefore
    ..consumerCarePhone = d.consumerCarePhone
    ..consumerCareEmail = d.consumerCareEmail
    ..fssaiLicenseNumber = d.fssaiLicense
    ..hasHindiText = d.hasHindi
    ..hasEnglishText = d.hasEnglish
    ..averageOcrConfidence = avgOcrConfidence
    ..isImported = (d.importerName ?? d.importerAddress) != null;

  if (d.netQuantityValue != null) {
    p.netQuantityValue = d.netQuantityValue;
    p.netQuantityUnit = d.netQuantityUnit;
    p.netQuantityCategory = _categoryFor(d.netQuantityUnit);
  }
  return p;
}

QuantityCategory? _categoryFor(String? unit) {
  switch (unit) {
    case 'g':
    case 'kg':
    case 'mg':
      return QuantityCategory.weight;
    case 'ml':
    case 'l':
      return QuantityCategory.volume;
    case 'cm':
    case 'm':
    case 'mm':
      return QuantityCategory.length;
    case 'nos':
    case 'tablets':
    case 'capsules':
      return QuantityCategory.number;
  }
  return null;
}
