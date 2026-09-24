import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:kastra/services.dart';
import 'package:kastra/theme.dart';
import 'package:kastra/widgets.dart';

// ignore_for_file: use_build_context_synchronously

/// Shift kasir (buka/tutup laci + Z-report mini) dan riwayat shift.
class ShiftPage extends StatefulWidget {
  final int userId;
  const ShiftPage({super.key, required this.userId});

  @override
  State<ShiftPage> createState() => _ShiftPageState();
}

class _ShiftPageState extends State<ShiftPage> {
  Map<String, dynamic>? _active;
  List<Map<String, dynamic>> _history = [];
  bool _load = true;

  @override
  void initState() {
    super.initState();
    _fetch();
  }

  Future<void> _fetch() async {
    try {
      final a = await DB.activeShift(widget.userId);
      final h = await DB.shifts(userId: widget.userId);
      if (!mounted) return;
      setState(() {
        _active = a;
        _history = h.where((s) => s['selesai'] != null).toList();
        _load = false;
      });
    } catch (e) {
      debugPrint('$e');
      if (mounted) setState(() => _load = false);
    }
  }

  Future<void> _open() async {
    final ctrl = TextEditingController(text: '0');
    final ok = await showDialog<bool>(
      context: context,
      builder: (d) => AlertDialog(
        title: const Text('Buka Shift', textAlign: TextAlign.center),
        content: TextField(
          controller: ctrl,
          keyboardType: TextInputType.number,
          autofocus: true,
          decoration: const InputDecoration(labelText: 'Modal awal laci (Rp)', prefixText: 'Rp '),
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(d), child: const Text('Batal')),
          ElevatedButton(onPressed: () => Navigator.pop(d, true), child: const Text('Buka Shift')),
        ],
      ),
    );
    if (ok != true || !mounted) return;
    final modal = int.tryParse(ctrl.text.replaceAll('.', '')) ?? 0;
    final res = await DB.openShiftReturn(widget.userId, modal);
    if (!mounted) return;
    if (res == null) {
      snack(context, 'Gagal: ${DB.lastError ?? 'unknown'}', err: true);
      return;
    }
    snack(context, 'Shift dibuka — selamat bertugas!');
    _fetch();
  }

  Future<void> _close() async {
    final saldo = TextEditingController();
    final catatan = TextEditingController();
    final sh = _active;
    if (sh == null) return;
    // perkiraan uang di laci untuk ditampilkan
    final hasil = await showDialog<Map<String, dynamic>>(
      context: context,
      builder: (d) => AlertDialog(
        title: const Text('Tutup Shift', textAlign: TextAlign.center),
        content: Column(mainAxisSize: MainAxisSize.min, children: [
          const Text('Hitung uang fisik di laci, lalu masukkan jumlahnya.',
              textAlign: TextAlign.center, style: TextStyle(fontSize: 12, color: C.sub)),
          const SizedBox(height: 12),
          TextField(
            controller: saldo,
            keyboardType: TextInputType.number,
            autofocus: true,
            decoration: const InputDecoration(labelText: 'Saldo hitung (Rp)', prefixText: 'Rp '),
          ),
          const SizedBox(height: 10),
          TextField(controller: catatan, decoration: const InputDecoration(labelText: 'Catatan (opsional)')),
        ]),
        actions: [
          TextButton(onPressed: () => Navigator.pop(d), child: const Text('Batal')),
          ElevatedButton(
            onPressed: () => Navigator.pop(d, {
              'saldo': int.tryParse(saldo.text.replaceAll('.', '')) ?? 0,
              'catatan': catatan.text.trim(),
            }),
            child: const Text('Tutup Shift'),
          ),
        ],
      ),
    );
    if (hasil == null || !mounted) return;
    final ringkas = await DB.closeShift(widget.userId, hasil['saldo'] as int, hasil['catatan'] as String);
    if (!mounted) return;
    if (ringkas == null) {
      snack(context, 'Gagal: ${DB.lastError ?? 'unknown'}', err: true);
      return;
    }
    final selisih = ringkas['selisih'] as int;
    showDialog<void>(
      context: context,
      builder: (d) => AlertDialog(
        title: const Text('Z-Report Shift', textAlign: TextAlign.center),
        content: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.start, children: [
          _kv('Penjualan tunai', rp(ringkas['penjualan_tunai'] as int)),
          _kv('Seharusnya di laci', rp(ringkas['seharusnya'] as int)),
          _kv('Saldo hitung', rp(hasil['saldo'] as int)),
          _kv('Selisih', rp(selisih),
              color: selisih == 0 ? C.green : (selisih < 0 ? C.red : C.orange)),
        ]),
        actions: [
          ElevatedButton(onPressed: () {
            Navigator.pop(d);
            _fetch();
          }, child: const Text('Selesai')),
        ],
      ),
    );
  }

  Widget _kv(String l, String v, {Color? color}) => Padding(
        padding: const EdgeInsets.symmetric(vertical: 4),
        child: Row(mainAxisAlignment: MainAxisAlignment.spaceBetween, children: [
          Text(l, style: const TextStyle(fontSize: 13, color: C.sub)),
          Text(v, style: TextStyle(fontSize: 13.5, fontWeight: FontWeight.w800, color: color ?? C.ink)),
        ]),
      );

  @override
  Widget build(BuildContext context) => Scaffold(
        appBar: AppBar(title: const Text('Shift Kasir'), actions: [AccountButton(userId: widget.userId)]),
        drawer: AppDrawer(userId: widget.userId, role: 'kasir'),
        body: _load
            ? const Center(child: CircularProgressIndicator(color: C.primary))
            : ListView(
                padding: const EdgeInsets.all(16),
                children: [
                  // --- kartu shift aktif / buka shift ---
                  Container(
                    padding: const EdgeInsets.all(18),
                    decoration: BoxDecoration(
                      gradient: waveGradient,
                      borderRadius: BorderRadius.circular(18),
                    ),
                    child: _active == null
                        ? Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                            const Text('Belum ada shift terbuka',
                                style: TextStyle(color: Colors.white, fontSize: 15, fontWeight: FontWeight.w800)),
                            const SizedBox(height: 4),
                            const Text('Buka shift untuk mulai melayani transaksi hari ini.',
                                style: TextStyle(color: Colors.white70, fontSize: 12)),
                            const SizedBox(height: 14),
                            SizedBox(
                              height: 46,
                              child: ElevatedButton.icon(
                                onPressed: _open,
                                style: ElevatedButton.styleFrom(
                                    backgroundColor: Colors.white, foregroundColor: C.primary, elevation: 0),
                                icon: const Icon(Icons.lock_open_rounded, size: 18),
                                label: const Text('Buka Shift', style: TextStyle(fontWeight: FontWeight.w800)),
                              ),
                            ),
                          ])
                        : Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                            const Text('SHIFT SEDANG BERJALAN',
                                style: TextStyle(color: Colors.white70, fontSize: 10.5, fontWeight: FontWeight.w800, letterSpacing: 2)),
                            const SizedBox(height: 6),
                            Text('Mulai: ${DateFormat('dd MMM yyyy HH:mm').format(DateTime.parse(_active!['mulai'].toString()))}',
                                style: const TextStyle(color: Colors.white, fontSize: 14, fontWeight: FontWeight.w700)),
                            Text('Modal awal: ${rp(_active!['modal_awal'] ?? 0)}',
                                style: const TextStyle(color: Colors.white70, fontSize: 12.5)),
                            const SizedBox(height: 14),
                            Row(children: [
                              Expanded(
                                child: SizedBox(
                                  height: 46,
                                  child: ElevatedButton.icon(
                                    onPressed: _close,
                                    style: ElevatedButton.styleFrom(
                                        backgroundColor: Colors.white, foregroundColor: C.red, elevation: 0),
                                    icon: const Icon(Icons.lock_outline_rounded, size: 18),
                                    label: const Text('Tutup Shift', style: TextStyle(fontWeight: FontWeight.w800)),
                                  ),
                                ),
                              ),
                            ]),
                          ]),
                  ),
                  const SizedBox(height: 20),
                  const Text('Riwayat Shift',
                      style: TextStyle(fontSize: 14, fontWeight: FontWeight.w800, color: C.ink)),
                  const SizedBox(height: 10),
                  if (_history.isEmpty)
                    const Padding(
                      padding: EdgeInsets.all(12),
                      child: Text('Belum ada shift yang ditutup.', style: TextStyle(color: C.sub, fontSize: 12.5)),
                    ),
                  ..._history.map((s) {
                    final selisih = (s['selisih'] ?? 0) as int;
                    return Container(
                      margin: const EdgeInsets.only(bottom: 10),
                      padding: const EdgeInsets.all(14),
                      decoration: BoxDecoration(
                          color: Colors.white, borderRadius: BorderRadius.circular(16), border: Border.all(color: C.border)),
                      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                        Row(mainAxisAlignment: MainAxisAlignment.spaceBetween, children: [
                          Text(
                              '${DateFormat('dd MMM HH:mm').format(DateTime.parse(s['mulai'].toString()))} – '
                              '${s['selesai'] == null ? '...' : DateFormat('HH:mm').format(DateTime.parse(s['selesai'].toString()))}',
                              style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w700, color: C.ink)),
                          Pill(
                            selisih == 0 ? 'SESUAI' : (selisih < 0 ? 'MINUS ${rp(-selisih)}' : 'PLUS ${rp(selisih)}'),
                            fg: selisih == 0 ? C.green : C.red,
                            bg: selisih == 0 ? C.greenBg : C.redBg,
                          ),
                        ]),
                        const SizedBox(height: 4),
                        Text('Modal: ${rp(s['modal_awal'] ?? 0)} · Hitung: ${s['saldo_hitung'] == null ? '-' : rp(s['saldo_hitung'])}',
                            style: const TextStyle(fontSize: 11.5, color: C.sub)),
                        if ((s['catatan'] ?? '').toString().isNotEmpty)
                          Text('Catatan: ${s['catatan']}', style: const TextStyle(fontSize: 11, color: C.sub)),
                      ]),
                    );
                  }),
                ],
              ),
      );
