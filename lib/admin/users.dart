import 'package:flutter/material.dart';
import 'package:kastra/services.dart';
import 'package:kastra/theme.dart';
import 'package:kastra/widgets.dart';

// ignore_for_file: deprecated_member_use, use_build_context_synchronously

class UsersPage extends StatefulWidget {
  final int userId;
  final bool readOnly;
  final bool ownerMode; // true = dibuka oleh owner (kendali penuh)
  const UsersPage({super.key, required this.userId, this.readOnly = false, this.ownerMode = false});

  @override
  State<UsersPage> createState() => _UsersPageState();
}

class _UsersPageState extends State<UsersPage> {
  final _search = TextEditingController();
  List<Map<String, dynamic>> _users = [];
  String _role = 'all';
  bool _load = true;

  @override
  void initState() {
    super.initState();
    _fetch();
  }

  Future<void> _fetch() async {
    setState(() => _load = true);
    try {
      final r = await DB.users;
      if (mounted) {
        setState(() {
          _users = r;
          _load = false;
        });
      }
    } catch (e) {
      debugPrint('$e');
      if (mounted) setState(() => _load = false);
    }
  }

  List<Map<String, dynamic>> get _filtered {
    final q = _search.text.toLowerCase();
    return _users.where((u) {
      final match = (u['nama_lengkap'] ?? '').toString().toLowerCase().contains(q) ||
          (u['username'] ?? '').toString().toLowerCase().contains(q);
      return match && (_role == 'all' || u['role'] == _role);
    }).toList();
  }

  Color _roleColor(String r) => {'admin': C.primary, 'owner': C.purple, 'kasir': C.teal}[r] ?? C.sub;

  bool _isOwner(Map<String, dynamic> u) => (u['role'] ?? '').toString() == 'owner';

  bool _isSelf(Map<String, dynamic> u) => u['id_user'] == widget.userId;

  /// Status teks di bawah nama (plain dulu, tanpa fungsi).
  String _statusText(String role) =>
      role == 'kasir' ? 'Terakhir kirim data: —' : 'Terakhir aktif: —';

  Future<void> _form([Map<String, dynamic>? u]) async {
    // Admin tidak boleh menyentuh akun owner.
    if (!widget.ownerMode && u != null && _isOwner(u)) {
      snack(context, 'Hanya owner yang dapat mengubah akun owner', err: true);
      return;
    }

    final nama = TextEditingController(text: u?['nama_lengkap']);
    final user = TextEditingController(text: u?['username']);
    final pass = TextEditingController();
    final pass2 = TextEditingController();
    bool obscure1 = true, obscure2 = true;
    String role = u?['role'] ?? 'kasir';

    final save = await showDialog<bool>(
      context: context,
      builder: (d) => StatefulBuilder(
        builder: (d, ss) {
          String? passErr;
          if (pass2.text.isNotEmpty && pass.text != pass2.text) passErr = 'Konfirmasi tidak sama';
          return AlertDialog(
            title: Text(u == null ? 'Tambah User' : 'Edit User', textAlign: TextAlign.center),
            content: Column(mainAxisSize: MainAxisSize.min, children: [
              TextField(controller: nama, decoration: const InputDecoration(labelText: 'Nama Lengkap')),
              const SizedBox(height: 10),
              TextField(controller: user, decoration: const InputDecoration(labelText: 'Username')),
              const SizedBox(height: 10),
              TextField(
                controller: pass,
                obscureText: obscure1,
                decoration: InputDecoration(
                  labelText: u == null ? 'Password' : 'Password baru (opsional)',
                  suffixIcon: IconButton(
                    icon: Icon(obscure1 ? Icons.visibility_off_outlined : Icons.visibility_outlined, size: 20),
                    onPressed: () => ss(() => obscure1 = !obscure1),
                  ),
                ),
              ),
              const SizedBox(height: 10),
              TextField(
                controller: pass2,
                obscureText: obscure2,
                decoration: InputDecoration(
                  labelText: u == null ? 'Konfirmasi Password' : 'Ulangi password baru',
                  errorText: passErr,
                  suffixIcon: IconButton(
                    icon: Icon(obscure2 ? Icons.visibility_off_outlined : Icons.visibility_outlined, size: 20),
                    onPressed: () => ss(() => obscure2 = !obscure2),
                  ),
                ),
              ),
              if (u == null) ...[
                const SizedBox(height: 10),
                DropdownButtonFormField<String>(
                  value: role,
                  decoration: const InputDecoration(labelText: 'Role'),
                  items: [
                    const DropdownMenuItem(value: 'kasir', child: Text('Kasir')),
                    const DropdownMenuItem(value: 'admin', child: Text('Admin')),
                    if (widget.ownerMode) const DropdownMenuItem(value: 'owner', child: Text('Owner')),
                  ],
                  onChanged: (v) => ss(() => role = v ?? 'kasir'),
                ),
              ],
            ]),
            actions: [
              SizedBox(width: double.infinity, height: 48, child: ElevatedButton(onPressed: () => Navigator.pop(d, true), child: const Text('Simpan'))),
            ],
          );
        },
      ),
    );
    if (save != true || !mounted) return;

    // Validasi: nama & username wajib; password wajib saat tambah, dan harus sama dengan konfirmasinya.
    final isiPass = pass.text.isNotEmpty;
    if (nama.text.isEmpty || user.text.isEmpty || (u == null && !isiPass)) {
      snack(context, 'Lengkapi data', err: true);
      return;
    }
    if (isiPass && pass.text != pass2.text) {
      snack(context, 'Konfirmasi password tidak sama', err: true);
      return;
    }

    bool ok;
    if (u == null) {
      ok = await DB.insertUser({
        'nama_lengkap': nama.text.trim(),
        'username': user.text.trim(),
        'role': role,
        'password': pass.text.trim(),
        'is_active': 1,
      });
      if (ok) await DB.log(widget.userId, 'Menambah user: ${nama.text} ($role)');
    } else {
      final data = <String, dynamic>{'nama_lengkap': nama.text.trim(), 'username': user.text.trim()};
      if (isiPass) data['password'] = pass.text.trim();
      ok = await DB.updateUser(u['id_user'], data);
      if (ok) await DB.log(widget.userId, 'Mengubah user: ${u['nama_lengkap']}');
    }
    if (mounted) {
      snack(context, ok ? 'Tersimpan' : 'Gagal (username mungkin sudah dipakai)', err: !ok);
      if (ok) _fetch();
    }
  }

  Future<void> _toggle(Map<String, dynamic> u) async {
    if (!widget.ownerMode && _isOwner(u)) {
      snack(context, 'Akun owner hanya dapat dikelola oleh owner', err: true);
      return;
    }
    if (_isSelf(u)) {
      snack(context, 'Tidak bisa menonaktifkan akun sendiri', err: true);
      return;
    }
    final active = u['is_active'] ?? true;
    if (!await confirm(context, active ? 'Nonaktifkan Akun?' : 'Aktifkan Akun?', '"${u['nama_lengkap']}"',
        okLabel: active ? 'Nonaktifkan' : 'Aktifkan', okColor: active ? C.red : C.green)) {
      return;
    }
    final ok = await DB.updateUser(u['id_user'], {'is_active': active ? 0 : 1});
    if (ok) await DB.log(widget.userId, '${active ? 'Menonaktifkan' : 'Mengaktifkan'} akun: ${u['nama_lengkap']}');
    if (ok) _fetch();
  }

  Future<void> _del(Map<String, dynamic> u) async {
    try {
      if (!widget.ownerMode && _isOwner(u)) {
        snack(context, 'Akun owner hanya dapat dikelola oleh owner', err: true);
        return;
      }
      if (_isSelf(u)) {
        snack(context, 'Tidak bisa menghapus akun sendiri', err: true);
        return;
      }
      final hasHistory = await DB.userHasHistory(u['id_user']);
      if (!mounted) return;
      if (hasHistory) {
        snack(context, 'User punya riwayat, hanya bisa dinonaktifkan', err: true);
        return;
      }
      if (!await confirm(context, 'Hapus Akun?', 'Yakin hapus permanen "${u['nama_lengkap']}"?')) return;
      final ok = await DB.deleteUser(u['id_user']);
      if (ok) await DB.log(widget.userId, 'Menghapus akun: ${u['nama_lengkap']}');
      if (mounted) {
        snack(context, ok ? 'Akun dihapus' : 'Gagal menghapus', err: !ok);
        if (ok) _fetch();
      }
    } catch (e) {
      debugPrint('$e');
    }
  }

  /// Bottom sheet aksi (mode owner) — gaya halaman produk.
  Future<void> _action(Map<String, dynamic> u) async {
    final active = u['is_active'] ?? true;
    final choice = await showModalBottomSheet<String>(
      context: context,
      backgroundColor: Colors.white,
      shape: const RoundedRectangleBorder(borderRadius: BorderRadius.vertical(top: Radius.circular(24))),
      builder: (b) => SafeArea(
        child: Wrap(children: [
          ListTile(
            leading: const IconBox(Icons.edit_outlined, color: C.primary),
            title: const Text('Edit User', style: TextStyle(fontSize: 14, fontWeight: FontWeight.w600, color: C.label)),
            onTap: () => Navigator.pop(b, 'edit'),
          ),
          ListTile(
            leading: const IconBox(Icons.delete_outline, color: C.red),
            title: const Text('Hapus User', style: TextStyle(fontSize: 14, fontWeight: FontWeight.w600, color: C.label)),
            onTap: () => Navigator.pop(b, 'del'),
          ),
          ListTile(
            leading: IconBox(active ? Icons.toggle_off_outlined : Icons.toggle_on_outlined, color: C.orange),
            title: Text(active ? 'Nonaktifkan' : 'Aktifkan',
                style: const TextStyle(fontSize: 14, fontWeight: FontWeight.w600, color: C.label)),
            onTap: () => Navigator.pop(b, 'toggle'),
          ),
        ]),
      ),
    );
    if (choice == null || !mounted) return;
    if (choice == 'edit') {
      _form(u);
    } else if (choice == 'toggle') {
      _toggle(u);
    } else if (choice == 'del') {
      _del(u);
    }
  }

  @override
  Widget build(BuildContext context) => Scaffold(
        appBar: AppBar(
          title: Text(widget.readOnly ? 'Daftar User' : 'Manajemen User'),
          actions: [AccountButton(userId: widget.userId)],
        ),
        drawer: AppDrawer(userId: widget.userId, role: widget.ownerMode ? 'owner' : 'admin'),
        body: Column(children: [
          Padding(padding: const EdgeInsets.all(16), child: SearchField(_search, hint: 'Cari nama / username...', onChanged: () => setState(() {}))),
          SizedBox(
            height: 42,
            child: ListView(scrollDirection: Axis.horizontal, padding: const EdgeInsets.symmetric(horizontal: 16), children: [
              FChip('Semua', selected: _role == 'all', onTap: () => setState(() => _role = 'all')),
              FChip('Admin', selected: _role == 'admin', onTap: () => setState(() => _role = 'admin')),
              FChip('Kasir', selected: _role == 'kasir', color: C.teal, onTap: () => setState(() => _role = 'kasir')),
              if (widget.ownerMode)
                FChip('Owner', selected: _role == 'owner', color: C.purple, onTap: () => setState(() => _role = 'owner')),
            ]),
          ),
          Expanded(
            child: _load
                ? const Center(child: CircularProgressIndicator(color: C.primary))
                : _filtered.isEmpty
                    ? const Center(child: Text('Tidak ada user', style: TextStyle(color: C.sub)))
                    : ListView.builder(
                        padding: const EdgeInsets.fromLTRB(16, 12, 16, 16),
                        itemCount: _filtered.length,
                        itemBuilder: (c, i) {
                          final u = _filtered[i];
                          final active = u['is_active'] ?? true;
                          final role = (u['role'] ?? '').toString();
                          final rc = _roleColor(role);
                          final ownerLocked = !widget.ownerMode && !widget.readOnly && _isOwner(u);
                          return Container(
                            margin: const EdgeInsets.only(bottom: 10),
                            decoration: BoxDecoration(
                              color: active ? Colors.white : C.redBg,
                              borderRadius: BorderRadius.circular(16),
                              border: Border.all(color: active ? C.border : C.redBorder),
                            ),
                            child: ListTile(
                              contentPadding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
                              leading: Container(
                                width: 44,
                                height: 44,
                                decoration: BoxDecoration(color: rc.withOpacity(.12), borderRadius: BorderRadius.circular(13)),
                                child: Center(
                                  child: Text(initialOf(u['nama_lengkap']?.toString()),
                                      style: TextStyle(fontSize: 16, fontWeight: FontWeight.w800, color: rc)),
                                ),
                              ),
                              title: Row(children: [
                                Expanded(
                                  child: Text('${u['nama_lengkap'] ?? '-'}',
                                      style: const TextStyle(fontSize: 13.5, fontWeight: FontWeight.w700, color: C.ink),
                                      maxLines: 1,
                                      overflow: TextOverflow.ellipsis),
                                ),
                                if (!active) const SizedBox(width: 6),
                                if (!active) const Pill('NON-AKTIF', fg: C.red, bg: Colors.white),
                              ]),
                              subtitle: Padding(
                                padding: const EdgeInsets.only(top: 4),
                                child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                                  Container(
                                    padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 2),
                                    decoration: BoxDecoration(color: rc.withOpacity(.1), borderRadius: BorderRadius.circular(6)),
                                    child: Text(role.toUpperCase(),
                                        style: TextStyle(fontSize: 9.5, fontWeight: FontWeight.w800, color: rc, letterSpacing: .5)),
                                  ),
                                  const SizedBox(height: 5),
                                  Text(_statusText(role), style: const TextStyle(fontSize: 10.5, color: C.sub)),
                                ]),
                              ),
                              trailing: widget.readOnly
                                  ? null
                                  : widget.ownerMode
                                      // Mode owner: titik 3 → bottom sheet (gaya halaman produk)
                                      ? IconButton(
                                          icon: const Icon(Icons.more_vert, color: C.iconIdle),
                                          onPressed: () => _action(u),
                                        )
                                      // Mode admin: tombol langsung
                                      : Row(mainAxisSize: MainAxisSize.min, children: [
                                          IconBox(Icons.edit_outlined, color: ownerLocked ? C.iconIdle : C.primary, onTap: () => _form(u)),
                                          const SizedBox(width: 5),
                                          IconBox(Icons.delete_outline, color: ownerLocked ? C.iconIdle : C.red, onTap: () => _del(u)),
                                          const SizedBox(width: 5),
                                          IconBox(active ? Icons.person_off_outlined : Icons.person_add_alt_outlined,
                                              color: ownerLocked ? C.iconIdle : (active ? C.orange : C.green), onTap: () => _toggle(u)),
                                        ]),
                            ),
                          );
                        },
                      ),
          ),
        ]),
        floatingActionButton: widget.readOnly
            ? null
            : FloatingActionButton(onPressed: _form, child: const Icon(Icons.person_add_alt)),
      );
}