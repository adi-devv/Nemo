import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

void main() {
  runApp(const MyApp());
}

class MyApp extends StatelessWidget {
  const MyApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'Hisaab',
      debugShowCheckedModeBanner: false,
      theme: ThemeData(
        brightness: Brightness.dark,
        scaffoldBackgroundColor: const Color(0xFF0A0A0A),
        colorScheme: const ColorScheme.dark(
          surface: Color(0xFF1C1C1E),
          primary: Colors.white,
        ),
      ),
      home: const HomeScreen(),
    );
  }
}

// ── Repo ──────────────────────────────────────────────────────────

class Repo {
  static const _ch = MethodChannel('com.hisaab.app/db');

  static Future<List<Map<String, dynamic>>> txns({String? from, String? to}) async {
    final r = await _ch.invokeMethod<List>('getTransactions', {'from': from, 'to': to});
    return r?.map((e) => Map<String, dynamic>.from(e as Map)).toList() ?? [];
  }

  static Future<Map<String, double>> totals({String? from, String? to}) async {
    final r = await _ch.invokeMethod<Map>('getCategoryTotals', {'from': from, 'to': to});
    return r?.map((k, v) => MapEntry(k.toString(), (v as num).toDouble())) ?? {};
  }
}

// ── Home Screen ───────────────────────────────────────────────────

class HomeScreen extends StatefulWidget {
  const HomeScreen({super.key});
  @override
  State<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends State<HomeScreen> with WidgetsBindingObserver {
  List<Map<String, dynamic>> _txns = [];
  Map<String, double> _totals = {};
  String _range = 'This Month';
  bool _loading = true;

  final _ranges = ['This Week', 'This Month', 'Last Month', 'All Time'];

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _load();
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed) _load();
  }

  Future<void> _load() async {
    setState(() => _loading = true);
    final now = DateTime.now();
    String? from, to;

    switch (_range) {
      case 'This Week':
        from = DateTime(now.year, now.month, now.day - now.weekday + 1)
            .millisecondsSinceEpoch.toString();
      case 'This Month':
        from = DateTime(now.year, now.month, 1).millisecondsSinceEpoch.toString();
      case 'Last Month':
        from = DateTime(now.year, now.month - 1, 1).millisecondsSinceEpoch.toString();
        to   = DateTime(now.year, now.month, 1).millisecondsSinceEpoch.toString();
    }

    try {
      final t = await Repo.txns(from: from, to: to);
      final c = await Repo.totals(from: from, to: to);
      setState(() { _txns = t; _totals = c; _loading = false; });
    } catch (_) {
      setState(() => _loading = false);
    }
  }

  double get _spent => _txns
      .where((t) => t['type'] == 'debit')
      .fold(0.0, (s, t) => s + (t['amount'] as num).toDouble());

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFF0A0A0A),
      body: SafeArea(
        child: RefreshIndicator(
          onRefresh: _load,
          color: Colors.white,
          backgroundColor: const Color(0xFF1C1C1E),
          child: CustomScrollView(
            slivers: [
              // Header
              SliverToBoxAdapter(
                child: Padding(
                  padding: const EdgeInsets.fromLTRB(24, 32, 24, 0),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text('HISAAB',
                          style: TextStyle(
                              fontSize: 11,
                              letterSpacing: 4,
                              color: Colors.white.withOpacity(0.25),
                              fontWeight: FontWeight.w600)),
                      const SizedBox(height: 28),
                      Text('₹${_fmt(_spent)}',
                          style: const TextStyle(
                              fontSize: 56,
                              fontWeight: FontWeight.w200,
                              color: Colors.white,
                              letterSpacing: -2)),
                      const SizedBox(height: 4),
                      Text('spent · $_range',
                          style: TextStyle(
                              fontSize: 14,
                              color: Colors.white.withOpacity(0.3))),
                    ],
                  ),
                ),
              ),

              // Range pills
              SliverToBoxAdapter(
                child: Padding(
                  padding: const EdgeInsets.fromLTRB(24, 24, 24, 0),
                  child: SingleChildScrollView(
                    scrollDirection: Axis.horizontal,
                    child: Row(
                      children: _ranges.map((r) {
                        final sel = r == _range;
                        return GestureDetector(
                          onTap: () { setState(() => _range = r); _load(); },
                          child: AnimatedContainer(
                            duration: const Duration(milliseconds: 180),
                            margin: const EdgeInsets.only(right: 8),
                            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
                            decoration: BoxDecoration(
                              color: sel ? Colors.white : const Color(0xFF1C1C1E),
                              borderRadius: BorderRadius.circular(20),
                            ),
                            child: Text(r,
                                style: TextStyle(
                                    fontSize: 13,
                                    color: sel ? Colors.black : Colors.white.withOpacity(0.4),
                                    fontWeight: sel ? FontWeight.w600 : FontWeight.normal)),
                          ),
                        );
                      }).toList(),
                    ),
                  ),
                ),
              ),

              if (_loading)
                const SliverFillRemaining(
                  child: Center(
                      child: CircularProgressIndicator(color: Colors.white24, strokeWidth: 1)),
                )
              else if (_txns.isEmpty)
                SliverFillRemaining(
                  child: Center(
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Text('₹',
                            style: TextStyle(
                                fontSize: 48, color: Colors.white.withOpacity(0.07))),
                        const SizedBox(height: 12),
                        Text('No transactions yet',
                            style: TextStyle(
                                color: Colors.white.withOpacity(0.2), fontSize: 15)),
                        const SizedBox(height: 4),
                        Text('Make a UPI payment to get started',
                            style: TextStyle(
                                color: Colors.white.withOpacity(0.1), fontSize: 12)),
                      ],
                    ),
                  ),
                )
              else ...[
                  // Categories
                  if (_totals.isNotEmpty)
                    SliverToBoxAdapter(
                      child: Padding(
                        padding: const EdgeInsets.fromLTRB(24, 36, 24, 0),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text('BY CATEGORY',
                                style: TextStyle(
                                    fontSize: 11,
                                    letterSpacing: 2,
                                    color: Colors.white.withOpacity(0.25),
                                    fontWeight: FontWeight.w600)),
                            const SizedBox(height: 20),
                            ..._totals.entries.map((e) =>
                                _CatRow(category: e.key, amount: e.value, total: _spent)),
                          ],
                        ),
                      ),
                    ),

                  // Recent
                  SliverToBoxAdapter(
                    child: Padding(
                      padding: const EdgeInsets.fromLTRB(24, 36, 24, 16),
                      child: Text('RECENT',
                          style: TextStyle(
                              fontSize: 11,
                              letterSpacing: 2,
                              color: Colors.white.withOpacity(0.25),
                              fontWeight: FontWeight.w600)),
                    ),
                  ),
                  SliverList(
                    delegate: SliverChildBuilderDelegate(
                          (_, i) => _TxnTile(txn: _txns[i]),
                      childCount: _txns.length,
                    ),
                  ),
                  const SliverToBoxAdapter(child: SizedBox(height: 48)),
                ],
            ],
          ),
        ),
      ),
    );
  }
}

// ── Category row ──────────────────────────────────────────────────

class _CatRow extends StatelessWidget {
  final String category;
  final double amount;
  final double total;
  const _CatRow({required this.category, required this.amount, required this.total});

  @override
  Widget build(BuildContext context) {
    final pct = total > 0 ? (amount / total).clamp(0.0, 1.0) : 0.0;
    return Padding(
      padding: const EdgeInsets.only(bottom: 20),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(children: [
            Expanded(
              child: Text(category,
                  style: const TextStyle(
                      color: Colors.white, fontSize: 14, fontWeight: FontWeight.w400)),
            ),
            Text('₹${_fmt(amount)}',
                style: TextStyle(
                    color: Colors.white.withOpacity(0.6),
                    fontSize: 14,
                    fontWeight: FontWeight.w500)),
          ]),
          const SizedBox(height: 8),
          ClipRRect(
            borderRadius: BorderRadius.circular(2),
            child: LinearProgressIndicator(
              value: pct,
              minHeight: 2,
              backgroundColor: Colors.white.withOpacity(0.06),
              valueColor: const AlwaysStoppedAnimation<Color>(Colors.white),
            ),
          ),
        ],
      ),
    );
  }
}

// ── Transaction tile ──────────────────────────────────────────────

class _TxnTile extends StatelessWidget {
  final Map<String, dynamic> txn;
  const _TxnTile({required this.txn});

  @override
  Widget build(BuildContext context) {
    final isDebit = txn['type'] == 'debit';
    final amount  = (txn['amount'] as num).toDouble();
    final ts      = txn['timestamp'] as int;
    final date    = DateTime.fromMillisecondsSinceEpoch(ts);
    final cat     = (txn['category'] as String? ?? 'M');

    return Padding(
      padding: const EdgeInsets.fromLTRB(24, 0, 24, 0),
      child: Column(
        children: [
          Padding(
            padding: const EdgeInsets.symmetric(vertical: 14),
            child: Row(children: [
              // Initial avatar
              Container(
                width: 40,
                height: 40,
                decoration: BoxDecoration(
                  color: Colors.white.withOpacity(0.06),
                  borderRadius: BorderRadius.circular(12),
                ),
                child: Center(
                  child: Text(
                    cat.substring(0, 1).toUpperCase(),
                    style: TextStyle(
                      color: Colors.white.withOpacity(0.5),
                      fontSize: 14,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                ),
              ),
              const SizedBox(width: 14),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(txn['merchant_name'],
                        style: const TextStyle(
                            color: Colors.white, fontSize: 15, fontWeight: FontWeight.w400)),
                    const SizedBox(height: 3),
                    Text(_fmtDate(date),
                        style: TextStyle(
                            color: Colors.white.withOpacity(0.22), fontSize: 12)),
                  ],
                ),
              ),
              Text(
                '${isDebit ? '-' : '+'}₹${_fmt(amount)}',
                style: TextStyle(
                  color: isDebit
                      ? Colors.white.withOpacity(0.75)
                      : const Color(0xFF30D158),
                  fontSize: 15,
                  fontWeight: FontWeight.w500,
                ),
              ),
            ]),
          ),
          Divider(height: 1, color: Colors.white.withOpacity(0.04), indent: 54),
        ],
      ),
    );
  }
}

// ── Helpers ───────────────────────────────────────────────────────

String _fmt(double a) {
  if (a >= 100000) return '${(a / 100000).toStringAsFixed(1)}L';
  if (a >= 1000)   return '${(a / 1000).toStringAsFixed(1)}K';
  return a.toStringAsFixed(0);
}

String _fmtDate(DateTime d) {
  final now = DateTime.now();
  if (d.day == now.day && d.month == now.month && d.year == now.year) {
    final h  = d.hour == 0 ? 12 : d.hour > 12 ? d.hour - 12 : d.hour;
    final m  = d.minute.toString().padLeft(2, '0');
    final ap = d.hour >= 12 ? 'PM' : 'AM';
    return 'Today $h:$m $ap';
  }
  const mo = ['Jan','Feb','Mar','Apr','May','Jun','Jul','Aug','Sep','Oct','Nov','Dec'];
  return '${d.day} ${mo[d.month - 1]}';
}