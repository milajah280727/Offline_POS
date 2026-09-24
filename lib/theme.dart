import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:intl/intl.dart';

// ignore_for_file: deprecated_member_use

/// Design tokens — diselaraskan dengan halaman login.
class C {
  C._();
  static const primary = Color(0xFF5F85DA);
  static const primaryDark = Color(0xFF3F63B8);
  static const sky = Color(0xFF7EA2E8);
  static const ink = Color(0xFF0F172A);
  static const sub = Color(0xFF64748B);
  static const label = Color(0xFF334155);
  static const iconIdle = Color(0xFF94A3B8);
  static const border = Color(0xFFE2E8F0);
  static const fieldFill = Color(0xFFF8FAFC);
  static const fieldFocus = Color(0xFFF5F9FF);

  static const bg = Color(0xFFF8FAFC);
  static const red = Color(0xFFDC2626);
  static const redBg = Color(0xFFFEF2F2);
  static const redBorder = Color(0xFFFECACA);
  static const green = Color(0xFF16A34A);
  static const greenBg = Color(0xFFF0FDF4);
  static const orange = Color(0xFFD97706);
  static const orangeBg = Color(0xFFFFFBEB);
  static const teal = Color(0xFF0D9488);
  static const purple = Color(0xFF7C3AED);
  static const pink = Color(0xFFDB2777);
}

/// Gradient gelombang — dipakai header drawer & kartu laba rugi owner.
const waveGradient = LinearGradient(
  begin: Alignment.topLeft,
  end: Alignment.bottomRight,
  colors: [C.sky, C.primary, C.primaryDark],
);

final appTheme = ThemeData(
  useMaterial3: true,
  colorScheme: ColorScheme.fromSeed(seedColor: C.primary, primary: C.primary, surface: Colors.white),
  scaffoldBackgroundColor: C.bg,
  textTheme: GoogleFonts.plusJakartaSansTextTheme().apply(bodyColor: C.ink, displayColor: C.ink),
  appBarTheme: const AppBarTheme(
    backgroundColor: Colors.white,
    surfaceTintColor: Colors.transparent,
    scrolledUnderElevation: 0,
    centerTitle: true,
    iconTheme: IconThemeData(color: C.ink),
    titleTextStyle: TextStyle(color: C.ink, fontWeight: FontWeight.w800, fontSize: 16.5),
    shape: Border(bottom: BorderSide(color: C.border)),
  ),
  dividerTheme: const DividerThemeData(color: C.border, thickness: 1),
  inputDecorationTheme: InputDecorationTheme(
    filled: true,
    fillColor: const Color(0xFFF5F5F5),
    hintStyle: const TextStyle(fontSize: 14.5, fontWeight: FontWeight.w400, color: C.iconIdle),
    labelStyle: const TextStyle(fontSize: 14, fontWeight: FontWeight.w600, color: C.label),
    contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 15),
    enabledBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(12), borderSide: BorderSide.none),
    focusedBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(12), borderSide: BorderSide.none),
    border: OutlineInputBorder(borderRadius: BorderRadius.circular(12), borderSide: BorderSide.none),
  ),
  elevatedButtonTheme: ElevatedButtonThemeData(
    style: ElevatedButton.styleFrom(
      backgroundColor: C.primary,
      foregroundColor: Colors.white,
      minimumSize: const Size(0, 52),
      elevation: 0,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
      textStyle: const TextStyle(fontWeight: FontWeight.w700, fontSize: 15, letterSpacing: .2),
      disabledBackgroundColor: C.primary.withOpacity(.4),
    ),
  ),
  outlinedButtonTheme: OutlinedButtonThemeData(
    style: OutlinedButton.styleFrom(
      foregroundColor: C.label,
      side: const BorderSide(color: C.border),
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
      textStyle: const TextStyle(fontWeight: FontWeight.w600, fontSize: 12.5),
    ),
  ),
  textButtonTheme: TextButtonThemeData(
    style: TextButton.styleFrom(foregroundColor: C.primary, textStyle: const TextStyle(fontWeight: FontWeight.w700)),
  ),
  checkboxTheme: CheckboxThemeData(
    fillColor: WidgetStateProperty.resolveWith((s) => s.contains(WidgetState.selected) ? C.primary : null),
    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(6)),
    side: const BorderSide(color: C.border, width: 1.4),
  ),
  dialogTheme: DialogThemeData(
    backgroundColor: Colors.white,
    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
    titleTextStyle: const TextStyle(fontSize: 17, fontWeight: FontWeight.w800, color: C.ink),
    contentTextStyle: const TextStyle(fontSize: 14, color: C.sub, height: 1.5),
  ),
  snackBarTheme: SnackBarThemeData(
    behavior: SnackBarBehavior.floating,
    backgroundColor: C.ink,
    contentTextStyle: const TextStyle(color: Colors.white, fontWeight: FontWeight.w600, fontSize: 14),
    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
  ),
  floatingActionButtonTheme: FloatingActionButtonThemeData(
    backgroundColor: C.primary,
    foregroundColor: Colors.white,
    elevation: 2,
    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
  ),
);

String fmt(dynamic n) =>
    (n ?? 0).toString().replaceAllMapped(RegExp(r'(\d{1,3})(?=(\d{3})+(?!\d))'), (m) => '${m[1]}.');
String rp(dynamic n) => 'Rp ${fmt(n)}';

String fdate(dynamic s, [String p = 'dd MMM yyyy, HH:mm']) {
  try {
    return DateFormat(p).format(DateTime.parse(s.toString()).toLocal());
  } catch (_) {
    return s.toString();
  }
}

DateTime dayOnly(dynamic d) {
  final dt = d is DateTime ? d : DateTime.parse(d.toString());
  return DateTime(dt.year, dt.month, dt.day);
}

String initialOf(String? s) => (s == null || s.isEmpty) ? 'U' : s.substring(0, 1).toUpperCase();