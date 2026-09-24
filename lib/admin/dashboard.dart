import 'package:flutter/material.dart';
import 'package:kastra/services.dart';
import 'package:kastra/theme.dart';
import 'package:kastra/widgets.dart';

// ignore_for_file: deprecated_member_use

class AdminDashboard extends StatefulWidget {
  final int userId;
  const AdminDashboard({super.key, required this.userId});

  @override
  State<AdminDashboard> createState() => _AdminDashboardState();
}

class _AdminDashboardState extends State<AdminDashboard> {
  bool _load = true;
  int _produk = 0, _trx = 0, _omset = 0, _low = 0;
  List<Map<String, dynamic>> _nearExp = [];

  @override
  void initState() {
    super.initState();
    _fetch();
  }

  Future<void> _fetch() async {
    setState(() => _load = true);
    try {
      final s = await DB.adminToday();
      if (!mounted) return;
      setState(() {
        _produk = s['produk'] as int;
        _low = s['low'] as int;
        _trx = s['trx'] as int;
        _omset = s['omset'] as int;
        _nearExp = List<Map<String, dynamic>>.from(s['nearExp']);
        _load = false;
      });
    } catch (e) {
      debugPrint('$e');
      if (mounted) setState(() => _load = false);
    }
  }

  @override
  Widget build(BuildContext context) => Scaffold(
        appBar: AppBar(
          title: const Text('Dashboard Admin'),
          actions: [AccountButton(userId: widget.userId)],
        ),
        drawer: AppDrawer(userId: widget.userId, role: 'admin'),
        body: _load
            ? const Center(child: CircularProgressIndicator(color: C.primary))
            : ListView(padding: const EdgeInsets.all(16), children: [
                Text('Ringkasan Hari Ini', style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w800, color: C.ink)),
                const SizedBox(height: 3),
                Text(fdate(DateTime.now(), 'EEEE, d MMM yyyy'), style: const TextStyle(fontSize: 12, color: C.sub)),
                const SizedBox(height: 16),
                GridView.count(
                  shrinkWrap: true,
                  physics: const NeverScrollableScrollPhysics(),
                  crossAxisCount: 2,
                  crossAxisSpacing: 12,
                  mainAxisSpacing: 12,
                  childAspectRatio: 1.15,
                  children: [
                    StatCard('Total Produk', '$_produk', Icons.inventory_2_outlined, C.primary),
                    StatCard('Transaksi', '$_trx', Icons.receipt_long_outlined, C.teal),
                    StatCard('Omset Hari Ini', rp(_omset), Icons.payments_outlined, C.pink),
                    StatCard('Stok Menipis', '$_low', Icons.warning_amber_rounded, C.red),
                  ],
                ),
                const SizedBox(height: 26),
                Row(mainAxisAlignment: MainAxisAlignment.spaceBetween, children: [
                  const Text('Peringatan Kadaluarsa', style: TextStyle(fontSize: 15, fontWeight: FontWeight.w800, color: C.ink)),
                  Pill('≤ 30 hari', fg: C.orange, bg: C.orangeBg),
                ]),
                const SizedBox(height: 12),
                if (_nearExp.isEmpty)
                  const CardX(
                    padding: EdgeInsets.all(28),
                    child: Center(
                      child: Column(children: [
                        Icon(Icons.check_circle_outline, color: C.green, size: 36),
                        SizedBox(height: 10),
                        Text('Aman! Tidak ada produk mendekati kadaluarsa',
                            style: TextStyle(color: C.sub, fontSize: 13), textAlign: TextAlign.center),
                      ]),
                    ),
                  )
                else
                  ..._nearExp.map((b) {
                    final today = dayOnly(DateTime.now());
                    final exp = dayOnly(b['tanggal_exp']);
                    final days = exp.difference(today).inDays;
                    return Container(
                      margin: const EdgeInsets.only(bottom: 10),
                      padding: const EdgeInsets.all(14),
                      decoration: BoxDecoration(color: Colors.white, borderRadius: BorderRadius.circular(16), border: Border.all(color: C.border)),
                      child: Row(children: [
                        Container(width: 4, height: 38, decoration: BoxDecoration(color: C.orange, borderRadius: BorderRadius.circular(4))),
                        const SizedBox(width: 12),
                        Expanded(
                          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                            Text((b['produk'] as Map?)?['nama_produk'] ?? '-',
                                style: const TextStyle(fontSize: 13.5, fontWeight: FontWeight.w700, color: C.ink),
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis),
                            const SizedBox(height: 3),
                            Text('${b['jumlah_stok']} pcs · Exp ${fdate(b['tanggal_exp'], 'd MMM yyyy')}',
                                style: const TextStyle(fontSize: 11.5, color: C.sub)),
                          ]),
                        ),
                        Container(
                          padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 5),
                          decoration: BoxDecoration(color: C.orangeBg, borderRadius: BorderRadius.circular(8)),
                          child: Text(days <= 0 ? 'Hari ini' : '$days hari',
                              style: const TextStyle(fontSize: 11, fontWeight: FontWeight.w800, color: C.orange)),
                        ),
                      ]),
                    );
                  }),
              ]),
      );
}