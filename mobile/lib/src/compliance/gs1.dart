/// Dart port of `legal_metrology_ml/layer1_feature_extraction/gs1.py`.
///
/// Pure, offline. Structurally verifies a scanned bar code as a GS1 GTIN.
library;

/// GS1 prefix ranges -> issuing member organisation / economy.
/// (Condensed from the Python `GS1_PREFIXES` table; extend as needed.)
const List<List<Object>> _gs1Prefixes = [
  [0, 19, 'United States / Canada'],
  [20, 29, 'Restricted distribution'],
  [30, 39, 'United States (drugs)'],
  [40, 49, 'Restricted distribution'],
  [50, 59, 'Coupons'],
  [60, 139, 'United States / Canada'],
  [300, 379, 'France & Monaco'],
  [380, 380, 'Bulgaria'],
  [383, 383, 'Slovenia'],
  [385, 385, 'Croatia'],
  [387, 387, 'Bosnia and Herzegovina'],
  [400, 440, 'Germany'],
  [450, 459, 'Japan'],
  [460, 469, 'Russia'],
  [471, 471, 'Taiwan'],
  [474, 474, 'Estonia'],
  [475, 475, 'Latvia'],
  [477, 477, 'Lithuania'],
  [479, 479, 'Sri Lanka'],
  [480, 480, 'Philippines'],
  [482, 482, 'Ukraine'],
  [485, 485, 'Armenia'],
  [489, 489, 'Hong Kong'],
  [490, 499, 'Japan'],
  [500, 509, 'United Kingdom'],
  [520, 521, 'Greece'],
  [528, 528, 'Lebanon'],
  [529, 529, 'Cyprus'],
  [531, 531, 'North Macedonia'],
  [535, 535, 'Malta'],
  [539, 539, 'Ireland'],
  [540, 549, 'Belgium & Luxembourg'],
  [560, 560, 'Portugal'],
  [569, 569, 'Iceland'],
  [570, 579, 'Denmark, Faroe Islands & Greenland'],
  [590, 590, 'Poland'],
  [594, 594, 'Romania'],
  [599, 599, 'Hungary'],
  [600, 601, 'South Africa'],
  [603, 603, 'Ghana'],
  [608, 608, 'Bahrain'],
  [609, 609, 'Mauritius'],
  [611, 611, 'Morocco'],
  [613, 613, 'Algeria'],
  [615, 615, 'Nigeria'],
  [616, 616, 'Kenya'],
  [619, 619, 'Tunisia'],
  [621, 621, 'Syria'],
  [622, 622, 'Egypt'],
  [624, 624, 'Libya'],
  [625, 625, 'Jordan'],
  [626, 626, 'Iran'],
  [627, 627, 'Kuwait'],
  [628, 628, 'Saudi Arabia'],
  [629, 629, 'United Arab Emirates'],
  [640, 649, 'Finland'],
  [690, 699, 'China'],
  [700, 709, 'Norway'],
  [729, 729, 'Israel'],
  [730, 739, 'Sweden'],
  [740, 745, 'Central America'],
  [750, 750, 'Mexico'],
  [754, 755, 'Canada'],
  [759, 759, 'Venezuela'],
  [760, 769, 'Switzerland & Liechtenstein'],
  [770, 771, 'Colombia'],
  [773, 773, 'Uruguay'],
  [775, 775, 'Peru'],
  [777, 777, 'Bolivia'],
  [778, 779, 'Argentina'],
  [780, 780, 'Chile'],
  [784, 784, 'Paraguay'],
  [786, 786, 'Ecuador'],
  [789, 790, 'Brazil'],
  [800, 839, 'Italy, San Marino & Vatican City'],
  [840, 849, 'Spain'],
  [850, 850, 'Cuba'],
  [858, 858, 'Slovakia'],
  [859, 859, 'Czech Republic'],
  [860, 860, 'Serbia'],
  [865, 865, 'Mongolia'],
  [867, 867, 'North Korea'],
  [868, 869, 'Turkey'],
  [870, 879, 'Netherlands'],
  [880, 880, 'South Korea'],
  [884, 884, 'Cambodia'],
  [885, 885, 'Thailand'],
  [888, 888, 'Singapore'],
  [890, 890, 'India'],
  [893, 893, 'Vietnam'],
  [896, 896, 'Pakistan'],
  [899, 899, 'Indonesia'],
  [900, 919, 'Austria'],
  [930, 939, 'Australia'],
  [940, 949, 'New Zealand'],
  [955, 955, 'Malaysia'],
  [958, 958, 'Macau'],
];

const List<List<Object>> _restrictedRanges = [
  [20, 29, 'Restricted distribution (retailer in-store number)'],
  [40, 49, 'Restricted distribution (retailer in-store number)'],
  [50, 59, 'Coupons'],
  [200, 299, 'Restricted distribution (in-store / variable measure)'],
  [977, 977, 'ISSN (serial publications)'],
  [978, 979, 'ISBN / ISMN (Bookland)'],
  [980, 980, 'Refund receipts'],
  [981, 984, 'GS1 coupon identification'],
  [99, 99, 'Coupons'],
];

const Map<int, String> _gtinLengths = {
  8: 'GTIN-8',
  12: 'UPC-A (GTIN-12)',
  13: 'EAN-13 (GTIN-13)',
  14: 'GTIN-14 / ITF-14',
};

String stripGtin(String code) =>
    code.split('').where((c) => '0123456789'.contains(c)).join();

/// GS1 mod-10 check digit for a GTIN body (all digits except the last).
int gtinCheckDigit(String body) {
  var total = 0;
  final digits = body.split('').map(int.parse).toList().reversed.toList();
  for (var i = 0; i < digits.length; i++) {
    total += digits[i] * (i.isEven ? 3 : 1);
  }
  return (10 - (total % 10)) % 10;
}

bool validateGtin(String code) {
  final d = stripGtin(code);
  if (!_gtinLengths.containsKey(d.length)) return false;
  return gtinCheckDigit(d.substring(0, d.length - 1)) ==
      int.parse(d[d.length - 1]);
}

String? _countryForPrefix(int p) {
  for (final r in _gs1Prefixes) {
    if (p >= (r[0] as int) && p <= (r[1] as int)) return r[2] as String;
  }
  return null;
}

String? _restrictedReason(int p) {
  for (final r in _restrictedRanges) {
    if (p >= (r[0] as int) && p <= (r[1] as int)) return r[2] as String;
  }
  return null;
}

class GtinInfo {
  final String raw;
  final String digits;
  final int length;
  final String? format;
  final bool isGtinLength;
  final bool checksumValid;
  final String? gs1Prefix;
  final String? issuingCountry;
  final bool isGs1India;
  final bool isRestricted;
  final String? restrictedReason;
  final String? gtin14;
  final List<String> notes;

  const GtinInfo({
    required this.raw,
    required this.digits,
    required this.length,
    required this.format,
    required this.isGtinLength,
    required this.checksumValid,
    required this.gs1Prefix,
    required this.issuingCountry,
    required this.isGs1India,
    required this.isRestricted,
    required this.restrictedReason,
    required this.gtin14,
    this.notes = const [],
  });

  bool get isValid => isGtinLength && checksumValid && !isRestricted;

  Map<String, dynamic> toJson() => {
        'digits': digits,
        'format': format,
        'is_gtin_length': isGtinLength,
        'checksum_valid': checksumValid,
        'gs1_prefix': gs1Prefix,
        'issuing_country': issuingCountry,
        'is_gs1_india': isGs1India,
        'is_restricted': isRestricted,
        'restricted_reason': restrictedReason,
        'is_valid': isValid,
        'notes': notes,
      };
}

GtinInfo classifyGtin(String code) {
  final raw = code.trim();
  final digits = stripGtin(raw);
  final length = digits.length;
  final isLen = _gtinLengths.containsKey(length);
  final checksumValid = isLen &&
      gtinCheckDigit(digits.substring(0, length - 1)) ==
          int.parse(digits[length - 1]);

  final gtin14 = isLen ? digits.padLeft(14, '0') : null;
  String? prefix3;
  String? country;
  var restricted = false;
  String? restrictedReason;

  if (gtin14 != null && length != 8) {
    prefix3 = gtin14.substring(1, 4);
    final p = int.parse(prefix3);
    country = _countryForPrefix(p);
    restrictedReason = _restrictedReason(p);
    restricted = restrictedReason != null;
  }

  final isIndia = prefix3 == '890';
  final notes = <String>[];
  if (!isLen) {
    notes.add('$length digits is not a valid GTIN length (expected 8, 12, 13 or 14).');
  } else if (!checksumValid) {
    notes.add('GS1 mod-10 check digit does not match — mistyped or misprinted.');
  }
  if (restricted) {
    notes.add('Prefix $prefix3 is reserved: $restrictedReason. Not a consumer product GTIN.');
  }
  if (isIndia) {
    notes.add('Prefix 890 is allocated by GS1 India — the brand owner holds an Indian GS1 licence.');
  }

  return GtinInfo(
    raw: raw,
    digits: digits,
    length: length,
    format: _gtinLengths[length],
    isGtinLength: isLen,
    checksumValid: checksumValid,
    gs1Prefix: prefix3,
    issuingCountry: country,
    isGs1India: isIndia,
    isRestricted: restricted,
    restrictedReason: restrictedReason,
    gtin14: gtin14,
    notes: notes,
  );
}
