import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:math';
import 'dart:typed_data';

import 'package:crypto/crypto.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter_image_compress/flutter_image_compress.dart';
import 'package:intl/intl.dart';
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:sqflite/sqflite.dart';

/// ---------------------------------------------------------------------------
/// HASH PASSWORD — PBKDF2-HMAC-SHA256 (bukan plaintext lagi).
/// Format tersimpan: `pbkdf2$<iterasi>$<saltHex>$<hashHex>`.
/// Hash lama yang masih plaintext akan dimigrasikan otomatis saat login.
/// ---------------------------------------------------------------------------
class PasswordHasher {
  static const int iterations = 120000;

  static String generateSalt() {
    final rnd = Random.secure();
    return base64Encode(List<int>.generate(16, (_) => rnd.nextInt(256)));
  }

  static Uint8List _pbkdf2(String password, String saltB64, int iter, int len) {
    final salt = base64Decode(saltB64);
    final hmac = Hmac(sha256, utf8.encode(password));
    var u = hmac.convert([...salt, 0, 0, 0, 1]).bytes;
    final out = Uint8List.fromList(u);
    for (var i = 1; i < iter; i++) {
      u = hmac.convert(u).bytes;
      for (var j = 0; j < out.length; j++) {
        out[j] ^= u[j];
      }
    }
    return Uint8List.sublistView(out, 0, len);
  }

  static String hash(String password, String saltB64) {
    final Uint8List dk = _pbkdf2(password, saltB64, iterations, 32);
    return 'pbkdf2\$$iterations\$$saltB64\$${base64Encode(dk)}';
  }

  /// Perbandingan konstan-waktu terhadap nilai tersimpan.
  /// Mengembalikan true jika cocok; [needsUpgrade] di-set bila stored masih plaintext.
  static bool verify(String password, String stored, {bool Function()? onPlaintextMatch}) {
    if (stored.isEmpty) return false;
    final parts = stored.split(r'$');
    if (parts.length != 4 || parts[0] != 'pbkdf2') {
      // Data lama: plaintext — cocokkan langsung, pemanggil wajib meng-upgrade.
      final ok = stored == password;
      if (ok && onPlaintextMatch != null) onPlaintextMatch();
      return ok;
    }
    final iter = int.tryParse(parts[1]) ?? iterations;
    final expected = base64Decode(parts[3]);
    Uint8List dk;
    if (iter == iterations) {
      dk = _pbkdf2(password, parts[2], iter, expected.length);
    } else {
      // iterasi lama — hitung ulang sesuai parameter tersimpan
      final salt = base64Decode(parts[2]);
      final hmac = Hmac(sha256, utf8.encode(password));
      var u = hmac.convert([...salt, 0, 0, 0, 1]).bytes;
      final o = Uint8List.fromList(u);
      for (var i = 1; i < iter; i++) {
        u = hmac.convert(u).bytes;
        for (var j = 0; j < o.length; j++) {
          o[j] ^= u[j];
        }
      }
      dk = Uint8List.sublistView(o, 0, expected.length);
    }
    if (dk.length != expected.length) return false;
    var diff = 0;
    for (var i = 0; i < dk.length; i++) {
      diff |= dk[i] ^ expected[i];
    }
    return diff == 0;
  }
}

class _LockState {
  final int fails;
  final DateTime? lockedUntil;
  const _LockState(this.fails, this.lockedUntil);
}

class DB {
  static Database? _db;
  static SharedPreferences? _prefs;
  static String? lastError;

  /// Persisten di file DB (bukan memori) sehingga tidak bisa di-bypass
  /// dengan restart aplikasi.
  static Future<_LockState> _loadLock() async {
    try {
      final rows = await _db!.query('login_lock', limit: 1);
      if (rows.isEmpty) return const _LockState(0, null);
      final until = rows.first['locked_until'];
      return _LockState(
        (rows.first['fails'] as int?) ?? 0,
        until == null ? null : DateTime.tryParse(until.toString()),
      );
    } catch (_) {
      return const _LockState(0, null);
    }
  }

  static Future<void> _saveLock(int fails, DateTime? lockedUntil) async {
    try {
      await _db!.delete('login_lock');
      await _db!.insert('login_lock', {
        'id': 1,
        'fails': fails,
        'locked_until': lockedUntil?.toIso8601String(),
      });
    } catch (e) {
      debugPrint('saveLock: $e');
    }
  }

  static Future<void> init() async {
    _prefs = await SharedPreferences.getInstance();
    _db = await _open();
    // Migrasi ringan untuk database lama: pastikan tabel toko ada.
    await _db!.execute(
        'CREATE TABLE IF NOT EXISTS toko (id_toko INTEGER PRIMARY KEY AUTOINCREMENT, nama_toko TEXT, alamat TEXT, recovery_key TEXT)');
    // Pengaturan POS (pajak, diskon persen maks, notifikasi stok menipis).
    await _db!.execute('CREATE TABLE IF NOT EXISTS settings (key TEXT PRIMARY KEY, value TEXT)');
    // Rate-limit login persisten antar-restart.
    await _db!.execute('CREATE TABLE IF NOT EXISTS login_lock (id INTEGER PRIMARY KEY, fails INTEGER DEFAULT 0, locked_until TEXT)');
    await _ensureIndexes();
    _lockCache = await _loadLock();
  }

  /// Simpan/ambil pengaturan sederhana key-value.
  static Future<void> setSetting(String key, String value) async {
    try {
      await _db!.insert('settings', {'key': key, 'value': value},
          conflictAlgorithm: ConflictAlgorithm.replace);
    } catch (e) {
      debugPrint('setSetting: $e');
    }
  }

  static Future<String?> getSetting(String key) async {
    try {
      final rows = await _db!.query('settings', where: 'key = ?', whereArgs: [key], limit: 1);
      return rows.isEmpty ? null : rows.first['value']?.toString();
    } catch (_) {
      return null;
    }
  }

  /// Persentase pajak toko (default 0).
  static Future<int> taxPercent() async => int.tryParse(await getSetting('tax_percent') ?? '0') ?? 0;

  /// Ambang stok menipis per produk (default 10) — dipakai indikator dashboard.
  static Future<int> lowStockThreshold() async => int.tryParse(await getSetting('low_stock') ?? '10') ?? 10;

  /// Nama perangkat kasir ini (muncul di struk & laporan).
  static Future<String> deviceName() async => await getSetting('device_name') ?? 'Kasir 1';

  /// Simpan pengaturan dengan validasi numerik opsional. Return pesan error / null.
  static Future<String?> setSettingValidated(String key, String value, {int? min, int? max}) async {
    if (min != null || max != null) {
      final n = int.tryParse(value.trim());
      if (n == null) return 'Nilai harus angka';
      if (min != null && n < min) return 'Minimal $min';
      if (max != null && n > max) return 'Maksimal $max';
      value = '$n';
    }
    await setSetting(key, value);
    return null;
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

  /// Buat hash password baru (PBKDF2). Jalankan di compute isolate agar UI tidak freeze.
  static Future<String> hashPassword(String password) async {
    final salt = PasswordHasher.generateSalt();
    return compute((pw) => PasswordHasher.hash(pw, salt), password);
  }

  static Future<Database> _open() async {
    final dir = await getDatabasesPath();
    return openDatabase(p.join(dir, 'kastra.db'), version: 3,
        onConfigure: (db) async {
      // Foreign key ON — integritas referensial ditegakkan SQLite.
      await db.execute('PRAGMA foreign_keys = ON');
    },
        onCreate: (db, v) async {
      await db.execute('CREATE TABLE users (id_user INTEGER PRIMARY KEY AUTOINCREMENT, nama_lengkap TEXT, username TEXT UNIQUE, password TEXT, salt TEXT, role TEXT, is_active INTEGER DEFAULT 1)');
      await db.execute('CREATE TABLE categories (id_kategori INTEGER PRIMARY KEY AUTOINCREMENT, nama_kategori TEXT UNIQUE)');
      await db.execute('CREATE TABLE produk (id_produk INTEGER PRIMARY KEY AUTOINCREMENT, nama_produk TEXT, kategori TEXT, harga_jual INTEGER DEFAULT 0, harga_beli INTEGER DEFAULT 0, barcode TEXT UNIQUE, gambar TEXT, is_active INTEGER DEFAULT 1)');
      await db.execute('CREATE TABLE stok_batch (id_batch INTEGER PRIMARY KEY AUTOINCREMENT, id_produk INTEGER REFERENCES produk(id_produk) ON DELETE CASCADE, jumlah_stok INTEGER DEFAULT 0 CHECK (jumlah_stok >= 0), harga_beli_satuan INTEGER DEFAULT 0, tanggal_masuk TEXT, tanggal_exp TEXT)');
      await db.execute('CREATE TABLE transaksi (id_transaksi INTEGER PRIMARY KEY AUTOINCREMENT, no_transaksi TEXT UNIQUE, id_user INTEGER REFERENCES users(id_user), total_bayar INTEGER DEFAULT 0, diskon INTEGER DEFAULT 0, pajak INTEGER DEFAULT 0, uang_diterima INTEGER DEFAULT 0, kembalian INTEGER DEFAULT 0, metode TEXT DEFAULT "tunai", status TEXT DEFAULT "selesai", void_alasan TEXT, void_oleh INTEGER, void_pada TEXT, shift_id INTEGER REFERENCES shift(id_shift), tanggal TEXT)');
      await db.execute('CREATE TABLE detail_transaksi (id_detail INTEGER PRIMARY KEY AUTOINCREMENT, id_transaksi INTEGER REFERENCES transaksi(id_transaksi) ON DELETE CASCADE, id_produk INTEGER REFERENCES produk(id_produk), id_batch INTEGER REFERENCES stok_batch(id_batch), qty INTEGER, subtotal INTEGER, harga_beli_satuan INTEGER DEFAULT 0, qty_retur INTEGER DEFAULT 0)');
      await db.execute('CREATE TABLE pembelian (id_pembelian INTEGER PRIMARY KEY AUTOINCREMENT, id_user INTEGER REFERENCES users(id_user), supplier TEXT, total_beli INTEGER DEFAULT 0, tanggal TEXT)');
      await db.execute('CREATE TABLE detail_pembelian (id_detail INTEGER PRIMARY KEY AUTOINCREMENT, id_pembelian INTEGER REFERENCES pembelian(id_pembelian) ON DELETE CASCADE, id_produk INTEGER REFERENCES produk(id_produk), qty INTEGER, harga_beli_satuan INTEGER, subtotal INTEGER)');
      await db.execute('CREATE TABLE pengeluaran (id_pengeluaran INTEGER PRIMARY KEY AUTOINCREMENT, keterangan TEXT, nominal INTEGER DEFAULT 0, tanggal TEXT)');
      await db.execute('CREATE TABLE log (id_log INTEGER PRIMARY KEY AUTOINCREMENT, id_user INTEGER, aktivitas TEXT, waktu TEXT)');
      await db.execute('CREATE TABLE toko (id_toko INTEGER PRIMARY KEY AUTOINCREMENT, nama_toko TEXT, alamat TEXT, recovery_hash TEXT)');
      await db.execute('CREATE TABLE shift (id_shift INTEGER PRIMARY KEY AUTOINCREMENT, id_user INTEGER REFERENCES users(id_user), mulai TEXT, selesai TEXT, modal_awal INTEGER DEFAULT 0, saldo_hitung INTEGER, selisih INTEGER, catatan TEXT)');
      await db.execute('CREATE TABLE opname (id_opname INTEGER PRIMARY KEY AUTOINCREMENT, id_user INTEGER REFERENCES users(id_user), id_produk INTEGER REFERENCES produk(id_produk), stok_sistem INTEGER DEFAULT 0, stok_fisik INTEGER DEFAULT 0, selisih INTEGER DEFAULT 0, alasan TEXT, tanggal TEXT)');
      await db.execute('CREATE TABLE settings (key TEXT PRIMARY KEY, value TEXT)');
      await db.execute('CREATE TABLE login_lock (id INTEGER PRIMARY KEY, fails INTEGER DEFAULT 0, locked_until TEXT)');
    },
        onUpgrade: (db, oldV, newV) async {
      // --- v2: keamanan & integritas data + fitur POS ---
      if (oldV < 2) {
        // kolom salt untuk hash (DB lama menyimpan password plaintext)
        try {
          await db.execute('ALTER TABLE users ADD COLUMN salt TEXT');
        } catch (_) {/* sudah ada */}
        // kolom pembayaran/void pada transaksi
        for (final c in ['diskon INTEGER DEFAULT 0', 'pajak INTEGER DEFAULT 0', 'metode TEXT DEFAULT "tunai"',
          'status TEXT DEFAULT "selesai"', 'void_alasan TEXT', 'void_oleh INTEGER', 'void_pada TEXT']) {
          try {
            await db.execute('ALTER TABLE transaksi ADD COLUMN $c');
          } catch (_) {}
        }
        // barcode unik (abaikan jika data lama duplikat — index dibuat manual nanti)
        try {
          await db.execute('CREATE UNIQUE INDEX IF NOT EXISTS idx_produk_barcode ON produk(barcode) WHERE barcode IS NOT NULL AND barcode != ""');
        } catch (_) {}
        await db.execute('CREATE TABLE IF NOT EXISTS shift (id_shift INTEGER PRIMARY KEY AUTOINCREMENT, id_user INTEGER, mulai TEXT, selesai TEXT, modal_awal INTEGER DEFAULT 0, saldo_hitung INTEGER, selisih INTEGER, catatan TEXT)');
        await db.execute('CREATE TABLE IF NOT EXISTS opname (id_opname INTEGER PRIMARY KEY AUTOINCREMENT, id_user INTEGER, id_produk INTEGER, stok_sistem INTEGER DEFAULT 0, stok_fisik INTEGER DEFAULT 0, selisih INTEGER DEFAULT 0, alasan TEXT, tanggal TEXT)');
        // recovery_key lama -> pindahkan ke recovery_hash (di-upgrade penuh saat dipakai)
        try {
          await db.execute('ALTER TABLE toko ADD COLUMN recovery_hash TEXT');
          final rows = await db.query('toko', limit: 1);
          if (rows.isNotEmpty && rows.first['recovery_hash'] == null) {
            final legacy = (rows.first['recovery_key'] ?? '').toString();
            if (legacy.isNotEmpty) {
              await db.update('toko', {'recovery_hash': legacy.toUpperCase()}, where: 'id_toko = ?', whereArgs: [rows.first['id_toko']]);
            }
          }
        } catch (_) {}
      }
      // --- v3: retur parsial, shift_id pada transaksi, tabel settings & login_lock ---
      if (oldV < 3) {
        for (final c in ['shift_id INTEGER', ]) {
          try { await db.execute('ALTER TABLE transaksi ADD COLUMN $c'); } catch (_) {}
        }
        try { await db.execute('ALTER TABLE detail_transaksi ADD COLUMN qty_retur INTEGER DEFAULT 0'); } catch (_) {}
        try { await db.execute('CREATE TABLE IF NOT EXISTS settings (key TEXT PRIMARY KEY, value TEXT)'); } catch (_) {}
        try { await db.execute('CREATE TABLE IF NOT EXISTS login_lock (id INTEGER PRIMARY KEY, fails INTEGER DEFAULT 0, locked_until TEXT)'); } catch (_) {}
      }
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

  // --- proteksi brute-force (rate limit PERSISTEN di DB) ---
  static const int _maxFails = 5;
  static const Duration _lockDuration = Duration(minutes: 1);
  static _LockState _lockCache = const _LockState(0, null);

  /// Sisa waktu kunci akun akibat gagal login berulang (null = tidak terkunci).
  static Duration? get loginLockRemaining {
    final until = _lockCache.lockedUntil;
    if (until == null) return null;
    final rem = until.difference(DateTime.now());
    if (rem.isNegative) {
      _lockCache = const _LockState(0, null);
      unawaited(_saveLock(0, null));
      return null;
    }
    return rem;
  }

  // --- user ---
  static Future<Map<String, dynamic>?> login(String u, String p) async {
    try {
      if (loginLockRemaining != null) return null; // akun terkunci sementara
      final rows = await _db!.query('users', where: 'username = ? AND is_active = 1', whereArgs: [u.trim()], limit: 1);
      if (rows.isEmpty) {
        await _registerFail();
        return null;
      }
      final row = rows.first;
      final stored = (row['password'] ?? '').toString();
      // Verifikasi PBKDF2 (120k iterasi) dijalankan di background isolate
      // agar UI tidak freeze.
      final res = await compute(
          (msg) => PasswordHasher.verify(msg[0], msg[1]), [p, stored]);
      final ok = res == true;
      final isPlaintext = !stored.startsWith('pbkdf2\$');
      if (!ok) {
        await _registerFail();
        return null;
      }
      _lockCache = const _LockState(0, null);
      await _saveLock(0, null);
      if (isPlaintext) {
        // migrasikan data lama (plaintext) -> hash PBKDF2
        unawaited(_upgradePassword(row['id_user'] as int, p));
      }
      final m = Map<String, dynamic>.from(row)..remove('password')..remove('salt');
      m['is_active'] = _b(row['is_active']);
      return m;
    } catch (e) {
      debugPrint('login: $e');
      return null;
    }
  }

  static Future<void> _registerFail() async {
    final fails = _lockCache.fails + 1;
    if (fails >= _maxFails) {
      final until = DateTime.now().add(_lockDuration);
      _lockCache = _LockState(0, until);
      await _saveLock(0, until);
    } else {
      _lockCache = _LockState(fails, null);
      await _saveLock(fails, null);
    }
  }

  static Future<void> _upgradePassword(int id, String plain) async {
    try {
      final h = await hashPassword(plain);
      await _db!.update('users', {'password': h}, where: 'id_user = ?', whereArgs: [id]);
    } catch (e) {
      debugPrint('upgradePassword: $e');
    }
  }

  static Future<Map<String, dynamic>?> getUser(int id) async {
    try {
      final rows = await _db!.query('users', columns: ['id_user', 'nama_lengkap', 'username', 'role', 'is_active'],
          where: 'id_user = ?', whereArgs: [id], limit: 1);
      if (rows.isEmpty) return null;
      final m = Map<String, dynamic>.from(rows.first);
      m['is_active'] = _b(m['is_active']);
      return m;
    } catch (_) {
      return null;
    }
  }

  static Future<List<Map<String, dynamic>>> get users async {
    final rows = await _db!.query('users',
        columns: ['id_user', 'nama_lengkap', 'username', 'role', 'is_active'], orderBy: 'id_user DESC');
    return rows.map((r) {
      final m = Map<String, dynamic>.from(r);
      m['is_active'] = _b(m['is_active']);
      return m;
    }).toList();
  }

  /// Insert user dengan password sudah ter-hash. [plainPassword] di-hash otomatis.
  static Future<bool> insertUser(Map<String, dynamic> d, {String? plainPassword}) => run(() async {
        final data = Map<String, dynamic>.from(d);
        if (plainPassword != null) {
          data['password'] = await hashPassword(plainPassword);
        }
        data.remove('salt'); // kolom salt internal hasher tersimpan dalam string hash
        await _db!.insert('users', data);
      });

  static Future<bool> updateUser(int id, Map<String, dynamic> d) => run(() async {
        final data = Map<String, dynamic>.from(d);
        final pw = data.remove('newPassword');
        if (pw is String && pw.isNotEmpty) {
          data['password'] = await hashPassword(pw);
        }
        await _db!.update('users', data, where: 'id_user = ?', whereArgs: [id]);
      });

  static Future<bool> changeOwnPassword(int id, String lama, String baru) async {
    try {
      final rows = await _db!.query('users', where: 'id_user = ?', whereArgs: [id], limit: 1);
      if (rows.isEmpty) return false;
      if (!PasswordHasher.verify(lama, (rows.first['password'] ?? '').toString())) return false;
      await _db!.update('users', {'password': await hashPassword(baru)}, where: 'id_user = ?', whereArgs: [id]);
      return true;
    } catch (e) {
      lastError = e.toString();
      return false;
    }
  }

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
  /// Pembelian atomik: header + detail + batch stok baru dalam satu transaksi.
  static Future<bool> addPembelian({
    required int userId,
    required String supplier,
    required int idProduk,
    required int qty,
    required int harga,
    required DateTime masuk,
    required DateTime exp,
  }) {
    return run(() => _db!.transaction((txn) async {
      final total = qty * harga;
      final idP = await txn.insert('pembelian', {
        'id_user': userId,
        'supplier': supplier,
        'total_beli': total,
        'tanggal': DateTime.now().toIso8601String(),
      });
      await txn.insert('detail_pembelian', {
        'id_pembelian': idP,
        'id_produk': idProduk,
        'qty': qty,
        'harga_beli_satuan': harga,
        'subtotal': total,
      });
      await txn.insert('stok_batch', {
        'id_produk': idProduk,
        'jumlah_stok': qty,
        'harga_beli_satuan': harga,
        'tanggal_masuk': masuk.toIso8601String(),
        'tanggal_exp': DateFormat('yyyy-MM-dd').format(exp),
      });
    }));
  }

  static Future<bool> updateBatch(int id, Map<String, dynamic> d) =>
      run(() => _db!.update('stok_batch', d, where: 'id_batch = ?', whereArgs: [id]));
  static Future<bool> deleteBatch(int id) => run(() => _db!.delete('stok_batch', where: 'id_batch = ?', whereArgs: [id]));

  /// Opname stok (stock take): catat selisih fisik vs sistem dan sesuaikan
  /// batch FEFO terdekat secara atomik. Return pesan error / null jika sukses.
  static Future<String?> opnameStok({
    required int userId,
    required int idProduk,
    required int stokFisik,
    String alasan = 'Opname',
  }) async {
    try {
      await _db!.transaction((txn) async {
        final agg = await txn.rawQuery(
            'SELECT COALESCE(SUM(jumlah_stok),0) AS s FROM stok_batch WHERE id_produk = ?', [idProduk]);
        final sistem = (agg.first['s'] ?? 0) as int;
        final selisih = stokFisik - sistem;
        if (selisih > 0) {
          // tambahan: masukkan ke batch aktif terakhir, atau buat batch baru
          final last = await txn.query('stok_batch',
              columns: ['id_batch', 'harga_beli_satuan'],
              where: 'id_produk = ?', whereArgs: [idProduk], orderBy: 'id_batch DESC', limit: 1);
          if (last.isNotEmpty) {
            await txn.rawUpdate('UPDATE stok_batch SET jumlah_stok = jumlah_stok + ? WHERE id_batch = ?',
                [selisih, last.first['id_batch']]);
          } else {
            await txn.insert('stok_batch', {
              'id_produk': idProduk,
              'jumlah_stok': selisih,
              'harga_beli_satuan': 0,
              'tanggal_masuk': DateTime.now().toIso8601String(),
              'tanggal_exp': '9999-12-31',
            });
          }
        } else if (selisih < 0) {
          var sisa = -selisih;
          final batches = await txn.query('stok_batch',
              columns: ['id_batch', 'jumlah_stok'],
              where: 'id_produk = ? AND jumlah_stok > 0', whereArgs: [idProduk], orderBy: 'tanggal_exp ASC');
          for (final b in batches) {
            if (sisa <= 0) break;
            final take = ((b['jumlah_stok'] as int) > sisa) ? sisa : (b['jumlah_stok'] as int);
            await txn.rawUpdate('UPDATE stok_batch SET jumlah_stok = jumlah_stok - ? WHERE id_batch = ?', [take, b['id_batch']]);
            sisa -= take;
          }
        }
        await txn.insert('opname', {
          'id_user': userId,
          'id_produk': idProduk,
          'stok_sistem': sistem,
          'stok_fisik': stokFisik,
          'selisih': selisih,
          'alasan': alasan,
          'tanggal': DateTime.now().toIso8601String(),
        });
        await txn.insert('log', {
          'id_user': userId,
          'aktivitas': 'Opname produk $idProduk: sistem $sistem, fisik $stokFisik ($alasan)',
          'waktu': DateTime.now().toIso8601String(),
        });
      });
      return null;
    } catch (e) {
      lastError = e.toString();
      return e.toString();
    }
  }

  static Future<List<Map<String, dynamic>>> get opnames async {
    final rows = await _db!.rawQuery(
        'SELECT o.*, p.nama_produk AS _nm, u.nama_lengkap AS _usr FROM opname o '
        'LEFT JOIN produk p ON p.id_produk = o.id_produk '
        'LEFT JOIN users u ON u.id_user = o.id_user ORDER BY o.tanggal DESC LIMIT 200');
    return rows.map((r) {
      final m = Map<String, dynamic>.from(r);
      m['produk'] = {'nama_produk': m.remove('_nm')};
      m['_kasir'] = m.remove('_usr');
      return m;
    }).toList();
  }

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

  /// Nomor transaksi unik & berurutan: TRX-YYYYMMDD-0001 (dibuat di dalam txn).
  static Future<String> _nextNoTrx(Transaction txn, DateTime now, {String prefix = 'TRX'}) async {
    final day = DateFormat('yyyyMMdd').format(now);
    final rows = await txn.rawQuery(
        "SELECT COUNT(*) AS n FROM transaksi WHERE no_transaksi LIKE ?", ['$prefix-$day-%']);
    final n = ((rows.first['n'] ?? 0) as int) + 1;
    return '$prefix-$day-${n.toString().padLeft(4, '0')}';
  }

  /// Simpan transaksi SECARA ATOMIK: header + detail + deduksi stok FEFO
  /// dalam satu SQLite transaction. Jika salah satu gagal (mis. stok kurang),
  /// seluruh operasi dibatalkan otomatis — tidak ada stok "hilang" sebagian.
  /// Return header transaksi jika sukses, null jika gagal (cek [lastError]).
  static Future<Map<String, dynamic>?> commitSale({
    required int userId,
    required List<Map<String, dynamic>> items, // {id_produk, qty, harga_jual}
    required int diskon,
    required int pajak,
    required int uangDiterima,
    required String metode,
    int? shiftId,
  }) async {
    try {
      shiftId ??= (await activeShift(userId))?['id_shift'] as int?;
      final subTotal = items.fold<int>(0, (a, i) => a + (i['harga_jual'] as int) * (i['qty'] as int));
      var total = subTotal - diskon + pajak;
      if (total < 0) total = 0;
      if (uangDiterima < total) throw Exception('Uang diterima kurang dari total');
      final now = DateTime.now();
      late Map<String, dynamic> header;
      await _db!.transaction((txn) async {
        final no = await _nextNoTrx(txn, now);
        final idTrx = await txn.insert('transaksi', {
          'no_transaksi': no,
          'id_user': userId,
          'total_bayar': total,
          'diskon': diskon,
          'pajak': pajak,
          'uang_diterima': metode == 'tunai' ? uangDiterima : total,
          'kembalian': metode == 'tunai' ? uangDiterima - total : 0,
          'metode': metode,
          'status': 'selesai',
          'shift_id': shiftId,
          'tanggal': now.toIso8601String(),
        });
        for (final item in items) {
          final idProduk = item['id_produk'] as int;
          var need = item['qty'] as int;
          final batches = await txn.query('stok_batch',
              columns: ['id_batch', 'jumlah_stok', 'harga_beli_satuan'],
              where: 'id_produk = ? AND jumlah_stok > 0',
              whereArgs: [idProduk],
              orderBy: 'tanggal_exp ASC');
          int tersedia = batches.fold<int>(0, (a, b) => a + (b['jumlah_stok'] as int));
          if (tersedia < need) {
            throw Exception('Stok ${item['nama_produk'] ?? idProduk} tidak mencukupi (butuh $need, ada $tersedia)');
          }
          for (final b in batches) {
            if (need <= 0) break;
            final stok = b['jumlah_stok'] as int;
            final take = stok > need ? need : stok;
            await txn.rawUpdate(
                'UPDATE stok_batch SET jumlah_stok = jumlah_stok - ? WHERE id_batch = ? AND jumlah_stok >= ?',
                [take, b['id_batch'], take]);
            await txn.insert('detail_transaksi', {
              'id_transaksi': idTrx,
              'id_produk': idProduk,
              'qty': take,
              'subtotal': (item['harga_jual'] as int) * take,
              'id_batch': b['id_batch'],
              'harga_beli_satuan': b['harga_beli_satuan'] ?? 0,
            });
            need -= take;
          }
        }
        await txn.insert('log', {
          'id_user': userId,
          'aktivitas': 'Transaksi $no sebesar $total',
          'waktu': now.toIso8601String(),
        });
        header = {
          'id_transaksi': idTrx,
          'no_transaksi': no,
          'id_user': userId,
          'total_bayar': total,
          'diskon': diskon,
          'pajak': pajak,
          'uang_diterima': uangDiterima,
          'kembalian': metode == 'tunai' ? uangDiterima - total : 0,
          'metode': metode,
          'status': 'selesai',
          'tanggal': now.toIso8601String(),
        };
      });
      return header;
    } catch (e) {
      lastError = e.toString();
      debugPrint('commitSale: $e');
      return null;
    }
  }

  /// VOID transaksi: kembalikan stok ke batch asal, tandai status void.
  /// Atomik. Return pesan error, null jika sukses.
  static Future<String?> voidTransaction(int idTrx, int olehUserId, String alasan) async {
    try {
      await _db!.transaction((txn) async {
        final rows = await txn.query('transaksi', where: 'id_transaksi = ?', whereArgs: [idTrx], limit: 1);
        if (rows.isEmpty) throw Exception('Transaksi tidak ditemukan');
        if ((rows.first['status'] ?? '') == 'void') throw Exception('Transaksi sudah divoid');
        final details = await txn.query('detail_transaksi', where: 'id_transaksi = ?', whereArgs: [idTrx]);
        for (final d in details) {
          final b = d['id_batch'];
          final q = d['qty'] as int;
          if (b != null) {
            await txn.rawUpdate('UPDATE stok_batch SET jumlah_stok = jumlah_stok + ? WHERE id_batch = ?', [q, b]);
          }
        }
        await txn.update('transaksi', {
          'status': 'void',
          'void_alasan': alasan,
          'void_oleh': olehUserId,
          'void_pada': DateTime.now().toIso8601String(),
        }, where: 'id_transaksi = ?', whereArgs: [idTrx]);
        await txn.insert('log', {
          'id_user': olehUserId,
          'aktivitas': 'VOID transaksi ${rows.first['no_transaksi']}: $alasan',
          'waktu': DateTime.now().toIso8601String(),
        });
      });
      return null;
    } catch (e) {
      lastError = e.toString();
      debugPrint('voidTransaction: $e');
      return e.toString();
    }
  }

  /// RETUR PARSIAL: kembalikan sebagian qty item tertentu ke batch asal
  /// (FEFO terbalik: batch yang paling akhir dipakai dikembalikan lebih dulu),
  /// lalu buat transaksi penyesuaian bertipe 'retur' dengan total negatif.
  /// Transaksi asal TETAP selesai (tidak divoid) — sesuai praktik POS.
  /// Return header transaksi retur; null jika gagal (cek [lastError]).
  static Future<Map<String, dynamic>?> partialReturn({
    required int idTrxAsal,
    required List<Map<String, dynamic>> items, // {id_detail, qty_retur}
    required int userId,
    required String alasan,
    String metode = 'tunai',
  }) async {
    try {
      final now = DateTime.now();
      late Map<String, dynamic> header;
      await _db!.transaction((txn) async {
        final orig = await txn.query('transaksi', where: 'id_transaksi = ?', whereArgs: [idTrxAsal], limit: 1);
        if (orig.isEmpty) throw Exception('Transaksi tidak ditemukan');
        if ((orig.first['status'] ?? '') == 'void') throw Exception('Transaksi void tidak bisa diretur');
        int totalRetur = 0;
        for (final it in items) {
          final idDetail = it['id_detail'] as int;
          final qtyRetur = it['qty_retur'] as int;
          if (qtyRetur <= 0) continue;
          final drows = await txn.query('detail_transaksi', where: 'id_detail = ?', whereArgs: [idDetail], limit: 1);
          if (drows.isEmpty) throw Exception('Detail transaksi tidak ditemukan');
          final d = drows.first;
          final qtyAwal = d['qty'] as int;
          final sudahRetur = (d['qty_retur'] as int?) ?? 0;
          if (qtyRetur + sudahRetur > qtyAwal) {
            throw Exception('Qty retur melebihi sisa item (${qtyAwal - sudahRetur} tersedia)');
          }
          final hargaSatuan = qtyAwal == 0 ? 0 : ((d['subtotal'] as int) / qtyAwal).round();
          totalRetur += hargaSatuan * qtyRetur;
          // tandai qty_retur pada detail asal
          await txn.update('detail_transaksi', {'qty_retur': sudahRetur + qtyRetur},
              where: 'id_detail = ?', whereArgs: [idDetail]);
          // kembalikan stok ke batch asal bila masih ada kolomnya
          final idBatch = d['id_batch'];
          if (idBatch != null) {
            await txn.rawUpdate('UPDATE stok_batch SET jumlah_stok = jumlah_stok + ? WHERE id_batch = ?',
                [qtyRetur, idBatch]);
          } else {
            // fallback: batch aktif produk tersebut
            final b = await txn.query('stok_batch',
                columns: ['id_batch'], where: 'id_produk = ?', whereArgs: [d['id_produk']],
                orderBy: 'tanggal_exp ASC', limit: 1);
            if (b.isNotEmpty) {
              await txn.rawUpdate('UPDATE stok_batch SET jumlah_stok = jumlah_stok + ? WHERE id_batch = ?',
                  [qtyRetur, b.first['id_batch']]);
            }
          }
          // catat sebagai baris retur (qty negatif) pada transaksi baru nanti
        }
        if (totalRetur <= 0) throw Exception('Tidak ada item untuk diretur');
        final no = await _nextNoTrx(txn, now, prefix: 'RTX');
        final idRetur = await txn.insert('transaksi', {
          'no_transaksi': no,
          'id_user': userId,
          'total_bayar': -totalRetur,
          'diskon': 0,
          'pajak': 0,
          'uang_diterima': -totalRetur,
          'kembalian': 0,
          'metode': metode,
          'status': 'retur',
          'void_alasan': alasan, // pakai kolom alasan untuk catatan retur
          'void_oleh': userId,
          'void_pada': now.toIso8601String(),
          'tanggal': now.toIso8601String(),
        });
        // salin baris detail dengan qty negatif agar laporan HPP/omset konsisten
        for (final it in items) {
          final idDetail = it['id_detail'] as int;
          final qtyRetur = it['qty_retur'] as int;
          if (qtyRetur <= 0) continue;
          final d = (await txn.query('detail_transaksi', where: 'id_detail = ?', whereArgs: [idDetail], limit: 1)).first;
          final qtyAwal = d['qty'] as int;
          final hargaSatuan = qtyAwal == 0 ? 0 : ((d['subtotal'] as int) / qtyAwal).round();
          await txn.insert('detail_transaksi', {
            'id_transaksi': idRetur,
            'id_produk': d['id_produk'],
            'id_batch': d['id_batch'],
            'qty': -qtyRetur,
            'subtotal': -hargaSatuan * qtyRetur,
            'harga_beli_satuan': d['harga_beli_satuan'] ?? 0,
          });
        }
        await txn.insert('log', {
          'id_user': userId,
          'aktivitas': 'RETUR ${orig.first['no_transaksi']} sebesar $totalRetur: $alasan',
          'waktu': now.toIso8601String(),
        });
        header = {
          'id_transaksi': idRetur,
          'no_transaksi': no,
          'id_user': userId,
          'total_bayar': -totalRetur,
          'metode': metode,
          'status': 'retur',
          'tanggal': now.toIso8601String(),
          'asal': orig.first['no_transaksi'],
        };
      });
      return header;
    } catch (e) {
      lastError = e.toString();
      debugPrint('partialReturn: $e');
      return null;
    }
  }

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

  /// Ambil satu transaksi (untuk refresh status setelah void).
  static Future<Map<String, dynamic>?> transaksiById(int idTrx) async {
    final rows = await _db!.rawQuery(
        'SELECT t.*, u.nama_lengkap AS _kasir FROM transaksi t LEFT JOIN users u ON u.id_user = t.id_user '
        'WHERE t.id_transaksi = ? LIMIT ?', [idTrx, 1]);
    if (rows.isEmpty) return null;
    final m = Map<String, dynamic>.from(rows.first);
    m['users'] = {'nama_lengkap': m.remove('_kasir')};
    return m;
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
    final trx = await _db!.rawQuery("SELECT total_bayar FROM transaksi WHERE status='selesai' AND tanggal >= ? AND tanggal < ?", [start, end]);
    final prods = await products;
    final ambang = await lowStockThreshold();
    final exp = await nearExpBatches();
    return {
      'produk': prods.length,
      'low': prods.where((p) => ((p['stok'] ?? 0) as int) > 0 && ((p['stok'] ?? 0) as int) < ambang).length,
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
    if (rows.isEmpty) return null;
    final m = Map<String, dynamic>.from(rows.first);
    m.remove('recovery_key'); // jangan pernah bocorkan material rahasia ke UI
    m.remove('recovery_hash');
    return m;
  }

  static Future<bool> get hasToko async => (await toko) != null;

  static String _genRecoveryKey() {
    const chars = 'ABCDEFGHJKLMNPQRSTUVWXYZ23456789';
    final rnd = Random.secure();
    final s = List.generate(16, (_) => chars[rnd.nextInt(chars.length)]).join();
    return '${s.substring(0, 4)}-${s.substring(4, 8)}-${s.substring(8, 12)}-${s.substring(12, 16)}';
  }

  static String _normKey(String k) => k.trim().toUpperCase().replaceAll(RegExp(r'[^A-Z0-9]'), '');

  /// Simpan recovery key secara ter-hash (PBKDF2). Return hash.
  static Future<String> _hashRecovery(String key) async {
    final salt = PasswordHasher.generateSalt();
    return compute((msg) => PasswordHasher.hash(msg[0], msg[1]), [_normKey(key), salt]);
  }

  static Future<bool> _verifyRecovery(String storedHash, String input) async {
    if (storedHash.isEmpty) return false;
    if (!storedHash.startsWith('pbkdf2\$')) {
      // data lama plaintext — bandingkan lalu upgrade
      final ok = _normKey(storedHash) == _normKey(input);
      return ok;
    }
    return compute((msg) => PasswordHasher.verify(msg[0], msg[1]), [_normKey(input), storedHash])
        .then((v) => v == true);
  }

  /// Reset password user via recovery key milik toko. Return pesan error, null jika sukses.
  static Future<String?> resetPassword(String username, String recoveryKey, String newPass) async {
    try {
      final rows = await _db!.query('toko', limit: 1);
      if (rows.isEmpty) return 'Toko belum terdaftar';
      var stored = (rows.first['recovery_hash'] ?? rows.first['recovery_key'] ?? '').toString();
      final ok = await _verifyRecovery(stored, recoveryKey);
      if (!ok) return 'Recovery key salah';
      if (!stored.startsWith('pbkdf2\$')) {
        // upgrade hash recovery key lama ke PBKDF2
        final h = await _hashRecovery(recoveryKey);
        await _db!.update('toko', {'recovery_hash': h}, where: 'id_toko = ?', whereArgs: [rows.first['id_toko']]);
      }
      final u = await _db!.query('users', where: 'username = ?', whereArgs: [username.trim()], limit: 1);
      if (u.isEmpty) return 'Username tidak ditemukan';
      await _db!.update('users', {'password': await hashPassword(newPass)},
          where: 'id_user = ?', whereArgs: [u.first['id_user']]);
      await log(u.first['id_user'] as int, 'Reset password via recovery key');
      return null;
    } catch (e) {
      debugPrint('resetPassword: $e');
      return 'Gagal mereset password';
    }
  }

  /// Hapus SELURUH data toko lama: akun, produk, batch, transaksi, pembelian,
  /// pengeluaran, log, shift, opname, settings, data toko, dan file gambar produk lokal.
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
      'stok_batch', 'produk', 'categories', 'pengeluaran', 'log', 'shift', 'opname', 'users', 'toko',
      'settings', 'login_lock',
    ];
    for (final t in tables) {
      await _db!.delete(t);
    }
  }

  /// Daftarkan toko + akun owner pertama. Data lama DIHAPUS SEMUA dulu.
  /// Return recovery key (sekali saja, hanya disimpan dalam bentuk hash).
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
      final recoveryHash = await _hashRecovery(key);
      final passHash = await hashPassword(password);
      await _db!.transaction((txn) async {
        await txn.insert('toko', {'nama_toko': nama.trim(), 'alamat': alamat.trim(), 'recovery_hash': recoveryHash});
        await txn.insert('users', {
          'nama_lengkap': ownerNama.trim(),
          'username': ownerUsername.trim(),
          'password': passHash,
          'role': 'owner',
          'is_active': 1,
        });
      });
      return key;
    } catch (e) {
      lastError = e.toString();
      debugPrint('registerToko: $e');
      return null;
    }
  }

  // ===========================================================================
  // SHIFT KASIR (Z-report mini): buka/tutup laci per kasir dengan selisih.
  // ===========================================================================

  /// Shift aktif milik kasir, atau null jika belum buka shift.
  static Future<Map<String, dynamic>?> activeShift(int userId) async {
    final rows = await _db!.query('shift',
        where: 'id_user = ? AND selesai IS NULL', whereArgs: [userId], orderBy: 'id_shift DESC', limit: 1);
    return rows.isEmpty ? null : rows.first;
  }

  /// Buka shift kasir. Return header shift (berisi id_shift) atau null jika gagal.
  static Future<Map<String, dynamic>?> openShiftReturn(int userId, int modalAwal) async {
    try {
      final existing = await activeShift(userId);
      if (existing != null) throw Exception('Shift masih terbuka — tutup dulu sebelum buka baru');
      final id = await _db!.insert('shift', {
        'id_user': userId,
        'mulai': DateTime.now().toIso8601String(),
        'modal_awal': modalAwal,
      });
      await log(userId, 'Buka shift dengan modal Rp $modalAwal');
      final rows = await _db!.query('shift', where: 'id_shift = ?', whereArgs: [id], limit: 1);
      return rows.isEmpty ? {'id_shift': id} : rows.first;
    } catch (e) {
      lastError = e.toString();
      debugPrint('openShift: $e');
      return null;
    }
  }

  static Future<bool> openShift(int userId, int modalAwal) async =>
      (await openShiftReturn(userId, modalAwal)) != null;

  /// Tutup shift: hitung penjualan tunai selama shift, bandingkan dengan saldo hitung.
  /// Return ringkasan {penjualan_tunai, seharusnya, selisih} atau lempar lewat lastError.
  static Future<Map<String, dynamic>?> closeShift(int userId, int saldoHitung, String catatan) async {
    try {
      final sh = await activeShift(userId);
      if (sh == null) throw Exception('Tidak ada shift terbuka');
      final mulai = DateTime.parse(sh['mulai'].toString());
      // Prioritaskan transaksi yang di-tag ke shift ini; baris lama tanpa tag
      // dihitung berdasarkan rentang waktu (kompatibel sebelum fitur shift_id).
      final rows = await _db!.rawQuery(
          "SELECT COALESCE(SUM(kembalian),0) AS kembali, COALESCE(SUM(total_bayar),0) AS total FROM transaksi "
          "WHERE id_user = ? AND metode = 'tunai' AND status = 'selesai' AND tanggal >= ? "
          "AND (shift_id = ? OR shift_id IS NULL)",
          [userId, mulai.toIso8601String(), sh['id_shift']]);
      final totalTunai = (rows.first['total'] ?? 0) as int;
      final kembali = (rows.first['kembali'] ?? 0) as int;
      final penjualanTunai = totalTunai - kembali + (sh['modal_awal'] as int? ?? 0);
      final seharusnya = penjualanTunai; // uang di laci = modal + omset tunai (kembalian sudah keluar)
      final selisih = saldoHitung - seharusnya;
      await _db!.transaction((txn) async {
        await txn.update('shift', {
          'selesai': DateTime.now().toIso8601String(),
          'saldo_hitung': saldoHitung,
          'selisih': selisih,
          'catatan': catatan,
        }, where: 'id_shift = ?', whereArgs: [sh['id_shift']]);
        await txn.insert('log', {
          'id_user': userId,
          'aktivitas': 'Tutup shift — seharusnya $seharusnya, hitung $saldoHitung, selisih $selisih',
          'waktu': DateTime.now().toIso8601String(),
        });
      });
      return {'penjualan_tunai': penjualanTunai, 'seharusnya': seharusnya, 'selisih': selisih};
    } catch (e) {
      lastError = e.toString();
      debugPrint('closeShift: $e');
      return null;
    }
  }

  static Future<List<Map<String, dynamic>>> shifts({int? userId, DateTime? start, DateTime? end}) async {
    final where = <String>[];
    final args = <dynamic>[];
    if (userId != null) {
      where.add('s.id_user = ?');
      args.add(userId);
    }
    if (start != null) {
      where.add('s.mulai >= ?');
      args.add(start.toIso8601String());
    }
    if (end != null) {
      where.add('s.mulai <= ?');
      args.add(DateTime(end.year, end.month, end.day, 23, 59, 59).toIso8601String());
    }
    final rows = await _db!.rawQuery(
        'SELECT s.*, u.nama_lengkap AS _kasir FROM shift s LEFT JOIN users u ON u.id_user = s.id_user '
        '${where.isEmpty ? '' : 'WHERE ${where.join(' AND ')}'} ORDER BY s.id_shift DESC LIMIT 200', args);
    return rows.map((r) {
      final m = Map<String, dynamic>.from(r);
      m['_nama'] = m.remove('_kasir');
      return m;
    }).toList();
  }

  // ===========================================================================
  // LAPORAN ANALITIK (agregat sisi SQL — aman untuk DB besar)
  // ===========================================================================

  /// Penjualan harian: omset & jumlah transaksi per hari pada rentang tanggal.
  static Future<List<Map<String, dynamic>>> salesByDay(DateTime start, DateTime end) async {
    return _db!.rawQuery(
        "SELECT substr(tanggal,1,10) AS hari, COUNT(*) AS trx, SUM(total_bayar) AS omset, "
        "SUM(diskon) AS diskon, SUM(pajak) AS pajak "
        "FROM transaksi WHERE status='selesai' AND tanggal >= ? AND tanggal <= ? GROUP BY hari ORDER BY hari",
        [start.toIso8601String(), DateTime(end.year, end.month, end.day, 23, 59, 59).toIso8601String()]);
  }

  /// Produk terlaris berdasarkan qty pada rentang tanggal.
  static Future<List<Map<String, dynamic>>> topProducts(DateTime start, DateTime end, {int limit = 10}) async {
    return _db!.rawQuery(
        "SELECT p.nama_produk, SUM(d.qty) AS qty, SUM(d.subtotal) AS omset "
        "FROM detail_transaksi d JOIN transaksi t ON t.id_transaksi = d.id_transaksi JOIN produk p ON p.id_produk = d.id_produk "
        "WHERE t.status='selesai' AND t.tanggal >= ? AND t.tanggal <= ? "
        "GROUP BY d.id_produk ORDER BY qty DESC LIMIT ?",
        [start.toIso8601String(), DateTime(end.year, end.month, end.day, 23, 59, 59).toIso8601String(), limit]);
  }

  /// Rekap per metode pembayaran.
  static Future<List<Map<String, dynamic>>> salesByMethod(DateTime start, DateTime end) async {
    return _db!.rawQuery(
        "SELECT metode, COUNT(*) AS trx, SUM(total_bayar) AS omset FROM transaksi "
        "WHERE status='selesai' AND tanggal >= ? AND tanggal <= ? GROUP BY metode",
        [start.toIso8601String(), DateTime(end.year, end.month, end.day, 23, 59, 59).toIso8601String()]);
  }

  /// Laba/rugi periode: omset - HPP - pengeluaran.
  static Future<Map<String, dynamic>> profitReport(DateTime start, DateTime end) async {
    final e = DateTime(end.year, end.month, end.day, 23, 59, 59).toIso8601String();
    final s = start.toIso8601String();
    final om = await _db!.rawQuery(
        "SELECT COALESCE(SUM(total_bayar),0) AS o, COALESCE(SUM(diskon),0) AS d, COALESCE(SUM(pajak),0) AS p, COUNT(*) AS n "
        "FROM transaksi WHERE status='selesai' AND tanggal >= ? AND tanggal <= ?", [s, e]);
    final hp = await _db!.rawQuery(
        "SELECT COALESCE(SUM(d.harga_beli_satuan * d.qty),0) AS h FROM detail_transaksi d "
        "JOIN transaksi t ON t.id_transaksi = d.id_transaksi WHERE t.status='selesai' AND t.tanggal >= ? AND t.tanggal <= ?",
        [s, e]);
    final out = await _db!.rawQuery(
        'SELECT COALESCE(SUM(nominal),0) AS j FROM pengeluaran WHERE tanggal >= ? AND tanggal <= ?', [s, e]);
    final omset = (om.first['o'] ?? 0) as int;
    final hpp = (hp.first['h'] ?? 0) as int;
    final pengeluaran = (out.first['j'] ?? 0) as int;
    return {
      'omset': omset,
      'diskon': (om.first['d'] ?? 0) as int,
      'pajak': (om.first['p'] ?? 0) as int,
      'trx': (om.first['n'] ?? 0) as int,
      'hpp': hpp,
      'labaKotor': omset - hpp,
      'pengeluaran': pengeluaran,
      'labaBersih': omset - hpp - pengeluaran,
    };
  }

  /// Export CSV umum dari query yang diberikan (untuk laporan).
  static Future<List<List<dynamic>>> csvRows(String table, {String? where, List<dynamic>? args}) async {
    final rows = await _db!
        .rawQuery('SELECT * FROM $table ${where != null ? 'WHERE $where' : ''} ORDER BY rowid LIMIT 5000', args ?? []);
    if (rows.isEmpty) return [];
    final header = rows.first.keys.toList();
    return [header, ...rows.map((r) => header.map((k) => r[k]).toList())];
  }

  /// Tulis baris CSV ke file di folder Documents/export. Return path file.
  static Future<String> writeCsvFile(String name, List<List<dynamic>> rows) async {
    final dir = await getApplicationDocumentsDirectory();
    final expDir = Directory(p.join(dir.path, 'export'));
    if (!await expDir.exists()) await expDir.create(recursive: true);
    final safe = name.replaceAll(RegExp(r'[^A-Za-z0-9_\-]'), '_');
    final file = File(p.join(expDir.path, '$safe.csv'));
    final buf = StringBuffer();
    for (final r in rows) {
      buf.writeln(r.map((c) {
        final s = (c ?? '').toString();
        return s.contains(',') || s.contains('"') || s.contains('\n')
            ? '"${s.replaceAll('"', '""')}"'
            : s;
      }).join(','));
    }
    await file.writeAsString(buf.toString());
    return file.path;
  }

  // ===========================================================================
  // BACKUP & RESTORE — salinan penuh file SQLite (semua tabel) + auto-backup.
  // ===========================================================================

  /// Buat file backup .db di folder Documents/backup. Return path file.
  static Future<String> createBackup() async {
    final dir = await getApplicationDocumentsDirectory();
    final bakDir = Directory(p.join(dir.path, 'backup'));
    if (!await bakDir.exists()) await bakDir.create(recursive: true);
    final stamp = DateFormat('yyyyMMdd_HHmmss').format(DateTime.now());
    final target = p.join(bakDir.path, 'kastra_backup_$stamp.db');
    // jalankan checkpoint WAL agar salinan konsisten
    await _db!.rawQuery('PRAGMA wal_checkpoint(TRUNCATE)');
    final src = File(p.join(await getDatabasesPath(), 'kastra.db'));
    await src.copy(target);
    // simpan juga metadata utk auto-backup
    await _prefs?.setString('last_backup', DateTime.now().toIso8601String());
    await log(session ?? 0, 'Backup data dibuat: kastra_backup_$stamp.db');
    return target;
  }

  /// Daftar file backup tersimpan (terbaru dulu).
  static Future<List<File>> listBackups() async {
    final dir = await getApplicationDocumentsDirectory();
    final bakDir = Directory(p.join(dir.path, 'backup'));
    if (!await bakDir.exists()) return [];
    final files = bakDir.listSync().whereType<File>().where((f) => f.path.endsWith('.db')).toList()
      ..sort((a, b) => b.path.compareTo(a.path));
    return files;
  }

  /// Pulihkan database dari file backup .db. Setelah ini app harus restart.
  static Future<String?> restoreBackup(String filePath) async {
    try {
      final src = File(filePath);
      if (!await src.exists()) return 'File backup tidak ditemukan';
      await _db!.close();
      final dst = File(p.join(await getDatabasesPath(), 'kastra.db'));
      // hapus WAL/shm lama
      for (final ext in ['-wal', '-shm']) {
        final f = File('${dst.path}$ext');
        if (await f.exists()) await f.delete();
      }
      await src.copy(dst.path);
      _db = await _open();
      return null;
    } catch (e) {
      lastError = e.toString();
      return e.toString();
    }
  }

  /// Auto-backup harian: panggil saat app start. Backup jika >24 jam dari terakhir.
  static Future<void> autoBackupIfDue() async {
    try {
      final last = _prefs?.getString('last_backup');
      final due = last == null ||
          DateTime.now().difference(DateTime.parse(last)) > const Duration(hours: 24);
      if (!due) return;
      await createBackup();
      // rotasi: simpan maksimal 14 backup terakhir
      final all = await listBackups();
      for (final f in all.skip(14)) {
        try {
          await f.delete();
        } catch (_) {}
      }
    } catch (e) {
      debugPrint('autoBackup: $e');
    }
  }

  /// Export seluruh data toko ke file JSON di folder Documents/backup.
  /// Format kompatibel dengan importBackup (restore sebagian: master data).
  /// Return path file, atau null jika gagal.
  static Future<String?> exportBackupJson() async {
    try {
      final dir = await getApplicationDocumentsDirectory();
      final bakDir = Directory(p.join(dir.path, 'backup'));
      if (!await bakDir.exists()) await bakDir.create(recursive: true);
      final stamp = DateFormat('yyyyMMdd_HHmmss').format(DateTime.now());
      final file = File(p.join(bakDir.path, 'kastra_export_$stamp.json'));
      final data = <String, dynamic>{};
      for (final t in ['toko', 'users', 'categories', 'produk', 'stok_batch',
        'transaksi', 'detail_transaksi', 'pembelian', 'detail_pembelian',
        'pengeluaran', 'shift', 'opname', 'settings']) {
        final rows = await _db!.query(t);
        data[t] = rows;
      }
      data['_exported'] = DateTime.now().toIso8601String();
      await file.writeAsString(jsonEncode(data));
      await log(session ?? 0, 'Export JSON dibuat: ${p.basename(file.path)}');
      return file.path;
    } catch (e) {
      lastError = e.toString();
      debugPrint('exportBackupJson: $e');
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
      // Pulihkan tabel transaksi & pendukung bila ada (urutan mematuhi FK).
      for (final tbl in ['stok_batch', 'transaksi', 'detail_transaksi',
        'pembelian', 'detail_pembelian', 'pengeluaran', 'shift', 'opname', 'settings']) {
        for (final r in (json[tbl] as List? ?? [])) {
          await _db!.insert(tbl, Map<String, dynamic>.from(r),
              conflictAlgorithm: ConflictAlgorithm.replace);
        }
      }
      return null;
    } catch (e) {
      debugPrint('importBackup: $e');
      return e.toString();
    }
  }
}