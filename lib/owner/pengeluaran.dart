import 'package:flutter/material.dart';
import 'package:kastra/services.dart';
import 'package:kastra/theme.dart';
import 'package:kastra/widgets.dart';

// ignore_for_file: deprecated_member_use, use_build_context_synchronously

class PengeluaranPage extends StatefulWidget {
  final int userId;
  const PengeluaranPage({super.key, required this.userId});

  @override
  State<PengeluaranPage> createState() => _PengeluaranPageState();
}

class _PengeluaranPageState extends State<PengeluaranPage> {
  List<Map<String, dynamic>> _list = [];
  Map<String, dynamic> _fin = {'omset': 0, 'hpp': 0, 'labaKotor': 0, 'pengeluaran': 0, 'labaBersih': 0};
  bool _load = true;

  @override
  void initState() {
    super.initState();
    _fetch();
  }

  Future<void> _fetch() async {
    setState(() => _load = true);
    try {
      final d = await DB.pengeluaran;
      final f = await DB.todayFinance();
      if (mounted) {
        setState(() {
          _list = d;
          _fin = f;
          _load = false;
        });
      }
    } catch (e) {
      debugPrint('$e');
      if (mounted) setState(() => _load = false);
    }
  }

  int get _labaKotor => _fin['labaKotor'] as int;
  int get _pengeluaranHariIni => _fin['pengeluaran'] as int;
  int get _sisa => _labaKotor - _pengeluaranHariIni;

  bool _isToday(dynamic t) {
    try {
      return dayOnly(t) == dayOnly(DateTime.now());
    } catch (_) {
      return false;
    }
  }

  Future<void> _form([Map<String, dynamic>? d]) async {
    // Sisa anggaran = laba kotor hari ini - pengeluaran hari ini lain (di luar data yang diedit).
    final terpakaiLain = _pengeluaranHariIni - ((d != null && _isToday(d['tanggal'])) ? ((d['nominal'] ?? 0) as int) : 0);
    final sisa = _labaKotor - terpakaiLain;

    final ket = TextEditingController(text: d?['keterangan']);
    final nom = TextEditingController(text: d?['nominal']?.toString());
    final save = await showDialog<bool>(
      context: context,
      builder: (b) => StatefulBuilder(
        builder: (b, ss) {
          final v = int.tryParse(nom.text.replaceAll('.', '')) ?? 0;
          final over = v > sisa;
          return AlertDialog(
            title: Text(d == null ? 'Tambah Pengeluaran' : 'Edit Pengeluaran', textAlign: TextAlign.center),
            content: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.start, children: [
              TextField(controller: ket, decoration: const InputDecoration(labelText: 'Keterangan')),
              const SizedBox(height: 10),
              TextField(
                controller: nom,
                keyboardType: TextInputType.number,
                decoration: const InputDecoration(labelText: 'Nominal', prefixText: 'Rp '),
                onChanged: (_) => ss(() {}),
              ),
              const SizedBox(height: 12),
              Container(
                width: double.infinity,
                padding: const EdgeInsets.all(10),
                decoration: BoxDecoration(
                  color: sisa < 0 ? C.redBg : C.greenBg,
                  borderRadius: BorderRadius.circular(10),
                  border: Border.all(color: sisa < 0 ? C.redBorder : const Color(0xFFBBF7D0)),
                ),
                child: Text('Sisa anggaran hari ini: ${rp(sisa < 0 ? 0 : sisa)}',
                    style: TextStyle(fontSize: 12, fontWeight: FontWeight.w700, color: sisa < 0 ? C.red : C.green)),
              ),
              if (over) ...[
                const SizedBox(height: 8),
                Row(children: [
                  const Icon(Icons.warning_amber_rounded, size: 16, color: C.red),
                  const SizedBox(width: 6),
                  Expanded(
                    child: Text('Melebihi laba hari ini! Maksimal ${rp(sisa < 0 ? 0 : sisa)}',
                        style: const TextStyle(fontSize: 12, fontWeight: FontWeight.w700, color: C.red)),
                  ),
                ]),
              ],
            ]),
            actions: [
              SizedBox(width: double.infinity, height: 48, child: ElevatedButton(onPressed: () => Navigator.pop(b, true), child: const Text('Simpan'))),
            ],
          );
        },
      ),
    );
    if (save != true || !mounted) return;

    final nominal = int.tryParse(nom.text.replaceAll('.', ''));
    if (ket.text.trim().isEmpty || nominal == null || nominal <= 0) {
      snack(context, 'Data tidak valid', err: true);
      return;
    }
    // Tolak jika pengeluaran membuat laba bersih minus.
    if (nominal > sisa) {
      snack(context, 'Ditolak: pengeluaran melebihi laba hari ini. Maksimal ${rp(sisa < 0 ? 0 : sisa)}', err: true);
      return;
    }

    final ok = d == null
        ? await DB.addPengeluaran({'keterangan': ket.text.trim(), 'nominal': nominal})
        : await DB.updatePengeluaran(d['id_pengeluaran'], {'keterangan': ket.text.trim(), 'nominal': nominal});
    if (ok) await DB.log(widget.userId, '${d == null ? 'Menambah' : 'Mengubah'} pengeluaran: ${ket.text}');
    if (mounted) {
      snack(context, ok ? 'Tersimpan' : 'Gagal menyimpan', err: !ok);
      if (ok) _fetch();
    }
  }

  Future<void> _del(Map<String, dynamic> d) async {
    if (!await confirm(context, 'Hapus Pengeluaran', 'Yakin hapus "${d['keterangan']}"?')) return;
    final ok = await DB.deletePengeluaran(d['id_pengeluaran']);
    if (ok) await DB.log(widget.userId, 'Menghapus pengeluaran: ${d['keterangan']}');
    if (mounted) {
      snack(context, ok ? 'Dihapus' : 'Gagal menghapus', err: !ok);
      if (ok) _fetch();
    }
  }

  @override
  Widget build(BuildContext context) {
    final labaBersih = _fin['labaBersih'] as int;
    return Scaffold(
      appBar: AppBar(title: const Text('Pengeluaran Operasional'), actions: [AccountButton(userId: widget.userId)]),
      drawer: AppDrawer(userId: widget.userId, role: 'owner'),
      body: _load
          ? const Center(child: CircularProgressIndicator(color: C.primary))
          : RefreshIndicator(
              color: C.primary,
              onRefresh: _fetch,
              child: ListView(
                physics: const AlwaysScrollableScrollPhysics(),
                padding: const EdgeInsets.all(16),
                children: [
                  // --- KARTU 1: LABA RUGI HARI INI ---
                  Container(
                    width: double.infinity,
                    padding: const EdgeInsets.all(18),
                    decoration: BoxDecoration(
                      gradient: waveGradient,
                      borderRadius: BorderRadius.circular(18),
                      boxShadow: [BoxShadow(color: C.primary.withOpacity(.25), blurRadius: 12, offset: const Offset(0, 6))],
                    ),
                    child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                      const Text('Laba Rugi Hari Ini',
                          style: TextStyle(color: Colors.white, fontSize: 13.5, fontWeight: FontWeight.w700)),
                      const SizedBox(height: 12),
                      _f('Pendapatan (Omset)', _fin['omset'] as int),
                      _f('HPP (Harga Pokok)', -(_fin['hpp'] as int)),
                      const Divider(color: Colors.white24, height: 20),
                      _f('Laba Kotor', _labaKotor, bold: true),
                      _f('Pengeluaran Operasional', -_pengeluaranHariIni),
                      const Divider(color: Colors.white24, height: 20),
                      _f('Laba Bersih', labaBersih, big: true),
                    ]),
                  ),
                  const SizedBox(height: 12),
                  // --- KARTU 2: PENGELUARAN HARI INI + SISA ANGGARAN ---
                  Container(
                    width: double.infinity,
                    padding: const EdgeInsets.all(16),
                    decoration: BoxDecoration(
                      color: Colors.white,
                      borderRadius: BorderRadius.circular(16),
                      border: Border.all(color: _sisa < 0 ? C.redBorder : C.border),
                    ),
                    child: Row(children: [
                      Container(
                        padding: const EdgeInsets.all(10),
                        decoration: BoxDecoration(color: C.redBg, borderRadius: BorderRadius.circular(12)),
                        child: const Icon(Icons.trending_up, color: C.red, size: 22),
                      ),
                      const SizedBox(width: 14),
                      Expanded(
                        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                          const Text('Pengeluaran Hari Ini',
                              style: TextStyle(fontSize: 11.5, fontWeight: FontWeight.w600, color: C.sub)),
                          const SizedBox(height: 2),
                          Text(rp(_pengeluaranHariIni),
                              style: const TextStyle(fontSize: 18, fontWeight: FontWeight.w800, color: C.red)),
                        ]),
                      ),
                      Pill('Sisa: ${rp(_sisa < 0 ? 0 : _sisa)}', fg: _sisa < 0 ? C.red : C.green),
                    ]),
                  ),
                  const SizedBox(height: 18),
                  Text('Riwayat Pengeluaran',
                      style: const TextStyle(fontSize: 15, fontWeight: FontWeight.w800, color: C.ink)),
                  const SizedBox(height: 10),
                  if (_list.isEmpty)
                    const CardX(
                      padding: EdgeInsets.all(28),
                      child: Center(child: Text('Belum ada data', style: TextStyle(color: C.sub))),
                    )
                  else
                    ..._list.map(_tile),
                ],
              ),
            ),
      floatingActionButton: FloatingActionButton(onPressed: _form, child: const Icon(Icons.add)),
    );
  }

  Widget _f(String label, int value, {bool bold = false, bool big = false}) => Padding(
        padding: const EdgeInsets.symmetric(vertical: 3),
        child: Row(mainAxisAlignment: MainAxisAlignment.spaceBetween, children: [
          Text(label,
              style: TextStyle(
                  color: Colors.white.withOpacity(.85),
                  fontSize: big ? 14 : 12.5,
                  fontWeight: bold || big ? FontWeight.w700 : FontWeight.w500)),
          Text(rp(value),
              style: TextStyle(color: Colors.white, fontSize: big ? 20 : 13.5, fontWeight: FontWeight.w800)),
        ]),
      );

  Widget _tile(Map<String, dynamic> d) => Container(
        margin: const EdgeInsets.only(bottom: 10),
        decoration: BoxDecoration(color: Colors.white, borderRadius: BorderRadius.circular(16), border: Border.all(color: C.border)),
        child: ListTile(
          contentPadding: const EdgeInsets.symmetric(horizontal: 14, vertical: 4),
          leading: Container(
            width: 42,
            height: 42,
            decoration: BoxDecoration(color: C.redBg, borderRadius: BorderRadius.circular(12)),
            child: const Icon(Icons.north_east_rounded, size: 20, color: C.red),
          ),
          title: Text('${d['keterangan']}', style: const TextStyle(fontSize: 13.5, fontWeight: FontWeight.w700, color: C.ink)),
          subtitle: Text(fdate(d['tanggal']), style: const TextStyle(fontSize: 11.5, color: C.sub)),
          trailing: Row(mainAxisSize: MainAxisSize.min, children: [
            Text('- ${rp(d['nominal'])}', style: const TextStyle(fontSize: 12.5, fontWeight: FontWeight.w800, color: C.red)),
            const SizedBox(width: 4),
            IconBox(Icons.edit_outlined, color: C.primary, onTap: () => _form(d)),
            const SizedBox(width: 5),
            IconBox(Icons.delete_outline, color: C.red, onTap: () => _del(d)),
          ]),
        ),
      );
}