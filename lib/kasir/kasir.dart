// ignore_for_file: prefer_final_fields

import 'package:flutter/material.dart';
import 'package:kastra/scanner.dart';
import 'package:kastra/services.dart';
import 'package:kastra/theme.dart';
import 'package:kastra/widgets.dart';
import 'package:pdf/pdf.dart';
import 'package:pdf/widgets.dart' as pw;
import 'package:printing/printing.dart';

// ignore_for_file: deprecated_member_use, use_build_context_synchronously

class KasirPage extends StatefulWidget {
  final int userId;
  const KasirPage({super.key, required this.userId});

  @override
  State<KasirPage> createState() => _KasirPageState();
}

class _KasirPageState extends State<KasirPage> {
  final _search = TextEditingController();
  List<Map<String, dynamic>> _produk = [], _cats = [], _cart = [];
  String? _cat;
  String _name = 'Kasir';
  Map<String, dynamic>? _toko;

  @override
  void initState() {
    super.initState();
    _refresh();
    DB.getUser(widget.userId).then((u) {
      if (mounted && u != null) setState(() => _name = u['nama_lengkap'] ?? 'Kasir');
    });
    DB.toko.then((t) {
      if (mounted) setState(() => _toko = t);
    });
  }

  Future<void> _refresh() async {
    try {
      final p = await DB.products;
      final c = await DB.categories;
      if (mounted) {
        setState(() {
          _produk = p;
          _cats = c;
        });
      }
    } catch (e) {
      debugPrint('$e');
    }
  }

  List<Map<String, dynamic>> get _list {
    final q = _search.text.toLowerCase();
    return _produk.where((p) {
      if (!(p['is_active'] ?? true)) return false;
      if (_cat != null && p['kategori'] != _cat) return false;
      if (q.isEmpty) return true;
      return (p['nama_produk'] ?? '').toString().toLowerCase().contains(q) || (p['barcode'] ?? '').toString().contains(q);
    }).toList();
  }

  int get _total => _cart.fold<int>(0, (a, i) => a + ((i['harga_jual'] ?? 0) as int) * ((i['qty'] ?? 0) as int));

  void _add(Map<String, dynamic> p) {
    final stok = (p['stok'] ?? 0) as int;
    if (stok <= 0) {
      snack(context, 'Stok habis', err: true);
      return;
    }
    final i = _cart.indexWhere((c) => c['id_produk'] == p['id_produk']);
    if (i != -1 && (_cart[i]['qty'] as int) >= stok) {
      snack(context, 'Stok tidak mencukupi', err: true);
      return;
    }
    setState(() {
      if (i == -1) {
        _cart.add({...p, 'qty': 1});
      } else {
        _cart[i]['qty']++;
      }
    });
  }

  Future<void> _scan() async {
    final items = await Navigator.push<List<Map<String, dynamic>>>(
        context, MaterialPageRoute(builder: (_) => ScanContinuous(products: _produk.where((p) => (p['is_active'] ?? true)).toList())));
    if (items == null || items.isEmpty || !mounted) return;
    setState(() {
      for (final it in items) {
        final i = _cart.indexWhere((c) => c['id_produk'] == it['id_produk']);
        if (i == -1) {
          _cart.add({...it});
        } else {
          _cart[i]['qty'] = ((_cart[i]['qty'] as int) + (it['qty'] as int)).clamp(0, (it['stok'] ?? 0) as int);
        }
      }
      _cart.removeWhere((c) => (c['qty'] ?? 0) <= 0);
    });
    _refresh();
  }

  Future<void> _editQty(int i) async {
    final v = await askQty(context, current: _cart[i]['qty'] ?? 1, max: _cart[i]['stok'] ?? 0);
    if (v == null || !mounted) return;
    setState(() {
      if (v <= 0) {
        _cart.removeAt(i);
      } else {
        _cart[i]['qty'] = v.clamp(1, (_cart[i]['stok'] ?? 1) as int);
      }
    });
  }

  Future<void> _pay() async {
    if (_cart.isEmpty) {
      snack(context, 'Keranjang kosong', err: true);
      return;
    }
    final ctrl = TextEditingController();
    final discCtrl = TextEditingController();
    int uang = 0;
    int diskon = 0;
    String metode = 'tunai';

    final ok = await showDialog<bool>(
      context: context,
      builder: (d) => StatefulBuilder(
        builder: (d, ss) {
          final totalDiskon = (diskon > _total) ? _total : diskon;
          final tagihan = _total - totalDiskon;
          final back = uang - tagihan;
          return AlertDialog(
            title: const Text('Pembayaran', textAlign: TextAlign.center),
            content: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.start, children: [
              Container(
                width: double.infinity,
                padding: const EdgeInsets.all(14),
                decoration: BoxDecoration(color: C.fieldFill, borderRadius: BorderRadius.circular(12), border: Border.all(color: C.border)),
                child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                  Row(mainAxisAlignment: MainAxisAlignment.spaceBetween, children: [
                    const Text('Subtotal', style: TextStyle(fontSize: 12.5, fontWeight: FontWeight.w600, color: C.sub)),
                    Text(rp(_total), style: const TextStyle(fontSize: 14, fontWeight: FontWeight.w700, color: C.ink)),
                  ]),
                  if (totalDiskon > 0) ...[
                    const SizedBox(height: 4),
                    Row(mainAxisAlignment: MainAxisAlignment.spaceBetween, children: [
                      const Text('Diskon', style: TextStyle(fontSize: 12.5, fontWeight: FontWeight.w600, color: C.red)),
                      Text('-${rp(totalDiskon)}', style: const TextStyle(fontSize: 14, fontWeight: FontWeight.w700, color: C.red)),
                    ]),
                    const SizedBox(height: 4),
                  ],
                  Row(mainAxisAlignment: MainAxisAlignment.spaceBetween, children: [
                    const Text('Total Tagihan', style: TextStyle(fontSize: 12.5, fontWeight: FontWeight.w600, color: C.sub)),
                    Text(rp(tagihan), style: const TextStyle(fontSize: 15, fontWeight: FontWeight.w800, color: C.ink)),
                  ]),
                ]),
              ),
              const SizedBox(height: 12),
              // Metode pembayaran — non-tunai tidak perlu uang diterima.
              Wrap(spacing: 8, children: ['tunai', 'qris', 'debit'].map((m) {
                final sel = metode == m;
                return ChoiceChip(
                  label: Text(m.toUpperCase()),
                  selected: sel,
                  onSelected: (_) => ss(() => metode = m),
                );
              }).toList()),
              const SizedBox(height: 10),
              TextField(
                controller: discCtrl,
                keyboardType: TextInputType.number,
                decoration: const InputDecoration(labelText: 'Diskon (Rp, opsional)', prefixText: 'Rp '),
                onChanged: (v) => ss(() => diskon = int.tryParse(v.replaceAll('.', '')) ?? 0),
              ),
              if (metode == 'tunai') ...[
                const SizedBox(height: 10),
                TextField(
                  controller: ctrl,
                  autofocus: true,
                  keyboardType: TextInputType.number,
                  decoration: const InputDecoration(labelText: 'Uang Diterima', prefixText: 'Rp '),
                  onChanged: (v) => ss(() => uang = int.tryParse(v.replaceAll('.', '')) ?? 0),
                ),
                const SizedBox(height: 12),
                Container(
                  width: double.infinity,
                  padding: const EdgeInsets.all(14),
                  decoration: BoxDecoration(
                    color: back < 0 ? C.redBg : C.greenBg,
                    borderRadius: BorderRadius.circular(12),
                    border: Border.all(color: back < 0 ? C.redBorder : const Color(0xFFBBF7D0)),
                  ),
                  child: Row(mainAxisAlignment: MainAxisAlignment.spaceBetween, children: [
                    const Text('Kembalian', style: TextStyle(fontSize: 12.5, fontWeight: FontWeight.w600, color: C.sub)),
                    Text(rp(back < 0 ? 0 : back), style: TextStyle(fontSize: 15, fontWeight: FontWeight.w800, color: back < 0 ? C.red : C.green)),
                  ]),
                ),
              ],
            ]),
            actions: [
              SizedBox(
                width: double.infinity,
                height: 52,
                child: ElevatedButton(
                  onPressed: (metode == 'tunai' ? uang >= tagihan : true) ? () => Navigator.pop(d, true) : null,
                  child: const Text('Bayar'),
                ),
              ),
            ],
          );
        },
      ),
    );
    if (ok == true) _process(uang, List<Map<String, dynamic>>.from(_cart), diskon, metode);
  }

  /// Proses penjualan via DB.commitSale — atomik (header + detail + stok FEFO).
  Future<void> _process(int uang, List<Map<String, dynamic>> cart, int diskonIn, String metode) async {
    showDialog(context: context, barrierDismissible: false, builder: (_) => const Center(child: CircularProgressIndicator(color: C.primary)));
    try {
      final subTotal = cart.fold<int>(0, (a, i) => a + (i['harga_jual'] as int) * (i['qty'] as int));
      final diskon = diskonIn.clamp(0, subTotal);
      final trx = await DB.commitSale(
        userId: widget.userId,
        items: cart.map((i) => {
          'id_produk': i['id_produk'],
          'qty': i['qty'],
          'harga_jual': i['harga_jual'],
          'nama_produk': i['nama_produk'],
        }).toList(),
        diskon: diskon,
        pajak: 0,
        uangDiterima: metode == 'tunai' ? uang : subTotal - diskon,
        metode: metode,
      );
      if (trx == null) throw Exception(DB.lastError ?? 'Gagal menyimpan transaksi');

      if (!mounted) return;
      Navigator.of(context, rootNavigator: true).pop();
      setState(() => _cart.clear());
      _refresh();
      snack(context, 'Transaksi berhasil');
      await _receipt(trx, cart);
    } catch (e) {
      debugPrint('$e');
      if (mounted) {
        Navigator.of(context, rootNavigator: true).pop();
        snack(context, 'Gagal: ${DB.lastError ?? e}', err: true);
      }
    }
  }

  Future<void> _receipt(Map trx, List<Map<String, dynamic>> items) async {
    try {
      final pdf = pw.Document();
      pw.Widget row(String l, dynamic v, {bool bold = false}) => pw.Padding(
            padding: const pw.EdgeInsets.only(top: 3),
            child: pw.Row(mainAxisAlignment: pw.MainAxisAlignment.spaceBetween, children: [
              pw.Text(l, style: pw.TextStyle(fontSize: bold ? 10 : 9, fontWeight: bold ? pw.FontWeight.bold : pw.FontWeight.normal)),
              pw.Text(rp(v), style: pw.TextStyle(fontSize: bold ? 10 : 9, fontWeight: bold ? pw.FontWeight.bold : pw.FontWeight.normal)),
            ]),
          );
      pdf.addPage(pw.Page(
        pageFormat: PdfPageFormat.roll80,
        margin: const pw.EdgeInsets.all(10),
        build: (c) => pw.Column(crossAxisAlignment: pw.CrossAxisAlignment.center, children: [
          // Nama & alamat toko dari data pendaftaran
          pw.Text((_toko?['nama_toko'] ?? 'KASTRA').toString(),
              style: pw.TextStyle(fontSize: 20, fontWeight: pw.FontWeight.bold)),
          if (_toko?['alamat'] != null && _toko!['alamat'].toString().isNotEmpty)
            pw.Text(_toko!['alamat'].toString(), style: const pw.TextStyle(fontSize: 8)),
          pw.Divider(),
          pw.Text('${trx['no_transaksi']} · ${fdate(trx['tanggal'], 'dd/MM/yy HH:mm')}\nKasir: $_name', textAlign: pw.TextAlign.center, style: const pw.TextStyle(fontSize: 8)),
          pw.Divider(),
          ...items.map((i) => pw.Padding(
                padding: const pw.EdgeInsets.only(bottom: 3),
                child: pw.Row(crossAxisAlignment: pw.CrossAxisAlignment.start, children: [
                  pw.Expanded(child: pw.Text('${i['nama_produk']}', style: const pw.TextStyle(fontSize: 9))),
                  pw.Text('${i['qty']}x ${fmt(i['harga_jual'])}', style: const pw.TextStyle(fontSize: 9)),
                ]),
              )),
          pw.Divider(),
          row('TOTAL', trx['total_bayar'], bold: true),
          row('BAYAR', trx['uang_diterima']),
          row('KEMBALIAN', trx['kembalian'], bold: true),
          pw.SizedBox(height: 10),
          pw.Center(child: pw.Text('*** TERIMA KASIH ***', style: pw.TextStyle(fontWeight: pw.FontWeight.bold, fontSize: 9))),
        ]),
      ));
      await Printing.layoutPdf(onLayout: (f) => pdf.save(), name: 'Struk_${trx['no_transaksi']}.pdf');
    } catch (e) {
      debugPrint('pdf: $e');
    }
  }

  @override
  Widget build(BuildContext context) => Scaffold(
        appBar: AppBar(title: const Text('Transaksi Kasir')),
        drawer: AppDrawer(userId: widget.userId, role: 'kasir'),
        body: Column(children: [
          Padding(
            padding: const EdgeInsets.all(16),
            child: Row(children: [
              Expanded(child: SearchField(_search, hint: 'Cari produk / barcode...', onChanged: () => setState(() {}))),
              const SizedBox(width: 10),
              InkWell(
                onTap: _scan,
                borderRadius: BorderRadius.circular(14),
                child: Container(
                  width: 54,
                  height: 54,
                  decoration: BoxDecoration(color: Colors.white, borderRadius: BorderRadius.circular(14), border: Border.all(color: C.border)),
                  child: const Icon(Icons.qr_code_scanner, color: C.primary, size: 24),
                ),
              ),
            ]),
          ),
          SizedBox(
            height: 40,
            child: ListView(scrollDirection: Axis.horizontal, padding: const EdgeInsets.symmetric(horizontal: 16), children: [
              FChip('Semua', selected: _cat == null, onTap: () => setState(() => _cat = null)),
              ..._cats.map((c) => FChip('${c['nama_kategori']}', selected: _cat == c['nama_kategori'], onTap: () => setState(() => _cat = c['nama_kategori']))),
            ]),
          ),
          Expanded(
            child: _list.isEmpty
                ? const Center(child: Text('Produk tidak ditemukan', style: TextStyle(color: C.sub)))
                : ListView.builder(
                    padding: const EdgeInsets.fromLTRB(16, 10, 16, 10),
                    itemCount: _list.length,
                    itemBuilder: (c, i) {
                      final p = _list[i];
                      final stok = p['stok'] ?? 0;
                      final out = stok == 0;
                      return Container(
                        margin: const EdgeInsets.only(bottom: 10),
                        padding: const EdgeInsets.all(10),
                        decoration: BoxDecoration(color: Colors.white, borderRadius: BorderRadius.circular(16), border: Border.all(color: C.border)),
                        child: Row(children: [
                          ProductImage(p['gambar'], size: 52),
                          const SizedBox(width: 12),
                          Expanded(
                            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                              Text(p['nama_produk'] ?? '-',
                                  style: const TextStyle(fontSize: 13.5, fontWeight: FontWeight.w700, color: C.ink),
                                  maxLines: 1,
                                  overflow: TextOverflow.ellipsis),
                              const SizedBox(height: 3),
                              Text(rp(p['harga_jual']), style: const TextStyle(fontSize: 12.5, fontWeight: FontWeight.w700, color: C.primary)),
                              const SizedBox(height: 5),
                              Pill('Stok: $stok', fg: out ? C.red : (stok < 10 ? C.orange : C.green)),
                            ]),
                          ),
                          IconBox(
                            Icons.add,
                            color: out ? C.iconIdle : C.primary,
                            size: 22,
                            onTap: out ? null : () => _add(p),
                          ),
                        ]),
                      );
                    },
                  ),
          ),
          _cartBar(),
        ]),
      );

  Widget _cartBar() => Container(
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: const BorderRadius.vertical(top: Radius.circular(20)),
          border: Border(top: BorderSide(color: C.border)),
          boxShadow: [BoxShadow(color: C.ink.withOpacity(.04), blurRadius: 10, offset: const Offset(0, -4))],
        ),
        child: Column(mainAxisSize: MainAxisSize.min, children: [
          Center(
            child: Container(
              width: 40,
              height: 4,
              margin: const EdgeInsets.only(top: 10),
              decoration: BoxDecoration(color: C.border, borderRadius: BorderRadius.circular(2)),
            ),
          ),
          if (_cart.isEmpty)
            const Padding(padding: EdgeInsets.all(14), child: Text('Keranjang kosong', style: TextStyle(color: C.sub, fontSize: 13)))
          else
            ConstrainedBox(
              constraints: const BoxConstraints(maxHeight: 180),
              child: ListView.builder(
                shrinkWrap: true,
                padding: const EdgeInsets.symmetric(horizontal: 12),
                itemCount: _cart.length,
                itemBuilder: (c, i) {
                  final it = _cart[i];
                  return ListTile(
                    dense: true,
                    contentPadding: const EdgeInsets.symmetric(horizontal: 4),
                    title: Text('${it['nama_produk']}',
                        style: const TextStyle(fontSize: 12.5, fontWeight: FontWeight.w700, color: C.ink),
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis),
                    subtitle: Text(rp(it['harga_jual']), style: const TextStyle(fontSize: 11, color: C.primary, fontWeight: FontWeight.w600)),
                    trailing: Row(mainAxisSize: MainAxisSize.min, children: [
                      IconBox(Icons.remove, color: C.red, size: 17, onTap: () => setState(() {
                            if ((it['qty'] as int) > 1) {
                              it['qty']--;
                            } else {
                              _cart.removeAt(i);
                            }
                          })),
                      const SizedBox(width: 6),
                      InkWell(
                        onTap: () => _editQty(i),
                        borderRadius: BorderRadius.circular(8),
                        child: Container(
                          padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                          decoration: BoxDecoration(color: C.fieldFill, borderRadius: BorderRadius.circular(8), border: Border.all(color: C.border)),
                          child: Text('${it['qty']}', style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w800)),
                        ),
                      ),
                      const SizedBox(width: 6),
                      IconBox(Icons.add, color: C.green, size: 17, onTap: () => setState(() {
                            if ((it['qty'] as int) < ((it['stok'] ?? 0) as int)) it['qty']++;
                          })),
                    ]),
                  );
                },
              ),
            ),
          const Divider(height: 1),
          Padding(
            padding: const EdgeInsets.all(14),
            child: Row(children: [
              Expanded(
                child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                  const Text('Total', style: TextStyle(fontSize: 11, fontWeight: FontWeight.w600, color: C.sub)),
                  FittedBox(child: Text(rp(_total), style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w800, color: C.ink))),
                ]),
              ),
              const SizedBox(width: 12),
              SizedBox(
                width: 130,
                height: 50,
                child: ElevatedButton(onPressed: _pay, child: const Text('Bayar')),
              ),
            ]),
          ),
        ]),
      );
}