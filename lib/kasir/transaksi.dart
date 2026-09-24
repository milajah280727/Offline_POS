import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:kastra/services.dart';
import 'package:kastra/theme.dart';
import 'package:kastra/widgets.dart';

// ignore_for_file: deprecated_member_use

/// Riwayat transaksi (kasir) & laporan transaksi (owner, semua: true).
class TransaksiPage extends StatefulWidget {
  final int userId;
  final bool semua;
  const TransaksiPage({super.key, required this.userId, this.semua = false});

  @override
  State<TransaksiPage> createState() => _TransaksiPageState();
}

class _TransaksiPageState extends State<TransaksiPage> {
  final _search = TextEditingController();
  List<Map<String, dynamic>> _trx = [], _list = [];
  DateTime? _start, _end;
  bool _load = true;

  @override
  void initState() {
    super.initState();
    _fetch();
  }

  Future<void> _fetch() async {
    setState(() => _load = true);
    try {
      final data = await DB.transaksi(
        userId: widget.semua ? null : widget.userId,
        start: _start,
        end: _end,
      );
      if (mounted) {
        setState(() {
          _trx = data;
          _list = _trx;
          _load = false;
        });
      }
    } catch (e) {
      debugPrint('$e');
      if (mounted) setState(() => _load = false);
    }
  }

  void _filterSearch() {
    final q = _search.text.toLowerCase();
    setState(() {
      _list = q.isEmpty
          ? _trx
          : _trx.where((t) => (t['no_transaksi'] ?? '').toString().toLowerCase().contains(q) || t['total_bayar'].toString().contains(q)).toList();
    });
  }

  int get _omset => _list.fold<int>(0, (a, t) => a + ((t['total_bayar'] ?? 0) as int));

  Future<void> _pick(bool start) async {
    final d = await showDatePicker(context: context, initialDate: DateTime.now(), firstDate: DateTime(2020), lastDate: DateTime.now());
    if (d == null) return;
    setState(() {
      if (start) {
        _start = d;
        if (_end != null && _end!.isBefore(d)) _end = d;
      } else {
        _end = d;
        if (_start != null && _start!.isAfter(d)) _start = d;
      }
    });
    _fetch();
  }

  @override
  Widget build(BuildContext context) => Scaffold(
        appBar: AppBar(
          title: Text(widget.semua ? 'Laporan Transaksi' : 'Riwayat Transaksi'),
          actions: [AccountButton(userId: widget.userId)],
        ),
        drawer: AppDrawer(userId: widget.userId, role: widget.semua ? 'owner' : 'kasir'),
        body: Column(children: [
          Container(
            color: Colors.white,
            padding: const EdgeInsets.fromLTRB(16, 16, 16, 14),
            child: Column(children: [
              SearchField(_search, hint: 'Cari no. transaksi / nominal...', onChanged: _filterSearch),
              const SizedBox(height: 10),
                            Row(children: [
                Expanded(
                  child: OutlinedButton.icon(
                    onPressed: () => _pick(true),
                    icon: const Icon(Icons.calendar_today_outlined, size: 15),
                    label: Text(_start == null ? 'Dari Tanggal' : DateFormat('dd MMM yy').format(_start!)),
                  ),
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: OutlinedButton.icon(
                    onPressed: () => _pick(false),
                    icon: const Icon(Icons.calendar_today_outlined, size: 15),
                    label: Text(_end == null ? 'Sampai Tanggal' : DateFormat('dd MMM yy').format(_end!)),
                  ),
                ),
                if (_start != null || _end != null)
                  IconButton(
                    icon: const Icon(Icons.filter_alt_off_outlined, size: 20, color: C.sub),
                    tooltip: 'Reset filter',
                    onPressed: () {
                      setState(() {
                        _start = null;
                        _end = null;
                      });
                      _fetch();
                    },
                  ),
              ]),
              if (widget.semua) ...[
                const SizedBox(height: 12),
                Container(
                  width: double.infinity,
                  padding: const EdgeInsets.all(12),
                  decoration: BoxDecoration(color: C.greenBg, borderRadius: BorderRadius.circular(12), border: Border.all(color: const Color(0xFFBBF7D0))),
                  child: Row(mainAxisAlignment: MainAxisAlignment.spaceBetween, children: [
                    const Text('Total Omset', style: TextStyle(fontSize: 12.5, fontWeight: FontWeight.w600, color: C.sub)),
                    Text(rp(_omset), style: const TextStyle(fontSize: 15, fontWeight: FontWeight.w800, color: C.green)),
                  ]),
                ),
              ],
            ]),
          ),
          Expanded(
            child: _load
                ? const Center(child: CircularProgressIndicator(color: C.primary))
                : _list.isEmpty
                    ? const Center(child: Text('Tidak ada transaksi', style: TextStyle(color: C.sub)))
                    : ListView.builder(
                        padding: const EdgeInsets.all(16),
                        itemCount: _list.length,
                        itemBuilder: (c, i) {
                          final t = _list[i];
                          return Container(
                            margin: const EdgeInsets.only(bottom: 10),
                            decoration: BoxDecoration(color: Colors.white, borderRadius: BorderRadius.circular(16), border: Border.all(color: C.border)),
                            child: ListTile(
                              contentPadding: const EdgeInsets.symmetric(horizontal: 14, vertical: 6),
                              onTap: () => Navigator.push(context, MaterialPageRoute(builder: (_) => DetailPage(trx: t))),
                              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
                              leading: Container(
                                width: 44,
                                height: 44,
                                decoration: BoxDecoration(color: C.primary.withOpacity(.09), borderRadius: BorderRadius.circular(12)),
                                child: const Icon(Icons.receipt_long_outlined, size: 20, color: C.primary),
                              ),
                              title: Text(t['no_transaksi'] ?? '-', style: const TextStyle(fontSize: 13.5, fontWeight: FontWeight.w700, color: C.ink)),
                              subtitle: Padding(
                                padding: const EdgeInsets.only(top: 3),
                                child: Text('${fdate(t['tanggal'])}\nKasir: ${((t['users'] as Map?)?['nama_lengkap']) ?? '-'}',
                                    style: const TextStyle(fontSize: 11, color: C.sub, height: 1.5)),
                              ),
                              isThreeLine: true,
                              trailing: Column(crossAxisAlignment: CrossAxisAlignment.end, children: [
                                Text(rp(t['total_bayar']), style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w800, color: C.green)),
                                if ((t['status'] ?? '') == 'void')
                                  const Padding(
                                    padding: EdgeInsets.only(top: 4),
                                    child: Pill('VOID', fg: C.red, bg: C.redBg),
                                  ),
                              ]),
                            ),
                          );
                        },
                      ),
          ),
        ]),
      );
}

class DetailPage extends StatefulWidget {
  final Map<String, dynamic> trx;
  const DetailPage({super.key, required this.trx});

  @override
  State<DetailPage> createState() => _DetailPageState();
}

class _DetailPageState extends State<DetailPage> {
  List<Map<String, dynamic>> _items = [];
  bool _load = true;
  Map<String, dynamic>? _me;

  @override
  void initState() {
    super.initState();
    _fetch();
    if (DB.session != null) DB.getUser(DB.session!).then((u) { if (mounted) setState(() => _me = u); });
  }

  Future<void> _fetch() async {
    try {
      final r = await DB.detailTransaksi(widget.trx['id_transaksi']);
      if (mounted) {
        setState(() {
          _items = r;
          _load = false;
        });
      }
    } catch (e) {
      debugPrint('$e');
      if (mounted) setState(() => _load = false);
    }
  }

  /// Void transaksi — hanya admin/owner, wajib alasan, stok otomatis kembali.
  Future<void> _voidTrx() async {
    final ctrl = TextEditingController();
    final ok = await showDialog<bool>(
      context: context,
      builder: (d) => AlertDialog(
        title: const Text('Void Transaksi', textAlign: TextAlign.center),
        content: Column(mainAxisSize: MainAxisSize.min, children: [
          const Text('Stok akan dikembalikan ke batch asal. Tindakan dicatat di log.',
              textAlign: TextAlign.center, style: TextStyle(fontSize: 12, color: C.sub)),
          const SizedBox(height: 12),
          TextField(controller: ctrl, decoration: const InputDecoration(labelText: 'Alasan void (wajib)')),
        ]),
        actions: [
          TextButton(onPressed: () => Navigator.pop(d), child: const Text('Batal')),
          ElevatedButton(
            style: ElevatedButton.styleFrom(backgroundColor: C.red, foregroundColor: Colors.white),
            onPressed: () {
              if (ctrl.text.trim().isEmpty) return;
              Navigator.pop(d, true);
            },
            child: const Text('Void'),
          ),
        ],
      ),
    );
    if (ok != true || !mounted) return;
    final err = await DB.voidTransaction(widget.trx['id_transaksi'] as int, _me!['id_user'] as int, ctrl.text.trim());
    if (!mounted) return;
    snack(context, err ?? 'Transaksi divoid — stok dikembalikan', err: err != null);
    if (err == null) {
      // muat ulang header agar status void tampil
      final fresh = await DB.transaksiById(widget.trx['id_transaksi'] as int);
      if (fresh != null && mounted) setState(() => widget.trx..clear()..addAll(fresh));
    }
  }

  @override
  Widget build(BuildContext context) {
    final t = widget.trx;
    final isVoid = (t['status'] ?? '') == 'void';
    final role = (_me?['role'] ?? '').toString();
    final mayVoid = !isVoid && (role == 'admin' || role == 'owner');
    return Scaffold(
      appBar: AppBar(title: const Text('Detail Transaksi')),
      body: Column(children: [
        Padding(
          padding: const EdgeInsets.all(16),
          child: CardX(
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Row(mainAxisAlignment: MainAxisAlignment.spaceBetween, children: [
                Expanded(child: Text(t['no_transaksi'] ?? '-', style: const TextStyle(fontSize: 14, fontWeight: FontWeight.w800, color: C.ink))),
                Pill(isVoid ? 'VOID' : 'Berhasil', fg: isVoid ? C.red : C.green, bg: isVoid ? C.redBg : C.greenBg),
              ]),
              const SizedBox(height: 6),
              Text(fdate(t['tanggal']), style: const TextStyle(fontSize: 12, color: C.sub)),
              Text('Kasir: ${((t['users'] as Map?)?['nama_lengkap']) ?? '-'}', style: const TextStyle(fontSize: 12, color: C.sub)),
              Text('Metode: ${(t['metode'] ?? 'tunai').toString().toUpperCase()}', style: const TextStyle(fontSize: 12, color: C.sub)),
              if (isVoid && (t['void_alasan'] ?? '').toString().isNotEmpty)
                Text('Alasan void: ${t['void_alasan']} (${fdate(t['void_pada'])})',
                    style: const TextStyle(fontSize: 11.5, color: C.red)),
            ]),
          ),
        ),
        Expanded(
          child: _load
              ? const Center(child: CircularProgressIndicator(color: C.primary))
              : ListView.builder(
                  padding: const EdgeInsets.symmetric(horizontal: 16),
                  itemCount: _items.length,
                  itemBuilder: (c, i) {
                    final it = _items[i];
                    final p = it['produk'] as Map?;
                    return Container(
                      margin: const EdgeInsets.only(bottom: 10),
                      padding: const EdgeInsets.all(10),
                      decoration: BoxDecoration(color: Colors.white, borderRadius: BorderRadius.circular(16), border: Border.all(color: C.border)),
                      child: Row(children: [
                        ProductImage(p?['gambar'], size: 50),
                        const SizedBox(width: 12),
                        Expanded(
                          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                            Text(p?['nama_produk'] ?? '-', style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w700, color: C.ink)),
                            const SizedBox(height: 2),
                            Text('Kategori: ${p?['kategori'] ?? '-'}', style: const TextStyle(fontSize: 10.5, color: C.sub)),
                            const SizedBox(height: 2),
                            Text('${rp((it['subtotal'] ?? 0) ~/ ((it['qty'] ?? 1) as int))} /pcs',
                                style: const TextStyle(fontSize: 11, fontWeight: FontWeight.w600, color: C.primary)),
                          ]),
                        ),
                        Column(crossAxisAlignment: CrossAxisAlignment.end, children: [
                          Container(
                            padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                            decoration: BoxDecoration(color: C.primary.withOpacity(.1), borderRadius: BorderRadius.circular(6)),
                            child: Text('x${it['qty']}', style: const TextStyle(fontSize: 11, fontWeight: FontWeight.w800, color: C.primary)),
                          ),
                          const SizedBox(height: 5),
                          Text(rp(it['subtotal']), style: const TextStyle(fontSize: 12.5, fontWeight: FontWeight.w800, color: C.ink)),
                        ]),
                      ]),
                    );
                  },
                ),
        ),
        Container(
          width: double.infinity,
          decoration: const BoxDecoration(
            color: Colors.white,
            border: Border(top: BorderSide(color: C.border)),
          ),
          padding: const EdgeInsets.all(16),
          child: Column(children: [
            _row('Total Belanja', t['total_bayar']),
            if (((t['diskon'] ?? 0) as int) > 0) _row('Diskon', -((t['diskon']) as int)),
            _row('Uang Diterima', t['uang_diterima']),
            _row('Kembalian', t['kembalian'], accent: true),
            if (mayVoid) ...[
              const SizedBox(height: 10),
              SizedBox(
                width: double.infinity,
                height: 48,
                child: OutlinedButton.icon(
                  onPressed: _voidTrx,
                  icon: const Icon(Icons.block_rounded, size: 18),
                  label: const Text('Void Transaksi'),
                  style: OutlinedButton.styleFrom(
                    foregroundColor: C.red,
                    side: const BorderSide(color: C.redBorder, width: 1.3),
                  ),
                ),
              ),
            ],
          ]),
        ),
      ]),
    );
  }

  Widget _row(String label, dynamic v, {bool accent = false}) => Padding(
        padding: const EdgeInsets.symmetric(vertical: 3),
        child: Row(mainAxisAlignment: MainAxisAlignment.spaceBetween, children: [
          Text(label, style: const TextStyle(fontSize: 13, color: C.sub)),
          Text(rp(v), style: TextStyle(fontSize: 14, fontWeight: FontWeight.w800, color: accent ? C.primary : C.ink)),
        ]),
      );
}