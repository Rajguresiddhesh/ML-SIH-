import 'package:flutter/material.dart';
import 'package:image_picker/image_picker.dart';

import '../compliance/audit.dart';
import '../compliance/models.dart';
import '../extraction/barcode_scanner.dart';
import '../extraction/label_ocr.dart';
import '../extraction/text_parser.dart';
import 'result_page.dart';
import 'settings.dart';

class HomePage extends StatefulWidget {
  const HomePage({super.key});

  @override
  State<HomePage> createState() => _HomePageState();
}

class _HomePageState extends State<HomePage> {
  final _picker = ImagePicker();
  final _barcodeCtrl = TextEditingController();
  final _barcodeService = BarcodeScannerService();
  final _ocrService = LabelOcrService();
  bool _busy = false;
  String _status = '';

  @override
  void dispose() {
    _barcodeCtrl.dispose();
    _barcodeService.dispose();
    _ocrService.dispose();
    super.dispose();
  }

  Future<void> _run(Future<ComplianceReport> Function() task) async {
    setState(() => _busy = true);
    try {
      final report = await task();
      if (!mounted) return;
      Navigator.of(context).push(
        MaterialPageRoute(builder: (_) => ResultPage(report: report)),
      );
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context)
            .showSnackBar(SnackBar(content: Text('Error: $e')));
      }
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _auditTypedBarcode() async {
    final code = _barcodeCtrl.text.trim();
    if (code.replaceAll(RegExp(r'\D'), '').length < 8) {
      ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Enter a valid bar code / GTIN.')));
      return;
    }
    final cfg = await Settings.load();
    await _run(() {
      setState(() => _status = 'Verifying GTIN and querying registries…');
      return runBarcodeAudit(code, lookupConfig: cfg);
    });
  }

  Future<void> _auditBarcodePhoto(ImageSource src) async {
    final file = await _picker.pickImage(source: src, imageQuality: 90);
    if (file == null) return;
    setState(() => _status = 'Decoding bar code…');
    final codes = await _barcodeService.scanFile(file.path);
    if (codes.isEmpty) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(content: Text('No bar code detected. Try a closer shot.')));
      }
      return;
    }
    _barcodeCtrl.text = codes.first.value;
    final cfg = await Settings.load();
    await _run(() {
      setState(() => _status = 'Auditing GTIN ${codes.first.value}…');
      return runBarcodeAudit(codes.first.value, lookupConfig: cfg);
    });
  }

  Future<void> _auditLabelPhoto(ImageSource src) async {
    final file = await _picker.pickImage(source: src, imageQuality: 95);
    if (file == null) return;
    final cfg = await Settings.load();
    await _run(() async {
      setState(() => _status = 'Reading label text…');
      final ocr = await _ocrService.recognise(file.path);
      final parsed = parseOcr(ocr);
      final pkg = toPackageData(parsed);
      // opportunistic bar code on the same photo
      final codes = await _barcodeService.scanFile(file.path);
      final barcode = codes.isNotEmpty ? codes.first.value : null;
      setState(() => _status = 'Running rulebook…');
      return runLabelAudit(pkg, barcode: barcode, lookupConfig: cfg);
    });
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Legal Metrology Checker'),
        actions: [
          IconButton(
            icon: const Icon(Icons.settings),
            onPressed: () => Navigator.of(context).push(
              MaterialPageRoute(builder: (_) => const _SettingsPage()),
            ),
          ),
        ],
      ),
      body: AbsorbPointer(
        absorbing: _busy,
        child: ListView(
          padding: const EdgeInsets.all(16),
          children: [
            Text('LM(PC) Rules 2011 — Rule 6 declarations',
                style: Theme.of(context).textTheme.titleMedium),
            const SizedBox(height: 4),
            Text(
              'Offline-first. The bar-code audit works without a network; '
              'product registries and GS1 India enrich it when online.',
              style: Theme.of(context).textTheme.bodySmall,
            ),
            const SizedBox(height: 20),
            _Section(
              title: 'Scan / enter a bar code',
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  TextField(
                    controller: _barcodeCtrl,
                    keyboardType: TextInputType.number,
                    decoration: const InputDecoration(
                      labelText: 'Bar code / GTIN (e.g. 8901030928239)',
                      border: OutlineInputBorder(),
                    ),
                  ),
                  const SizedBox(height: 10),
                  FilledButton.icon(
                    onPressed: _auditTypedBarcode,
                    icon: const Icon(Icons.rule),
                    label: const Text('Verify Every Declaration (Rules 2011)'),
                  ),
                  const SizedBox(height: 8),
                  Row(children: [
                    Expanded(
                      child: OutlinedButton.icon(
                        onPressed: () => _auditBarcodePhoto(ImageSource.camera),
                        icon: const Icon(Icons.camera_alt),
                        label: const Text('Camera'),
                      ),
                    ),
                    const SizedBox(width: 8),
                    Expanded(
                      child: OutlinedButton.icon(
                        onPressed: () => _auditBarcodePhoto(ImageSource.gallery),
                        icon: const Icon(Icons.photo_library),
                        label: const Text('Gallery'),
                      ),
                    ),
                  ]),
                ],
              ),
            ),
            const SizedBox(height: 16),
            _Section(
              title: 'Audit a label photo (on-device OCR)',
              child: Row(children: [
                Expanded(
                  child: OutlinedButton.icon(
                    onPressed: () => _auditLabelPhoto(ImageSource.camera),
                    icon: const Icon(Icons.camera_alt),
                    label: const Text('Capture label'),
                  ),
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: OutlinedButton.icon(
                    onPressed: () => _auditLabelPhoto(ImageSource.gallery),
                    icon: const Icon(Icons.photo_library),
                    label: const Text('Pick label'),
                  ),
                ),
              ]),
            ),
            if (_busy) ...[
              const SizedBox(height: 24),
              const Center(child: CircularProgressIndicator()),
              const SizedBox(height: 8),
              Center(child: Text(_status)),
            ],
          ],
        ),
      ),
    );
  }
}

class _Section extends StatelessWidget {
  final String title;
  final Widget child;
  const _Section({required this.title, required this.child});

  @override
  Widget build(BuildContext context) {
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(14),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(title, style: Theme.of(context).textTheme.titleSmall),
            const SizedBox(height: 12),
            child,
          ],
        ),
      ),
    );
  }
}

class _SettingsPage extends StatefulWidget {
  const _SettingsPage();
  @override
  State<_SettingsPage> createState() => _SettingsPageState();
}

class _SettingsPageState extends State<_SettingsPage> {
  final _keyCtrl = TextEditingController();
  final _urlCtrl = TextEditingController();

  @override
  void initState() {
    super.initState();
    Settings.load().then((c) {
      _keyCtrl.text = c.gs1IndiaKey ?? '';
      _urlCtrl.text = c.gs1IndiaUrlTemplate;
      setState(() {});
    });
  }

  @override
  void dispose() {
    _keyCtrl.dispose();
    _urlCtrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Settings')),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          const Text('GS1 India / DataKart (optional)'),
          const SizedBox(height: 8),
          TextField(
            controller: _keyCtrl,
            decoration: const InputDecoration(
                labelText: 'GS1 India API key', border: OutlineInputBorder()),
          ),
          const SizedBox(height: 12),
          TextField(
            controller: _urlCtrl,
            decoration: const InputDecoration(
                labelText: 'GS1 India URL template ({gtin})',
                border: OutlineInputBorder()),
          ),
          const SizedBox(height: 16),
          FilledButton(
            onPressed: () async {
              await Settings.save(
                  gs1Key: _keyCtrl.text.trim(), gs1Url: _urlCtrl.text.trim());
              if (context.mounted) Navigator.pop(context);
            },
            child: const Text('Save'),
          ),
          const SizedBox(height: 16),
          Text(
            'Without a key the free registries (Open Food Facts, UPCItemDB, '
            'Wikidata) are used. Everything still works fully offline from the '
            'GTIN structure alone.',
            style: Theme.of(context).textTheme.bodySmall,
          ),
        ],
      ),
    );
  }
}
