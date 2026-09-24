import 'package:flutter/material.dart';
import 'package:kastra/services.dart';
import 'package:kastra/theme.dart';
import 'package:kastra/widgets.dart';

// ignore_for_file: deprecated_member_use, use_build_context_synchronously

class KategoriPage extends StatefulWidget {
  final int userId;
  const KategoriPage({super.key, required this.userId});

  @override
  State<KategoriPage> createState() => _KategoriPageState();
}

class _KategoriPageState extends State<KategoriPage> {
  final _search = TextEditingController();
  List<Map<String, dynamic>> _cats = [];
  bool _load = true;

  @override
  void initState() {
    super.initState();
    _fetch();
  }

  Future<void> _fetch() async {
    setState(() => _load = true);
    try {
      final c = await DB.categories;
      if (mounted) {
        setState(() {
          _cats = c;
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
    return q.isEmpty ? _cats : _cats.where((c) => (c['nama_kategori'] ?? '').toString().toLowerCase().contains(q)).toList();
  }

  Future<void> _form([Map<String, dynamic>? cat]) async {
    final ctrl = TextEditingController(text: cat?['nama_kategori']);
    final nama = await showDialog<String>(
      context: context,
      builder: (d) => AlertDialog(
        title: Text(cat == null ? 'Tambah Kategori' : 'Edit Kategori', textAlign: TextAlign.center),
        content: TextField(controller: ctrl, autofocus: true, decoration: const InputDecoration(hintText: 'Nama kategori')),
        actions: [
          SizedBox(
            width: double.infinity,
            height: 48,
            child: ElevatedButton(onPressed: () => Navigator.pop(d, ctrl.text.trim()), child: const Text('Simpan')),
          ),
        ],
      ),
    );
    if (nama == null || nama.isEmpty || nama == cat?['nama_kategori'] || !mounted) return;

    bool ok;
    if (cat == null) {
      ok = await DB.insertCategory(nama);
      if (ok) await DB.log(widget.userId, 'Menambah kategori: $nama');
    } else {
      ok = await DB.renameCategory(cat['id_kategori'], cat['nama_kategori'], nama);
      if (ok) await DB.log(widget.userId, 'Mengubah kategori "${cat['nama_kategori']}" menjadi "$nama"');
    }
    if (mounted) {
      snack(context, ok ? 'Tersimpan' : 'Gagal menyimpan', err: !ok);
      if (ok) _fetch();
    }
  }

  Future<void> _del(Map<String, dynamic> cat) async {
    try {
      final used = await DB.categoryInUse(cat['nama_kategori']);
      if (!mounted) return;
      if (used) {
        snack(context, 'Kategori masih dipakai produk', err: true);
        return;
      }
      if (!await confirm(context, 'Hapus Kategori', 'Yakin hapus "${cat['nama_kategori']}"?')) return;
      final ok = await DB.deleteCategory(cat['id_kategori']);
      if (ok) await DB.log(widget.userId, 'Menghapus kategori: ${cat['nama_kategori']}');
      if (mounted) {
        snack(context, ok ? 'Kategori dihapus' : 'Gagal menghapus', err: !ok);
        if (ok) _fetch();
      }
    } catch (e) {
      debugPrint('$e');
    }
  }

  Future<void> _showProduk(Map<String, dynamic> cat) async {
    List items = [];
    try {
      items = await DB.productsInCategory(cat['nama_kategori']);
    } catch (_) {}
    if (!mounted) return;
    await pickSheet<Map>(context, title: '${cat['nama_kategori']} (${items.length})', items: List<Map>.from(items), label: (p) => '${p['nama_produk']} · ${rp(p['harga_jual'])}');
  }

  @override
  Widget build(BuildContext context) => Scaffold(
        appBar: AppBar(title: const Text('Kategori Produk')),
        drawer: AppDrawer(userId: widget.userId, role: 'admin'),
        body: Column(children: [
          Padding(padding: const EdgeInsets.all(16), child: SearchField(_search, hint: 'Cari kategori...', onChanged: () => setState(() {}))),
          Expanded(
            child: _load
                ? const Center(child: CircularProgressIndicator(color: C.primary))
                : _filtered.isEmpty
                    ? const Center(child: Text('Tidak ada kategori', style: TextStyle(color: C.sub)))
                    : ListView.builder(
                        padding: const EdgeInsets.fromLTRB(16, 4, 16, 16),
                        itemCount: _filtered.length,
                        itemBuilder: (c, i) {
                          final cat = _filtered[i];
                          return Container(
                            margin: const EdgeInsets.only(bottom: 10),
                            decoration: BoxDecoration(color: Colors.white, borderRadius: BorderRadius.circular(16), border: Border.all(color: C.border)),
                            child: ListTile(
                              contentPadding: const EdgeInsets.symmetric(horizontal: 14, vertical: 4),
                              onTap: () => _showProduk(cat),
                              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
                              leading: Container(
                                width: 42,
                                height: 42,
                                decoration: BoxDecoration(color: C.primary.withOpacity(.09), borderRadius: BorderRadius.circular(12)),
                                child: const Icon(Icons.category_outlined, size: 20, color: C.primary),
                              ),
                              title: Text('${cat['nama_kategori']}', style: const TextStyle(fontSize: 14, fontWeight: FontWeight.w700, color: C.ink)),
                              subtitle: const Text('Ketuk untuk lihat produk', style: TextStyle(fontSize: 11.5, color: C.sub)),
                              trailing: Row(mainAxisSize: MainAxisSize.min, children: [
                                IconBox(Icons.edit_outlined, color: C.primary, onTap: () => _form(cat)),
                                const SizedBox(width: 6),
                                IconBox(Icons.delete_outline, color: C.red, onTap: () => _del(cat)),
                              ]),
                            ),
                          );
                        },
                      ),
          ),
        ]),
        floatingActionButton: FloatingActionButton(onPressed: _form, child: const Icon(Icons.add)),
      );
}