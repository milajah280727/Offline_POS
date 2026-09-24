import 'package:flutter/material.dart';
import 'package:kastra/services.dart';
import 'package:kastra/theme.dart';
import 'package:kastra/widgets.dart';

// ignore_for_file: deprecated_member_use

class LogPage extends StatefulWidget {
  final int userId;
  const LogPage({super.key, required this.userId});

  @override
  State<LogPage> createState() => _LogPageState();
}

class _LogPageState extends State<LogPage> {
  List<Map<String, dynamic>> _logs = [];
  bool _load = true;

  @override
  void initState() {
    super.initState();
    _fetch();
  }

  Future<void> _fetch() async {
    try {
      final d = await DB.logs;
      if (mounted) {
        setState(() {
          _logs = d;
          _load = false;
        });
      }
    } catch (e) {
      debugPrint('$e');
      if (mounted) setState(() => _load = false);
    }
  }

  @override
  Widget build(BuildContext context) => Scaffold(
        appBar: AppBar(title: const Text('Log Aktivitas'), actions: [AccountButton(userId: widget.userId)],),
        drawer: AppDrawer(userId: widget.userId, role: 'owner'),
        body: _load
            ? const Center(child: CircularProgressIndicator(color: C.primary))
            : _logs.isEmpty
                ? const Center(child: Text('Belum ada aktivitas', style: TextStyle(color: C.sub)))
                : RefreshIndicator(
                    color: C.primary,
                    onRefresh: _fetch,
                    child: ListView.builder(
                      physics: const AlwaysScrollableScrollPhysics(),
                      padding: const EdgeInsets.all(16),
                      itemCount: _logs.length,
                      itemBuilder: (c, i) {
                        final l = _logs[i];
                        final nama = ((l['users'] as Map?)?['nama_lengkap']) ?? '-';
                        return Container(
                          margin: const EdgeInsets.only(bottom: 10),
                          padding: const EdgeInsets.all(14),
                          decoration: BoxDecoration(color: Colors.white, borderRadius: BorderRadius.circular(16), border: Border.all(color: C.border)),
                          child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
                            Container(
                              width: 36,
                              height: 36,
                              decoration: BoxDecoration(color: C.primary.withOpacity(.09), borderRadius: BorderRadius.circular(11)),
                              child: Center(
                                child: Text(initialOf(nama.toString()),
                                    style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w800, color: C.primary)),
                              ),
                            ),
                            const SizedBox(width: 12),
                            Expanded(
                              child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                                Row(mainAxisAlignment: MainAxisAlignment.spaceBetween, children: [
                                  Expanded(
                                    child: Text(nama.toString(),
                                        style: const TextStyle(fontSize: 12.5, fontWeight: FontWeight.w800, color: C.ink),
                                        overflow: TextOverflow.ellipsis),
                                  ),
                                  Text(fdate(l['waktu']), style: const TextStyle(fontSize: 10, color: C.iconIdle)),
                                ]),
                                const SizedBox(height: 5),
                                Text(l['aktivitas'] ?? '-',
                                    style: const TextStyle(fontSize: 12.5, color: C.label, height: 1.5)),
                              ]),
                            ),
                          ]),
                        );
                      },
                    ),
                  ),
      );
}