// ignore_for_file: unnecessary_underscores, curly_braces_in_flow_control_structures

import 'dart:io';
import 'dart:math';
import 'package:barcode_widget/barcode_widget.dart';
import 'package:flutter/material.dart';
import 'package:image_picker/image_picker.dart';
import 'package:kastra/scanner.dart';
import 'package:kastra/services.dart';
import 'package:kastra/theme.dart';
import 'package:kastra/widgets.dart';
import 'package:pdf/pdf.dart';
import 'package:pdf/widgets.dart' as pw;
import 'package:printing/printing.dart';

// ignore_for_file: deprecated_member_use, use_build_context_synchronously

class ProdukPage extends StatefulWidget {
  final int userId;
  final bool readOnly;
  const ProdukPage({super.key, required this.userId, this.readOnly = false});

  @override
  State<ProdukPage> createState() => _ProdukPageState();
}

class _ProdukPageState extends State<ProdukPage> {
  final _search = TextEditingController();
  List<Map<String, dynamic>> _produk = [], _cats = [];
  String? _cat;
  String _status = 'all';
  String _sort = 'name_asc';
  bool _load = true;

  static const _sorts = {
    'name_asc': 'Nama A-Z',
    'name_desc': 'Nama Z-A',
    'stock_asc': 'Stok Terendah',
    'stock_desc': 'Stok Tertinggi',
    'price_asc': 'Harga Termurah',
    'price_desc': 'Harga Termahal',
  };

  @override
  void initState() {
    super.initState();
    _fetch();
  }

  Future<void> _fetch() async {
    setState(() => _load = true);
    try {
      final cats = await DB.categories;
      final prods = await DB.products;
      if (mounted) {
        setState(() {
          _cats = cats;
          _produk = prods;
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
    final list = _produk.where((p) {
      if (q.isNotEmpty &&
          !((p['nama_produk'] ?? '').toString().toLowerCase().contains(q) ||
              (p['kategori'] ?? '').toString().toLowerCase().contains(q) ||
              (p['barcode'] ?? '').toString().contains(q))) return false;
      if (_cat != null && p['kategori'] != _cat) return false;
      final stok = p['stok'] ?? 0;
      switch (_status) {
        case 'empty':
          if (stok != 0) return false;
          break;
        case 'low':
          if (stok == 0 || stok > 10) return false;
          break;
        case 'off':
          if (p['is_active'] ?? true) return false;
          break;
      }
      return true;
    }).toList();

    String nm(Map p) => (p['nama_produk'] ?? '').toString();
    switch (_sort) {
      case 'name_desc':
        list.sort((a, b) => nm(b).compareTo(nm(a)));
        break;
      case 'stock_asc':
        list.sort((a, b) => ((a['stok'] ?? 0) as int).compareTo((b['stok'] ?? 0) as int));
        break;
      case 'stock_desc':
        list.sort((a, b) => ((b['stok'] ?? 0) as int).compareTo((a['stok'] ?? 0) as int));
        break;
      case 'price_asc':
        list.sort((a, b) => ((a['harga_jual'] ?? 0) as int).compareTo((b['harga_jual'] ?? 0) as int));
        break;
      case 'price_desc':
        list.sort((a, b) => ((b['harga_jual'] ?? 0) as int).compareTo((a['harga_jual'] ?? 0) as int));
        break;
      default:
        list.sort((a, b) => nm(a).compareTo(nm(b)));
    }
    return list;
  }

  Future<void> _openForm([Map<String, dynamic>? p]) async {
    final ok = await Navigator.push(context, MaterialPageRoute(builder: (_) => ProdukForm(userId: widget.userId, produk: p)));
    if (ok == true) _fetch();
  }

  Future<void> _action(Map<String, dynamic> p) async {
    try {
      final id = p['id_produk'] as int;
      final hasBatch = await DB.productHasBatch(id);
      final hasTrx = await DB.productHasTrx(id);
      if (!mounted) return;
      if (hasBatch) {
        snack(context, 'Produk masih punya batch stok. Hapus batch dulu.', err: true);
        return;
      }

      final active = p['is_active'] ?? true;
      final choice = await showModalBottomSheet<String>(
        context: context,
        backgroundColor: Colors.white,
        shape: const RoundedRectangleBorder(borderRadius: BorderRadius.vertical(top: Radius.circular(24))),
        builder: (b) => SafeArea(
          child: Wrap(children: [
            ListTile(
              leading: const IconBox(Icons.edit_outlined, color: C.primary),
              title: const Text('Edit Produk', style: TextStyle(fontSize: 14, fontWeight: FontWeight.w600, color: C.label)),
              onTap: () => Navigator.pop(b, 'edit'),
            ),
            if (!hasTrx)
              ListTile(
                leading: const IconBox(Icons.delete_outline, color: C.red),
                title: const Text('Hapus Produk', style: TextStyle(fontSize: 14, fontWeight: FontWeight.w600, color: C.label)),
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
        _openForm(p);
      } else if (choice == 'toggle') {
        await DB.updateProduct(id, {'is_active': active ? 0 : 1});
        await DB.log(widget.userId, '${active ? 'Menonaktifkan' : 'Mengaktifkan'} produk: ${p['nama_produk']}');
        _fetch();
      } else if (await confirm(context, 'Hapus Produk', 'Yakin hapus "${p['nama_produk']}"?')) {
        await DB.deleteProduct(id);
        await DB.log(widget.userId, 'Menghapus produk: ${p['nama_produk']}');
        _fetch();
      }
    } catch (e) {
      debugPrint('$e');
    }
  }

  Color _stockColor(int stok) => stok == 0 ? C.red : (stok < 10 ? C.orange : C.green);

  @override
  Widget build(BuildContext context) => Scaffold(
        appBar: AppBar(
          title: Text(widget.readOnly ? 'Data Produk' : 'Daftar Produk'),
          actions: [AccountButton(userId: widget.userId)],
        ),
        drawer: AppDrawer(userId: widget.userId, role: widget.readOnly ? 'owner' : 'admin'),
        body: Column(children: [
          Padding(padding: const EdgeInsets.all(16), child: SearchField(_search, hint: 'Cari nama, kategori, barcode...', onChanged: () => setState(() {}))),
          SizedBox(
            height: 42,
            child: ListView(scrollDirection: Axis.horizontal, padding: const EdgeInsets.symmetric(horizontal: 16), children: [
              FChip('Semua', selected: _cat == null, onTap: () => setState(() => _cat = null)),
              ..._cats.map((c) => FChip('${c['nama_kategori']}', selected: _cat == c['nama_kategori'], onTap: () => setState(() => _cat = c['nama_kategori']))),
            ]),
          ),
          SizedBox(
            height: 42,
            child: ListView(scrollDirection: Axis.horizontal, padding: const EdgeInsets.symmetric(horizontal: 16), children: [
              FChip('Semua Status', selected: _status == 'all', onTap: () => setState(() => _status = 'all')),
              FChip('Stok Habis', selected: _status == 'empty', color: C.red, onTap: () => setState(() => _status = 'empty')),
              FChip('Stok Rendah', selected: _status == 'low', color: C.orange, onTap: () => setState(() => _status = 'low')),
              FChip('Non-Aktif', selected: _status == 'off', onTap: () => setState(() => _status = 'off')),
              FChip('Urutkan', selected: false, onTap: () async {
                final e = await pickSheet<MapEntry<String, String>>(context, title: 'Urutkan', items: _sorts.entries.toList(), label: (e) => e.value);
                if (e != null && mounted) setState(() => _sort = e.key);
              }),
            ]),
          ),
          Expanded(
            child: _load
                ? const Center(child: CircularProgressIndicator(color: C.primary))
                : _filtered.isEmpty
                    ? const Center(child: Text('Tidak ada produk', style: TextStyle(color: C.sub)))
                    : ListView.builder(
                        padding: const EdgeInsets.fromLTRB(16, 12, 16, 16),
                        itemCount: _filtered.length,
                        itemBuilder: (c, i) {
                          final p = _filtered[i];
                          final active = p['is_active'] ?? true;
                          final stok = p['stok'] ?? 0;
                          return Container(
                            margin: const EdgeInsets.only(bottom: 10),
                            padding: const EdgeInsets.all(12),
                            decoration: BoxDecoration(
                              color: Colors.white,
                              borderRadius: BorderRadius.circular(16),
                              border: Border.all(color: active ? C.border : C.redBorder),
                            ),
                            child: Row(children: [
                              ProductImage(p['gambar'], size: 52),
                              const SizedBox(width: 12),
                              Expanded(
                                child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                                  Row(children: [
                                    Expanded(
                                      child: Text(p['nama_produk'] ?? '-',
                                          style: const TextStyle(fontSize: 13.5, fontWeight: FontWeight.w700, color: C.ink),
                                          maxLines: 1,
                                          overflow: TextOverflow.ellipsis),
                                    ),
                                    if (!active) const SizedBox(width: 6),
                                    if (!active) const Pill('NON-AKTIF', fg: C.red, bg: C.redBg),
                                  ]),
                                  const SizedBox(height: 3),
                                  Text(rp(p['harga_jual']),
                                      style: const TextStyle(fontSize: 12.5, fontWeight: FontWeight.w700, color: C.primary)),
                                  const SizedBox(height: 6),
                                  Pill('Stok: $stok', fg: _stockColor(stok)),
                                ]),
                              ),
                              if (!widget.readOnly)
                                IconButton(
                                  icon: const Icon(Icons.more_vert, color: C.iconIdle),
                                  onPressed: () => _action(p),
                                ),
                            ]),
                          );
                        },
                      ),
          ),
        ]),
        floatingActionButton: widget.readOnly
            ? null
            : FloatingActionButton(onPressed: _openForm, child: const Icon(Icons.add)),
      );
}

/// Form gabungan Tambah & Edit Produk.
class ProdukForm extends StatefulWidget {
  final int userId;
  final Map<String, dynamic>? produk;
  const ProdukForm({super.key, required this.userId, this.produk});

  @override
  State<ProdukForm> createState() => _ProdukFormState();
}

class _ProdukFormState extends State<ProdukForm> {
  final _nama = TextEditingController();
  final _harga = TextEditingController();
  final _barcode = TextEditingController();
  final _picker = ImagePicker();
  File? _img;
  String? _imgUrl;
  String? _kat;
  List<Map<String, dynamic>> _cats = [];
  bool _load = false;

  bool get _edit => widget.produk != null;

  @override
  void initState() {
    super.initState();
    final p = widget.produk;
    if (p != null) {
      _nama.text = p['nama_produk'] ?? '';
      _harga.text = (p['harga_jual'] ?? '').toString();
      _barcode.text = (p['barcode'] ?? '').toString();
      _imgUrl = p['gambar'];
      _kat = p['kategori'];
    } else {
      _barcode.text = _rand();
    }
    _loadCats();
  }

  Future<void> _loadCats() async {
    try {
      final v = await DB.categories;
      if (mounted) setState(() => _cats = v);
    } catch (_) {}
  }

  String _rand() => List.generate(8, (_) => Random().nextInt(10)).join();

  /// Pilih kategori dari daftar, atau buat kategori baru langsung dari sini.
  Future<void> _pickKategori() async {
    final k = await showModalBottomSheet<Map<String, dynamic>>(
      context: context,
      backgroundColor: Colors.white,
      shape: const RoundedRectangleBorder(borderRadius: BorderRadius.vertical(top: Radius.circular(24))),
      builder: (b) => SafeArea(
        child: Column(mainAxisSize: MainAxisSize.min, children: [
          const Padding(
            padding: EdgeInsets.fromLTRB(16, 16, 16, 8),
            child: Text('Pilih Kategori', style: TextStyle(fontSize: 16, fontWeight: FontWeight.w800, color: C.ink)),
          ),
          if (_cats.isEmpty)
            const Padding(
              padding: EdgeInsets.symmetric(horizontal: 16, vertical: 20),
              child: Text('Belum ada kategori.\nBuat kategori baru lewat tombol di bawah.',
                  style: TextStyle(fontSize: 13, color: C.sub), textAlign: TextAlign.center),
            )
          else
            ConstrainedBox(
              constraints: BoxConstraints(maxHeight: MediaQuery.of(b).size.height * 0.45),
              child: ListView.builder(
                shrinkWrap: true,
                itemCount: _cats.length,
                itemBuilder: (_, i) {
                  final c = _cats[i];
                  final sel = c['nama_kategori'] == _kat;
                  return ListTile(
                    title: Text('${c['nama_kategori']}',
                        style: TextStyle(
                            fontSize: 14,
                            fontWeight: sel ? FontWeight.w700 : FontWeight.w500,
                            color: sel ? C.primary : C.ink)),
                    trailing: sel ? const Icon(Icons.check_circle, color: C.primary, size: 20) : null,
                    onTap: () => Navigator.pop(b, c),
                  );
                },
              ),
            ),
          const Divider(height: 1),
          ListTile(
            leading: const IconBox(Icons.add, color: C.primary),
            title: const Text('Buat Kategori Baru',
                style: TextStyle(fontSize: 14, fontWeight: FontWeight.w700, color: C.primary)),
            onTap: () async {
              Navigator.pop(b);
              final nama = await _askNewCategory();
              if (nama != null && mounted) setState(() => _kat = nama);
            },
          ),
          const SizedBox(height: 8),
        ]),
      ),
    );
    if (k != null && mounted) setState(() => _kat = k['nama_kategori']);
  }

  /// Dialog input nama kategori baru; otomatis tersimpan ke tabel categories.
  Future<String?> _askNewCategory() async {
    final ctrl = TextEditingController();
    final nama = await showDialog<String>(
      context: context,
      builder: (d) => AlertDialog(
        title: const Text('Kategori Baru', textAlign: TextAlign.center),
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
    if (nama == null || nama.isEmpty) return null;
    final ok = await DB.insertCategory(nama);
    if (!mounted) return null;
    if (!ok) {
      snack(context, 'Gagal membuat kategori (mungkin sudah ada)', err: true);
      return null;
    }
    snack(context, 'Kategori "$nama" dibuat');
    await _loadCats();
    return nama;
  }

  Future<void> _pick() async {
    final src = await showModalBottomSheet<ImageSource>(
      context: context,
      backgroundColor: Colors.white,
      shape: const RoundedRectangleBorder(borderRadius: BorderRadius.vertical(top: Radius.circular(24))),
      builder: (b) => SafeArea(
        child: Wrap(children: [
          ListTile(leading: const IconBox(Icons.photo_outlined, color: C.primary), title: const Text('Galeri'), onTap: () => Navigator.pop(b, ImageSource.gallery)),
          ListTile(leading: const IconBox(Icons.photo_camera_outlined, color: C.primary), title: const Text('Kamera'), onTap: () => Navigator.pop(b, ImageSource.camera)),
        ]),
      ),
    );
    if (src == null) return;
    final x = await _picker.pickImage(source: src);
    if (x == null) return;
    final f = await DB.compress(File(x.path));
    if (mounted) setState(() => _img = f);
  }

  Future<void> _scan() async {
    final code = await Navigator.push<String>(context, MaterialPageRoute(builder: (_) => const ScanSingle()));
    if (code != null && mounted) setState(() => _barcode.text = code);
  }

  Future<void> _print() async {
    final code = _barcode.text.isEmpty ? '12345678' : _barcode.text;
    final pdf = pw.Document();
    pdf.addPage(pw.Page(
      pageFormat: PdfPageFormat.roll80,
      build: (c) => pw.Center(
        child: pw.Column(mainAxisAlignment: pw.MainAxisAlignment.center, children: [
          pw.Text('Kastra', style: pw.TextStyle(fontSize: 14, fontWeight: pw.FontWeight.bold)),
          pw.SizedBox(height: 5),
          pw.BarcodeWidget(barcode: pw.Barcode.code128(), data: code, width: 150, height: 50),
          pw.SizedBox(height: 5),
          pw.Text(code),
        ]),
      ),
    ));
    await Printing.layoutPdf(onLayout: (f) => pdf.save());
  }

  Future<void> _save() async {
    // Validasi dengan pesan spesifik
    if (_nama.text.trim().isEmpty) {
      snack(context, 'Nama produk masih kosong', err: true);
      return;
    }
    final harga = int.tryParse(_harga.text.replaceAll('.', '')) ?? -1;
    if (_harga.text.trim().isEmpty || harga < 0) {
      snack(context, 'Harga jual tidak valid', err: true);
      return;
    }
    if (_kat == null) {
      snack(context, 'Pilih atau buat kategori dulu', err: true);
      return;
    }
    if (!await confirm(context, _edit ? 'Simpan Perubahan?' : 'Simpan Produk?',
        'Nama: ${_nama.text}\nKategori: $_kat\nHarga: ${rp(harga)}', okLabel: 'Ya, Simpan', okColor: C.primary)) return;

    setState(() => _load = true);
    String? url = _imgUrl;
    if (_img != null) url = await DB.uploadImage(XFile(_img!.path));
    final data = <String, dynamic>{
      'nama_produk': _nama.text.trim(),
      'kategori': _kat,
      'harga_jual': harga,
      'barcode': _barcode.text.trim(),
      'gambar': url,
    };
    bool ok;
    if (_edit) {
      ok = await DB.updateProduct(widget.produk!['id_produk'], data);
    } else {
      ok = await DB.addProduct({...data, 'harga_beli': 0, 'is_active': 1});
    }
    if (!mounted) return;
    setState(() => _load = false);
    if (ok) {
      await DB.log(widget.userId, '${_edit ? 'Mengubah' : 'Menambahkan'} produk: ${_nama.text}');
      if (!mounted) return;
      snack(context, 'Produk tersimpan');
      Navigator.pop(context, true);
    } else {
      final err = DB.lastError ?? 'tidak diketahui';
      snack(context, 'Gagal menyimpan: $err', err: true);
    }
  }

  @override
  Widget build(BuildContext context) => Scaffold(
        appBar: AppBar(title: Text(_edit ? 'Edit Produk' : 'Tambah Produk')),
        body: SingleChildScrollView(
          padding: const EdgeInsets.all(16),
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            // Gambar
            GestureDetector(
              onTap: _pick,
              child: Container(
                width: double.infinity,
                height: 170,
                decoration: BoxDecoration(
                  color: C.fieldFill,
                  borderRadius: BorderRadius.circular(18),
                  border: Border.all(color: C.border),
                ),
                child: _img != null
                    ? ClipRRect(borderRadius: BorderRadius.circular(17), child: Image.file(_img!, fit: BoxFit.cover))
                    : (_imgUrl != null && _imgUrl!.isNotEmpty
                        ? ClipRRect(
                            borderRadius: BorderRadius.circular(17),
                            child: (_imgUrl!.startsWith('http')
                                ? Image.network(_imgUrl!, fit: BoxFit.cover, errorBuilder: (_, __, ___) => _placeholder())
                                : Image.file(File(_imgUrl!), fit: BoxFit.cover, errorBuilder: (_, __, ___) => _placeholder())))
                        : _placeholder()),
              ),
            ),
            const SizedBox(height: 20),
            // Barcode
            CardX(
              child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                Row(mainAxisAlignment: MainAxisAlignment.spaceBetween, children: [
                  const Text('Barcode', style: TextStyle(fontSize: 13.5, fontWeight: FontWeight.w700, color: C.label)),
                  Row(children: [
                    IconBox(Icons.refresh, color: C.sub, onTap: () => setState(() => _barcode.text = _rand())),
                    const SizedBox(width: 6),
                    IconBox(Icons.qr_code_scanner, color: C.primary, onTap: _scan),
                    const SizedBox(width: 6),
                    IconBox(Icons.print_outlined, color: C.primary, onTap: _print),
                  ]),
                ]),
                const SizedBox(height: 12),
                BarcodeWidget(
                    barcode: Barcode.code128(),
                    data: _barcode.text.isEmpty ? '12345678' : _barcode.text,
                    width: double.infinity,
                    height: 60),
                TextField(
                  controller: _barcode,
                  keyboardType: TextInputType.number,
                  textAlign: TextAlign.center,
                  style: const TextStyle(fontSize: 14, fontWeight: FontWeight.w700, letterSpacing: 2),
                  decoration: const InputDecoration(hintText: 'Kode barcode', border: InputBorder.none, filled: false, contentPadding: EdgeInsets.symmetric(vertical: 8)),
                  onChanged: (_) => setState(() {}),
                ),
              ]),
            ),
            const SizedBox(height: 20),
            const FieldLabel('Nama Produk'),
            const SizedBox(height: 8),
            TextField(controller: _nama),
            const SizedBox(height: 16),
            const FieldLabel('Kategori'),
            const SizedBox(height: 8),
            InkWell(
              onTap: _pickKategori,
              borderRadius: BorderRadius.circular(14),
              child: Container(
                height: 54,
                padding: const EdgeInsets.symmetric(horizontal: 16),
                decoration: BoxDecoration(color: C.fieldFill, borderRadius: BorderRadius.circular(14), border: Border.all(color: C.border)),
                child: Row(children: [
                  Expanded(
                    child: Text(_kat ?? 'Pilih Kategori',
                        style: TextStyle(fontSize: 15, fontWeight: FontWeight.w500, color: _kat == null ? C.iconIdle : C.ink)),
                  ),
                  const Icon(Icons.arrow_drop_down, color: C.iconIdle),
                ]),
              ),
            ),
            const SizedBox(height: 16),
            const FieldLabel('Harga Jual'),
            const SizedBox(height: 8),
            TextField(controller: _harga, keyboardType: TextInputType.number, decoration: const InputDecoration(prefixText: 'Rp ')),
            const SizedBox(height: 28),
            SizedBox(
              width: double.infinity,
              height: 54,
              child: ElevatedButton(
                onPressed: _load ? null : _save,
                child: _load
                    ? const SizedBox(width: 20, height: 20, child: CircularProgressIndicator(color: Colors.white, strokeWidth: 2.4))
                    : Text(_edit ? 'Simpan Perubahan' : 'Simpan Produk'),
              ),
            ),
          ]),
        ),
      );

  Widget _placeholder() => Center(
        child: Column(mainAxisSize: MainAxisSize.min, children: [
          const Icon(Icons.add_photo_alternate_outlined, size: 36, color: C.iconIdle),
          const SizedBox(height: 8),
          Text('Ketuk untuk pilih gambar', style: TextStyle(fontSize: 12, color: C.sub)),
        ]),
      );
}