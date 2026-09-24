// Pengaturan toko: pajak, ambang stok menipis, nama perangkat kasir.
import 'package:flutter/material.dart';
import 'package:kastra/services.dart';
import 'package:kastra/theme.dart';
import 'package:kastra/widgets.dart';

class PengaturanPage extends StatefulWidget {
  final int userId;
  const PengaturanPage({super.key, required this.userId});

  @override
  State<PengaturanPage> createState() => _PengaturanPageState();
}

class _PengaturanPageState extends State<PengaturanPage> {
  final _tax = TextEditingController();
  final _low = TextEditingController();
  final _dev = TextEditingController();
  bool _load = true;
  bool _saving = false;

  @override
  void initState() {
    super.initState();
    _loadAll();
  }

  Future<void> _loadAll() async {
    final t = await DB.getSetting('tax_percent');
    final l = await DB.getSetting('low_stock');
    final d = await DB.getSetting('device_name');
    if (!mounted) return;
    setState(() {
      _tax.text = t ?? '0';
      _low.text = l ?? '10';
      _dev.text = d ?? 'Kasir 1';
      _load = false;
    });
  }

  @override
  void dispose() {
    _tax.dispose();
    _low.dispose();
    _dev.dispose();
    super.dispose();
  }

  Future<void> _save() async {
    setState(() => _saving = true);
    // validasi berurutan — berhenti di error pertama
    final errs = <String?>[
      await DB.setSettingValidated('tax_percent', _tax.text, min: 0, max: 100),
      await DB.setSettingValidated('low_stock', _low.text, min: 1, max: 9999),
      _dev.text.trim().isEmpty ? 'Nama perangkat tidak boleh kosong' : null,
    ];
    for (final e in errs) {
      if (e != null) {
        if (mounted) snack(context, e, err: true);
        setState(() => _saving = false);
        return;
      }
    }
    await DB.setSetting('device_name', _dev.text.trim());
    await DB.log(widget.userId, 'Mengubah pengaturan toko (pajak ${_tax.text}% / batas stok ${_low.text})');
    if (!mounted) return;
    setState(() => _saving = false);
    snack(context, 'Pengaturan tersimpan');
  }

  Widget _field(String label, TextEditingController c, {String suffix = '', TextInputType? kb}) => Padding(
        padding: const EdgeInsets.only(bottom: 16),
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Text(label, style: const TextStyle(fontSize: 12.5, fontWeight: FontWeight.w700, color: C.label)),
          const SizedBox(height: 6),
          TextField(
            controller: c,
            keyboardType: kb,
            decoration: InputDecoration(
              hintText: label,
              suffixText: suffix.isEmpty ? null : suffix,
              filled: true,
              fillColor: C.fieldFill,
              border: OutlineInputBorder(borderRadius: BorderRadius.circular(12), borderSide: const BorderSide(color: C.border)),
              enabledBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(12), borderSide: const BorderSide(color: C.border)),
              focusedBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(12), borderSide: const BorderSide(color: C.primary, width: 1.4)),
              contentPadding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
            ),
          ),
        ]),
      );

  @override
  Widget build(BuildContext context) => Scaffold(
        appBar: AppBar(title: const Text('Pengaturan Toko')),
        drawer: AppDrawer(userId: widget.userId, role: 'admin'),
        body: _load
            ? const Center(child: CircularProgressIndicator(color: C.primary))
            : ListView(padding: const EdgeInsets.all(16), children: [
                const CardX(
                  padding: EdgeInsets.all(14),
                  child: Row(children: [
                    Icon(Icons.info_outline, color: C.primary, size: 20),
                    SizedBox(width: 10),
                    Expanded(
                      child: Text('Nilai pajak & batas stok berlaku untuk seluruh transaksi di perangkat ini.',
                          style: TextStyle(fontSize: 12, color: C.sub)),
                    ),
                  ]),
                ),
                const SizedBox(height: 20),
                const Text('Pajak & Stok', style: TextStyle(fontSize: 15, fontWeight: FontWeight.w800, color: C.ink)),
                const SizedBox(height: 12),
                CardX(
                  padding: const EdgeInsets.all(16),
                  child: Column(children: [
                    _field('Pajak penjualan (%)', _tax, suffix: '%', kb: TextInputType.number),
                    _field('Batas "stok menipis" (pcs)', _low, suffix: 'pcs', kb: TextInputType.number),
                  ]),
                ),
                const SizedBox(height: 24),
                const Text('Perangkat Kasir', style: TextStyle(fontSize: 15, fontWeight: FontWeight.w800, color: C.ink)),
                const SizedBox(height: 12),
                CardX(
                  padding: const EdgeInsets.all(16),
                  child: _field('Nama perangkat (tampil di struk)', _dev),
                ),
                const SizedBox(height: 28),
                FilledButton.icon(
                  onPressed: _saving ? null : _save,
                  icon: const Icon(Icons.save_outlined),
                  label: Text(_saving ? 'Menyimpan…' : 'Simpan Pengaturan'),
                  style: FilledButton.styleFrom(
                    minimumSize: const Size(double.infinity, 50),
                    backgroundColor: C.primary,
                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
                  ),
                ),
                const SizedBox(height: 30),
              ]),
      );
}
