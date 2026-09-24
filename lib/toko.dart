import 'dart:convert';
import 'dart:io';

import 'package:file_picker/file_picker.dart' as fp;
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:kastra/login.dart';
import 'package:kastra/services.dart';
import 'package:kastra/theme.dart';

// ignore_for_file: deprecated_member_use, use_build_context_synchronously

/// ---------------------------------------------------------------------------
/// FIELD INPUT (gaya login — icon mata untuk show/hide password)
/// ---------------------------------------------------------------------------
class _AuthFieldToko extends StatelessWidget {
  const _AuthFieldToko({
    required this.label,
    required this.hint,
    required this.icon,
    required this.controller,
    this.obscure = false,
    this.onToggleObscure,
  });

  final String label;
  final String hint;
  final IconData icon;
  final TextEditingController controller;
  final bool obscure;
  final VoidCallback? onToggleObscure;

  @override
  Widget build(BuildContext context) => Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(label, style: const TextStyle(fontSize: 13.5, fontWeight: FontWeight.w600, color: kLabel)),
          const SizedBox(height: 8),
          Container(
            height: 54,
            padding: const EdgeInsets.symmetric(horizontal: 16),
            decoration: BoxDecoration(color: const Color(0xFFF5F5F5), borderRadius: BorderRadius.circular(14)),
            child: Row(children: [
              Icon(icon, size: 20, color: kIconIdle),
              const SizedBox(width: 12),
              Expanded(
                child: TextField(
                  controller: controller,
                  obscureText: obscure,
                  cursorColor: kPrimary,
                  cursorWidth: 1.8,
                  style: const TextStyle(fontSize: 15, fontWeight: FontWeight.w500, color: kInk),
                  decoration: InputDecoration(
                    border: InputBorder.none,
                    isCollapsed: true,
                    hintText: hint,
                    hintStyle: const TextStyle(fontSize: 14.5, fontWeight: FontWeight.w400, color: kIconIdle),
                  ),
                ),
              ),
              if (onToggleObscure != null)
                GestureDetector(
                  onTap: onToggleObscure,
                  behavior: HitTestBehavior.opaque,
                  child: Padding(
                    padding: const EdgeInsets.fromLTRB(8, 14, 0, 14),
                    child: Icon(
                      obscure ? Icons.visibility_off_outlined : Icons.visibility_outlined,
                      size: 20,
                      color: kIconIdle,
                    ),
                  ),
                ),
            ]),
          ),
        ],
      );
}

/// ---------------------------------------------------------------------------
/// DAFTAR TOKO BARU (data toko lama dihapus total)
/// ---------------------------------------------------------------------------
class RegisterTokoPage extends StatefulWidget {
  const RegisterTokoPage({super.key});

  @override
  State<RegisterTokoPage> createState() => _RegisterTokoPageState();
}

class _RegisterTokoPageState extends State<RegisterTokoPage> {
  final _nama = TextEditingController();
  final _alamat = TextEditingController();
  final _ownerNama = TextEditingController();
  final _ownerUser = TextEditingController();
  final _pass = TextEditingController();
  final _pass2 = TextEditingController();
  bool _obscure1 = true;
  bool _obscure2 = true;
  bool _load = false;

  String? _validate() {
    if (_nama.text.trim().isEmpty) return 'Nama toko masih kosong';
    if (_alamat.text.trim().isEmpty) return 'Alamat toko masih kosong';
    if (_ownerNama.text.trim().isEmpty) return 'Nama owner masih kosong';
    if (_ownerUser.text.trim().isEmpty) return 'Username owner masih kosong';
    if (_pass.text.isEmpty) return 'Password masih kosong';
    if (_pass.text.length < 6) return 'Password minimal 6 karakter';
    if (_pass.text != _pass2.text) return 'Konfirmasi password tidak sama';
    return null;
  }

  Future<void> _submit() async {
    FocusScope.of(context).unfocus();
    final err = _validate();
    if (err != null) {
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(err), backgroundColor: C.red));
      return;
    }

    // Data toko lama akan dihapus total — wajib konfirmasi dulu.
    if (await DB.hasToko) {
      final go = await showDialog<bool>(
        context: context,
        builder: (d) => AlertDialog(
          title: const Text('Ganti Data Toko?', textAlign: TextAlign.center),
          content: const Text(
            'Perangkat ini sudah berisi data toko.\n\nSemua data lama (akun, produk, stok, transaksi, pengeluaran, log, dan gambarnya) akan DIHAPUS PERMANEN dan diganti dengan toko baru ini.\n\nLanjutkan?',
            textAlign: TextAlign.center,
            style: TextStyle(height: 1.5),
          ),
          actions: [
            Row(children: [
              Expanded(
                child: ElevatedButton(
                  onPressed: () => Navigator.pop(d, false),
                  style: ElevatedButton.styleFrom(
                      backgroundColor: const Color(0xFFF1F5F9), foregroundColor: kLabel, minimumSize: const Size(0, 46)),
                  child: const Text('Batal'),
                ),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: ElevatedButton(
                  onPressed: () => Navigator.pop(d, true),
                  style: ElevatedButton.styleFrom(backgroundColor: C.red, minimumSize: const Size(0, 46)),
                  child: const Text('Ya, Hapus & Daftar'),
                ),
              ),
            ]),
          ],
        ),
      );
      if (go != true || !mounted) return;
    }

    setState(() => _load = true);
    final key = await DB.registerToko(
      nama: _nama.text,
      alamat: _alamat.text,
      ownerNama: _ownerNama.text,
      ownerUsername: _ownerUser.text,
      password: _pass.text,
    );
    if (!mounted) return;
    setState(() => _load = false);
    if (key == null) {
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(
        content: Text('Gagal mendaftarkan: ${DB.lastError ?? 'username mungkin sudah dipakai'}'),
        backgroundColor: C.red,
      ));
      return;
    }
    _showRecoveryKey(key);
  }

  /// Recovery key ditampilkan SEKALI — wajib disimpan owner.
  void _showRecoveryKey(String key) {
    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (d) => AlertDialog(
        title: const Text('Pendaftaran Berhasil', textAlign: TextAlign.center),
        content: Column(mainAxisSize: MainAxisSize.min, children: [
          const Icon(Icons.key_rounded, color: kPrimary, size: 44),
          const SizedBox(height: 12),
          const Text('Recovery Key Anda',
              style: TextStyle(fontSize: 13, fontWeight: FontWeight.w700, color: kLabel)),
          const SizedBox(height: 8),
          Container(
            width: double.infinity,
            padding: const EdgeInsets.all(14),
            decoration: BoxDecoration(color: const Color(0xFFF5F5F5), borderRadius: BorderRadius.circular(12)),
            child: SelectableText(key,
                textAlign: TextAlign.center,
                style: const TextStyle(fontSize: 18, fontWeight: FontWeight.w800, letterSpacing: 1.5, color: kInk)),
          ),
          const SizedBox(height: 12),
          const Text(
            'Simpan dan jaga kode ini! Hanya dengan kode ini kata sandi dapat direset jika lupa. Kode ini hanya ditampilkan sekali.',
            style: TextStyle(fontSize: 12, color: kSub, height: 1.5),
          ),
        ]),
        actions: [
          Row(children: [
            Expanded(
              child: ElevatedButton(
                onPressed: () {
                  Clipboard.setData(ClipboardData(text: key));
                  ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Recovery key disalin')));
                },
                style: ElevatedButton.styleFrom(
                    backgroundColor: const Color(0xFFF1F5F9), foregroundColor: kLabel, minimumSize: const Size(0, 46)),
                child: const Text('Salin'),
              ),
            ),
            const SizedBox(width: 10),
            Expanded(
              child: ElevatedButton(
                onPressed: () {
                  Navigator.of(d).pop(); // tutup dialog
                  Navigator.of(context).pop(); // kembali ke login
                },
                child: const Text('Selesai'),
              ),
            ),
          ]),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) => Scaffold(
        backgroundColor: Colors.white,
        appBar: AppBar(
          title: const Text('Daftar Toko'),
          backgroundColor: kPrimary,
          foregroundColor: Colors.white,
          iconTheme: const IconThemeData(color: Colors.white),
        ),
        body: SingleChildScrollView(
          padding: const EdgeInsets.all(24),
          child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
            const Icon(Icons.storefront_rounded, color: kPrimary, size: 48),
            const SizedBox(height: 10),
            const Text('Buat Toko & Akun Owner',
                textAlign: TextAlign.center,
                style: TextStyle(fontSize: 20, fontWeight: FontWeight.w800, color: kInk)),
            const SizedBox(height: 4),
            const Text('Data toko akan muncul pada struk transaksi',
                textAlign: TextAlign.center, style: TextStyle(fontSize: 13, color: kSub)),
            const SizedBox(height: 24),
            _AuthFieldToko(label: 'Nama Toko', hint: 'Contoh: Toko Kastra Jaya', icon: Icons.store_outlined, controller: _nama),
            const SizedBox(height: 14),
            _AuthFieldToko(label: 'Alamat Toko', hint: 'Muncul di struk / bukti transaksi', icon: Icons.location_on_outlined, controller: _alamat),
            const SizedBox(height: 14),
            _AuthFieldToko(label: 'Nama Owner', hint: 'Nama lengkap owner', icon: Icons.badge_outlined, controller: _ownerNama),
            const SizedBox(height: 14),
            _AuthFieldToko(label: 'Username Owner', hint: 'Untuk login', icon: Icons.person_outline_rounded, controller: _ownerUser),
            const SizedBox(height: 14),
            _AuthFieldToko(
                label: 'Password',
                hint: 'Minimal 6 karakter',
                icon: Icons.lock_outline_rounded,
                controller: _pass,
                obscure: _obscure1,
                onToggleObscure: () => setState(() => _obscure1 = !_obscure1)),
            const SizedBox(height: 14),
            _AuthFieldToko(
                label: 'Konfirmasi Password',
                hint: 'Ulangi password',
                icon: Icons.lock_outline_rounded,
                controller: _pass2,
                obscure: _obscure2,
                onToggleObscure: () => setState(() => _obscure2 = !_obscure2)),
            const SizedBox(height: 16),
            SizedBox(
              width: double.infinity,
              height: 54,
              child: ElevatedButton(
                onPressed: _load ? null : _submit,
                style: ElevatedButton.styleFrom(
                  backgroundColor: kPrimary,
                  foregroundColor: Colors.white,
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
                ),
                child: _load
                    ? const SizedBox(width: 20, height: 20, child: CircularProgressIndicator(color: Colors.white, strokeWidth: 2.4))
                    : const Text('Daftarkan Toko', style: TextStyle(fontSize: 16, fontWeight: FontWeight.w700)),
              ),
            ),
          ]),
        ),
      );
}

/// ---------------------------------------------------------------------------
/// LUPA KATA SANDI — reset via recovery key
/// ---------------------------------------------------------------------------
class ForgotPasswordPage extends StatefulWidget {
  const ForgotPasswordPage({super.key});

  @override
  State<ForgotPasswordPage> createState() => _ForgotPasswordPageState();
}

class _ForgotPasswordPageState extends State<ForgotPasswordPage> {
  final _user = TextEditingController();
  final _key = TextEditingController();
  final _pass = TextEditingController();
  final _pass2 = TextEditingController();
  bool _obscure1 = true;
  bool _obscure2 = true;
  bool _load = false;

  Future<void> _submit() async {
    FocusScope.of(context).unfocus();
    String? err;
    if (_user.text.trim().isEmpty) {
      err = 'Username masih kosong';
    } else if (_key.text.trim().isEmpty) {
      err = 'Recovery key masih kosong';
    } else if (_pass.text.isEmpty) {
      err = 'Password baru masih kosong';
    } else if (_pass.text.length < 6) {
      err = 'Password minimal 6 karakter';
    } else if (_pass.text != _pass2.text) {
      err = 'Konfirmasi password tidak sama';
    }
    if (err != null) {
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(err), backgroundColor: C.red));
      return;
    }
    setState(() => _load = true);
    final error = await DB.resetPassword(_user.text, _key.text, _pass.text);
    if (!mounted) return;
    setState(() => _load = false);
    if (error != null) {
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(error), backgroundColor: C.red));
      return;
    }
    ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Password berhasil direset. Silakan login.')));
    Navigator.pop(context);
  }

  @override
  Widget build(BuildContext context) => Scaffold(
        backgroundColor: Colors.white,
        appBar: AppBar(
          title: const Text('Lupa Kata Sandi'),
          backgroundColor: kPrimary,
          foregroundColor: Colors.white,
          iconTheme: const IconThemeData(color: Colors.white),
        ),
        body: SingleChildScrollView(
          padding: const EdgeInsets.all(24),
          child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
            const Icon(Icons.key_rounded, color: kPrimary, size: 48),
            const SizedBox(height: 10),
            const Text('Reset via Recovery Key',
                textAlign: TextAlign.center,
                style: TextStyle(fontSize: 18, fontWeight: FontWeight.w800, color: kInk)),
            const SizedBox(height: 4),
            const Text('Masukkan recovery key yang diberikan saat pendaftaran toko',
                textAlign: TextAlign.center, style: TextStyle(fontSize: 13, color: kSub)),
            const SizedBox(height: 24),
            _AuthFieldToko(label: 'Username', hint: 'Username akun yang direset', icon: Icons.person_outline_rounded, controller: _user),
            const SizedBox(height: 14),
            _AuthFieldToko(label: 'Recovery Key', hint: 'XXXX-XXXX-XXXX-XXXX', icon: Icons.key_outlined, controller: _key),
            const SizedBox(height: 14),
            _AuthFieldToko(
                label: 'Password Baru',
                hint: 'Minimal 6 karakter',
                icon: Icons.lock_outline_rounded,
                controller: _pass,
                obscure: _obscure1,
                onToggleObscure: () => setState(() => _obscure1 = !_obscure1)),
            const SizedBox(height: 14),
            _AuthFieldToko(
                label: 'Konfirmasi Password Baru',
                hint: 'Ulangi password baru',
                icon: Icons.lock_outline_rounded,
                controller: _pass2,
                obscure: _obscure2,
                onToggleObscure: () => setState(() => _obscure2 = !_obscure2)),
            const SizedBox(height: 16),
            SizedBox(
              width: double.infinity,
              height: 54,
              child: ElevatedButton(
                onPressed: _load ? null : _submit,
                style: ElevatedButton.styleFrom(
                  backgroundColor: kPrimary,
                  foregroundColor: Colors.white,
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
                ),
                child: _load
                    ? const SizedBox(width: 20, height: 20, child: CircularProgressIndicator(color: Colors.white, strokeWidth: 2.4))
                    : const Text('Reset Kata Sandi', style: TextStyle(fontSize: 16, fontWeight: FontWeight.w700)),
              ),
            ),
          ]),
        ),
      );
}

/// ---------------------------------------------------------------------------
/// IMPORT DATA TOKO — via FILE PICKER
/// Format: {"toko": {...}, "users": [...], "categories": [...], "produk": [...]}
/// ---------------------------------------------------------------------------
Future<void> importTokoFlow(BuildContext context) async {
  // Pilih file backup.
  final res = await fp.FilePicker.platform.pickFiles(type: fp.FileType.any);
  if (res == null || res.files.isEmpty) return;
  final path = res.files.single.path;
  if (path == null) {
    if (!context.mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('File tidak dapat dibaca'), backgroundColor: C.red));
    return;
  }

  // Data lama akan diganti total — konfirmasi dulu.
  final go = await showDialog<bool>(
    context: context,
    builder: (d) => AlertDialog(
      title: const Text('Import Data Toko', textAlign: TextAlign.center),
      content: const Text(
        'Seluruh data toko yang ada di perangkat ini (akun, produk, transaksi, dll.) akan DIHAPUS PERMANEN dan diganti dengan data dari file backup.\n\nLanjutkan?',
        textAlign: TextAlign.center,
        style: TextStyle(height: 1.5),
      ),
      actions: [
        Row(children: [
          Expanded(
            child: ElevatedButton(
              onPressed: () => Navigator.pop(d, false),
              style: ElevatedButton.styleFrom(
                  backgroundColor: const Color(0xFFF1F5F9), foregroundColor: kLabel, minimumSize: const Size(0, 46)),
              child: const Text('Batal'),
            ),
          ),
          const SizedBox(width: 10),
          Expanded(
            child: ElevatedButton(
              onPressed: () => Navigator.pop(d, true),
              child: const Text('Import'),
            ),
          ),
        ]),
      ],
    ),
  );
  if (go != true || !context.mounted) return;

  try {
    final content = await File(path).readAsString();
    final json = jsonDecode(content) as Map<String, dynamic>;
    final error = await DB.importBackup(json);
    if (!context.mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(
      content: Text(error ?? 'Data toko berhasil diimpor. Silakan login.'),
      backgroundColor: error == null ? C.green : C.red,
      duration: const Duration(seconds: 4),
    ));
  } catch (e) {
    if (!context.mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(
      content: Text('File tidak valid: $e'),
      backgroundColor: C.red,
      duration: const Duration(seconds: 4),
    ));
  }
}