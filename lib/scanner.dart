import 'dart:async';
import 'package:flutter/material.dart';
import 'package:kastra/theme.dart';
import 'package:kastra/widgets.dart';
import 'package:mobile_scanner/mobile_scanner.dart';

// ignore_for_file: deprecated_member_use

/// Scanner sekali-scan, mengembalikan string barcode.
class ScanSingle extends StatefulWidget {
  const ScanSingle({super.key});

  @override
  State<ScanSingle> createState() => _ScanSingleState();
}

class _ScanSingleState extends State<ScanSingle> {
  bool _done = false;

  void _onDetect(BarcodeCapture cap) {
    if (_done) return;
    final code = cap.barcodes.firstOrNull?.rawValue;
    if (code == null || code.isEmpty) return;
    _done = true;
    Navigator.pop(context, code);
  }

  @override
  Widget build(BuildContext context) => Scaffold(
        backgroundColor: Colors.black,
        appBar: AppBar(title: const Text('Scan Barcode'), backgroundColor: Colors.black, foregroundColor: Colors.white),
        body: Stack(children: [
          MobileScanner(onDetect: _onDetect),
          Center(child: Container(width: 280, height: 160, decoration: BoxDecoration(border: Border.all(color: Colors.white, width: 3), borderRadius: BorderRadius.circular(16)))),
          const Positioned(bottom: 40, left: 0, right: 0, child: Text('Arahkan kamera ke barcode', textAlign: TextAlign.center, style: TextStyle(color: Colors.white))),
        ]),
      );
}

/// Scanner berkelanjutan untuk kasir. Mengembalikan list produk + qty.
class ScanContinuous extends StatefulWidget {
  final List<Map<String, dynamic>> products;
  const ScanContinuous({super.key, required this.products});

  @override
  State<ScanContinuous> createState() => _ScanContinuousState();
}

class _ScanContinuousState extends State<ScanContinuous> {
  final Map<int, Map<String, dynamic>> _picked = {};
  DateTime? _last;
  String? _msg;
  Timer? _msgTimer;

  /// Tampilkan pesan di banner layar scan (bukan snackbar, agar tidak saling menimpa).
  void _showMsg(String m) {
    _msgTimer?.cancel();
    setState(() => _msg = m);
    _msgTimer = Timer(const Duration(seconds: 3), () {
      if (mounted) setState(() => _msg = null);
    });
  }

  void _onDetect(BarcodeCapture cap) {
    final code = cap.barcodes.firstOrNull?.rawValue;
    if (code == null) return;
    final now = DateTime.now();
    if (_last != null && now.difference(_last!) < const Duration(milliseconds: 800)) return;
    _last = now;

    final p = widget.products.where((m) => (m['barcode'] ?? '').toString() == code).firstOrNull;
    if (p == null) {
      _showMsg('Barcode tidak terdaftar: $code');
      return;
    }

    final stok = (p['stok'] ?? 0) as int;
    final id = p['id_produk'] as int;
    final item = _picked[id];
    if (item == null) {
      if (stok > 0) {
        setState(() => _picked[id] = {...p, 'qty': 1});
      } else {
        _showMsg('Stok ${p['nama_produk']} habis');
      }
    } else if ((item['qty'] as int) < stok) {
      setState(() => item['qty']++);
    } else {
      _showMsg('Stok maksimal tercapai: ${p['nama_produk']}');
    }
  }

  Future<void> _editQty(int id) async {
    final item = _picked[id]!;
    final v = await askQty(context, current: item['qty'], max: item['stok'] ?? 0);
    if (v == null || !mounted) return;
    setState(() {
      if (v <= 0) {
        _picked.remove(id);
      } else {
        item['qty'] = v.clamp(1, (item['stok'] ?? 1) as int);
      }
    });
  }

  @override
  void dispose() {
    _msgTimer?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => Scaffold(
        appBar: AppBar(
          title: const Text('Scan Barang'),
          backgroundColor: C.primary,
          foregroundColor: Colors.white,
          actions: [IconButton(icon: const Icon(Icons.check), onPressed: () => Navigator.pop(context, _picked.values.map((m) => Map<String, dynamic>.from(m)).toList()))],
        ),
        body: Column(children: [
          Expanded(
            flex: 2,
            child: Stack(children: [
              MobileScanner(onDetect: _onDetect),
              Center(child: Container(width: 250, height: 150, decoration: BoxDecoration(border: Border.all(color: Colors.red, width: 2), borderRadius: BorderRadius.circular(12)))),
            ]),
          ),
          if (_msg != null)
            Container(
              width: double.infinity,
              color: C.redBg,
              padding: const EdgeInsets.symmetric(vertical: 8, horizontal: 12),
              child: Text(_msg!,
                  textAlign: TextAlign.center,
                  style: const TextStyle(color: C.red, fontSize: 12.5, fontWeight: FontWeight.w700)),
            ),
          Expanded(
            child: _picked.isEmpty
                ? const Center(child: Text('Scan ulang barang untuk menambah qty', style: TextStyle(color: Colors.grey)))
                : ListView.builder(
                    itemCount: _picked.length,
                    itemBuilder: (c, i) {
                      final item = _picked.values.elementAt(i);
                      final id = item['id_produk'] as int;
                      return ListTile(
                        title: Text('${item['nama_produk']}', style: const TextStyle(fontWeight: FontWeight.w600)),
                        subtitle: Text('Stok: ${item['stok']}', style: const TextStyle(fontSize: 11)),
                        trailing: Row(mainAxisSize: MainAxisSize.min, children: [
                          IconButton(icon: const Icon(Icons.remove_circle_outline, color: C.red), onPressed: () => setState(() {
                                if ((item['qty'] as int) > 1) {
                                  item['qty']--;
                                } else {
                                  _picked.remove(id);
                                }
                              })),
                          InkWell(onTap: () => _editQty(id), child: Container(padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4), decoration: BoxDecoration(border: Border.all(color: Colors.grey.shade300)), child: Text('${item['qty']}', style: const TextStyle(fontWeight: FontWeight.bold)))),
                          IconButton(icon: const Icon(Icons.add_circle_outline, color: C.green), onPressed: () => setState(() {
                                if ((item['qty'] as int) < ((item['stok'] ?? 0) as int)) item['qty']++;
                              })),
                        ]),
                      );
                    },
                  ),
          ),
        ]),
      );
}