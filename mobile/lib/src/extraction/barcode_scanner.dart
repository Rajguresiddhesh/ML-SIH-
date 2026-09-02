/// On-device bar code decoding via Google ML Kit (offline after model install).
library;

import 'package:google_mlkit_barcode_scanning/google_mlkit_barcode_scanning.dart';

class ScannedBarcode {
  final String value;
  final String format; // ML Kit format name
  const ScannedBarcode(this.value, this.format);
}

class BarcodeScannerService {
  final BarcodeScanner _scanner = BarcodeScanner(formats: [
    BarcodeFormat.ean13,
    BarcodeFormat.ean8,
    BarcodeFormat.upca,
    BarcodeFormat.upce,
    BarcodeFormat.code128,
    BarcodeFormat.code39,
    BarcodeFormat.itf,
    BarcodeFormat.qrCode,
  ]);

  /// Decode every bar code in the image at [imagePath].
  Future<List<ScannedBarcode>> scanFile(String imagePath) async {
    final input = InputImage.fromFilePath(imagePath);
    final barcodes = await _scanner.processImage(input);
    return [
      for (final b in barcodes)
        if ((b.rawValue ?? b.displayValue ?? '').trim().isNotEmpty)
          ScannedBarcode(
            (b.rawValue ?? b.displayValue!).trim(),
            b.format.name,
          ),
    ];
  }

  Future<void> dispose() => _scanner.close();
}
