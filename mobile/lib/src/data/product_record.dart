/// Dart port of `legal_metrology_ml/data_sources/product_lookup.py::ProductRecord`.
library;

class ProductRecord {
  final String gtin;

  String? productName;
  String? brand;
  String? manufacturerName;
  String? manufacturerAddress;
  String? packerName;
  String? importerName;
  String? importerAddress;
  String? countryOfOrigin;

  String? netQuantityRaw;
  double? netQuantityValue;
  String? netQuantityUnit;

  double? mrpValue;
  String? mrpCurrency;

  String? manufactureDate;
  String? bestBefore;

  String? fssaiLicense;
  String? vegNonVeg; // VEG | NON_VEG
  String? consumerCare;
  String? consumerCarePhone;
  String? consumerCareEmail;

  final List<String> categories = [];
  final List<String> imageUrls = [];

  final List<String> sources = [];
  final Map<String, String> fieldSources = {};

  ProductRecord(this.gtin);

  bool get found =>
      sources.isNotEmpty &&
      (productName != null ||
          brand != null ||
          netQuantityRaw != null ||
          manufacturerName != null);

  void set(String key, Object? value, String source) {
    if (value == null || value == '' || (value is List && value.isEmpty)) return;
    final cur = _get(key);
    if (cur == null || cur == '') {
      _set(key, value);
      fieldSources[key] = source;
    }
  }

  Object? _get(String k) => switch (k) {
        'product_name' => productName,
        'brand' => brand,
        'manufacturer_name' => manufacturerName,
        'manufacturer_address' => manufacturerAddress,
        'packer_name' => packerName,
        'importer_name' => importerName,
        'importer_address' => importerAddress,
        'country_of_origin' => countryOfOrigin,
        'net_quantity_raw' => netQuantityRaw,
        'net_quantity_value' => netQuantityValue,
        'net_quantity_unit' => netQuantityUnit,
        'mrp_value' => mrpValue,
        'mrp_currency' => mrpCurrency,
        'manufacture_date' => manufactureDate,
        'best_before' => bestBefore,
        'fssai_license' => fssaiLicense,
        'veg_non_veg' => vegNonVeg,
        'consumer_care' => consumerCare,
        'consumer_care_phone' => consumerCarePhone,
        'consumer_care_email' => consumerCareEmail,
        _ => null,
      };

  void _set(String k, Object v) {
    switch (k) {
      case 'product_name':
        productName = v as String;
      case 'brand':
        brand = v as String;
      case 'manufacturer_name':
        manufacturerName = v as String;
      case 'manufacturer_address':
        manufacturerAddress = v as String;
      case 'packer_name':
        packerName = v as String;
      case 'importer_name':
        importerName = v as String;
      case 'importer_address':
        importerAddress = v as String;
      case 'country_of_origin':
        countryOfOrigin = v as String;
      case 'net_quantity_raw':
        netQuantityRaw = v as String;
      case 'net_quantity_value':
        netQuantityValue = (v as num).toDouble();
      case 'net_quantity_unit':
        netQuantityUnit = v as String;
      case 'mrp_value':
        mrpValue = (v as num).toDouble();
      case 'mrp_currency':
        mrpCurrency = v as String;
      case 'manufacture_date':
        manufactureDate = v as String;
      case 'best_before':
        bestBefore = v as String;
      case 'fssai_license':
        fssaiLicense = v as String;
      case 'veg_non_veg':
        vegNonVeg = v as String;
      case 'consumer_care':
        consumerCare = v as String;
      case 'consumer_care_phone':
        consumerCarePhone = v as String;
      case 'consumer_care_email':
        consumerCareEmail = v as String;
    }
  }

  Map<String, dynamic> toJson() => {
        'gtin': gtin,
        'found': found,
        'sources': sources,
        'field_sources': fieldSources,
        'product_name': productName,
        'brand': brand,
        'manufacturer_name': manufacturerName,
        'manufacturer_address': manufacturerAddress,
        'country_of_origin': countryOfOrigin,
        'net_quantity_raw': netQuantityRaw,
        'net_quantity_value': netQuantityValue,
        'net_quantity_unit': netQuantityUnit,
        'mrp_value': mrpValue,
        'manufacture_date': manufactureDate,
        'fssai_license': fssaiLicense,
      };
}
