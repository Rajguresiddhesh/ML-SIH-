/// On-device label OCR via Google ML Kit Text Recognition.
///
/// Runs the Latin script recogniser and, when available, the Devanagari
/// recogniser (for the Hindi declarations required by Rule 9), then returns the
/// combined block text plus per-line geometry used by the commodity-name
/// heuristic.
library;

import 'package:google_mlkit_text_recognition/google_mlkit_text_recognition.dart';

class OcrLine {
  final String text;
  final double top;
  final double height;
  const OcrLine(this.text, this.top, this.height);
}

class OcrResult {
  final String fullText;
  final List<OcrLine> lines;
  final bool hasDevanagari;
  final bool hasLatin;
  const OcrResult(this.fullText, this.lines, this.hasDevanagari, this.hasLatin);
}

class LabelOcrService {
  final TextRecognizer _latin = TextRecognizer(script: TextRecognitionScript.latin);
  final TextRecognizer _devanagari =
      TextRecognizer(script: TextRecognitionScript.devanagiri);

  Future<OcrResult> recognise(String imagePath) async {
    final input = InputImage.fromFilePath(imagePath);

    final results = <RecognizedText>[];
    try {
      results.add(await _latin.processImage(input));
    } catch (_) {/* keep going */}
    try {
      results.add(await _devanagari.processImage(input));
    } catch (_) {/* Devanagari model may be unavailable */}

    final lines = <OcrLine>[];
    final buf = StringBuffer();
    for (final rt in results) {
      for (final block in rt.blocks) {
        for (final line in block.lines) {
          buf.writeln(line.text);
          lines.add(OcrLine(
            line.text,
            line.boundingBox.top,
            line.boundingBox.height,
          ));
        }
      }
    }

    final text = buf.toString();
    final hasDev = RegExp(r'[ऀ-ॿ]').hasMatch(text);
    final hasLat = RegExp(r'[A-Za-z]').hasMatch(text);
    return OcrResult(text, lines, hasDev, hasLat);
  }

  Future<void> dispose() async {
    await _latin.close();
    await _devanagari.close();
  }
}
