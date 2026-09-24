import 'dart:io';

import 'package:flutter/material.dart';
import 'package:kastra/admin/batch.dart';
import 'package:kastra/admin/dashboard.dart';
import 'package:kastra/admin/kategori.dart';
import 'package:kastra/admin/produk.dart';
import 'package:kastra/admin/users.dart';
import 'package:kastra/admin/opname.dart';
import 'package:kastra/admin/pengaturan.dart';
import 'package:kastra/kasir/kasir.dart';
import 'package:kastra/kasir/shift.dart';
import 'package:kastra/kasir/transaksi.dart';
import 'package:kastra/login.dart';
import 'package:kastra/owner/dashboard.dart';
import 'package:kastra/owner/laporan.dart';
import 'package:kastra/owner/log.dart';
import 'package:kastra/owner/pengeluaran.dart';
import 'package:kastra/services.dart';
import 'package:kastra/theme.dart';

// ignore_for_file: deprecated_member_use, use_build_context_synchronously

void snack(BuildContext c, String msg, {bool err = false}) =>
    ScaffoldMessenger.of(c).showSnackBar(
      SnackBar(
        content: Text(msg),
        backgroundColor: err ? C.red : C.ink,
        duration: Duration(seconds: err ? 4 : 2),
      ),
    );

/// Kartu dasar: putih, border tipis, radius 16 — gaya clean.
class CardX extends StatelessWidget {
  final Widget child;
  final EdgeInsetsGeometry padding;
  final Color? color;
  final Color? borderColor;
  const CardX({super.key, required this.child, this.padding = const EdgeInsets.all(14), this.color, this.borderColor});

  @override
  Widget build(BuildContext context) => Container(
        width: double.infinity,
        padding: padding,
        decoration: BoxDecoration(
          color: color ?? Colors.white,
          borderRadius: BorderRadius.circular(16),
          border: Border.all(color: borderColor ?? C.border),
        ),
        child: child,
      );
}

/// Label kecil bulat (badge status).
class Pill extends StatelessWidget {
  final String text;
  final Color fg;
  final Color? bg;
  const Pill(this.text, {super.key, required this.fg, this.bg});

  @override
  Widget build(BuildContext context) => Container(
        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
        decoration: BoxDecoration(color: bg ?? fg.withOpacity(.1), borderRadius: BorderRadius.circular(6)),
        child: Text(text, style: TextStyle(fontSize: 10, fontWeight: FontWeight.w800, color: fg)),
      );
}

/// Label di atas field (gaya login).
class FieldLabel extends StatelessWidget {
  final String text;
  const FieldLabel(this.text, {super.key});

  @override
  Widget build(BuildContext context) =>
      Text(text, style: const TextStyle(fontSize: 13.5, fontWeight: FontWeight.w600, color: C.label));
}

/// Tombol ikon kecil dalam kotak tinted.
class IconBox extends StatelessWidget {
  final IconData icon;
  final Color color;
  final VoidCallback? onTap;
  final double size;
  const IconBox(this.icon, {super.key, required this.color, this.onTap, this.size = 19});

  @override
  Widget build(BuildContext context) => InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(10),
        child: Container(
          width: 38,
          height: 38,
          decoration: BoxDecoration(color: color.withOpacity(.09), borderRadius: BorderRadius.circular(10)),
          child: Icon(icon, size: size, color: color),
        ),
      );
}

Future<bool> confirm(BuildContext c, String title, String msg,
    {String okLabel = 'Hapus', Color okColor = C.red}) async {
  final ok = await showDialog<bool>(
    context: c,
    builder: (d) => AlertDialog(
      title: Text(title, textAlign: TextAlign.center),
      content: Text(msg, textAlign: TextAlign.center),
      actions: [
        Row(children: [
          Expanded(
            child: ElevatedButton(
              onPressed: () => Navigator.pop(d, false),
              style: ElevatedButton.styleFrom(
                  backgroundColor: const Color(0xFFF1F5F9), foregroundColor: C.label, minimumSize: const Size(0, 46)),
              child: const Text('Batal'),
            ),
          ),
          const SizedBox(width: 10),
          Expanded(
            child: ElevatedButton(
              onPressed: () => Navigator.pop(d, true),
              style: ElevatedButton.styleFrom(backgroundColor: okColor, minimumSize: const Size(0, 46)),
              child: Text(okLabel),
            ),
          ),
        ]),
      ],
    ),
  );
  return ok == true;
}

class SearchField extends StatelessWidget {
  final TextEditingController controller;
  final String hint;
  final VoidCallback onChanged;
  const SearchField(this.controller, {super.key, this.hint = 'Cari...', required this.onChanged});

  @override
  Widget build(BuildContext context) => Container(
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(10),
          boxShadow: [
            BoxShadow(color: Colors.grey.withOpacity(0.3), spreadRadius: 1, blurRadius: 4, offset: const Offset(0, 2)),
          ],
        ),
        child: TextField(
          controller: controller,
          onChanged: (_) => onChanged(),
          cursorColor: C.primary,
          cursorWidth: 1.8,
          style: const TextStyle(fontSize: 15, fontWeight: FontWeight.w500, color: C.ink),
          decoration: InputDecoration(
            hintText: hint,
            hintStyle: const TextStyle(fontSize: 14.5, color: C.iconIdle),
            prefixIcon: const Icon(Icons.search, size: 20, color: C.iconIdle),
            filled: false,
            border: InputBorder.none,
            enabledBorder: InputBorder.none,
            focusedBorder: InputBorder.none,
            contentPadding: const EdgeInsets.symmetric(vertical: 14),
          ),
        ),
      );
}

class FChip extends StatelessWidget {
  final String label;
  final bool selected;
  final Color color;
  final VoidCallback onTap;
  const FChip(this.label, {super.key, required this.selected, required this.onTap, this.color = C.primary});

  @override
  Widget build(BuildContext context) => Padding(
        padding: const EdgeInsets.only(right: 8),
        child: ChoiceChip(
          label: Text(label, style: TextStyle(fontSize: 12, fontWeight: FontWeight.w600, color: selected ? color : C.sub)),
          selected: selected,
          showCheckmark: false,
          selectedColor: color.withOpacity(.12),
          backgroundColor: Colors.white,
          side: BorderSide(color: selected ? color : C.border),
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
          onSelected: (_) => onTap(),
        ),
      );
}

/// Bottom sheet pencarian generik (pilih produk/kategori/sort).
Future<T?> pickSheet<T>(BuildContext context,
    {required String title, required List<T> items, required String Function(T) label, T? selected}) {
  final ctrl = TextEditingController();
  return showModalBottomSheet<T>(
    context: context,
    isScrollControlled: true,
    backgroundColor: Colors.white,
    shape: const RoundedRectangleBorder(borderRadius: BorderRadius.vertical(top: Radius.circular(24))),
    builder: (b) => StatefulBuilder(
      builder: (ctx, ss) {
        final q = ctrl.text.toLowerCase();
        final list = items.where((i) => label(i).toLowerCase().contains(q)).toList();
        return Container(
          height: MediaQuery.of(ctx).size.height * 0.65,
          padding: const EdgeInsets.all(16),
          child: Column(children: [
            Container(width: 40, height: 4, decoration: BoxDecoration(color: C.border, borderRadius: BorderRadius.circular(2))),
            const SizedBox(height: 14),
            Text(title, style: const TextStyle(fontSize: 17, fontWeight: FontWeight.w800, color: C.ink)),
            const SizedBox(height: 16),
            SearchField(ctrl, onChanged: () => ss(() {})),
            const SizedBox(height: 16),
            Expanded(
              child: list.isEmpty
                  ? const Center(child: Text('Tidak ditemukan', style: TextStyle(color: C.sub)))
                  : ListView.builder(
                      itemCount: list.length,
                      itemBuilder: (_, i) {
                        final item = list[i];
                        final sel = item == selected;
                        return ListTile(
                          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                          tileColor: sel ? C.primary.withOpacity(.08) : null,
                          title: Text(label(item),
                              style: TextStyle(fontWeight: sel ? FontWeight.w700 : FontWeight.w500, fontSize: 14, color: sel ? C.primary : C.ink)),
                          trailing: sel ? const Icon(Icons.check_circle, color: C.primary, size: 20) : null,
                          onTap: () => Navigator.pop(ctx, item),
                        );
                      },
                    ),
            ),
          ]),
        );
      },
    ),
  );
}

Future<int?> askQty(BuildContext context, {required int current, required int max}) {
  final ctrl = TextEditingController(text: '$current');
  return showDialog<int>(
    context: context,
    builder: (d) => AlertDialog(
      title: const Text('Edit Jumlah', textAlign: TextAlign.center),
      content: Column(mainAxisSize: MainAxisSize.min, children: [
        Text('Stok tersedia: $max', style: const TextStyle(fontSize: 12.5, fontWeight: FontWeight.w700, color: C.sub)),
        const SizedBox(height: 12),
        TextField(
          controller: ctrl,
          autofocus: true,
          keyboardType: TextInputType.number,
          textAlign: TextAlign.center,
          style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w700),
        ),
      ]),
      actions: [
        Row(children: [
          Expanded(
            child: ElevatedButton(
              onPressed: () => Navigator.pop(d),
              style: ElevatedButton.styleFrom(
                  backgroundColor: const Color(0xFFF1F5F9), foregroundColor: C.label, minimumSize: const Size(0, 46)),
              child: const Text('Batal'),
            ),
          ),
          const SizedBox(width: 10),
          Expanded(
            child: ElevatedButton(
              onPressed: () => Navigator.pop(d, int.tryParse(ctrl.text) ?? 0),
              child: const Text('Simpan'),
            ),
          ),
        ]),
      ],
    ),
  );
}

class StatCard extends StatelessWidget {
  final String title, value;
  final IconData icon;
  final Color color;
  final VoidCallback? onTap;
  const StatCard(this.title, this.value, this.icon, this.color, {super.key, this.onTap});

  @override
  Widget build(BuildContext context) => InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(16),
        child: Container(
          padding: const EdgeInsets.all(14),
          decoration: BoxDecoration(
            color: Colors.white,
            borderRadius: BorderRadius.circular(16),
            border: Border.all(color: C.border),
          ),
          child: Column(mainAxisAlignment: MainAxisAlignment.center, children: [
            Container(
              padding: const EdgeInsets.all(9),
              decoration: BoxDecoration(color: color.withOpacity(.1), borderRadius: BorderRadius.circular(12)),
              child: Icon(icon, color: color, size: 22),
            ),
            const SizedBox(height: 10),
            FittedBox(child: Text(value, style: const TextStyle(fontSize: 18, fontWeight: FontWeight.w800, color: C.ink))),
            const SizedBox(height: 3),
            Text(title,
                style: const TextStyle(fontSize: 11, fontWeight: FontWeight.w600, color: C.sub),
                textAlign: TextAlign.center,
                maxLines: 2),
          ]),
        ),
      );
}

/// Gambar produk: mendukung file lokal (offline) & URL (http).
class ProductImage extends StatelessWidget {
  final String? url;
  final double size;
  const ProductImage(this.url, {super.key, this.size = 50});

  @override
  Widget build(BuildContext context) => Container(
        width: size,
        height: size,
        decoration: BoxDecoration(
          color: C.fieldFill,
          borderRadius: BorderRadius.circular(12),
          border: Border.all(color: C.border),
        ),
        child: ClipRRect(
          borderRadius: BorderRadius.circular(11),
          child: (url == null || url!.isEmpty)
              ? Icon(Icons.inventory_2_outlined, size: size * 0.4, color: C.iconIdle)
              : url!.startsWith('http')
                  ? Image.network(url!,
                      fit: BoxFit.cover,
                      errorBuilder: (_, _, _) => Icon(Icons.broken_image, size: size * 0.4, color: C.iconIdle),
                      loadingBuilder: (_, child, prog) =>
                          prog == null ? child : const Center(child: CircularProgressIndicator(strokeWidth: 2)))
                  : Image.file(File(url!),
                      fit: BoxFit.cover,
                      errorBuilder: (_, _, _) => Icon(Icons.broken_image, size: size * 0.4, color: C.iconIdle)),
        ),
      );
}

/// Avatar akun aktif untuk AppBar (pengganti tombol refresh).
/// Ketuk untuk melihat info akun yang sedang login.
class AccountButton extends StatefulWidget {
  final int userId;
  const AccountButton({super.key, required this.userId});

  @override
  State<AccountButton> createState() => _AccountButtonState();
}

class _AccountButtonState extends State<AccountButton> {
  Map<String, dynamic>? _user;

  @override
  void initState() {
    super.initState();
    DB.getUser(widget.userId).then((u) {
      if (mounted) setState(() => _user = u);
    });
  }

  Color get _rc =>
      {'admin': C.primary, 'owner': C.purple, 'kasir': C.teal}[(_user?['role'] ?? '').toString()] ?? C.sub;

  /// Ganti password sendiri — verifikasi password lama, simpan hash baru.
  Future<void> _changePassword() async {
    final lama = TextEditingController();
    final baru = TextEditingController();
    final ulang = TextEditingController();
    final ok = await showDialog<bool>(
      context: context,
      builder: (d) => AlertDialog(
        title: const Text('Ganti Password', textAlign: TextAlign.center),
        content: Column(mainAxisSize: MainAxisSize.min, children: [
          TextField(controller: lama, obscureText: true, decoration: const InputDecoration(labelText: 'Password Lama')),
          const SizedBox(height: 10),
          TextField(controller: baru, obscureText: true, decoration: const InputDecoration(labelText: 'Password Baru')),
          const SizedBox(height: 10),
          TextField(controller: ulang, obscureText: true, decoration: const InputDecoration(labelText: 'Ulangi Password Baru')),
        ]),
        actions: [
          TextButton(onPressed: () => Navigator.pop(d), child: const Text('Batal')),
          Builder(builder: (dd) => ElevatedButton(
            onPressed: () {
              if (baru.text.length < 6) {
                snack(dd, 'Password baru minimal 6 karakter', err: true);
                return;
              }
              if (baru.text != ulang.text) {
                snack(dd, 'Konfirmasi tidak sama', err: true);
                return;
              }
              Navigator.pop(d, true);
            },
            child: const Text('Simpan'),
          )),
        ],
      ),
    );
    if (ok == true && mounted) {
      final success = await DB.changeOwnPassword(widget.userId, lama.text, baru.text);
      if (mounted) snack(context, success ? 'Password berhasil diganti' : 'Ganti password gagal / password lama salah', err: !success);
    }
  }

  Future<void> _logout() async {
    if (!await confirm(context, 'Logout', 'Yakin ingin logout?', okLabel: 'Logout', okColor: C.red)) return;
    await DB.log(widget.userId, 'Logout pada ${fdate(DateTime.now())}');
    await DB.clearSession();
    if (!mounted) return;
    Navigator.pushAndRemoveUntil(context, MaterialPageRoute(builder: (_) => const LoginPage()), (r) => false);
  }

  void _showInfo() {
    final u = _user;
    if (u == null) return;
    showModalBottomSheet(
      context: context,
      backgroundColor: Colors.white,
      shape: const RoundedRectangleBorder(borderRadius: BorderRadius.vertical(top: Radius.circular(24))),
      builder: (b) => SafeArea(
        child: Padding(
          padding: const EdgeInsets.all(20),
          child: Column(mainAxisSize: MainAxisSize.min, children: [
            Container(width: 40, height: 4, decoration: BoxDecoration(color: C.border, borderRadius: BorderRadius.circular(2))),
            const SizedBox(height: 18),
            Container(
              width: 64,
              height: 64,
              decoration: BoxDecoration(color: _rc.withOpacity(.12), shape: BoxShape.circle),
              child: Center(
                child: Text(initialOf(u['nama_lengkap']?.toString()),
                    style: TextStyle(fontSize: 24, fontWeight: FontWeight.w800, color: _rc)),
              ),
            ),
            const SizedBox(height: 12),
            Text('${u['nama_lengkap'] ?? '-'}', style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w800, color: C.ink)),
            const SizedBox(height: 4),
            Text('@${u['username'] ?? '-'}', style: const TextStyle(fontSize: 13, color: C.sub)),
            const SizedBox(height: 10),
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 5),
              decoration: BoxDecoration(color: _rc.withOpacity(.1), borderRadius: BorderRadius.circular(8)),
              child: Text((u['role'] ?? '').toString().toUpperCase(),
                  style: TextStyle(fontSize: 11, fontWeight: FontWeight.w800, color: _rc, letterSpacing: 1)),
            ),
            const SizedBox(height: 16),
            SizedBox(
              width: double.infinity,
              height: 48,
              child: OutlinedButton.icon(
                onPressed: () {
                  Navigator.pop(b);
                  _changePassword();
                },
                icon: const Icon(Icons.lock_outline_rounded, size: 18),
                label: const Text('Ganti Password'),
                style: OutlinedButton.styleFrom(
                  foregroundColor: C.ink,
                  side: const BorderSide(color: C.border, width: 1.3),
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
                ),
              ),
            ),
            const SizedBox(height: 8),
            SizedBox(
              width: double.infinity,
              height: 48,
              child: ElevatedButton.icon(
                onPressed: () {
                  Navigator.pop(b);
                  _logout();
                },
                style: ElevatedButton.styleFrom(
                  backgroundColor: C.redBg,
                  foregroundColor: C.red,
                  elevation: 0,
                  side: const BorderSide(color: C.redBorder, width: 1.3),
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
                ),
                icon: const Icon(Icons.logout_rounded, size: 18),
                label: const Text('Log Out', style: TextStyle(fontWeight: FontWeight.w800)),
              ),
            ),
            const SizedBox(height: 8),
          ]),
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) => GestureDetector(
        onTap: _showInfo,
        child: Padding(
          padding: const EdgeInsets.only(right: 14),
          child: Container(
            width: 36,
            height: 36,
            decoration: BoxDecoration(color: _rc.withOpacity(.12), shape: BoxShape.circle, border: Border.all(color: _rc.withOpacity(.3))),
            child: Center(
              child: Text(initialOf(_user?['nama_lengkap']?.toString()),
                  style: TextStyle(fontSize: 14, fontWeight: FontWeight.w800, color: _rc)),
            ),
          ),
        ),
      );
}

Widget dashboardFor(String role, int userId) {
  if (role == 'kasir') return KasirPage(userId: userId);
  if (role == 'owner') return OwnerDashboard(userId: userId);
  return AdminDashboard(userId: userId);
}

/// Drawer tunggal untuk semua role — gaya modern.
class AppDrawer extends StatefulWidget {
  final int userId;
  final String role;
  const AppDrawer({super.key, required this.userId, required this.role});

  @override
  State<AppDrawer> createState() => _AppDrawerState();
}

class _AppDrawerState extends State<AppDrawer> {
  String _name = '...';

  @override
  void initState() {
    super.initState();
    DB.getUser(widget.userId).then((u) {
      if (mounted && u != null) setState(() => _name = u['nama_lengkap'] ?? 'User');
    });
  }

  List<(IconData, String, Widget)> get _menu {
    final id = widget.userId;
    switch (widget.role) {
      case 'kasir':
        return [
          (Icons.dashboard_outlined, 'Beranda Kasir', KasirPage(userId: id)),
          (Icons.lock_open_outlined, 'Shift Kasir', ShiftPage(userId: id)),
          (Icons.receipt_long_outlined, 'Riwayat Transaksi', TransaksiPage(userId: id)),
        ];
      case 'owner':
        return [
          (Icons.dashboard_outlined, 'Beranda Owner', OwnerDashboard(userId: id)),
          (Icons.insights_outlined, 'Laporan Analitik', LaporanPage(userId: id)),
          (Icons.people_outline, 'Manajemen User', UsersPage(userId: id, ownerMode: true)),
          (Icons.inventory_2_outlined, 'Data Produk', ProdukPage(userId: id, readOnly: true)),
          (Icons.receipt_long_outlined, 'Laporan Transaksi', TransaksiPage(userId: id, semua: true)),
          (Icons.money_off_outlined, 'Pengeluaran', PengeluaranPage(userId: id)),
          (Icons.history_edu_outlined, 'Log Aktivitas', LogPage(userId: id)),
        ];
      default:
        return [
          (Icons.dashboard_outlined, 'Beranda Admin', AdminDashboard(userId: id)),
          (Icons.inventory_2_outlined, 'Daftar Produk', ProdukPage(userId: id)),
          (Icons.batch_prediction_outlined, 'Batch Stok', BatchPage(userId: id)),
          (Icons.fact_check_outlined, 'Opname Stok', OpnamePage(userId: id)),
          (Icons.category_outlined, 'Kategori Produk', KategoriPage(userId: id)),
          (Icons.people_outline, 'Manajemen User', UsersPage(userId: id)),
          (Icons.settings_outlined, 'Pengaturan Toko', PengaturanPage(userId: id)),
        ];
    }
  }

  Future<void> _logout() async {
    if (!await confirm(context, 'Logout', 'Yakin ingin logout?', okLabel: 'Logout', okColor: C.red)) return;
    await DB.clearSession();
    await DB.log(widget.userId, 'Logout pada ${fdate(DateTime.now())}');
    if (!mounted) return;
    Navigator.pushAndRemoveUntil(context, MaterialPageRoute(builder: (_) => const LoginPage()), (r) => false);
  }

  @override
  Widget build(BuildContext context) => Drawer(
        backgroundColor: Colors.white,
        child: Column(children: [
          // Header gradient gelombang (sama dengan login)
          Container(
            width: double.infinity,
            padding: const EdgeInsets.fromLTRB(20, 52, 20, 22),
            decoration: const BoxDecoration(gradient: waveGradient),
            child: Row(children: [
              Container(
                width: 46,
                height: 46,
                decoration: BoxDecoration(color: Colors.white.withOpacity(.18), borderRadius: BorderRadius.circular(14)),
                child: Center(
                  child: Text(initialOf(_name),
                      style: const TextStyle(fontSize: 18, fontWeight: FontWeight.w800, color: Colors.white)),
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                  Text(_name,
                      style: const TextStyle(color: Colors.white, fontWeight: FontWeight.w800, fontSize: 15),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis),
                  const SizedBox(height: 3),
                  Text(widget.role.toUpperCase(),
                      style: TextStyle(
                          color: Colors.white.withOpacity(.75), fontSize: 10.5, fontWeight: FontWeight.w800, letterSpacing: 2)),
                ]),
              ),
            ]),
          ),
          const SizedBox(height: 8),
          ..._menu.map((m) => Padding(
                padding: const EdgeInsets.symmetric(horizontal: 10),
                child: ListTile(
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                  leading: Icon(m.$1, size: 21, color: C.sub),
                  title: Text(m.$2, style: const TextStyle(fontSize: 14, fontWeight: FontWeight.w600, color: C.label)),
                  onTap: () {
                    Navigator.pop(context);
                    if (m.$2.contains('Beranda')) {
                      Navigator.pushAndRemoveUntil(context, MaterialPageRoute(builder: (_) => m.$3), (r) => false);
                    } else {
                      Navigator.pushReplacement(context, MaterialPageRoute(builder: (_) => m.$3));
                    }
                  },
                ),
              )),
          const Spacer(),
          const Divider(),
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 8, 16, 16),
            child: SizedBox(
              width: double.infinity,
              height: 50,
              child: ElevatedButton.icon(
                onPressed: _logout,
                style: ElevatedButton.styleFrom(
                  backgroundColor: C.redBg,
                  foregroundColor: C.red,
                  elevation: 0,
                  side: const BorderSide(color: C.redBorder, width: 1.3),
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
                ),
                icon: const Icon(Icons.logout_rounded, size: 18),
                label: const Text('Log Out', style: TextStyle(fontWeight: FontWeight.w800)),
              ),
            ),
          ),
        ]),
      );
}