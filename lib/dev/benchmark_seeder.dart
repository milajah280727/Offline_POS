import 'dart:io';
import 'dart:math';

import 'package:flutter/material.dart';
import 'package:path/path.dart' as p;
import 'package:sqflite/sqflite.dart';
import 'package:kastra/services.dart';
import 'package:kastra/theme.dart';
import 'package:kastra/widgets.dart';

// ignore_for_file: deprecated_member_use, use_build_context_synchronously

/// ============================================================================
/// KASTRA — GENERATOR DATA BENCHMARK
/// Simulasi toko yang sudah berjalan bertahun-tahun. HANYA untuk device
/// testing! Semua data lama di perangkat AKAN DIHAPUS.
///
/// Login setelah generate: owner/owner123 · admin/admin123 · kasir/kasir123
/// ============================================================================

class BenchPreset {
  final String label;
  final int years, avgTrxPerDay, skuTarget;
  const BenchPreset(this.label, this.years, this.avgTrxPerDay, this.skuTarget);
}

const kPresets = [
  BenchPreset('Ringan · 1 tahun', 1, 120, 400),
  BenchPreset('Sedang · 3 tahun', 3, 150, 800),
  BenchPreset('Ekstrem · 10 tahun (toko mapan)', 10, 200, 1200),
];

// ================================ SEEDER ====================================

class BenchmarkSeeder {
  static const _kategori = [
    'Makanan Instan', 'Minuman Kemasan', 'Minuman Serbuk', 'Kopi & Teh', 'Snack',
    'Biskuit & Kue', 'Roti', 'Sembako', 'Minyak & Saus', 'Bumbu Dapur',
    'Susu & Olahan', 'Kebersihan Diri', 'Kebersihan Rumah', 'Perawatan Rambut',
    'Rokok', 'Perlengkapan Bayi', 'Obat Umum', 'Alat Tulis', 'Peralatan Dapur',
    'Makanan Kaleng', 'Frozen Food', 'Mainan Anak', 'Pakaian & Aksesoris',
    'Minuman Energi', 'Kebutuhan Rumah',
  ];

  /// (nama, kategori, harga 2024, expired bulan)
  static const _pool = <(String, String, int, int)>[
    ('Indomie Goreng', 'Makanan Instan', 3500, 6), ('Indomie Goreng Spesial', 'Makanan Instan', 4200, 6),
    ('Indomie Kari Ayam', 'Makanan Instan', 3200, 6), ('Indomie Ayam Bawang', 'Makanan Instan', 3100, 6),
    ('Indomie Soto Mie', 'Makanan Instan', 3200, 6), ('Mie Sedaap Goreng', 'Makanan Instan', 3300, 6),
    ('Mie Sedaap Kari Ayam', 'Makanan Instan', 3100, 6), ('Mie Sedaap Soto', 'Makanan Instan', 3000, 6),
    ('Sarimi Isi 2', 'Makanan Instan', 3200, 6), ('Supermie Soto', 'Makanan Instan', 3000, 6),
    ('Mi Sukses Goreng', 'Makanan Instan', 3000, 6), ('Lakumi Goreng', 'Makanan Instan', 4000, 6),
    ('Aqua 600ml', 'Minuman Kemasan', 4000, 12), ('Aqua 1500ml', 'Minuman Kemasan', 6500, 12),
    ('Le Minerale 600ml', 'Minuman Kemasan', 4500, 12), ('Club Air 600ml', 'Minuman Kemasan', 3500, 12),
    ('Coca Cola 250ml', 'Minuman Kemasan', 5000, 9), ('Sprite 250ml', 'Minuman Kemasan', 5000, 9),
    ('Fanta 250ml', 'Minuman Kemasan', 5000, 9), ('Teh Pucuk Harum 350ml', 'Minuman Kemasan', 4000, 9),
    ('Teh Kotak 250ml', 'Minuman Kemasan', 4000, 9), ('Teh Botol Sosro 350ml', 'Minuman Kemasan', 4500, 9),
    ('Ultra Milk Full Cream 250ml', 'Minuman Kemasan', 5500, 6), ('Milk Life Cokelat 250ml', 'Minuman Kemasan', 6000, 6),
    ('Frisian Flag UHT 250ml', 'Minuman Kemasan', 6000, 8), ('Pocari Sweat 500ml', 'Minuman Kemasan', 8500, 12),
    ('You C1000 Orange 500ml', 'Minuman Kemasan', 9500, 9),
    ('Tang Orange Sachet', 'Minuman Serbuk', 1000, 12), ('Tang Orange 200gr', 'Minuman Serbuk', 15000, 18),
    ('Kopiko Blanca Sachet', 'Minuman Serbuk', 1500, 12), ('Milo Activ-Go Sachet', 'Minuman Serbuk', 2000, 12),
    ('Dancow Full Cream Sachet', 'Minuman Serbuk', 2000, 12), ('Good Day Cappuccino Sachet', 'Minuman Serbuk', 1500, 12),
    ('Nano Nano Sachet', 'Minuman Serbuk', 500, 12), ('Kuku Bima Energi', 'Minuman Serbuk', 2000, 12),
    ('Nu Green Tea Sachet', 'Minuman Serbuk', 1000, 12),
    ('Kapal Api Special 165gr', 'Kopi & Teh', 18000, 18), ('Kopi ABC 165gr', 'Kopi & Teh', 17000, 18),
    ('Torabika Creme 65gr', 'Kopi & Teh', 3500, 18), ('BSK Kopi Susu 65gr', 'Kopi & Teh', 3500, 18),
    ('Nescafe Classic 100gr', 'Kopi & Teh', 23000, 18), ('Indocafe Murni 100gr', 'Kopi & Teh', 14000, 18),
    ('Sariwangi 25gr', 'Kopi & Teh', 1500, 18), ('Teh Celup Sosro', 'Kopi & Teh', 12000, 18),
    ('Chitato Sapi Panggang 68gr', 'Snack', 12500, 6), ('Chitato Dipinggit 68gr', 'Snack', 11000, 6),
    ('Taro Net Seaweed 62gr', 'Snack', 8500, 6), ('Cheetos Keju', 'Snack', 2000, 6),
    ('Chiki Ball Keju', 'Snack', 2000, 6), ('Qtela Tempe 68gr', 'Snack', 8000, 6),
    ('Maxicorn 90gr', 'Snack', 10000, 6), ('Beng Beng', 'Snack', 2500, 9),
    ('SilverQueen Chunky Bar', 'Snack', 12000, 9), ('Kacang Garuda 200gr', 'Snack', 14000, 9),
    ('Oreo Original 133gr', 'Biskuit & Kue', 9500, 9), ('Oreo Small', 'Biskuit & Kue', 5000, 9),
    ('Roma Kelapa', 'Biskuit & Kue', 9000, 12), ('Roma Sari Gandum', 'Biskuit & Kue', 8500, 12),
    ('Khong Guan 300gr', 'Biskuit & Kue', 13000, 12), ('Nissin Wafer Cokelat', 'Biskuit & Kue', 11000, 9),
    ('Ritz Crackers 133gr', 'Biskuit & Kue', 10000, 9),
    ('Sari Roti Tawar', 'Roti', 9000, 1), ('Sari Roti Cokelat', 'Roti', 9500, 1),
    ('Sari Roti Nanas', 'Roti', 9500, 1), ('Roti Gandum', 'Roti', 11000, 1),
    ('Beras Pandan Wangi 5kg', 'Sembako', 72000, 12), ('Beras Ramos 5kg', 'Sembako', 60000, 12),
    ('Gula Pasir Gulaku 1kg', 'Sembako', 18000, 24), ('Gula Pasir Lokal 1kg', 'Sembako', 16000, 24),
    ('Minyak Goreng Bimoli 2L', 'Sembako', 39000, 12), ('Minyak Goreng Sania 2L', 'Sembako', 34000, 12),
    ('Tepung Segitiga Biru 1kg', 'Sembako', 13000, 12), ('Garam Beryodium 500gr', 'Sembako', 4000, 24),
    ('Kacang Hijau 500gr', 'Sembako', 12000, 12),
    ('Kecap Manis ABC 520ml', 'Minyak & Saus', 21000, 18), ('Kecap Bango 520ml', 'Minyak & Saus', 24000, 18),
    ('Saus Sambal ABC 340ml', 'Minyak & Saus', 12000, 18), ('Saus Tomat ABC 340ml', 'Minyak & Saus', 11000, 18),
    ('Saus Tiram 135ml', 'Minyak & Saus', 11000, 18),
    ('Royco Kaldu Ayam 120gr', 'Bumbu Dapur', 15000, 18), ('Royco Sachet', 'Bumbu Dapur', 1000, 18),
    ('Masako Ayam 250gr', 'Bumbu Dapur', 15000, 18), ('Bumbu Racik Tumis', 'Bumbu Dapur', 3000, 12),
    ('Bumbu Pecel', 'Bumbu Dapur', 6000, 12), ('Merica Bubuk 50gr', 'Bumbu Dapur', 8000, 24),
    ('Gula Merah 500gr', 'Bumbu Dapur', 12000, 12),
    ('Dancow 800gr', 'Susu & Olahan', 98000, 18), ('SGM Eksplor 400gr', 'Susu & Olahan', 38000, 18),
    ('Bebelac 400gr', 'Susu & Olahan', 45000, 18), ('Milo 300gr', 'Susu & Olahan', 45000, 18),
    ('Keju Cheddar 250gr', 'Susu & Olahan', 25000, 6),
    ('Sabun Lifebuoy', 'Kebersihan Diri', 4500, 36), ('Sabun Lux', 'Kebersihan Diri', 4500, 36),
    ('Sabun Giv', 'Kebersihan Diri', 3500, 36), ('Pepsodent 190gr', 'Kebersihan Diri', 18000, 24),
    ('Close Up 190gr', 'Kebersihan Diri', 18000, 24), ('Sikat Gigi', 'Kebersihan Diri', 5000, 36),
    ('Tissue Paseo 250s', 'Kebersihan Diri', 18000, 24),
    ('Sunlight 755ml', 'Kebersihan Rumah', 19000, 24), ('Sunlight Sachet', 'Kebersihan Rumah', 1000, 24),
    ('Rinso Anti Noda 770gr', 'Kebersihan Rumah', 21000, 24), ('Rinso Sachet', 'Kebersihan Rumah', 1500, 24),
    ('Daia 795gr', 'Kebersihan Rumah', 17000, 24), ('Molto Ultra 800ml', 'Kebersihan Rumah', 19000, 24),
    ('Molto Sachet', 'Kebersihan Rumah', 1000, 24), ('Wipol 500ml', 'Kebersihan Rumah', 14000, 24),
    ('Harpic 500ml', 'Kebersihan Rumah', 21000, 24),
    ('Shampo Clear Sachet', 'Perawatan Rambut', 1000, 24), ('Shampo Lifebuoy Sachet', 'Perawatan Rambut', 1000, 24),
    ('Shampo Pantene Sachet', 'Perawatan Rambut', 1500, 24), ('Shampo Sunsilk Sachet', 'Perawatan Rambut', 1000, 24),
    ('Pomade', 'Perawatan Rambut', 12000, 36),
    ('Sampoerna Mild 16', 'Rokok', 33000, 24), ('Gudang Garam Surya 12', 'Rokok', 28000, 24),
    ('Dji Sam Soe 12', 'Rokok', 28000, 24), ('GG Mild 16', 'Rokok', 28000, 24),
    ('Class Mild 16', 'Rokok', 31000, 24), ('LA Lights 16', 'Rokok', 30000, 24),
    ('U Mild 16', 'Rokok', 27000, 24), ('Marlboro Red 16', 'Rokok', 39000, 24),
    ('Mamypoko Pants M 4', 'Perlengkapan Bayi', 58000, 24), ('Sweety Silver M 4', 'Perlengkapan Bayi', 50000, 24),
    ('Pampers Premium 2', 'Perlengkapan Bayi', 60000, 24), ('Tissue Basah', 'Perlengkapan Bayi', 6000, 18),
    ('Minyak Telon', 'Perlengkapan Bayi', 25000, 24),
    ('Tolak Angin', 'Obat Umum', 7000, 24), ('Antangin', 'Obat Umum', 5000, 24),
    ('Panadol', 'Obat Umum', 10000, 24), ('Bodrex', 'Obat Umum', 4000, 24),
    ('Ambeven', 'Obat Umum', 12000, 24), ('Betadine 15ml', 'Obat Umum', 12000, 24),
    ('Minyak Kayu Putih 15ml', 'Obat Umum', 12000, 24), ('Cap Lang 30ml', 'Obat Umum', 15000, 24),
    ('Hemaviton', 'Obat Umum', 2500, 24), ('Promag', 'Obat Umum', 8000, 24),
    ('Pulpen Standard AE7', 'Alat Tulis', 3000, 36), ('Pensil Faber Castell', 'Alat Tulis', 3000, 36),
    ('Buku Tulis Sidu 38', 'Alat Tulis', 4000, 36), ('Penghapus', 'Alat Tulis', 2000, 36),
    ('Rautan', 'Alat Tulis', 2000, 36), ('Stabilo', 'Alat Tulis', 12000, 36),
    ('Spidol Snowman', 'Alat Tulis', 4000, 36),
    ('Sedotan', 'Peralatan Dapur', 2000, 36), ('Gelas Plastik', 'Peralatan Dapur', 3000, 36),
    ('Piring Foam', 'Peralatan Dapur', 3000, 36), ('Sendok Plastik', 'Peralatan Dapur', 1000, 36),
    ('Korek Api', 'Peralatan Dapur', 3000, 36), ('Korek Gas', 'Peralatan Dapur', 8000, 36),
    ('Spons Cuci', 'Peralatan Dapur', 3000, 36),
    ('Corned Beef 200gr', 'Makanan Kaleng', 23000, 24), ('Sarden ABC 155gr', 'Makanan Kaleng', 14000, 24),
    ('SKM Frisian Flag 545gr', 'Makanan Kaleng', 24000, 18),
    ('Nugget Fiesta 500gr', 'Frozen Food', 36000, 6), ('Sosis So Good 370gr', 'Frozen Food', 38000, 6),
    ('Bakso Sapi 500gr', 'Frozen Food', 32000, 6), ('Kentang Goreng 500gr', 'Frozen Food', 30000, 6),
    ('Balon', 'Mainan Anak', 3000, 36), ('Mobil Diecast', 'Mainan Anak', 12000, 36),
    ('Puzzle 60pcs', 'Mainan Anak', 18000, 36), ('Slime', 'Mainan Anak', 6000, 36),
    ('Kaos Kaki', 'Pakaian & Aksesoris', 8000, 36), ('CD Anak', 'Pakaian & Aksesoris', 10000, 36),
    ('Sandal Jepit', 'Pakaian & Aksesoris', 12000, 36), ('Masker', 'Pakaian & Aksesoris', 5000, 24),
    ('Kratingdaeng', 'Minuman Energi', 9000, 9), ('Extra Joss', 'Minuman Energi', 2500, 12),
    ('M-150', 'Minuman Energi', 8000, 9),
    ('Lampu LED', 'Kebutuhan Rumah', 15000, 36), ('Baterai AA', 'Kebutuhan Rumah', 5000, 24),
    ('Baterai AAA', 'Kebutuhan Rumah', 5000, 24), ('Obat Nyamuk Bakar', 'Kebutuhan Rumah', 12000, 24),
    ('Obat Nyamuk Liquid', 'Kebutuhan Rumah', 18000, 24), ('Kamper', 'Kebutuhan Rumah', 5000, 36),
  ];

  /// Template filler: (kategori, jenis, varian, ukuran, hargaMin, hargaMax, expBulan)
  static final _fill = <(String, List<String>, List<String>, List<String>, int, int, int)>[
    ('Snack', ['Keripik', 'Kacang', 'Wafer', 'Stick'], ['Balado', 'BBQ', 'Keju', 'Seaweed', 'Pedas Manis', 'Original'], ['25gr', '40gr', '68gr', '90gr'], 2500, 12000, 6),
    ('Minuman Kemasan', ['Teh', 'Jus', 'Air Minum', 'Soda'], ['Melati', 'Lemon', 'Leci', 'Jeruk', 'Apel', 'Mangga'], ['200ml', '250ml', '350ml', '450ml', '600ml'], 3000, 9000, 9),
    ('Kebersihan Rumah', ['Sabun Cuci', 'Pembersih Lantai', 'Pelembut', 'Pengharum'], ['Mawar', 'Lavender', 'Jeruk', 'Antiseptik', 'Melati'], ['350ml', '450ml', '770ml', '800ml'], 8000, 22000, 24),
    ('Kebersihan Diri', ['Sabun Mandi Cair', 'Shampo Botol', 'Hand Sanitizer'], ['Milk', 'Aloe Vera', 'Tea Tree', 'Vitamin'], ['50ml', '100ml', '170ml', '250ml'], 6000, 25000, 24),
    ('Biskuit & Kue', ['Wafer', 'Biskuit Selai', 'Crackers'], ['Cokelat', 'Vanila', 'Stroberi', 'Pandan', 'Keju'], ['55gr', '95gr', '130gr', '220gr'], 4000, 14000, 9),
    ('Makanan Instan', ['Mie Kuah', 'Bihun', 'Mie Goreng Istimewa'], ['Ayam Bawang', 'Soto', 'Kari', 'Sapi Bakar'], ['75gr', '85gr', '95gr'], 2800, 5500, 6),
  ];

  static const _fBrand = ['Yummy', 'Star', 'Lucky', 'Jaya', 'Bintang', 'Sari', 'Mekar', 'Oke', 'Top', 'Hemat'];
  static const _suppliers = [
    'PT Indofood Sukses Makmur', 'CV Sinar Niaga', 'PT Unilever Indonesia',
    'Distributor Mitra Jaya', 'Toko Grosir Sejahtera', 'PT Mayora Indah',
    'Agen Aqua Tirta', 'CV Berkah Amis', 'PT Sinar Sosro', 'Distributor Cahaya Baru',
  ];

    /// (nama, username, password, role, is_active) — username WAJIB unik
  static const _userDefs = [
    ('Budi Santoso', 'owner', 'owner123', 'owner', 1),
    ('Andi Wijaya', 'admin1', 'admin123', 'admin', 1),
    ('Siti Rahma', 'admin2', 'admin123', 'admin', 1),
    ('Dewi Lestari', 'admin3', 'admin123', 'admin', 0),
    ('Rina Marlina', 'kasir1', 'kasir123', 'kasir', 1),
    ('Joko Susilo', 'kasir2', 'kasir123', 'kasir', 1),
    ('Ayu Kusuma', 'kasir3', 'kasir123', 'kasir', 1),
    ('Hendra Gunawan', 'kasir4', 'kasir123', 'kasir', 0),
    ('Maya Anggraini', 'kasir5', 'kasir123', 'kasir', 1),
    ('Fajar Nugroho', 'kasir6', 'kasir123', 'kasir', 0),
    ('Lina Puspita', 'kasir7', 'kasir123', 'kasir', 1),
    ('Rudi Hartono', 'kasir8', 'kasir123', 'kasir', 1),
    ('Nia Ramadhani', 'kasir9', 'kasir123', 'kasir', 0),
    ('Bayu Pratama', 'kasir10', 'kasir123', 'kasir', 1),
    ('Citra Ayu', 'kasir11', 'kasir123', 'kasir', 1),
    ('Eko Saputra', 'admin4', 'admin123', 'admin', 1),
  ];

  static const _hourW = [0, 0, 0, 0, 0, 0, 1, 3, 5, 4, 4, 5, 7, 5, 4, 4, 5, 7, 9, 8, 6, 4, 2, 1];

  // ---------------- util ----------------
  static int _r100(int v) => (v / 100).round() * 100;
  static int _r500(int v) => (v / 500).round() * 500;
  static String _d(DateTime t) =>
      '${t.year.toString().padLeft(4, '0')}-${t.month.toString().padLeft(2, '0')}-${t.day.toString().padLeft(2, '0')}';
  static String _rp(int v) =>
      'Rp ${v.toString().replaceAllMapped(RegExp(r'\B(?=(\d{3})+(?!\d))'), (m) => '.')}';

  static int _price(int base, int yearIdx) {
    final v = (base * pow(1.045, yearIdx)).round(); // inflasi 4.5%/tahun
    return v >= 10000 ? _r500(v) : _r100(v);
  }

  static int _pickHour(Random r) {
    final total = _hourW.fold<int>(0, (a, b) => a + b);
    var x = r.nextInt(total);
    for (int h = 0; h < 24; h++) {
      x -= _hourW[h];
      if (x < 0) return h;
    }
    return 19;
  }

  static int _cash(int total, Random r) {
    if (r.nextDouble() < 0.25) return total;
    final step = total < 10000 ? 500 : (total < 50000 ? 1000 : (total < 200000 ? 5000 : 10000));
    return ((total / step).ceil() * step);
  }

  /// Insert banyak baris via batch — API sqflite tidak punya insertAll,
  /// jadi kita loop batch.insert() lalu commit sekali (tetap 1 transaksi).
  static Future<void> _bulkInsert(
      Transaction txn, String table, List<Map<String, Object?>> rows) async {
    if (rows.isEmpty) return;
    final b = txn.batch();
    for (final r in rows) {
      b.insert(table, r);
    }
    await b.commit(noResult: true);
  }

  /// PRAGMA aman untuk Android: harus rawQuery (bukan execute) jika PRAGMA
  /// mengembalikan baris hasil, else error "Queries can be performed using
  /// SQLiteDatabase query or rawQuery methods only."
  static Future<void> _pragma(Database db, String sql) async {
    try {
      await db.rawQuery(sql);
    } catch (_) {
      // beberapa device/perangkat mungkin menolak PRAGMA tertentu — abaikan.
    }
  }

  static Future<Map<String, dynamic>> run({
    required BenchPreset cfg,
    required bool createIndexes,
    required void Function(double progress, String msg) onProgress,
  }) async {
    final sw = Stopwatch()..start();
    final rnd = Random(20240915); // deterministic → hasil konsisten

    final dbPath = p.join(await getDatabasesPath(), 'kastra.db');
    final db = await openDatabase(dbPath);

    try {
      await _pragma(db, 'PRAGMA journal_mode=WAL');
      await _pragma(db, 'PRAGMA synchronous=NORMAL');
      await _pragma(db, 'PRAGMA cache_size=-32000');

      // ---------- 0. WIPE ----------
      onProgress(0, 'Membersihkan data lama...');
      const tables = [
        'detail_transaksi', 'transaksi', 'detail_pembelian', 'pembelian',
        'stok_batch', 'produk', 'categories', 'pengeluaran', 'log', 'users', 'toko',
      ];
      await db.transaction((txn) async {
        final b = txn.batch();
        for (final t in tables) {
          b.delete(t);
        }
        await b.commit(noResult: true);
        try {
          await txn.execute('DELETE FROM sqlite_sequence');
        } catch (_) {}
      });

      final seq = <String, int>{};
      int nextId(String t) => seq[t] = (seq[t] ?? 0) + 1;
      final bcUsed = <String>{};
      String barcode() {
        while (true) {
          final s = '899${List.generate(9, (_) => rnd.nextInt(10)).join()}';
          if (bcUsed.add(s)) return s;
        }
      }

      // ---------- 1. TOKO, USER, KATEGORI ----------
      onProgress(0.01, 'Membuat toko, user & kategori...');
      await db.insert('toko', {
        'nama_toko': 'Toko Kastra Jaya',
        'alamat': 'Jl. Merdeka No. 123, Jakarta',
        'recovery_key': 'BENCH-TEST-2024-DEMO',
      });

      final kasirIds = <int>[], adminIds = <int>[];
      for (int i = 0; i < _userDefs.length; i++) {
        final u = _userDefs[i];
        final id = i + 1;
        await db.insert('users', {
          'id_user': id, 'nama_lengkap': u.$1, 'username': u.$2,
          'password': u.$3, 'role': u.$4, 'is_active': u.$5,
        });
        if (u.$4 == 'kasir' && u.$5 == 1) kasirIds.add(id);
        if (u.$4 == 'admin' && u.$5 == 1) adminIds.add(id);
      }

      final List<Map<String, Object?>> catRows = [
        for (int i = 0; i < _kategori.length; i++)
          {'id_kategori': i + 1, 'nama_kategori': _kategori[i]},
      ];
      await db.transaction((txn) => _bulkInsert(txn, 'categories', catRows));

      // ---------- 2. KATALOG PRODUK ----------
      onProgress(0.02, 'Membangun katalog ${cfg.skuTarget} SKU...');
      final sims = <_Sim>[];
      final used = <String>{};
      for (final e in _pool) {
        if (sims.length >= cfg.skuTarget) break;
        if (!used.add(e.$1)) continue;
        sims.add(_Sim(
          nama: e.$1, kategori: e.$2, basePrice: e.$3,
          shelfDays: (e.$4 * 30 * (0.85 + rnd.nextDouble() * 0.4)).round(),
          weight: sims.length < 60 ? 4 + rnd.nextDouble() * 6 : 0.3 + rnd.nextDouble() * 1.2,
          restockEvery: 7 + rnd.nextInt(29),
          nextRestock: rnd.nextInt(30),
        ));
      }
      int guard = 0;
      while (sims.length < cfg.skuTarget && guard++ < 50000) {
        final t = _fill[guard % _fill.length];
        final nama = '${_fBrand[rnd.nextInt(_fBrand.length)]} '
            '${t.$2[rnd.nextInt(t.$2.length)]} ${t.$3[rnd.nextInt(t.$3.length)]} '
            '${t.$4[rnd.nextInt(t.$4.length)]}';
        if (!used.add(nama)) continue;
        final inactive = rnd.nextDouble() < 0.02;
        final s = _Sim(
          nama: nama, kategori: t.$1,
          basePrice: _r500(t.$5 + rnd.nextInt(t.$6 - t.$5)),
          shelfDays: (t.$7 * 30 * (0.85 + rnd.nextDouble() * 0.4)).round(),
          weight: inactive ? 0 : 0.1 + rnd.nextDouble() * 0.7,
          restockEvery: 7 + rnd.nextInt(29),
          nextRestock: rnd.nextInt(30),
        );
        s.inactive = inactive;
        sims.add(s);
      }

      final prodRows = <Map<String, Object?>>[];
      for (final s in sims) {
        s.id = nextId('produk');
        prodRows.add({
          'id_produk': s.id, 'nama_produk': s.nama, 'kategori': s.kategori,
          'harga_jual': s.basePrice, 'harga_beli': _r100((s.basePrice * 0.78).round()),
          'barcode': barcode(), 'gambar': null, 'is_active': s.inactive ? 0 : 1,
        });
      }
      await db.transaction((txn) => _bulkInsert(txn, 'produk', prodRows));

      // cumulative weights untuk weighted-random pick
      final cum = <double>[];
      double c = 0;
      for (final s in sims) {
        c += s.weight;
        cum.add(c);
      }
      final totalW = c;
      int pickIdx(double x) {
        int lo = 0, hi = cum.length - 1;
        while (lo < hi) {
          final mid = (lo + hi) >> 1;
          if (cum[mid] < x) {
            lo = mid + 1;
          } else {
            hi = mid;
          }
        }
        return lo;
      }
      _Sim? pickProduct() {
        for (int t = 0; t < 25; t++) {
          final s = sims[pickIdx(rnd.nextDouble() * totalW)];
          if (s.active > 0 && s.head < s.queue.length) return s;
        }
        return null;
      }

      // ---------- 3. SIMULASI HARIAN ----------
      final buf = _Buf();
      final now = DateTime.now();
      final start = DateTime(now.year - cfg.years, now.month, now.day);
      final totalDays = now.difference(start).inDays;
      int nTrx = 0, nDetail = 0;

      Future<void> flush() async {
        if (buf.batch.isEmpty &&
            buf.pem.isEmpty && buf.pemD.isEmpty &&
            buf.trx.isEmpty && buf.detail.isEmpty &&
            buf.out.isEmpty && buf.log.isEmpty) {
          return;
        }
        await db.transaction((txn) async {
          await _bulkInsert(txn, 'stok_batch', buf.batch);
          await _bulkInsert(txn, 'pembelian', buf.pem);
          await _bulkInsert(txn, 'detail_pembelian', buf.pemD);
          await _bulkInsert(txn, 'transaksi', buf.trx);
          await _bulkInsert(txn, 'detail_transaksi', buf.detail);
          await _bulkInsert(txn, 'pengeluaran', buf.out);
          await _bulkInsert(txn, 'log', buf.log);
        });
        buf.clear();
      }

      void addOut(DateTime date, String ket, int base, int spread, double mul) {
        buf.out.add({
          'id_pengeluaran': nextId('pengeluaran'), 'keterangan': ket,
          'nominal': _r100((base * mul + rnd.nextInt(spread)).round()),
          'tanggal': DateTime(date.year, date.month, date.day, 10, rnd.nextInt(240)).toIso8601String(),
        });
      }

      for (int day = 0; day < totalDays; day++) {
        final date = start.add(Duration(days: day));
        final yearIdx = day ~/ 365;
        final restock = <(_Sim, int, int)>[];

        // restock + sweep batch kadaluarsa
        for (final s in sims) {
          while (s.head < s.queue.length && s.queue[s.head].expDay <= day) {
            s.active -= s.queue[s.head].stok;
            s.head++;
          }
          if (s.weight > 0 && day >= s.nextRestock) {
            final qty = 20 + (s.weight * 25).round() + rnd.nextInt(30);
            final beli = _r100((_price(s.basePrice, yearIdx) * (0.72 + rnd.nextDouble() * 0.13)).round());
            final expDay = day + (s.shelfDays * (0.85 + rnd.nextDouble() * 0.5)).round();
            final bId = nextId('stok_batch');
            buf.batch.add({
              'id_batch': bId, 'id_produk': s.id, 'jumlah_stok': qty,
              'harga_beli_satuan': beli,
              'tanggal_masuk': date.toIso8601String(),
              'tanggal_exp': _d(start.add(Duration(days: expDay))),
            });
            s.queue.add(_B(bId, expDay, beli, qty));
            s.active += qty;
            restock.add((s, qty, beli));
            s.nextRestock = day + s.restockEvery + rnd.nextInt(7);
          }
        }

        // pembelian (dikelompokkan per supplier)
        int ri = 0;
        while (ri < restock.length) {
          final end = (ri + 1 + rnd.nextInt(3)).clamp(ri, restock.length);
          final pemId = nextId('pembelian');
          int total = 0;
          for (int k = ri; k < end; k++) {
            final (s, qty, beli) = restock[k];
            total += qty * beli;
            buf.pemD.add({
              'id_detail': nextId('detail_pembelian'), 'id_pembelian': pemId,
              'id_produk': s.id, 'qty': qty, 'harga_beli_satuan': beli, 'subtotal': qty * beli,
            });
          }
          buf.pem.add({
            'id_pembelian': pemId, 'id_user': adminIds[rnd.nextInt(adminIds.length)],
            'supplier': _suppliers[rnd.nextInt(_suppliers.length)],
            'total_beli': total,
            'tanggal': DateTime(date.year, date.month, date.day, 9 + rnd.nextInt(2), rnd.nextInt(60)).toIso8601String(),
          });
          ri = end;
        }

        // faktor ramai: tumbuh, weekend, gajian, Desember
        double factor = 0.62 + 0.5 * (day / totalDays);
        if (date.weekday == DateTime.saturday || date.weekday == DateTime.sunday) factor *= 1.35;
        if (date.day >= 25 || date.day <= 3) factor *= 1.25;
        if (date.month == 12) factor *= 1.35;
        if (date.month == 3 || date.month == 4) factor *= 1.15;
        final nTrxHari = (cfg.avgTrxPerDay * factor * (0.8 + rnd.nextDouble() * 0.4)).round();

        // log login harian
        buf.log.add({
          'id_log': nextId('log'), 'id_user': kasirIds[rnd.nextInt(kasirIds.length)],
          'aktivitas': 'Login pada ${_d(date)}',
          'waktu': DateTime(date.year, date.month, date.day, 7, rnd.nextInt(30)).toIso8601String(),
        });

        // transaksi
        for (int t = 0; t < nTrxHari; t++) {
          final trxId = nextId('transaksi');
          final no = 'TRX-$trxId';
          final hour = _pickHour(rnd);
          final tgl = DateTime(date.year, date.month, date.day, hour, rnd.nextInt(60));
          final userId = kasirIds[rnd.nextInt(kasirIds.length)];
          final nItems = rnd.nextDouble() < 0.55
              ? 1 + rnd.nextInt(3)
              : (rnd.nextDouble() < 0.67 ? 3 + rnd.nextInt(5) : 8 + rnd.nextInt(8));
          int total = 0;
          for (int it = 0; it < nItems; it++) {
            final s = pickProduct();
            if (s == null) continue;
            var need = rnd.nextDouble() < 0.70
                ? 1
                : (rnd.nextDouble() < 0.50 ? 2 : (rnd.nextDouble() < 0.67 ? 3 : 4 + rnd.nextInt(4)));
            if (need > s.active) need = s.active;
            if (need <= 0) continue;
            final price = _price(s.basePrice, yearIdx);
            while (need > 0 && s.head < s.queue.length) { // FEFO
              final b = s.queue[s.head];
              if (b.expDay <= day) {
                s.active -= b.stok;
                s.head++;
                continue;
              }
              final take = b.stok < need ? b.stok : need;
              b.stok -= take;
              s.active -= take;
              need -= take;
              total += price * take;
              buf.detail.add({
                'id_detail': nextId('detail_transaksi'), 'id_transaksi': trxId,
                'id_produk': s.id, 'id_batch': b.id, 'qty': take,
                'subtotal': price * take, 'harga_beli_satuan': b.hargaBeli,
              });
              nDetail++;
              if (b.stok == 0) s.head++;
            }
          }
          if (total <= 0) continue;
          final uang = _cash(total, rnd);
          buf.trx.add({
            'id_transaksi': trxId, 'no_transaksi': no, 'id_user': userId,
            'total_bayar': total, 'uang_diterima': uang, 'kembalian': uang - total,
            'tanggal': tgl.toIso8601String(),
          });
          nTrx++;
          if (trxId % 500 == 0) {
            buf.log.add({
              'id_log': nextId('log'), 'id_user': userId,
              'aktivitas': 'Transaksi $no sebesar ${_rp(total)}',
              'waktu': tgl.toIso8601String(),
            });
          }
        }

        // pengeluaran operasional
        final mul = pow(1.04, yearIdx).toDouble();
        if (date.day == 1) {
          addOut(date, 'Gaji Karyawan', 5200000, 800000, mul);
          addOut(date, 'Sewa Tempat', 4000000, 500000, mul);
          addOut(date, 'Listrik & Air', 650000, 250000, mul);
          addOut(date, 'Internet & Wifi', 350000, 100000, mul);
          if (rnd.nextDouble() < 0.6) addOut(date, 'Iuran RT/RW', 75000, 50000, mul);
        }
        if (rnd.nextDouble() < 0.4) addOut(date, 'Plastik & Kemasan', 60000, 80000, mul);
        if (rnd.nextDouble() < 0.2) addOut(date, 'Sampah & Kebersihan', 15000, 20000, mul);
        if (rnd.nextDouble() < 0.05) addOut(date, 'Perbaikan & Perawatan', 150000, 350000, mul);

        // flush mingguan + update progress
        if (day % 7 == 6 || day == totalDays - 1) {
          await flush();
          onProgress((day + 1) / totalDays,
              'Hari ${day + 1}/$totalDays · $nTrx transaksi · $nDetail item terjual');
          await Future.delayed(Duration.zero); // beri napas ke UI
        }
      }
      await flush();

      // ---------- 4. INDEX (opsional, untuk perbandingan) ----------
      if (createIndexes) {
        onProgress(1, 'Membuat index performa...');
        await _createIndexes(db);
      }

      // ---------- 5. LAPORAN ----------
      final counts = <String, int>{};
      for (final t in tables) {
        counts[t] = Sqflite.firstIntValue(await db.rawQuery('SELECT COUNT(*) FROM $t')) ?? 0;
      }
      await _pragma(db, 'PRAGMA wal_checkpoint(TRUNCATE)');
      await db.close();
      await DB.init(); // buka ulang koneksi DB aplikasi

      return {
        'counts': counts,
        'elapsed': sw.elapsed,
        'sizeBytes': File(dbPath).lengthSync(),
      };
    } catch (_) {
      try {
        await db.close();
      } catch (_) {}
      try {
        await DB.init();
      } catch (_) {}
      rethrow;
    }
  }

  static Future<void> _createIndexes(Database db) async {
    const idx = [
      'CREATE INDEX IF NOT EXISTS idx_trx_tanggal ON transaksi(tanggal)',
      'CREATE INDEX IF NOT EXISTS idx_trx_user ON transaksi(id_user)',
      'CREATE INDEX IF NOT EXISTS idx_detail_trx ON detail_transaksi(id_transaksi)',
      'CREATE INDEX IF NOT EXISTS idx_detail_produk ON detail_transaksi(id_produk)',
      'CREATE INDEX IF NOT EXISTS idx_batch_produk ON stok_batch(id_produk, tanggal_exp)',
      'CREATE INDEX IF NOT EXISTS idx_batch_stok ON stok_batch(id_produk, jumlah_stok)',
      'CREATE INDEX IF NOT EXISTS idx_batch_masuk ON stok_batch(tanggal_masuk)',
      'CREATE INDEX IF NOT EXISTS idx_pem_tanggal ON pembelian(tanggal)',
      'CREATE INDEX IF NOT EXISTS idx_log_user ON log(id_user)',
    ];
    for (final s in idx) {
      await db.execute(s);
    }
    await db.execute('ANALYZE');
  }

  static Future<void> addIndexesOnly() async {
    final db = await openDatabase(p.join(await getDatabasesPath(), 'kastra.db'));
    await _createIndexes(db);
    await db.close();
    await DB.init();
  }

  static Future<void> wipe() async {
    final db = await openDatabase(p.join(await getDatabasesPath(), 'kastra.db'));
    const tables = [
      'detail_transaksi', 'transaksi', 'detail_pembelian', 'pembelian',
      'stok_batch', 'produk', 'categories', 'pengeluaran', 'log', 'users', 'toko',
    ];
    await db.transaction((txn) async {
      for (final t in tables) {
        await txn.delete(t);
      }
    });
    await db.close();
    await DB.init();
  }
}

// ---------------- model simulasi internal ----------------
class _Sim {
  final String nama, kategori;
  final int basePrice, shelfDays, restockEvery;
  double weight;
  int nextRestock;
  int id = 0, head = 0, active = 0;
  bool inactive = false;
  final List<_B> queue = [];
  _Sim({
    required this.nama,
    required this.kategori,
    required this.basePrice,
    required this.shelfDays,
    required this.weight,
    required this.restockEvery,
    required this.nextRestock,
  });
}

class _B {
  final int id, expDay, hargaBeli;
  int stok;
  _B(this.id, this.expDay, this.hargaBeli, this.stok);
}

class _Buf {
  final trx = <Map<String, Object?>>[],
      detail = <Map<String, Object?>>[],
      batch = <Map<String, Object?>>[],
      pem = <Map<String, Object?>>[],
      pemD = <Map<String, Object?>>[],
      out = <Map<String, Object?>>[],
      log = <Map<String, Object?>>[];
  void clear() {
    trx.clear();
    detail.clear();
    batch.clear();
    pem.clear();
    pemD.clear();
    out.clear();
    log.clear();
  }
}

// ================================ UI ========================================

class BenchmarkPage extends StatefulWidget {
  const BenchmarkPage({super.key});
  @override
  State<BenchmarkPage> createState() => _BenchmarkPageState();
}

class _BenchmarkPageState extends State<BenchmarkPage> {
  int _sel = 1;
  bool _idx = false, _run = false;
  double _prog = 0;
  String _msg = '', _res = '';

  Future<void> _start() async {
    final cfg = kPresets[_sel];
    final ok = await confirm(context, 'Generate Data Benchmark?',
        'PERINGATAN: Seluruh data di perangkat ini akan DIHAPUS dan diganti data benchmark "${cfg.label}".\n\nGunakan emulator/device testing. Proses bisa memakan waktu beberapa menit.',
        okLabel: 'Ya, Generate', okColor: C.orange);
    if (ok != true || !mounted) return;
    setState(() {
      _run = true;
      _prog = 0;
      _msg = 'Menyiapkan...';
      _res = '';
    });
    try {
      final r = await BenchmarkSeeder.run(
        cfg: cfg,
        createIndexes: _idx,
        onProgress: (p, m) => setState(() {
          _prog = p;
          _msg = m;
        }),
      );
      await DB.clearSession();
      if (!mounted) return;
      final counts = r['counts'] as Map<String, int>;
      final mb = ((r['sizeBytes'] as int) / 1048576).toStringAsFixed(1);
      setState(() {
        _res = '✅ Selesai dalam ${r['elapsed']}\n📦 Ukuran DB: $mb MB\n\n'
            'Transaksi: ${counts['transaksi']}\n'
            'Detail: ${counts['detail_transaksi']}\n'
            'Produk: ${counts['produk']}\n'
            'Batch: ${counts['stok_batch']}\n'
            'Pembelian: ${counts['pembelian']}\n'
            'Pengeluaran: ${counts['pengeluaran']}\n'
            'Log: ${counts['log']}\n\n'
            '🔄 Hot restart aplikasi, lalu login:\n'
            'owner/owner123 · admin1-admin4/admin123 · kasir1-kasir11/kasir123';
      });
    } catch (e) {
      if (!mounted) return;
      setState(() => _res = '❌ Gagal: $e');
    }
    if (mounted) setState(() => _run = false);
  }

  Future<void> _addIdx() async {
    setState(() {
      _run = true;
      _msg = 'Menambahkan index...';
    });
    await BenchmarkSeeder.addIndexesOnly();
    if (!mounted) return;
    snack(context, 'Index ditambahkan + ANALYZE');
    setState(() => _run = false);
  }

  Future<void> _wipe() async {
    final ok = await confirm(context, 'Hapus Semua Data?', 'Seluruh data benchmark akan dihapus.', okLabel: 'Hapus');
    if (ok != true) return;
    await BenchmarkSeeder.wipe();
    await DB.clearSession();
    if (!mounted) return;
    snack(context, 'Semua data dihapus');
  }

  @override
  Widget build(BuildContext context) => Scaffold(
        appBar: AppBar(title: const Text('Benchmark Data Generator')),
        body: ListView(padding: const EdgeInsets.all(16), children: [
          const CardX(
            child: Text('⚠️ Hanya untuk device testing!\nSemua data aplikasi di perangkat ini akan diganti.',
                style: TextStyle(color: C.red, fontWeight: FontWeight.w700)),
          ),
          const SizedBox(height: 16),
          ...kPresets.asMap().entries.map((e) => Container(
                margin: const EdgeInsets.only(bottom: 8),
                child: CardX(
                  padding: EdgeInsets.zero,
                  child: RadioListTile<int>(
                    value: e.key,
                    groupValue: _sel,
                    onChanged: _run ? null : (v) => setState(() => _sel = v!),
                    title: Text(e.value.label, style: const TextStyle(fontWeight: FontWeight.w700)),
                    subtitle: Text('${e.value.skuTarget} SKU · ~${e.value.avgTrxPerDay} trx/hari'),
                  ),
                ),
              )),
          CheckboxListTile(
            value: _idx,
            onChanged: _run ? null : (v) => setState(() => _idx = v ?? false),
            title: const Text('Buat index performa (SQL)', style: TextStyle(fontSize: 13.5)),
            subtitle: const Text('Untuk perbandingan sebelum vs sesudah index', style: TextStyle(fontSize: 11.5)),
          ),
          const SizedBox(height: 12),
          SizedBox(
            height: 52,
            child: ElevatedButton(onPressed: _run ? null : _start, child: const Text('Generate Data Benchmark')),
          ),
          const SizedBox(height: 8),
          OutlinedButton(onPressed: _run ? null : _addIdx, child: const Text('Tambah Index Saja (tanpa regenerate)')),
          const SizedBox(height: 8),
          OutlinedButton(
            onPressed: _run ? null : _wipe,
            style: OutlinedButton.styleFrom(foregroundColor: C.red, side: const BorderSide(color: C.red)),
            child: const Text('Hapus Semua Data'),
          ),
          if (_run) ...[
            const SizedBox(height: 20),
            LinearProgressIndicator(value: _prog, color: C.primary, minHeight: 8, borderRadius: BorderRadius.circular(4)),
            const SizedBox(height: 10),
            Text(_msg, style: const TextStyle(fontSize: 12, color: C.sub), textAlign: TextAlign.center),
            const Text('Jangan tutup aplikasi / matikan layar.',
                style: TextStyle(fontSize: 10.5, color: C.orange), textAlign: TextAlign.center),
          ],
          if (_res.isNotEmpty) ...[
            const SizedBox(height: 20),
            CardX(child: Text(_res, style: const TextStyle(fontSize: 12.5, height: 1.6))),
          ],
        ]),
      );
}