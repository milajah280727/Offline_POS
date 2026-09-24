import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:kastra/services.dart';
import 'package:kastra/theme.dart';
import 'package:kastra/widgets.dart';

// ignore_for_file: use_build_context_synchronously

/// Stock opname (physical count): bandingkan stok sistem vs fisik,
/// catat selisih dan sesuaikan batch FEFO secara atomik.
class OpnamePage extends StatefulWidget {
  final int userId;
  const OpnamePage({super.key, required this.userId});

  @override
  State<OpnamePage> createState() => _OpnamePageState();
}

class _OpnamePageState extends State<OpnamePage> {
  List<Map<String, dynamic>> _produk = [];
  List<Map<String, dynamic>> _riwayat = [];
  final _search = TextEditingController();
  bool _load = true;

  @override
  void initState() {
    super.initState();
    _fetch();
  }

  Future<void> _fetch() async {
    try {
      final p = await DB.products;
      final r = await DB.opnames;
      if (!mounted) return;
      setState(() {
        _produk = p;
        _riwayat = r;
        _load = false;
      });
    } catch (e) {
      debugPrint('$e');
      if (mounted) setState(() => _load = false);
    }
  }

  List<Map<String, dynamic>> get _filtered {
    final q = _search.text.toLowerCase();
    if (q.isEmpty) return _produk;
    return _produk.where((p) => (p['nama_produk'] ?? '').toString().toLowerCase().contains(q)).toList();
  }

  Future<void> _opname(Map<String, dynamic> p) async {
    final fisik = TextEditingController(text: '${p['stok'] ?? 0}');
    final alasan = TextEditingController();
    final ok = await showDialog<bool>(
      context: context,
      builder: (d) => AlertDialog(
        title: Text('Opname: ${p['nama_produk']}', textAlign: TextAlign.center),
        content: Column(mainAxisSize: MainAxisSize.min, children: [
          Text('Stok sistem: ${p['stok'] ?? 0}', style: const TextStyle(fontSize: 13, color: C.sub)),
          const SizedBox(height: 12),
          TextField(
            controller: fisik,
            keyboardType: TextInputType.number,
            autofocus: true,
            decoration: const InputDecoration(labelText: 'Stok fisik hasil hitung'),
          ),
          const SizedBox(height: 10),
          TextField(controller: alasan, decoration: const InputDecoration(labelText: 'Alasan (opsional)')),
        ]),
        actions: [
          TextButton(onPressed: () => Navigator.pop(d), child: const Text('Batal')),
          ElevatedButton(onPressed: () => Navigator.pop(d, true), child: const Text('Simpan')),
        ],
      ),
    );
    if (ok != true || !mounted) return;
    final f = int.tryParse(fisik.text.trim());
    if (f == null || f < 0) {
      snack(context, 'Stok fisik tidak valid', err: true);
      return;
    }
    final err = await DB.opnameStok(
      userId: widget.userId,
      idProduk: p['id_produk'] as int,
      stokFisik: f,
      alasan: alasan.text.trim().isEmpty ? 'Opname' : alasan.text.trim(),
    );
    if (!mounted) return;
    if (err != null) {
      snack(context, 'Gagal: $err', err: true);
      return;
    }
    snack(context, 'Opname tersimpan — stok disesuaikan');
    _fetch();
  }

  @override
  Widget build(BuildContext context) => DefaultTabController(
        length: 2,
        child: Scaffold(
          appBar: AppBar(
            title: const Text('Opname Stok'),
            actions: [AccountButton(userId: widget.userId)],
            bottom: const TabBar(tabs: [
              Tab(text: 'Hitung Fisik'),
              Tab(text: 'Riwayat'),
            ]),
          ),
          drawer: AppDrawer(userId: widget.userId, role: 'admin'),
          body: _load
              ? const Center(child: CircularProgressIndicator(color: C.primary))
              : TabBarView(children: [
                  Column(children: [
                    Padding(
                      padding: const EdgeInsets.fromLTRB(16, 12, 16, 4),
                      child: SearchField(_search, hint: 'Cari produk...', onChanged: () => setState(() {})),
                    ),
                    Expanded(
                      child: ListView.builder(
                        padding: const EdgeInsets.all(16),
                        itemCount: _filtered.length,
                        itemBuilder: (c, i) {
                          final p = _filtered[i];
                          return Container(
                            margin: const EdgeInsets.only(bottom: 10),
                            padding: const EdgeInsets.all(12),
                            decoration: BoxDecoration(
                                color: Colors.white, borderRadius: BorderRadius.circular(16), border: Border.all(color: C.border)),
                            child: Row(children: [
                              ProductImage(p['gambar'], size: 46),
                              const SizedBox(width: 12),
                              Expanded(
                                child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                                  Text(p['nama_produk'] ?? '-',
                                      style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w700, color: C.ink),
                                      maxLines: 1,
                                      overflow: TextOverflow.ellipsis),
                                  const SizedBox(height: 3),
                                  Text('Stok sistem: ${p['stok'] ?? 0}',
                                      style: const TextStyle(fontSize: 11.5, color: C.sub)),
                                ]),
                              ),
                              OutlinedButton.icon(
                                onPressed: () => _opname(p),
                                icon: const Icon(Icons.fact_check_outlined, size: 16),
                                label: const Text('Hitung'),
                              ),
                            ]),
                          );
                        },
                      ),
                    ),
                  ]),
                  RefreshIndicator(
                    onRefresh: _fetch,
                    child: _riwayat.isEmpty
                        ? ListView(children: const Padding(
                            padding: EdgeInsets.all(40),
                            child: Center(child: Text('Belum ada riwayat opname.', style: TextStyle(color: C.sub))),
                          ))
                        : ListView.builder(
                            padding: const EdgeInsets.all(16),
                            itemCount: _riwayat.length,
                            itemBuilder: (c, i) {
                              final o = _riwayat[i];
                              final selisih = (o['selisih'] ?? 0) as int;
                              return Container(
                                margin: const EdgeInsets.only(bottom: 10),
                                padding: const EdgeInsets.all(12),
                                decoration: BoxDecoration(
                                    color: Colors.white, borderRadius: BorderRadius.circular(16), border: Border.all(color: C.border)),
                                child: Row(children: [
                                  Expanded(
                                    child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                                      Text(((o['produk'] as Map?)?['nama_produk']) ?? '-',
                                          style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w700, color: C.ink)),
                                      const SizedBox(height: 3),
                                      Text(
                                          'Sistem ${o['stok_sistem']} → Fisik ${o['stok_fisik']} · ${o['_kasir'] ?? '-'}\n'
                                          '${o['alasan']} · ${DateFormat('dd MMM yyyy HH:mm').format(DateTime.parse(o['tanggal'].toString()))}',
                                          style: const TextStyle(fontSize: 11, color: C.sub, height: 1.5)),
                                    ]),
                                  ),
                                  Pill(
                                    selisih == 0 ? 'SESUAI' : (selisih > 0 ? '+$selisih' : '$selisih'),
                                    fg: selisih == 0 ? C.green : C.red,
                                    bg: selisih == 0 ? C.greenBg : C.redBg,
                                  ),
                                ]),
                              );
                            },
                          ),
                  ),
                ]),
        ),
      );
