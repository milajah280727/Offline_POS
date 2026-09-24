import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:kastra/services.dart';
import 'package:kastra/theme.dart';
import 'package:kastra/widgets.dart';

// ignore_for_file: deprecated_member_use, use_build_context_synchronously

class BatchPage extends StatefulWidget {
  final int userId;
  const BatchPage({super.key, required this.userId});

  @override
  State<BatchPage> createState() => _BatchPageState();
}

class _BatchPageState extends State<BatchPage> {
  final _search = TextEditingController();
  List<Map<String, dynamic>> _batch = [];
  String _filter = 'all', _preset = 'Semua Tanggal', _sort = 'date_desc';
  bool _load = true;

  static const _presets = ['Semua Tanggal', 'Hari Ini', '7 Hari Terakhir', '30 Hari Terakhir', 'Bulan Ini'];
  static const _sorts = {
    'date_desc': 'Tanggal Masuk Terbaru',
    'name_asc': 'Nama A-Z',
    'name_desc': 'Nama Z-A',
    'stock_asc': 'Stok Terendah',
    'stock_desc': 'Stok Tertinggi',
    'exp_asc': 'Kadaluarsa Terdekat',
  };

  @override
  void initState() {
    super.initState();
    _fetch();
  }

  Future<void> _fetch() async {
    setState(() => _load = true);
    try {
      final r = await DB.batches;
      if (mounted) {
        setState(() {
          _batch = r;
          _load = false;
        });
      }
    } catch (e) {
      debugPrint('$e');
      if (mounted) setState(() => _load = false);
    }
  }

  String _nama(Map b) => ((b['produk'] as Map?)?['nama_produk'] ?? '').toString();

  List<Map<String, dynamic>> get _filtered {
    final q = _search.text.toLowerCase();
    final today = dayOnly(DateTime.now());
    final list = _batch.where((b) {
      if (q.isNotEmpty && !_nama(b).toLowerCase().contains(q)) return false;
      final stok = b['jumlah_stok'] ?? 0;
      final exp = dayOnly(b['tanggal_exp']);
      final masuk = dayOnly(b['tanggal_masuk']);
      switch (_filter) {
        case 'empty':
          return stok == 0;
        case 'expired':
          return exp.isBefore(today);
        case 'near':
          return !exp.isBefore(today) && exp.isBefore(today.add(const Duration(days: 30)));
        case 'date':
          switch (_preset) {
            case 'Hari Ini':
              return masuk == today;
            case '7 Hari Terakhir':
              return !masuk.isBefore(today.subtract(const Duration(days: 7)));
            case '30 Hari Terakhir':
              return !masuk.isBefore(today.subtract(const Duration(days: 30)));
            case 'Bulan Ini':
              return masuk.year == today.year && masuk.month == today.month;
            default:
              return true;
          }
        default:
          return true;
      }
    }).toList();

    int stoi(dynamic v) => int.tryParse(v.toString()) ?? 0;
    switch (_sort) {
      case 'name_asc':
        list.sort((a, b) => _nama(a).compareTo(_nama(b)));
        break;
      case 'name_desc':
        list.sort((a, b) => _nama(b).compareTo(_nama(a)));
        break;
      case 'stock_asc':
        list.sort((a, b) => stoi(a['jumlah_stok']).compareTo(stoi(b['jumlah_stok'])));
        break;
      case 'stock_desc':
        list.sort((a, b) => stoi(b['jumlah_stok']).compareTo(stoi(a['jumlah_stok'])));
        break;
      case 'exp_asc':
        list.sort((a, b) => dayOnly(a['tanggal_exp']).compareTo(dayOnly(b['tanggal_exp'])));
        break;
      default:
        list.sort((a, b) => dayOnly(b['tanggal_masuk']).compareTo(dayOnly(a['tanggal_masuk'])));
    }
    return list;
  }

  Future<void> _openForm([Map<String, dynamic>? b]) async {
    final ok = await Navigator.push(context, MaterialPageRoute(builder: (_) => PembelianForm(userId: widget.userId, batch: b)));
    if (ok == true) _fetch();
  }

  Future<void> _del(Map<String, dynamic> b) async {
    if (!await confirm(context, 'Hapus Batch', 'Yakin hapus batch "${_nama(b)}"?')) return;
    final ok = await DB.deleteBatch(b['id_batch']);
    if (ok) await DB.log(widget.userId, 'Menghapus batch stok: ${_nama(b)}');
    if (mounted) {
      snack(context, ok ? 'Batch dihapus' : 'Gagal menghapus', err: !ok);
      if (ok) _fetch();
    }
  }

  @override
  Widget build(BuildContext context) => Scaffold(
        appBar: AppBar(
          title: const Text('Batch Stok'),
          actions: [AccountButton(userId: widget.userId)],
        ),
        drawer: AppDrawer(userId: widget.userId, role: 'admin'),
        body: Column(children: [
          Padding(padding: const EdgeInsets.all(16), child: SearchField(_search, hint: 'Cari nama produk...', onChanged: () => setState(() {}))),
          SizedBox(
            height: 42,
            child: ListView(scrollDirection: Axis.horizontal, padding: const EdgeInsets.symmetric(horizontal: 16), children: [
              FChip('Semua', selected: _filter == 'all', onTap: () => setState(() => _filter = 'all')),
              FChip('Stok Habis', selected: _filter == 'empty', color: C.red, onTap: () => setState(() => _filter = 'empty')),
              FChip('Kadaluarsa', selected: _filter == 'expired', color: C.red, onTap: () => setState(() => _filter = 'expired')),
              FChip('Exp < 30 Hari', selected: _filter == 'near', color: C.orange, onTap: () => setState(() => _filter = 'near')),
              FChip('Tanggal', selected: _filter == 'date', onTap: () async {
                final p = await pickSheet<String>(context, title: 'Filter Tanggal Masuk', items: _presets, label: (s) => s, selected: _preset);
                if (p != null && mounted) {
                  setState(() {
                    _filter = 'date';
                    _preset = p;
                  });
                }
              }),
              FChip('Urutkan', selected: false, onTap: () async {
                final e = await pickSheet<MapEntry<String, String>>(context, title: 'Urutkan Berdasarkan', items: _sorts.entries.toList(), label: (e) => e.value);
                if (e != null && mounted) setState(() => _sort = e.key);
              }),
            ]),
          ),
          Expanded(
            child: _load
                ? const Center(child: CircularProgressIndicator(color: C.primary))
                : _filtered.isEmpty
                    ? const Center(child: Text('Tidak ada data', style: TextStyle(color: C.sub)))
                    : ListView.builder(
                        padding: const EdgeInsets.fromLTRB(16, 12, 16, 16),
                        itemCount: _filtered.length,
                        itemBuilder: (c, i) {
                          final b = _filtered[i];
                          final expired = dayOnly(b['tanggal_exp']).isBefore(dayOnly(DateTime.now()));
                          return Container(
                            margin: const EdgeInsets.only(bottom: 10),
                            padding: const EdgeInsets.all(14),
                            decoration: BoxDecoration(
                              color: Colors.white,
                              borderRadius: BorderRadius.circular(16),
                              border: Border.all(color: expired ? C.redBorder : C.border),
                            ),
                            child: Column(children: [
                              Row(children: [
                                ProductImage((b['produk'] as Map?)?['gambar'], size: 44),
                                const SizedBox(width: 10),
                                Expanded(
                                  child: Text(_nama(b),
                                      style: const TextStyle(fontSize: 13.5, fontWeight: FontWeight.w700, color: C.ink),
                                      maxLines: 1,
                                      overflow: TextOverflow.ellipsis),
                                ),
                                const SizedBox(width: 4),
                                IconBox(Icons.edit_outlined, color: C.primary, onTap: () => _openForm(b)),
                                const SizedBox(width: 6),
                                IconBox(Icons.delete_outline, color: C.red, onTap: () => _del(b)),
                              ]),
                              const SizedBox(height: 12),
                              Container(height: 1, color: C.border),
                              const SizedBox(height: 10),
                              Row(children: [
                                _col('Stok', '${b['jumlah_stok']} pcs', stok: (b['jumlah_stok'] ?? 0) == 0),
                                _col('Masuk', fdate(b['tanggal_masuk'], 'd MMM yyyy')),
                                _col('Kadaluarsa', fdate(b['tanggal_exp'], 'd MMM yyyy'), danger: expired),
                              ]),
                              const SizedBox(height: 8),
                              Align(
                                alignment: Alignment.centerLeft,
                                child: Text('Harga beli: ${rp(b['harga_beli_satuan'])}',
                                    style: const TextStyle(fontSize: 11.5, color: C.sub)),
                              ),
                            ]),
                          );
                        },
                      ),
          ),
        ]),
        floatingActionButton: FloatingActionButton(onPressed: _openForm, child: const Icon(Icons.add)),
      );

  Widget _col(String label, String value, {bool danger = false, bool stok = false}) => Expanded(
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Text(label.toUpperCase(),
              style: const TextStyle(fontSize: 9.5, fontWeight: FontWeight.w800, color: C.iconIdle, letterSpacing: .8)),
          const SizedBox(height: 3),
          Text(value,
              style: TextStyle(
                  fontSize: 12.5,
                  fontWeight: FontWeight.w700,
                  color: danger ? C.red : (stok ? C.orange : C.ink))),
        ]),
      );
}

/// Form gabungan Tambah Pembelian & Edit Batch.
class PembelianForm extends StatefulWidget {
  final int userId;
  final Map<String, dynamic>? batch;
  const PembelianForm({super.key, required this.userId, this.batch});

  @override
  State<PembelianForm> createState() => _PembelianFormState();
}

class _PembelianFormState extends State<PembelianForm> {
  final _supplier = TextEditingController();
  final _qty = TextEditingController();
  final _harga = TextEditingController();
  List<Map<String, dynamic>> _produk = [];
  int? _idProduk;
  String? _namaProduk;
  DateTime _masuk = DateTime.now();
  DateTime _exp = DateTime.now().add(const Duration(days: 30));
  bool _load = false;

  bool get _edit => widget.batch != null;

  @override
  void initState() {
    super.initState();
    final b = widget.batch;
    if (b != null) {
      _qty.text = (b['jumlah_stok'] ?? '').toString();
      _harga.text = (b['harga_beli_satuan'] ?? '').toString();
      _idProduk = b['id_produk'];
      _namaProduk = (b['produk'] as Map?)?['nama_produk'] ?? 'Produk';
      try {
        _masuk = DateTime.parse(b['tanggal_masuk'].toString());
        _exp = DateTime.parse(b['tanggal_exp'].toString());
      } catch (_) {}
    }
    DB.products.then((list) {
      if (!mounted) return;
      setState(() {
        _produk = list;
        if (!_edit && list.isNotEmpty) {
          _idProduk = list.first['id_produk'];
          _namaProduk = list.first['nama_produk'];
        }
      });
    });
  }

  Future<void> _pickProduk() async {
    final p = await pickSheet<Map<String, dynamic>>(context,
        title: 'Pilih Produk',
        items: _produk,
        label: (p) => '${p['nama_produk']}',
        selected: _produk.where((x) => x['id_produk'] == _idProduk).firstOrNull);
    if (p != null && mounted) {
      setState(() {
        _idProduk = p['id_produk'];
        _namaProduk = p['nama_produk'];
      });
    }
  }

  Future<void> _pickDate(bool isExp) async {
    final d = await showDatePicker(
        context: context, initialDate: isExp ? _exp : _masuk, firstDate: DateTime(2000), lastDate: DateTime(2100));
    if (d != null && mounted) setState(() => isExp ? _exp = d : _masuk = d);
  }

  Future<void> _save() async {
    if (_qty.text.isEmpty || _harga.text.isEmpty || _idProduk == null || (!_edit && _supplier.text.isEmpty)) {
      snack(context, 'Lengkapi semua data wajib', err: true);
      return;
    }
    setState(() => _load = true);
    bool ok;
    if (_edit) {
      ok = await DB.updateBatch(widget.batch!['id_batch'], {
        'id_produk': _idProduk,
        'jumlah_stok': int.tryParse(_qty.text) ?? 0,
        'harga_beli_satuan': int.tryParse(_harga.text) ?? 0,
        'tanggal_masuk': _masuk.toIso8601String(),
        'tanggal_exp': DateFormat('yyyy-MM-dd').format(_exp),
      });
      if (ok) await DB.log(widget.userId, 'Mengubah batch stok: $_namaProduk');
    } else {
      ok = await DB.addPembelian(
        userId: widget.userId,
        supplier: _supplier.text.trim(),
        idProduk: _idProduk!,
        qty: int.tryParse(_qty.text) ?? 0,
        harga: int.tryParse(_harga.text) ?? 0,
        masuk: _masuk,
        exp: _exp,
      );
      if (ok) await DB.log(widget.userId, 'Menambah pembelian: ${_qty.text} $_namaProduk dari ${_supplier.text}');
    }
    if (!mounted) return;
    setState(() => _load = false);
    snack(context, ok ? 'Tersimpan' : 'Gagal menyimpan', err: !ok);
    if (ok) Navigator.pop(context, true);
  }

  @override
  Widget build(BuildContext context) => Scaffold(
        appBar: AppBar(title: Text(_edit ? 'Edit Batch Stok' : 'Tambah Pembelian')),
        body: ListView(padding: const EdgeInsets.all(16), children: [
          if (!_edit) ...[
            const FieldLabel('Nama Supplier'),
            const SizedBox(height: 8),
            TextField(controller: _supplier, decoration: const InputDecoration(prefixIcon: Icon(Icons.storefront_outlined, size: 20))),
            const SizedBox(height: 20),
          ],
          CardX(
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              const FieldLabel('Produk'),
              const SizedBox(height: 8),
              InkWell(
                onTap: _pickProduk,
                borderRadius: BorderRadius.circular(14),
                child: Container(
                  height: 54,
                  padding: const EdgeInsets.symmetric(horizontal: 16),
                  decoration: BoxDecoration(color: Colors.white, borderRadius: BorderRadius.circular(14), border: Border.all(color: C.border)),
                  child: Row(children: [
                    Expanded(
                      child: Text(_namaProduk ?? 'Pilih Produk',
                          style: TextStyle(fontSize: 15, fontWeight: FontWeight.w500, color: _namaProduk == null ? C.iconIdle : C.ink)),
                    ),
                    const Icon(Icons.arrow_drop_down, color: C.iconIdle),
                  ]),
                ),
              ),
              const SizedBox(height: 16),
              Row(children: [
                Expanded(child: TextField(controller: _qty, keyboardType: TextInputType.number, decoration: const InputDecoration(labelText: 'Jumlah'))),
                const SizedBox(width: 12),
                Expanded(child: TextField(controller: _harga, keyboardType: TextInputType.number, decoration: const InputDecoration(labelText: 'Harga Beli', prefixText: 'Rp '))),
              ]),
              const SizedBox(height: 16),
              _dateRow('Tanggal Masuk', _masuk, () => _pickDate(false)),
              const SizedBox(height: 10),
              _dateRow('Tanggal Expired', _exp, () => _pickDate(true)),
            ]),
          ),
          const SizedBox(height: 28),
          SizedBox(
            width: double.infinity,
            height: 54,
            child: ElevatedButton(
              onPressed: _load ? null : _save,
              child: _load
                  ? const SizedBox(width: 20, height: 20, child: CircularProgressIndicator(color: Colors.white, strokeWidth: 2.4))
                  : Text(_edit ? 'Simpan Perubahan' : 'Simpan Pembelian'),
            ),
          ),
        ]),
      );

  Widget _dateRow(String label, DateTime d, VoidCallback tap) => Row(mainAxisAlignment: MainAxisAlignment.spaceBetween, children: [
        Text(label, style: const TextStyle(fontSize: 12.5, fontWeight: FontWeight.w600, color: C.sub)),
        InkWell(
          onTap: tap,
          borderRadius: BorderRadius.circular(10),
          child: Container(
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
            decoration: BoxDecoration(color: C.fieldFill, borderRadius: BorderRadius.circular(10), border: Border.all(color: C.border)),
            child: Text(DateFormat('dd MMM yyyy').format(d), style: const TextStyle(color: C.primary, fontWeight: FontWeight.w700, fontSize: 12.5)),
          ),
        ),
      ]);
}