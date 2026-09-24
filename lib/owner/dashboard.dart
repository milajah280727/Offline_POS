import 'package:flutter/material.dart';
import 'package:kastra/admin/produk.dart';
import 'package:kastra/admin/users.dart';
import 'package:kastra/kasir/transaksi.dart';
import 'package:kastra/owner/pengeluaran.dart';
import 'package:kastra/services.dart';
import 'package:kastra/theme.dart';
import 'package:kastra/widgets.dart';

// ignore_for_file: deprecated_member_use

class OwnerDashboard extends StatefulWidget {
  final int userId;
  const OwnerDashboard({super.key, required this.userId});

  @override
  State<OwnerDashboard> createState() => _OwnerDashboardState();
}

class _OwnerDashboardState extends State<OwnerDashboard> {
  bool _load = true;
  int _omset = 0, _hpp = 0, _out = 0, _trx = 0, _produk = 0, _habis = 0, _users = 0;

  @override
  void initState() {
    super.initState();
    _fetch();
  }

  Future<void> _fetch() async {
    setState(() => _load = true);
    try {
      final s = await DB.ownerToday();
      if (!mounted) return;
      setState(() {
        _omset = s['omset'] as int;
        _hpp = s['hpp'] as int;
        _out = s['out'] as int;
        _trx = s['trx'] as int;
        _produk = s['produk'] as int;
        _habis = s['habis'] as int;
        _users = s['users'] as int;
        _load = false;
      });
    } catch (e) {
      debugPrint('$e');
      if (mounted) setState(() => _load = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final labaKotor = _omset - _hpp;
    final labaBersih = labaKotor - _out;
    return Scaffold(
      appBar: AppBar(title: const Text('Beranda Owner')),
      drawer: AppDrawer(userId: widget.userId, role: 'owner'),
      body: _load
          ? const Center(child: CircularProgressIndicator(color: C.primary))
          : ListView(padding: const EdgeInsets.all(16), children: [
              Text('Ringkasan Hari Ini', style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w800, color: C.ink)),
              const SizedBox(height: 3),
              Text(fdate(DateTime.now(), 'EEEE, d MMM yyyy'), style: const TextStyle(fontSize: 12, color: C.sub)),
              const SizedBox(height: 16),
              // Kartu Laba Rugi — gradient gelombang (gaya login)
              Container(
                width: double.infinity,
                padding: const EdgeInsets.all(20),
                decoration: BoxDecoration(
                  gradient: waveGradient,
                  borderRadius: BorderRadius.circular(20),
                  boxShadow: [BoxShadow(color: C.primary.withOpacity(.25), blurRadius: 14, offset: const Offset(0, 8))],
                ),
                child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                  Row(mainAxisAlignment: MainAxisAlignment.spaceBetween, children: [
                    const Text('Laba Rugi Hari Ini', style: TextStyle(color: Colors.white, fontSize: 13.5, fontWeight: FontWeight.w700)),
                    Container(
                      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                      decoration: BoxDecoration(color: Colors.white.withOpacity(.15), borderRadius: BorderRadius.circular(6)),
                      child: Text('Real-time', style: TextStyle(color: Colors.white.withOpacity(.85), fontSize: 10, fontWeight: FontWeight.w700)),
                    ),
                  ]),
                  const SizedBox(height: 16),
                  _f('Pendapatan (Omset)', _omset),
                  _f('HPP (Harga Pokok)', -_hpp),
                  const Divider(color: Colors.white24, height: 24),
                  _f('Laba Kotor', labaKotor, bold: true),
                  InkWell(
                    onTap: () => Navigator.push(context, MaterialPageRoute(builder: (_) => PengeluaranPage(userId: widget.userId))),
                    child: _f('Pengeluaran Operasional', -_out, tappable: true),
                  ),
                  const Divider(color: Colors.white24, height: 24),
                  _f('Laba Bersih', labaBersih, bold: true, big: true),
                ]),
              ),
              const SizedBox(height: 24),
              GridView.count(
                shrinkWrap: true,
                physics: const NeverScrollableScrollPhysics(),
                crossAxisCount: 2,
                crossAxisSpacing: 12,
                mainAxisSpacing: 12,
                childAspectRatio: 1.15,
                children: [
                  StatCard('Transaksi', '$_trx', Icons.shopping_bag_outlined, C.teal, onTap: () => Navigator.push(context, MaterialPageRoute(builder: (_) => TransaksiPage(userId: widget.userId, semua: true)))),
                  StatCard('Total Produk', '$_produk', Icons.inventory_2_outlined, C.primary, onTap: () => Navigator.push(context, MaterialPageRoute(builder: (_) => ProdukPage(userId: widget.userId, readOnly: true)))),
                  StatCard('Stok Habis', '$_habis', Icons.warning_amber_rounded, C.red, onTap: () => Navigator.push(context, MaterialPageRoute(builder: (_) => ProdukPage(userId: widget.userId, readOnly: true)))),
                  StatCard('Total User', '$_users', Icons.people_outline, C.green, onTap: () => Navigator.push(context, MaterialPageRoute(builder: (_) => UsersPage(userId: widget.userId, ownerMode: true)))),
                ],
              ),
            ]),
    );
  }

  Widget _f(String label, int value, {bool bold = false, bool big = false, bool tappable = false}) => Padding(
        padding: const EdgeInsets.symmetric(vertical: 3),
        child: Row(mainAxisAlignment: MainAxisAlignment.spaceBetween, children: [
          Row(children: [
            Text(label, style: TextStyle(color: Colors.white.withOpacity(.85), fontSize: big ? 14 : 12.5, fontWeight: bold ? FontWeight.w700 : FontWeight.w500)),
            if (tappable) const SizedBox(width: 4),
            if (tappable) Icon(Icons.chevron_right, size: 15, color: Colors.white.withOpacity(.6)),
          ]),
          Text(rp(value),
              style: TextStyle(color: Colors.white, fontSize: big ? 20 : 13.5, fontWeight: FontWeight.w800)),
        ]),
      );
}