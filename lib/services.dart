import 'dart:io';
import 'dart:math';

import 'package:flutter/foundation.dart';
import 'package:flutter_image_compress/flutter_image_compress.dart';
import 'package:intl/intl.dart';
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:sqflite/sqflite.dart';

class DB {
  static Database? _db;
  static SharedPreferences? _prefs;
  static String? lastError;

  static Future<void> init() async {
    _prefs = await SharedPreferences.getInstance();
    _db = await _open();
    // Migrasi ringan untuk database lama: pastikan tabel toko ada.
    await _db!.execute(
        'CREATE TABLE IF NOT EXISTS toko (id_toko INTEGER PRIMARY KEY AUTOINCREMENT, nama_toko TEXT, alamat TEXT, recovery_key TEXT)');
    await _ensureIndexes();
  }

  /// Index performa — KRUSIAL untuk database besar.
  /// IF NOT EXISTS = nyaris gratis setelah dibuat pertama kali.
  static Future<void> _ensureIndexes() async {
    const idx = [
      'CREATE INDEX IF NOT EXISTS idx_trx_tanggal ON transaksi(tanggal)',
      'CREATE INDEX IF NOT EXISTS idx_trx_user ON transaksi(id_user)',
      'CREATE INDEX IF NOT EXISTS idx_detail_trx ON detail_transaksi(id_transaksi)',
      'CREATE INDEX IF NOT EXISTS idx_detail_produk ON detail_transaksi(id_produk)',
      'CREATE INDEX IF NOT EXISTS idx_batch_produk ON stok_batch(id_produk, tanggal_exp)',
      'CREATE INDEX IF NOT EXISTS idx_batch_exp ON stok_batch(tanggal_exp)',
      'CREATE INDEX IF NOT EXISTS idx_batch_masuk ON stok_batch(tanggal_masuk)',
      'CREATE INDEX IF NOT EXISTS idx_pem_tanggal ON pembelian(tanggal)',
      'CREATE INDEX IF NOT EXISTS idx_log_user ON log(id_user)',
    ];
    for (final s in idx) {
      try {
        await _db!.execute(s);
      } catch (e) {
        debugPrint('index: $e');
      }
    }
  }

  static Future<Database> _open() async {
    final dir = await getDatabasesPath();
    return openDatabase(p.join(dir, 'kastra.db'), version: 1, onCreate: (db, v) async {
      await db.execute('CREATE TABLE users (id_user INTEGER PRIMARY KEY AUTOINCREMENT, nama_lengkap TEXT, username TEXT UNIQUE, password TEXT, role TEXT, is_active INTEGER DEFAULT 1)');
      await db.execute('CREATE TABLE categories (id_kategori INTEGER PRIMARY KEY AUTOINCREMENT, nama_kategori TEXT UNIQUE)');
      await db.execute('CREATE TABLE produk (id_produk INTEGER PRIMARY KEY AUTOINCREMENT, nama_produk TEXT, kategori TEXT, harga_jual INTEGER DEFAULT 0, harga_beli INTEGER DEFAULT 0, barcode TEXT, gambar TEXT, is_active INTEGER DEFAULT 1)');
      await db.execute('CREATE TABLE stok_batch (id_batch INTEGER PRIMARY KEY AUTOINCREMENT, id_produk INTEGER, jumlah_stok INTEGER DEFAULT 0, harga_beli_satuan INTEGER DEFAULT 0, tanggal_masuk TEXT, tanggal_exp TEXT)');
      await db.execute('CREATE TABLE transaksi (id_transaksi INTEGER PRIMARY KEY AUTOINCREMENT, no_transaksi TEXT, id_user INTEGER, total_bayar INTEGER DEFAULT 0, uang_diterima INTEGER DEFAULT 0, kembalian INTEGER DEFAULT 0, tanggal TEXT)');
      await db.execute('CREATE TABLE detail_transaksi (id_detail INTEGER PRIMARY KEY AUTOINCREMENT, id_transaksi INTEGER, id_produk INTEGER, id_batch INTEGER, qty INTEGER, subtotal INTEGER, harga_beli_satuan INTEGER DEFAULT 0)');
      await db.execute('CREATE TABLE pembelian (id_pembelian INTEGER PRIMARY KEY AUTOINCREMENT, id_user INTEGER, supplier TEXT, total_beli INTEGER DEFAULT 0, tanggal TEXT)');
      await db.execute('CREATE TABLE detail_pembelian (id_detail INTEGER PRIMARY KEY AUTOINCREMENT, id_pembelian INTEGER, id_produk INTEGER, qty INTEGER, harga_beli_satuan INTEGER, subtotal INTEGER)');
      await db.execute('CREATE TABLE pengeluaran (id_pengeluaran INTEGER PRIMARY KEY AUTOINCREMENT, keterangan TEXT, nominal INTEGER DEFAULT 0, tanggal TEXT)');
      await db.execute('CREATE TABLE log (id_log INTEGER PRIMARY KEY AUTOINCREMENT, id_user INTEGER, aktivitas TEXT, waktu TEXT)');
      await db.execute('CREATE TABLE toko (id_toko INTEGER PRIMARY KEY AUTOINCREMENT, nama_toko TEXT, alamat TEXT, recovery_key TEXT)');
    });
  }

  static bool _b(dynamic v) => v == 1 || v == true;

  static Future<bool> run(Future Function() f) async {
    try {
      await f();
      return true;
    } catch (e) {
      lastError = e.toString();
      debugPrint('DB: $e');
      return false;
    }
  }

  // --- sesi ---
  static Future<void> saveSession(int id) async => _prefs?.setInt('uid', id);
  static int? get session => _prefs?.getInt('uid');
  static Future<void> clearSession() async => _prefs?.remove('uid');

  // --- user ---
  static Future<Map<String, dynamic>?> login(String u, String p) async {
    try {
      final rows = await _db!.query('users', where: 'username = ? AND password = ? AND is_active = 1', whereArgs: [u, p], limit: 1);
      if (rows.isEmpty) return null;
      final m = Map<String, dynamic>.from(rows.first);
      m['is_active'] = _b(m['is_active']);
      return m;
    } catch (e) {
      debugPrint('login: $e');
      return null;
    }
  }

  static Future<Map<String, dynamic>?> getUser(int id) async {
    try {
      final rows = await _db!.query('users', where: 'id_user = ?', whereArgs: [id], limit: 1);
      if (rows.isEmpty) return null;
      final m = Map<String, dynamic>.from(rows.first);
      m['is_active'] = _b(m['is_active']);
      return m;
    } catch (_) {
      return null;
    }
  }

  static Future<List<Map<String, dynamic>>> get users async {
    final rows = await _db!.query('users', orderBy: 'id_user DESC');
    return rows.map((r) {
      final m = Map<String, dynamic>.from(r);
      m['is_active'] = _b(m['is_active']);
      return m;
    }).toList();
  }

  static Future<bool> insertUser(Map<String, dynamic> d) => run(() => _db!.insert('users', d));
  static Future<bool> updateUser(int id, Map<String, dynamic> d) =>
      run(() => _db!.update('users', d, where: 'id_user = ?', whereArgs: [id]));
  static Future<bool> deleteUser(int id) => run(() => _db!.delete('users', where: 'id_user = ?', whereArgs: [id]));

  static Future<bool> userHasHistory(int id) async {
    final trx = await _db!.rawQuery('SELECT id_transaksi FROM transaksi WHERE id_user = ? LIMIT 1', [id]);
    final logs = await _db!.rawQuery('SELECT id_log FROM log WHERE id_user = ? LIMIT 1', [id]);
    return trx.isNotEmpty || logs.isNotEmpty;
  }

  static Future<int> countUsers() async {
    final c = await _db!.rawQuery('SELECT COUNT(*) AS n FROM users WHERE is_active = 1');
    return ((c.first['n'] ?? 0) as int);
  }

  static Future<void> log(int userId, String aktivitas) =>
      run(() => _db!.insert('log', {'id_user': userId, 'aktivitas': aktivitas, 'waktu': DateTime.now().toIso8601String()}));

  static Future<List<Map<String, dynamic>>> get logs async {
    final rows = await _db!.rawQuery(
        'SELECT l.*, u.nama_lengkap AS _kasir FROM log l LEFT JOIN users u ON u.id_user = l.id_user ORDER BY l.waktu DESC LIMIT 50');
    return rows.map((r) {
      final m = Map<String, dynamic>.from(r);
      m['users'] = {'nama_lengkap': m.remove('_kasir')};
      return m;
    }).toList();
  }

  // --- kategori & produk ---
  static Future<List<Map<String, dynamic>>> get categories async =>
      await _db!.query('categories', orderBy: 'nama_kategori');

  static Future<bool> insertCategory(String nama) => run(() => _db!.insert('categories', {'nama_kategori': nama}));

  static Future<bool> renameCategory(int id, String oldName, String newName) => run(() async {
        await _db!.update('categories', {'nama_kategori': newName}, where: 'id_kategori = ?', whereArgs: [id]);
        await _db!.update('produk', {'kategori': newName}, where: 'kategori = ?', whereArgs: [oldName]);
      });

  static Future<bool> deleteCategory(int id) => run(() => _db!.delete('categories', where: 'id_kategori = ?', whereArgs: [id]));

  static Future<bool> categoryInUse(String nama) async =>
      (await _db!.query('produk', columns: ['id_produk'], where: 'kategori = ?', whereArgs: [nama], limit: 1)).isNotEmpty;

  static Future<List<Map<String, dynamic>>> productsInCategory(String nama) =>
      _db!.query('produk', columns: ['nama_produk', 'harga_jual'], where: 'kategori = ?', whereArgs: [nama]);

  static Future<List<Map<String, dynamic>>> get products async {
    final list = await _db!.query('produk', orderBy: 'id_produk');
    final stock = <int, int>{};
    final agg = await _db!.rawQuery('SELECT id_produk, SUM(jumlah_stok) AS total FROM stok_batch GROUP BY id_produk');
    for (final b in agg) {
      stock[b['id_produk'] as int] = (b['total'] as int?) ?? 0;
    }
    return list.map((e) {
      final m = Map<String, dynamic>.from(e);
      m['is_active'] = _b(m['is_active']);
      m['stok'] = stock[m['id_produk'] as int] ?? 0;
      return m;
    }).toList();
  }

  static Future<bool> addProduct(Map<String, dynamic> d) => run(() => _db!.insert('produk', d));
  static Future<bool> updateProduct(int id, Map<String, dynamic> d) =>
      run(() => _db!.update('produk', d, where: 'id_produk = ?', whereArgs: [id]));
  static Future<bool> deleteProduct(int id) => run(() => _db!.delete('produk', where: 'id_produk = ?', whereArgs: [id]));

  static Future<bool> productHasBatch(int id) async =>
      (await _db!.query('stok_batch', columns: ['id_batch'], where: 'id_produk = ?', whereArgs: [id], limit: 1)).isNotEmpty;

  static Future<bool> productHasTrx(int id) async =>
      (await _db!.query('detail_transaksi', columns: ['id_detail'], where: 'id_produk = ?', whereArgs: [id], limit: 1)).isNotEmpty;

  // --- gambar (disimpan lokal, return path file) ---
  static Future<String?> uploadImage(XFile f) async {
    try {
      final dir = await getApplicationDocumentsDirectory();
      final name = '${DateTime.now().millisecondsSinceEpoch}_${f.name}';
      final saved = await File(f.path).copy(p.join(dir.path, name));
      return saved.path;
    } catch (_) {
      return null;
    }
  }

  static Future<File> compress(File f) async {
    try {
      final path = f.absolute.path;
      final out = '${path.substring(0, path.lastIndexOf(RegExp(r'\.')) + 1)}c${DateTime.now().millisecondsSinceEpoch}.jpg';
      final r = await FlutterImageCompress.compressAndGetFile(path, out, quality: 70, minWidth: 800, minHeight: 600);
      return File(r?.path ?? f.path);
    } catch (_) {
      return f;
    }
  }

  // --- pengeluaran ---
  /// LIMIT 500: dengan data 10 tahun (~17rb baris), memuat semua
  /// akan melebihi CursorWindow Android (2 MB) dan membuat app crash.
  static Future<List<Map<String, dynamic>>> get pengeluaran async =>
      await _db!.query('pengeluaran', orderBy: 'tanggal DESC', limit: 500);

  static Future<bool> addPengeluaran(Map<String, dynamic> d) => run(() => _db!.insert('pengeluaran', d));
  static Future<bool> updatePengeluaran(int id, Map<String, dynamic> d) =>
      run(() => _db!.update('pengeluaran', d, where: 'id_pengeluaran = ?', whereArgs: [id]));
  static Future<bool> deletePengeluaran(int id) =>
      run(() => _db!.delete('pengeluaran', where: 'id_pengeluaran = ?', whereArgs: [id]));

  // --- pembelian & batch ---
  static Future<bool> addPembelian({
    required int userId,
    required String supplier,
    required int idProduk,
    required int qty,
    required int harga,
    required DateTime masuk,
    required DateTime exp,
  }) {
    return run(() async {
      final total = qty * harga;
      final idP = await _db!.insert('pembelian', {
        'id_user': userId,
        'supplier': supplier,
        'total_beli': total,
        'tanggal': DateTime.now().toIso8601String(),
      });
      await _db!.insert('detail_pembelian', {
        'id_pembelian': idP,
        'id_produk': idProduk,
        'qty': qty,
        'harga_beli_satuan': harga,
        'subtotal': total,
      });
      await _db!.insert('stok_batch', {
        'id_produk': idProduk,
        'jumlah_stok': qty,
        'harga_beli_satuan': harga,
        'tanggal_masuk': masuk.toIso8601String(),
        'tanggal_exp': DateFormat('yyyy-MM-dd').format(exp),
      });
    });
  }

  static Future<bool> updateBatch(int id, Map<String, dynamic> d) =>
      run(() => _db!.update('stok_batch', d, where: 'id_batch = ?', whereArgs: [id]));
  static Future<bool> deleteBatch(int id) => run(() => _db!.delete('stok_batch', where: 'id_batch = ?', whereArgs: [id]));

  /// LIMIT 300: daftar batch 10 tahun bisa 200rb+ baris — wajib dibatasi.
  static Future<List<Map<String, dynamic>>> get batches async {
    final rows = await _db!.rawQuery(
        'SELECT b.*, p.nama_produk AS _nm, p.gambar AS _img FROM stok_batch b '
        'LEFT JOIN produk p ON p.id_produk = b.id_produk ORDER BY b.id_batch DESC LIMIT 300');
    return rows.map((r) {
      final m = Map<String, dynamic>.from(r);
      m['produk'] = {'id_produk': m['id_produk'], 'nama_produk': m.remove('_nm'), 'gambar': m.remove('_img')};
      return m;
    }).toList();
  }

  /// Batch untuk FEFO: stok > 0, exp terdekat dulu.
  static Future<List<Map<String, dynamic>>> fefoBatches(int idProduk) => _db!.query('stok_batch',
      where: 'id_produk = ? AND jumlah_stok > 0', whereArgs: [idProduk], orderBy: 'tanggal_exp ASC', limit: 50);

  static Future<void> reduceBatch(int idBatch, int take) async =>
      await _db!.rawUpdate('UPDATE stok_batch SET jumlah_stok = jumlah_stok - ? WHERE id_batch = ?', [take, idBatch]);

  /// Batch mendekati kadaluarsa (≤30 hari) untuk dashboard admin.
  static Future<List<Map<String, dynamic>>> nearExpBatches() async {
    final today = DateTime.now();
    final t = DateFormat('yyyy-MM-dd').format(today);
    final next = DateFormat('yyyy-MM-dd').format(today.add(const Duration(days: 30)));
    final rows = await _db!.rawQuery(
        'SELECT b.jumlah_stok, b.tanggal_exp, p.nama_produk AS _nm FROM stok_batch b '
        'LEFT JOIN produk p ON p.id_produk = b.id_produk '
        'WHERE b.jumlah_stok > 0 AND b.tanggal_exp >= ? AND b.tanggal_exp <= ? ORDER BY b.tanggal_exp ASC LIMIT 10',
        [t, next]);
    return rows.map((r) {
      final m = Map<String, dynamic>.from(r);
      m['produk'] = {'nama_produk': m.remove('_nm')};
      return m;
    }).toList();
  }

  // --- transaksi ---
  static Future<Map<String, dynamic>?> insertTransaction(Map<String, dynamic> data) async {
    try {
      final id = await _db!.insert('transaksi', data);
      final rows = await _db!.query('transaksi', where: 'id_transaksi = ?', whereArgs: [id], limit: 1);
      return rows.isEmpty ? null : rows.first;
    } catch (e) {
      debugPrint('DB: $e');
      return null;
    }
  }

  static Future<void> insertDetail(Map<String, dynamic> data) async => await _db!.insert('detail_transaksi', data);

  /// Ambil transaksi TERBATAS (pagination). Wajib untuk database besar —
  /// memuat ratusan ribu baris sekaligus melebihi CursorWindow (crash).
  static Future<List<Map<String, dynamic>>> transaksi({
    int? userId,
    DateTime? start,
    DateTime? end,
    int limit = 100,
    int offset = 0,
  }) async {
    final where = <String>[];
    final args = <dynamic>[];
    if (userId != null) {
      where.add('t.id_user = ?');
      args.add(userId);
    }
    if (start != null) {
      where.add('t.tanggal >= ?');
      args.add(start.toIso8601String());
    }
    if (end != null) {
      where.add('t.tanggal <= ?');
      args.add(DateTime(end.year, end.month, end.day, 23, 59, 59).toIso8601String());
    }
    final rows = await _db!.rawQuery(
        'SELECT t.*, u.nama_lengkap AS _kasir FROM transaksi t LEFT JOIN users u ON u.id_user = t.id_user '
        '${where.isEmpty ? '' : 'WHERE ${where.join(' AND ')}'} '
        'ORDER BY t.tanggal DESC LIMIT ? OFFSET ?',
        [...args, limit, offset]);
    return rows.map((r) {
      final m = Map<String, dynamic>.from(r);
      m['users'] = {'nama_lengkap': m.remove('_kasir')};
      return m;
    }).toList();
  }

  /// Agregat di sisi SQL (jumlah & total omset) — aman untuk ratusan ribu baris.
  static Future<Map<String, int>> transaksiAgg({int? userId, DateTime? start, DateTime? end}) async {
    final where = <String>[];
    final args = <dynamic>[];
    if (userId != null) {
      where.add('t.id_user = ?');
      args.add(userId);
    }
    if (start != null) {
      where.add('t.tanggal >= ?');
      args.add(start.toIso8601String());
    }
    if (end != null) {
      where.add('t.tanggal <= ?');
      args.add(DateTime(end.year, end.month, end.day, 23, 59, 59).toIso8601String());
    }
    final rows = await _db!.rawQuery(
        'SELECT COUNT(*) AS n, COALESCE(SUM(t.total_bayar), 0) AS omset FROM transaksi t '
        '${where.isEmpty ? '' : 'WHERE ${where.join(' AND ')}'}',
        args);
    return {
      'count': (rows.first['n'] ?? 0) as int,
      'omset': (rows.first['omset'] ?? 0) as int,
    };
  }

  static Future<List<Map<String, dynamic>>> detailTransaksi(int idTrx) async {
    final rows = await _db!.rawQuery(
        'SELECT d.*, p.nama_produk AS _nm, p.kategori AS _kat, p.gambar AS _img FROM detail_transaksi d '
        'LEFT JOIN produk p ON p.id_produk = d.id_produk WHERE d.id_transaksi = ?',
        [idTrx]);
    return rows.map((r) {
      final m = Map<String, dynamic>.from(r);
      m['produk'] = {'nama_produk': m.remove('_nm'), 'kategori': m.remove('_kat'), 'gambar': m.remove('_img')};
      return m;
    }).toList();
  }

  // --- ringkasan dashboard ---
  static Future<Map<String, dynamic>> adminToday() async {
    final now = DateTime.now();
    final start = DateTime(now.year, now.month, now.day).toIso8601String();
    final end = DateTime(now.year, now.month, now.day + 1).toIso8601String();
    final trx = await _db!.rawQuery('SELECT total_bayar FROM transaksi WHERE tanggal >= ? AND tanggal < ?', [start, end]);
    final prods = await products;
    final exp = await nearExpBatches();
    return {
      'produk': prods.length,
      'low': prods.where((p) => ((p['stok'] ?? 0) as int) > 0 && ((p['stok'] ?? 0) as int) < 10).length,
      'trx': trx.length,
      'omset': trx.fold<int>(0, (a, t) => a + ((t['total_bayar'] ?? 0) as int)),
      'nearExp': exp,
    };
  }

  static Future<Map<String, dynamic>> ownerToday() async {
    final now = DateTime.now();
    final start = DateTime(now.year, now.month, now.day).toIso8601String();
    final end = DateTime(now.year, now.month, now.day + 1).toIso8601String();
    final rows = await _db!.rawQuery(
        'SELECT t.id_transaksi, t.total_bayar, d.harga_beli_satuan, d.qty FROM transaksi t '
        'LEFT JOIN detail_transaksi d ON d.id_transaksi = t.id_transaksi '
        'WHERE t.tanggal >= ? AND t.tanggal < ?',
        [start, end]);
    int omset = 0, hpp = 0;
    final ids = <int>{};
    for (final r in rows) {
      final id = r['id_transaksi'] as int;
      if (ids.add(id)) omset += (r['total_bayar'] ?? 0) as int;
      final h = r['harga_beli_satuan'];
      final q = r['qty'];
      if (h != null && q != null) hpp += (h as int) * (q as int);
    }
    final out = await _db!.rawQuery(
        'SELECT COALESCE(SUM(nominal), 0) AS total FROM pengeluaran WHERE tanggal >= ? AND tanggal < ?',
        [start, end]);
    final prods = await products;
    return {
      'omset': omset,
      'hpp': hpp,
      'out': (out.first['total'] ?? 0) as int,
      'trx': ids.length,
      'produk': prods.length,
      'habis': prods.where((p) => ((p['stok'] ?? 0) as int) <= 0).length,
      'users': await countUsers(),
    };
  }

  /// Ringkasan keuangan hari ini (untuk halaman pengeluaran owner).
  static Future<Map<String, dynamic>> todayFinance() async {
    final now = DateTime.now();
    final start = DateTime(now.year, now.month, now.day).toIso8601String();
    final end = DateTime(now.year, now.month, now.day + 1).toIso8601String();
    final rows = await _db!.rawQuery(
        'SELECT t.id_transaksi, t.total_bayar, d.harga_beli_satuan, d.qty FROM transaksi t '
        'LEFT JOIN detail_transaksi d ON d.id_transaksi = t.id_transaksi '
        'WHERE t.tanggal >= ? AND t.tanggal < ?',
        [start, end]);
    int omset = 0, hpp = 0;
    final ids = <int>{};
    for (final r in rows) {
      final id = r['id_transaksi'] as int;
      if (ids.add(id)) omset += (r['total_bayar'] ?? 0) as int;
      final h = r['harga_beli_satuan'];
      final q = r['qty'];
      if (h != null && q != null) hpp += (h as int) * (q as int);
    }
    final out = await _db!.rawQuery(
        'SELECT COALESCE(SUM(nominal), 0) AS total FROM pengeluaran WHERE tanggal >= ? AND tanggal < ?',
        [start, end]);
    final pengeluaran = (out.first['total'] ?? 0) as int;
    return {
      'omset': omset,
      'hpp': hpp,
      'labaKotor': omset - hpp,
      'pengeluaran': pengeluaran,
      'labaBersih': omset - hpp - pengeluaran,
    };
  }

  // --- toko & recovery ---
  static Future<Map<String, dynamic>?> get toko async {
    final rows = await _db!.query('toko', limit: 1);
    return rows.isEmpty ? null : rows.first;
  }

  static Future<bool> get hasToko async => (await toko) != null;

  static String _genRecoveryKey() {
    const chars = 'ABCDEFGHJKLMNPQRSTUVWXYZ23456789';
    final rnd = Random.secure();
    final s = List.generate(16, (_) => chars[rnd.nextInt(chars.length)]).join();
    return '${s.substring(0, 4)}-${s.substring(4, 8)}-${s.substring(8, 12)}-${s.substring(12, 16)}';
  }

  /// Reset password user via recovery key milik toko. Return pesan error, null jika sukses.
  static Future<String?> resetPassword(String username, String recoveryKey, String newPass) async {
    try {
      final t = await toko;
      if (t == null) return 'Toko belum terdaftar';
      if ((t['recovery_key'] ?? '').toString().trim().toUpperCase() != recoveryKey.trim().toUpperCase()) {
        return 'Recovery key salah';
      }
      final rows = await _db!.query('users', where: 'username = ?', whereArgs: [username.trim()], limit: 1);
      if (rows.isEmpty) return 'Username tidak ditemukan';
      await _db!.update('users', {'password': newPass}, where: 'id_user = ?', whereArgs: [rows.first['id_user']]);
      return null;
    } catch (e) {
      debugPrint('resetPassword: $e');
      return 'Gagal mereset password';
    }
  }

  /// Hapus SELURUH data toko lama: akun, produk, batch, transaksi, pembelian,
  /// pengeluaran, log, data toko, dan file gambar produk lokal.
  /// Dipakai sebelum pendaftaran/import toko baru demi keamanan.
  static Future<void> _wipeAll() async {
    try {
      final rows = await _db!.query('produk', columns: ['gambar']);
      for (final r in rows) {
        final g = (r['gambar'] ?? '').toString();
        if (g.isNotEmpty && !g.startsWith('http')) {
          final f = File(g);
          if (await f.exists()) await f.delete();
        }
      }
    } catch (_) {}
    const tables = [
      'detail_transaksi', 'transaksi', 'detail_pembelian', 'pembelian',
      'stok_batch', 'produk', 'categories', 'pengeluaran', 'log', 'users', 'toko',
    ];
    for (final t in tables) {
      await _db!.delete(t);
    }
  }

  /// Daftarkan toko + akun owner pertama. Data lama DIHAPUS SEMUA dulu.
  /// Return recovery key jika sukses, null jika gagal.
  static Future<String?> registerToko({
    required String nama,
    required String alamat,
    required String ownerNama,
    required String ownerUsername,
    required String password,
  }) async {
    try {
      await _wipeAll();
      final key = _genRecoveryKey();
      await _db!.insert('toko', {'nama_toko': nama.trim(), 'alamat': alamat.trim(), 'recovery_key': key});
      await _db!.insert('users', {
        'nama_lengkap': ownerNama.trim(),
        'username': ownerUsername.trim(),
        'password': password,
        'role': 'owner',
        'is_active': 1,
      });
      return key;
    } catch (e) {
      lastError = e.toString();
      debugPrint('registerToko: $e');
      return null;
    }
  }

  /// Import data toko dari file backup JSON. Data lama DIHAPUS SEMUA dulu.
  /// Return null jika sukses, berisi pesan error jika gagal.
  static Future<String?> importBackup(Map<String, dynamic> json) async {
    try {
      await _wipeAll();
      final t = json['toko'];
      if (t == null) return 'File tidak berisi data toko';
      await _db!.insert('toko', Map<String, dynamic>.from(t));
      for (final u in (json['users'] as List? ?? [])) {
        await _db!.insert('users', Map<String, dynamic>.from(u));
      }
      for (final c in (json['categories'] as List? ?? [])) {
        await _db!.insert('categories', Map<String, dynamic>.from(c));
      }
      for (final pr in (json['produk'] as List? ?? [])) {
        await _db!.insert('produk', Map<String, dynamic>.from(pr));
      }
      return null;
    } catch (e) {
      debugPrint('importBackup: $e');
      return e.toString();
    }
  }
}