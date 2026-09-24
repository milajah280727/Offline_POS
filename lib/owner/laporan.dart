// Laporan analitik periode: laba/rugi, penjualan harian, top produk,
// rekap metode pembayaran + export CSV.
import 'package:flutter/material.dart';
import 'package:kastra/services.dart';
import 'package:kastra/theme.dart';
import 'package:kastra/widgets.dart';

class LaporanPage extends StatefulWidget {
  final int userId;
  const LaporanPage({super.key, required this.userId});

  @override
  State<LaporanPage> createState() => _LaporanPageState();
}

class _LaporanPageState extends State<LaporanPage> {
  late DateTime _start;
  late DateTime _end;
  bool _load = true;
  Map<String, dynamic>? _profit;
  List<Map<String, dynamic>> _harian = [], _top = [], _metode = [];

  @override
  void initState() {
    super.initState();
    final now = DateTime.now();
    _end = now;
    _start = DateTime(now.year, now.month, 1); // awal bulan berjalan
    _refresh();
  }

  Future<void> _refresh() async {
    setState(() => _load = true);
    try {
      final p = await DB.profitReport(_start, _end);
      final h = await DB.salesByDay(_start, _end);
      final t = await DB.topProducts(_start, _end, limit: 10);
      final m = await DB.salesByMethod(_start, _end);
      if (!mounted) return;
      setState(() {
        _profit = p;
        _harian = h;
        _top = t;
        _metode = m;
        _load = false;
      });
    } catch (e) {
      debugPrint('$e');
      if (mounted) setState(() => _load = false);
    }
  }

  Future<void> _pickRange() async {
    final r = await showDateRangePicker(
      context: context,
      firstDate: DateTime(2020),
      lastDate: DateTime.now().add(const Duration(days: 1)),
      initialDateRange: DateTimeRange(start: _start, end: _end),
    );
    if (r != null) {
      setState(() {
        _start = r.start;
        _end = r.end;
      });
      _refresh();
    }
  }

  Future<void> _export(String what) async {
    try {
      final s = _start.toIso8601String();
      final e = DateTime(_end.year, _end.month, _end.day, 23, 59, 59).toIso8601String();
      late List<List<dynamic>> rows;
      late String name;
      if (what == 'transaksi') {
        rows = await DB.csvRows('transaksi', where: 'tanggal >= ? AND tanggal <= ?', args: [s, e]);
        name = 'transaksi_${_start.millisecondsSinceEpoch}';
      } else if (what == 'harian') {
        final data = await DB.salesByDay(_start, _end);
        rows = [
          ['hari', 'trx', 'omset', 'diskon', 'pajak'],
          ...data.map((r) => [r['hari'], r['trx'], r['omset'], r['diskon'], r['pajak']]),
        ];
        name = 'penjualan_harian';
      } else {
        final data = await DB.topProducts(_start, _end, limit: 100);
        rows = [
          ['produk', 'qty', 'omset'],
          ...data.map((r) => [r['nama_produk'], r['qty'], r['omset']]),
        ];
        name = 'top_produk';
      }
      if (rows.isEmpty) {
        if (mounted) snack(context, 'Tidak ada data untuk diekspor', err: true);
        return;
      }
      final path = await DB.writeCsvFile(name, rows);
      if (mounted) snack(context, 'CSV tersimpan:\n$path');
    } catch (e) {
      if (mounted) snack(context, 'Export gagal: $e', err: true);
    }
  }

  Widget _box(String title, List<Widget> children) => Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(title, style: const TextStyle(fontSize: 15, fontWeight: FontWeight.w800, color: C.ink)),
          const SizedBox(height: 10),
          ...children,
          const SizedBox(height: 24),
        ],
      );

  Widget _kv(String k, String v, {Color? color}) => Padding(
        padding: const EdgeInsets.symmetric(vertical: 5),
        child: Row(mainAxisAlignment: MainAxisAlignment.spaceBetween, children: [
          Text(k, style: const TextStyle(fontSize: 13, color: C.sub)),
          Text(v, style: TextStyle(fontSize: 13, fontWeight: FontWeight.w700, color: color ?? C.ink)),
        ]),
      );

  @override
  Widget build(BuildContext context) {
    final p = _profit;
    final maxOmset = _harian.fold<int>(0, (a, r) => a > ((r['omset'] ?? 0) as int) ? a : (r['omset'] ?? 0) as int);
    return Scaffold(
      appBar: AppBar(
        title: const Text('Laporan Analitik'),
        actions: [
          IconButton(onPressed: _pickRange, icon: const Icon(Icons.date_range_outlined), tooltip: 'Pilih periode'),
          PopupMenuButton<String>(
            onSelected: _export,
            itemBuilder: (_) => const [
              PopupMenuItem(value: 'transaksi', child: Text('Export Transaksi (CSV)')),
              PopupMenuItem(value: 'harian', child: Text('Export Penjualan Harian (CSV)')),
              PopupMenuItem(value: 'top', child: Text('Export Top Produk (CSV)')),
            ],
            icon: const Icon(Icons.download_outlined),
            tooltip: 'Export CSV',
          ),
        ],
      ),
      drawer: AppDrawer(userId: widget.userId, role: 'owner'),
      body: _load
          ? const Center(child: CircularProgressIndicator(color: C.primary))
          : RefreshIndicator(
              onRefresh: _refresh,
              child: ListView(padding: const EdgeInsets.all(16), children: [
                _Card(
                  padding: const EdgeInsets.all(14),
                  child: Row(children: [
                    const Icon(Icons.calendar_month_outlined, color: C.primary, size: 20),
                    const SizedBox(width: 10),
                    Expanded(
                      child: Text('${fdate(_start, 'd MMM yyyy')} — ${fdate(_end, 'd MMM yyyy')}',
                          style: const TextStyle(fontWeight: FontWeight.w700, color: C.ink, fontSize: 13)),
                    ),
                    TextButton(onPressed: _pickRange, child: const Text('Ubah')),
                  ]),
                ),
                const SizedBox(height: 20),
                _box('Laba / Rugi', [
                  _Card(
                    padding: const EdgeInsets.all(16),
                    child: p == null
                        ? const Text('Data tidak tersedia', style: TextStyle(color: C.sub))
                        : Column(children: [
                            _kv('Omset (${p['trx']} trx)', rp(p['omset'])),
                            _kv('Diskon diberikan', '- ${rp(p['diskon'])}', color: C.orange),
                            _kv('Pajak terkumpul', rp(p['pajak'])),
                            _kv('HPP (modal barang terjual)', '- ${rp(p['hpp'])}', color: C.red),
                            _kv('Laba Kotor', rp(p['labaKotor']), color: C.green),
                            _kv('Pengeluaran toko', '- ${rp(p['pengeluaran'])}', color: C.red),
                            const Divider(height: 20),
                            _kv('LABA BERSIH', rp(p['labaBersih']),
                                color: (p['labaBersih'] as int) >= 0 ? C.green : C.red),
                          ]),
                  ),
                ]),
                _box('Penjualan Harian', [
                  if (_harian.isEmpty)
                    const _Card(padding: EdgeInsets.all(24), child: Center(child: Text('Belum ada transaksi pada periode ini', style: TextStyle(color: C.sub, fontSize: 13))))
                  else
                    _Card(
                      padding: const EdgeInsets.fromLTRB(14, 16, 14, 8),
                      child: Column(children: _harian.map((r) {
                        final om = (r['omset'] ?? 0) as int;
                        final w = maxOmset == 0 ? 0.0 : (om / maxOmset).clamp(0.0, 1.0);
                        return Padding(
                          padding: const EdgeInsets.only(bottom: 10),
                          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                            Row(mainAxisAlignment: MainAxisAlignment.spaceBetween, children: [
                              Text(fdate(r['hari'], 'EEE, d MMM'),
                                  style: const TextStyle(fontSize: 12, fontWeight: FontWeight.w700, color: C.ink)),
                              Text('${r['trx']} trx · ${rp(om)}',
                                  style: const TextStyle(fontSize: 11.5, color: C.sub)),
                            ]),
                            const SizedBox(height: 4),
                            ClipRRect(
                              borderRadius: BorderRadius.circular(4),
                              child: LinearProgressIndicator(value: w, minHeight: 7, backgroundColor: C.bg, valueColor: const AlwaysStoppedAnimation(C.primary)),
                            ),
                          ]),
                        );
                      }).toList()),
                    ),
                ]),
                _box('Top Produk Terlaris', [
                  if (_top.isEmpty)
                    const _Card(padding: EdgeInsets.all(24), child: Center(child: Text('Belum ada data produk terjual', style: TextStyle(color: C.sub, fontSize: 13))))
                  else
                    ..._top.asMap().entries.map((en) {
                      final i = en.key, r = en.value;
                      return _Card(
                        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
                        margin: const EdgeInsets.only(bottom: 8),
                        child: Row(children: [
                          Container(
                            width: 26, height: 26,
                            decoration: BoxDecoration(color: i < 3 ? C.primary : C.fieldFill, borderRadius: BorderRadius.circular(8)),
                            child: Center(child: Text('${i + 1}',
                                style: TextStyle(fontSize: 12, fontWeight: FontWeight.w800, color: i < 3 ? Colors.white : C.sub))),
                          ),
                          const SizedBox(width: 12),
                          Expanded(
                            child: Text('${r['nama_produk']}',
                                style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w700, color: C.ink),
                                maxLines: 1, overflow: TextOverflow.ellipsis),
                          ),
                          Text('${r['qty']} pcs · ${rp(r['omset'])}',
                              style: const TextStyle(fontSize: 11.5, color: C.sub)),
                        ]),
                      );
                    }),
                ]),
                _box('Metode Pembayaran', [
                  if (_metode.isEmpty)
                    const _Card(padding: EdgeInsets.all(24), child: Center(child: Text('Belum ada data', style: TextStyle(color: C.sub, fontSize: 13))))
                  else
                    _Card(
                      padding: const EdgeInsets.all(16),
                      child: Column(children: _metode.map((m) {
                        final label = (m['metode'] ?? 'tunai').toString().toUpperCase();
                        return Padding(
                          padding: const EdgeInsets.symmetric(vertical: 4),
                          child: _kv('$label (${m['trx']} trx)', rp(m['omset'])),
                        );
                      }).toList()),
                    ),
                ]),
              ]),
            ),
    );
  }
}

/// CardX + margin bawah (laporan memakai daftar kartu berjarak).
class _Card extends StatelessWidget {
  final Widget child;
  final EdgeInsetsGeometry padding;
  final EdgeInsetsGeometry? margin;
  const _Card({required this.child, this.padding = const EdgeInsets.all(14), this.margin});

  @override
  Widget build(BuildContext context) => Padding(
        padding: margin ?? EdgeInsets.zero,
        child: CardX(padding: padding, child: child),
      );
}
