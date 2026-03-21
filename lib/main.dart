import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'dart:math' as math;

void main() => runApp(const MyApp());

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
      home: const PermissionScreen(),
    );
  }
}

// ══════════════════════════════════════════════════════════════════
// PERMISSION SCREEN
// ══════════════════════════════════════════════════════════════════

class PermissionScreen extends StatefulWidget {
  const PermissionScreen({super.key});
  @override
  State<PermissionScreen> createState() => _PermissionScreenState();
}

class _PermissionScreenState extends State<PermissionScreen>
    with WidgetsBindingObserver {
  static const _ch = MethodChannel('com.hisaab.app/permissions');
  bool _smsGranted = false, _overlayGranted = false;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _checkAll();
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed) _checkAll();
  }

  Future<void> _checkAll() async {
    try {
      final sms     = await _ch.invokeMethod<bool>('checkSms')     ?? false;
      final overlay = await _ch.invokeMethod<bool>('checkOverlay') ?? false;
      setState(() { _smsGranted = sms; _overlayGranted = overlay; });
      if (sms && overlay) _goHome();
    } catch (_) {}
  }

  void _goHome() {
    Navigator.of(context).pushReplacement(PageRouteBuilder(
      pageBuilder: (_, __, ___) => const RootScreen(),
      transitionsBuilder: (_, anim, __, child) =>
          FadeTransition(opacity: anim, child: child),
      transitionDuration: const Duration(milliseconds: 400),
    ));
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFF0A0A0A),
      body: SafeArea(
        child: Padding(
          padding: const EdgeInsets.fromLTRB(28, 48, 28, 40),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Text('Hisaab',
                  style: TextStyle(fontSize: 32, fontWeight: FontWeight.w300,
                      color: Colors.white, letterSpacing: -1)),
              const SizedBox(height: 8),
              Text('needs two permissions to work',
                  style: TextStyle(fontSize: 15,
                      color: Colors.white.withOpacity(0.35))),
              const SizedBox(height: 56),
              _PermCard(
                step: '1', title: 'Read SMS',
                desc: 'To detect UPI payments automatically — even when the app is closed.',
                granted: _smsGranted, locked: false,
                buttonLabel: 'Allow SMS',
                onTap: _smsGranted ? null : () async {
                  await _ch.invokeMethod('requestSms');
                  await _checkAll();
                },
              ),
              const SizedBox(height: 16),
              _PermCard(
                step: '2', title: 'Display over other apps',
                desc: 'To show a small popup when a payment is detected — like Truecaller.',
                granted: _overlayGranted, locked: !_smsGranted,
                buttonLabel: 'Open Settings →',
                onTap: (!_smsGranted || _overlayGranted) ? null : () async {
                  await _ch.invokeMethod('requestOverlay');
                },
              ),
              const Spacer(),
              if (_smsGranted && !_overlayGranted)
                Container(
                  padding: const EdgeInsets.all(18),
                  decoration: BoxDecoration(
                    color: const Color(0xFF1C1C1E),
                    borderRadius: BorderRadius.circular(14),
                  ),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text('How to allow',
                          style: TextStyle(color: Colors.white.withOpacity(0.7),
                              fontSize: 13, fontWeight: FontWeight.w600)),
                      const SizedBox(height: 10),
                      ...[
                        'Tap "Open Settings" above',
                        'Find Hisaab in the list',
                        'Turn on "Allow display over other apps"',
                        'Come back here',
                      ].asMap().entries.map((e) => Padding(
                        padding: const EdgeInsets.only(bottom: 6),
                        child: Row(children: [
                          Text('${e.key + 1}.  ',
                              style: TextStyle(color: Colors.white.withOpacity(0.35),
                                  fontSize: 12, fontWeight: FontWeight.w600)),
                          Text(e.value,
                              style: TextStyle(color: Colors.white.withOpacity(0.35),
                                  fontSize: 12)),
                        ]),
                      )),
                    ],
                  ),
                ),
              const SizedBox(height: 20),
              Center(
                child: Text('Your data never leaves your phone.',
                    style: TextStyle(color: Colors.white.withOpacity(0.15),
                        fontSize: 12)),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _PermCard extends StatelessWidget {
  final String step, title, desc, buttonLabel;
  final bool granted, locked;
  final VoidCallback? onTap;
  const _PermCard({required this.step, required this.title, required this.desc,
    required this.granted, required this.locked,
    required this.buttonLabel, required this.onTap});

  @override
  Widget build(BuildContext context) {
    return AnimatedContainer(
      duration: const Duration(milliseconds: 300),
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        color: granted ? const Color(0xFF1A2E1A) : const Color(0xFF1C1C1E),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(
          color: granted ? const Color(0xFF30D158).withOpacity(0.25)
              : Colors.white.withOpacity(0.06),
        ),
      ),
      child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
        AnimatedSwitcher(
          duration: const Duration(milliseconds: 300),
          child: granted
              ? Container(key: const ValueKey('check'), width: 32, height: 32,
              decoration: BoxDecoration(
                  color: const Color(0xFF30D158).withOpacity(0.12),
                  shape: BoxShape.circle),
              child: const Icon(Icons.check, color: Color(0xFF30D158), size: 16))
              : Container(key: const ValueKey('num'), width: 32, height: 32,
              decoration: BoxDecoration(
                  color: Colors.white.withOpacity(locked ? 0.04 : 0.08),
                  shape: BoxShape.circle),
              child: Center(child: Text(step, style: TextStyle(
                  color: Colors.white.withOpacity(locked ? 0.2 : 0.6),
                  fontSize: 13, fontWeight: FontWeight.w600)))),
        ),
        const SizedBox(width: 14),
        Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Text(title, style: TextStyle(
              color: Colors.white.withOpacity(locked ? 0.3 : 1.0),
              fontSize: 15, fontWeight: FontWeight.w500)),
          const SizedBox(height: 5),
          Text(desc, style: TextStyle(
              color: Colors.white.withOpacity(locked ? 0.15 : 0.38),
              fontSize: 13, height: 1.45)),
          if (granted) ...[
            const SizedBox(height: 8),
            Text('Granted', style: TextStyle(
                color: const Color(0xFF30D158).withOpacity(0.6), fontSize: 12)),
          ] else if (!locked) ...[
            const SizedBox(height: 14),
            GestureDetector(onTap: onTap,
                child: Container(
                  padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 9),
                  decoration: BoxDecoration(color: Colors.white,
                      borderRadius: BorderRadius.circular(20)),
                  child: Text(buttonLabel, style: const TextStyle(
                      color: Colors.black, fontSize: 13, fontWeight: FontWeight.w600)),
                )),
          ],
        ])),
      ]),
    );
  }
}

// ══════════════════════════════════════════════════════════════════
// ROOT SCREEN (bottom nav)
// ══════════════════════════════════════════════════════════════════

class RootScreen extends StatefulWidget {
  const RootScreen({super.key});
  @override
  State<RootScreen> createState() => _RootScreenState();
}

class _RootScreenState extends State<RootScreen> {
  int _tab = 0;

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFF0A0A0A),
      body: IndexedStack(
        index: _tab,
        children: const [HomeScreen(), AnalyticsScreen()],
      ),
      bottomNavigationBar: Container(
        decoration: BoxDecoration(
          border: Border(top: BorderSide(color: Colors.white.withOpacity(0.06))),
        ),
        child: BottomNavigationBar(
          currentIndex: _tab,
          onTap: (i) => setState(() => _tab = i),
          backgroundColor: const Color(0xFF0A0A0A),
          selectedItemColor: Colors.white,
          unselectedItemColor: Colors.white.withOpacity(0.3),
          selectedFontSize: 11,
          unselectedFontSize: 11,
          selectedLabelStyle: const TextStyle(letterSpacing: 0.5),
          unselectedLabelStyle: const TextStyle(letterSpacing: 0.5),
          items: const [
            BottomNavigationBarItem(
              icon: Padding(padding: EdgeInsets.only(bottom: 4),
                  child: Icon(Icons.receipt_long_outlined, size: 22)),
              activeIcon: Padding(padding: EdgeInsets.only(bottom: 4),
                  child: Icon(Icons.receipt_long, size: 22)),
              label: 'Transactions',
            ),
            BottomNavigationBarItem(
              icon: Padding(padding: EdgeInsets.only(bottom: 4),
                  child: Icon(Icons.bar_chart_outlined, size: 22)),
              activeIcon: Padding(padding: EdgeInsets.only(bottom: 4),
                  child: Icon(Icons.bar_chart, size: 22)),
              label: 'Analytics',
            ),
          ],
        ),
      ),
    );
  }
}

// ══════════════════════════════════════════════════════════════════
// REPO
// ══════════════════════════════════════════════════════════════════

class Repo {
  static const _ch = MethodChannel('com.hisaab.app/db');

  static Future<List<Map<String, dynamic>>> txns({
    String? from, String? to, String? category,
  }) async {
    final r = await _ch.invokeMethod<List>('getTransactions',
        {'from': from, 'to': to, 'category': category});
    return r?.map((e) => Map<String, dynamic>.from(e as Map)).toList() ?? [];
  }

  static Future<Map<String, double>> totals({String? from, String? to}) async {
    final r = await _ch.invokeMethod<Map>('getCategoryTotals', {'from': from, 'to': to});
    return r?.map((k, v) => MapEntry(k.toString(), (v as num).toDouble())) ?? {};
  }
}

// ══════════════════════════════════════════════════════════════════
// HOME SCREEN
// ══════════════════════════════════════════════════════════════════

class HomeScreen extends StatefulWidget {
  const HomeScreen({super.key});
  @override
  State<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends State<HomeScreen> with WidgetsBindingObserver {
  List<Map<String, dynamic>> _txns   = [];
  Map<String, double>        _totals = {};
  String  _range            = 'This Month';
  String? _selectedCategory;
  int?    _expandedTxnId;
  bool    _loading          = true;
  bool    _showPie          = true;

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

  (String?, String?) get _dateRange {
    final now = DateTime.now();
    return switch (_range) {
      'This Week'  => (DateTime(now.year, now.month, now.day - now.weekday + 1)
          .millisecondsSinceEpoch.toString(), null),
      'This Month' => (DateTime(now.year, now.month, 1)
          .millisecondsSinceEpoch.toString(), null),
      'Last Month' => (
      DateTime(now.year, now.month - 1, 1).millisecondsSinceEpoch.toString(),
      DateTime(now.year, now.month, 1).millisecondsSinceEpoch.toString()),
      _ => (null, null),
    };
  }

  Future<void> _load() async {
    setState(() => _loading = true);
    final (from, to) = _dateRange;
    try {
      final t = await Repo.txns(from: from, to: to, category: _selectedCategory);
      final c = await Repo.totals(from: from, to: to);
      setState(() { _txns = t; _totals = c; _loading = false; });
    } catch (_) {
      setState(() => _loading = false);
    }
  }

  Future<void> _loadTxns() async {
    final (from, to) = _dateRange;
    try {
      final t = await Repo.txns(from: from, to: to, category: _selectedCategory);
      setState(() { _txns = t; });
    } catch (_) {}
  }

  void _toggleCategory(String cat) {
    setState(() {
      _selectedCategory = _selectedCategory == cat ? null : cat;
      _expandedTxnId    = null;
    });
    _loadTxns(); // only reload transactions, not totals
  }

  void _toggleTxn(int id) {
    setState(() => _expandedTxnId = _expandedTxnId == id ? null : id);
  }

  double get _spent => _txns
      .where((t) => t['type'] == 'debit')
      .fold(0.0, (s, t) => s + (t['amount'] as num).toDouble());

  @override
  Widget build(BuildContext context) {
    final total = _totals.values.fold(0.0, (a, b) => a + b);

    return Scaffold(
      backgroundColor: const Color(0xFF0A0A0A),
      body: SafeArea(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [

            // ── Fixed header ──
            Padding(
              padding: const EdgeInsets.fromLTRB(24, 32, 24, 0),
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.center,
                children: [
                  Text('HISAAB', style: TextStyle(fontSize: 11, letterSpacing: 4,
                      color: Colors.white.withOpacity(0.25),
                      fontWeight: FontWeight.w600)),
                  const Spacer(),
                  GestureDetector(
                    onTap: () => setState(() => _showPie = !_showPie),
                    child: Container(
                      width: 32, height: 32,
                      margin: const EdgeInsets.only(right: 8),
                      decoration: BoxDecoration(
                        border: Border.all(color: Colors.white.withOpacity(0.12)),
                        borderRadius: BorderRadius.circular(10),
                      ),
                      child: Icon(
                        _showPie ? Icons.bar_chart : Icons.pie_chart_outline,
                        size: 15,
                        color: Colors.white.withOpacity(0.4),
                      ),
                    ),
                  ),
                  GestureDetector(
                    onTap: () => _showRangePicker(context),
                    child: Container(
                      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 7),
                      decoration: BoxDecoration(
                        border: Border.all(color: Colors.white.withOpacity(0.12)),
                        borderRadius: BorderRadius.circular(20),
                      ),
                      child: Row(mainAxisSize: MainAxisSize.min, children: [
                        Text(_range, style: TextStyle(fontSize: 12,
                            color: Colors.white.withOpacity(0.5), letterSpacing: 0.2)),
                        const SizedBox(width: 4),
                        Icon(Icons.expand_more, size: 14,
                            color: Colors.white.withOpacity(0.3)),
                      ]),
                    ),
                  ),
                ],
              ),
            ),

            // ── Total amount ──
            if (!_loading && _totals.isNotEmpty)
              Padding(
                padding: const EdgeInsets.fromLTRB(24, 20, 24, 0),
                child: Text('₹${_fmt(_spent)}',
                    style: const TextStyle(fontSize: 40,
                        fontWeight: FontWeight.w200,
                        color: Colors.white, letterSpacing: -1.5)),
              ),

            // ── Fixed chart (pie or bars) ──
            if (!_loading)
              Padding(
                padding: const EdgeInsets.fromLTRB(24, 12, 24, 0),
                child: _showPie
                    ? _totals.isNotEmpty
                    ? _PieSection(
                  cats: _totals,
                  total: total,
                  selected: _selectedCategory,
                  onSelect: _toggleCategory,
                )
                    : _EmptyDonut()
                    : _totals.isNotEmpty
                    ? _CatBars(
                  cats: _totals,
                  total: total,
                  selected: _selectedCategory,
                  onSelect: _toggleCategory,
                )
                    : const SizedBox.shrink(),
              ),

            // ── Scrollable transactions ──
            Expanded(
              child: _loading
                  ? const Center(child: CircularProgressIndicator(
                  color: Colors.white24, strokeWidth: 1))
                  : RefreshIndicator(
                onRefresh: _load,
                color: Colors.white,
                backgroundColor: const Color(0xFF1C1C1E),
                child: _txns.isEmpty
                    ? Center(child: Text('No transactions',
                    style: TextStyle(color: Colors.white.withOpacity(0.2),
                        fontSize: 15)))
                    : ListView.builder(
                  padding: const EdgeInsets.only(top: 24, bottom: 48),
                  itemCount: _txns.length + 1,
                  itemBuilder: (_, i) {
                    if (i == 0) {
                      return Padding(
                        padding: const EdgeInsets.fromLTRB(24, 0, 24, 16),
                        child: Text('RECENT', style: TextStyle(
                            fontSize: 11, letterSpacing: 2,
                            color: Colors.white.withOpacity(0.2),
                            fontWeight: FontWeight.w600)),
                      );
                    }
                    final txn = _txns[i - 1];
                    final id  = txn['id'] as int;
                    return _TxnTile(
                      txn: txn, expanded: _expandedTxnId == id,
                      onTap: () => _toggleTxn(id),
                    );
                  },
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  void _showRangePicker(BuildContext context) {
    showModalBottomSheet(
      context: context,
      backgroundColor: const Color(0xFF1C1C1E),
      shape: const RoundedRectangleBorder(
          borderRadius: BorderRadius.vertical(top: Radius.circular(20))),
      builder: (_) => Padding(
        padding: const EdgeInsets.fromLTRB(24, 20, 24, 40),
        child: Column(mainAxisSize: MainAxisSize.min, children: [
          Container(width: 36, height: 4,
              decoration: BoxDecoration(color: Colors.white24,
                  borderRadius: BorderRadius.circular(2))),
          const SizedBox(height: 20),
          ..._ranges.map((r) => GestureDetector(
            onTap: () { setState(() => _range = r); Navigator.pop(context); _load(); },
            child: Container(
              width: double.infinity,
              padding: const EdgeInsets.symmetric(vertical: 16),
              decoration: BoxDecoration(
                  border: Border(bottom: BorderSide(
                      color: Colors.white.withOpacity(0.06)))),
              child: Row(children: [
                Expanded(child: Text(r, style: TextStyle(
                    color: r == _range ? Colors.white : Colors.white.withOpacity(0.45),
                    fontSize: 16,
                    fontWeight: r == _range ? FontWeight.w500 : FontWeight.normal))),
                if (r == _range) const Icon(Icons.check, color: Colors.white, size: 16),
              ]),
            ),
          )),
        ]),
      ),
    );
  }
}

// ══════════════════════════════════════════════════════════════════
// ANALYTICS SCREEN
// ══════════════════════════════════════════════════════════════════

class AnalyticsScreen extends StatefulWidget {
  const AnalyticsScreen({super.key});
  @override
  State<AnalyticsScreen> createState() => _AnalyticsScreenState();
}

class _AnalyticsScreenState extends State<AnalyticsScreen>
    with WidgetsBindingObserver {
  bool _loading = true;
  // options: 'current' | '3' | '6' | '12'
  String _view = 'current';

  List<_MonthData> _months       = []; // for multi-month views
  List<_WeekData>  _weeks        = []; // for current-month weekly view
  int              _monthsInData = 0;  // how many months have data
  final Set<String> _selectedLines = {'__total__'};
  Set<String> _allCategories = {};

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
    try {
      final now     = DateTime.now();
      final allCats = <String>{};

      // Always load up to 12 months to know how many have data
      final allMonths = <_MonthData>[];
      for (var i = 11; i >= 0; i--) {
        final rawM = now.month - i;
        final y    = rawM <= 0 ? now.year - 1 : now.year;
        final m    = rawM <= 0 ? rawM + 12 : rawM;
        final from = DateTime(y, m, 1).millisecondsSinceEpoch.toString();
        final to   = DateTime(y, m + 1, 1).millisecondsSinceEpoch.toString();
        final cats = await Repo.totals(from: from, to: to);
        allCats.addAll(cats.keys);
        const mo = ['Jan','Feb','Mar','Apr','May','Jun',
          'Jul','Aug','Sep','Oct','Nov','Dec'];
        allMonths.add(_MonthData(label: mo[m - 1], cats: cats));
      }
      final monthsWithData = allMonths.where((m) => m.total > 0).length;

      // Weekly data for current month
      final monthFrom = DateTime(now.year, now.month, 1).millisecondsSinceEpoch.toString();
      final monthTxns = await Repo.txns(from: monthFrom);
      // Group into weeks: week 1 = days 1-7, week 2 = 8-14, week 3 = 15-21, week 4 = 22+
      final weekMap = <int, Map<String, double>>{1:{}, 2:{}, 3:{}, 4:{}};
      for (final t in monthTxns) {
        if (t['type'] != 'debit') continue;
        final day = DateTime.fromMillisecondsSinceEpoch(t['timestamp'] as int).day;
        final wk  = day <= 7 ? 1 : day <= 14 ? 2 : day <= 21 ? 3 : 4;
        final cat = t['category'] as String;
        final amt = (t['amount'] as num).toDouble();
        weekMap[wk]![cat] = (weekMap[wk]![cat] ?? 0) + amt;
      }
      final weeks = [
        _WeekData(label: 'W1', cats: weekMap[1]!),
        _WeekData(label: 'W2', cats: weekMap[2]!),
        _WeekData(label: 'W3', cats: weekMap[3]!),
        _WeekData(label: 'W4', cats: weekMap[4]!),
      ];

      // Pick months to show based on _view, trim trailing empty months
      List<_MonthData> pool;
      switch (_view) {
        case '3':  pool = allMonths.sublist(9);  break;
        case '6':  pool = allMonths.sublist(6);  break;
        case '12': pool = allMonths;             break;
        default:   pool = [allMonths.last];      break;
      }
      // Remove leading months with no data, keep all once data starts
      int firstWithData = pool.indexWhere((m) => m.total > 0);
      final months = firstWithData < 0 ? pool : pool.sublist(firstWithData);

      setState(() {
        _months       = months;
        _weeks        = weeks;
        _monthsInData = monthsWithData;
        _allCategories = allCats;
        _loading      = false;
      });
    } catch (_) {
      setState(() => _loading = false);
    }
  }

  void _showMonthPicker(BuildContext context) {
    final opts = <String>['current'];
    if (_monthsInData > 1) opts.add('3');
    if (_monthsInData > 3) opts.add('6');
    if (_monthsInData > 6) opts.add('12');

    final labels = {
      'current': 'This month (weekly)',
      '3':  'Last 3 months',
      '6':  'Last 6 months',
      '12': 'Last 12 months',
    };

    showModalBottomSheet(
      context: context,
      backgroundColor: const Color(0xFF1C1C1E),
      shape: const RoundedRectangleBorder(
          borderRadius: BorderRadius.vertical(top: Radius.circular(20))),
      builder: (_) => Padding(
        padding: const EdgeInsets.fromLTRB(24, 20, 24, 40),
        child: Column(mainAxisSize: MainAxisSize.min, children: [
          Container(width: 36, height: 4,
              decoration: BoxDecoration(color: Colors.white24,
                  borderRadius: BorderRadius.circular(2))),
          const SizedBox(height: 20),
          ...opts.map((v) => GestureDetector(
            onTap: () {
              setState(() => _view = v);
              Navigator.pop(context);
              _load();
            },
            child: Container(
              width: double.infinity,
              padding: const EdgeInsets.symmetric(vertical: 16),
              decoration: BoxDecoration(border: Border(bottom: BorderSide(
                  color: Colors.white.withOpacity(0.06)))),
              child: Row(children: [
                Expanded(child: Text(labels[v]!,
                    style: TextStyle(
                        color: v == _view ? Colors.white : Colors.white.withOpacity(0.45),
                        fontSize: 16,
                        fontWeight: v == _view ? FontWeight.w500 : FontWeight.normal))),
                if (v == _view) const Icon(Icons.check, color: Colors.white, size: 16),
              ]),
            ),
          )),
        ]),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFF0A0A0A),
      body: SafeArea(
        child: _loading
            ? const Center(child: CircularProgressIndicator(
            color: Colors.white24, strokeWidth: 1))
            : Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // Header
            Padding(
              padding: const EdgeInsets.fromLTRB(24, 32, 24, 0),
              child: Row(children: [
                Text('ANALYTICS', style: TextStyle(
                    fontSize: 11, letterSpacing: 4,
                    color: Colors.white.withOpacity(0.25),
                    fontWeight: FontWeight.w600)),
                const Spacer(),
                GestureDetector(
                  onTap: () => _showMonthPicker(context),
                  child: Container(
                    padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 7),
                    decoration: BoxDecoration(
                      border: Border.all(color: Colors.white.withOpacity(0.12)),
                      borderRadius: BorderRadius.circular(20),
                    ),
                    child: Row(mainAxisSize: MainAxisSize.min, children: [
                      Text(_view == 'current' ? 'This month' : 'Last $_view months',
                          style: TextStyle(fontSize: 12,
                              color: Colors.white.withOpacity(0.5))),
                      const SizedBox(width: 4),
                      Icon(Icons.expand_more, size: 14,
                          color: Colors.white.withOpacity(0.3)),
                    ]),
                  ),
                ),
              ]),
            ),
            const SizedBox(height: 24),

            // Line graph
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 24),
              child: _LineGraph(
                months: _months,
                weeks: _weeks,
                selectedLines: _selectedLines,
                isWeekly: _view == 'current',
              ),
            ),

            const SizedBox(height: 24),

            // Category selector chips
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 24),
              child: SingleChildScrollView(
                scrollDirection: Axis.horizontal,
                child: Row(
                  children: [
                    // Total chip
                    _LineChip(
                      label: 'Total',
                      color: Colors.white,
                      selected: _selectedLines.contains('__total__'),
                      onTap: () => setState(() {
                        if (_selectedLines.contains('__total__'))
                          _selectedLines.remove('__total__');
                        else
                          _selectedLines.add('__total__');
                      }),
                    ),
                    const SizedBox(width: 8),
                    // Category chips
                    ..._allCategories.toList().asMap().entries.map((e) {
                      final colors = _pieColors();
                      final color  = colors[e.key % colors.length];
                      final sel    = _selectedLines.contains(e.value);
                      return Padding(
                        padding: const EdgeInsets.only(right: 8),
                        child: _LineChip(
                          label: e.value,
                          color: color,
                          selected: sel,
                          onTap: () => setState(() {
                            if (sel) _selectedLines.remove(e.value);
                            else     _selectedLines.add(e.value);
                          }),
                        ),
                      );
                    }),
                  ],
                ),
              ),
            ),

            const SizedBox(height: 28),

            // Daily bars
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 24),
              child: _SectionLabel('LAST 7 DAYS'),
            ),
            const SizedBox(height: 12),
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 24),
              child: _DailyBarsAsync(),
            ),

            // Category changes
            if (_months.length >= 2) ...[
              const SizedBox(height: 28),
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 24),
                child: _SectionLabel('vs LAST MONTH'),
              ),
              const SizedBox(height: 12),
              Expanded(
                child: ListView(
                  padding: const EdgeInsets.fromLTRB(24, 0, 24, 48),
                  children: () {
                    final thisMonth = _months.last;
                    final lastMonth = _months[_months.length - 2];
                    return thisMonth.cats.entries.map((e) {
                      final last = lastMonth.cats[e.key] ?? 0;
                      final diff = e.value - last;
                      final pct  = last > 0 ? diff / last * 100 : 0.0;
                      return _CatComparison(
                        category: e.key,
                        thisAmount: e.value,
                        lastAmount: last,
                        pct: pct,
                      );
                    }).toList();
                  }(),
                ),
              ),
            ] else
              const Spacer(),
          ],
        ),
      ),
    );
  }
}

class _MonthData {
  final String label;
  final Map<String, double> cats;
  const _MonthData({required this.label, required this.cats});
  double get total => cats.values.fold(0, (a, b) => a + b);
}

class _WeekData {
  final String label;
  final Map<String, double> cats;
  const _WeekData({required this.label, required this.cats});
  double get total => cats.values.fold(0, (a, b) => a + b);
}

// ── Line Graph ──────────────────────────────────────────────────

class _LineGraph extends StatelessWidget {
  final List<_MonthData> months;
  final List<_WeekData>  weeks;
  final Set<String>      selectedLines;
  final bool             isWeekly;

  const _LineGraph({required this.months, required this.weeks,
    required this.selectedLines, required this.isWeekly});

  @override
  Widget build(BuildContext context) {
    final colors  = _pieColors();
    final allCats = isWeekly
        ? weeks.expand((w) => w.cats.keys).toSet().toList()
        : months.expand((m) => m.cats.keys).toSet().toList();
    final catColors = { for (var i = 0; i < allCats.length; i++)
      allCats[i]: colors[i % colors.length] };

    return SizedBox(
      height: 180,
      child: CustomPaint(
        painter: _LinePainter(
          months: months,
          weeks: weeks,
          isWeekly: isWeekly,
          selectedLines: selectedLines,
          allCats: allCats,
          catColors: catColors,
        ),
        size: const Size(double.infinity, 180),
      ),
    );
  }
}

class _LinePainter extends CustomPainter {
  final List<_MonthData> months;
  final List<_WeekData>  weeks;
  final bool             isWeekly;
  final Set<String>      selectedLines;
  final List<String>     allCats;
  final Map<String, Color> catColors;

  _LinePainter({required this.months, required this.weeks,
    required this.isWeekly, required this.selectedLines,
    required this.allCats, required this.catColors});

  @override
  void paint(Canvas canvas, Size size) {
    const padL = 36.0, padR = 12.0, padT = 8.0, padB = 24.0;
    final w = size.width - padL - padR;
    final h = size.height - padT - padB;

    if (isWeekly) {
      _paintWeekly(canvas, w, h, padL, padT);
    } else {
      _paintMonthly(canvas, w, h, padL, padT);
    }
  }

  void _paintWeekly(Canvas canvas, double w, double h, double padL, double padT) {
    final pts = weeks; // always show all 4 weeks
    if (pts.isEmpty) return;

    double maxVal = 0;
    for (final wk in pts) {
      if (selectedLines.contains('__total__') && wk.total > maxVal) maxVal = wk.total;
      for (final cat in allCats) {
        if (selectedLines.contains(cat) && (wk.cats[cat] ?? 0) > maxVal)
          maxVal = wk.cats[cat]!;
      }
    }
    if (maxVal == 0) maxVal = 1;

    _drawGrid(canvas, w, h, padL, padT, maxVal);

    // X labels
    for (var i = 0; i < pts.length; i++) {
      final x  = pts.length == 1 ? padL + w / 2 : padL + i / (pts.length - 1) * w;
      final tp = TextPainter(
        text: TextSpan(text: pts[i].label, style: TextStyle(
          color: i == pts.length - 1
              ? Colors.white.withOpacity(0.6) : Colors.white.withOpacity(0.25),
          fontSize: 9,
          fontWeight: i == pts.length - 1 ? FontWeight.w600 : FontWeight.normal,
        )),
        textDirection: TextDirection.ltr,
      )..layout();
      tp.paint(canvas, Offset(x - tp.width / 2, padT + h + 6));
    }

    void drawLine(List<double> vals, Color color) {
      if (vals.every((v) => v == 0)) return;
      final path = Path();
      bool penDown = false;
      int lastNonZeroIdx = -1;
      for (var i = 0; i < vals.length; i++) {
        if (vals[i] > 0) lastNonZeroIdx = i;
      }
      for (var i = 0; i < vals.length; i++) {
        if (vals[i] == 0) { penDown = false; continue; } // lift pen on empty
        final x = pts.length == 1 ? padL + w / 2 : padL + i / (pts.length - 1) * w;
        final y = padT + h - (vals[i] / maxVal).clamp(0, 1) * h;
        if (!penDown) { path.moveTo(x, y); penDown = true; }
        else path.lineTo(x, y);
        // Dot on each non-zero point
        canvas.drawCircle(Offset(x, y), 3.0, Paint()..color = color);
      }
      canvas.drawPath(path, Paint()
        ..color = color..strokeWidth = 1.8..style = PaintingStyle.stroke
        ..strokeCap = StrokeCap.round..strokeJoin = StrokeJoin.round);
    }

    if (selectedLines.contains('__total__'))
      drawLine(pts.map((wk) => wk.total).toList(), Colors.white);
    for (final cat in allCats) {
      if (selectedLines.contains(cat))
        drawLine(pts.map((wk) => wk.cats[cat] ?? 0.0).toList(),
            catColors[cat] ?? Colors.white);
    }
  }

  void _paintMonthly(Canvas canvas, double w, double h, double padL, double padT) {
    final pts = months.where((m) => true).toList(); // show all, even empty
    if (pts.length < 2) return;

    double maxVal = 0;
    for (final m in pts) {
      if (selectedLines.contains('__total__') && m.total > maxVal) maxVal = m.total;
      for (final cat in allCats) {
        if (selectedLines.contains(cat) && (m.cats[cat] ?? 0) > maxVal)
          maxVal = m.cats[cat]!;
      }
    }
    if (maxVal == 0) maxVal = 1;

    _drawGrid(canvas, w, h, padL, padT, maxVal);

    for (var i = 0; i < pts.length; i++) {
      final x  = padL + i / (pts.length - 1) * w;
      final tp = TextPainter(
        text: TextSpan(text: pts[i].label, style: TextStyle(
          color: i == pts.length - 1
              ? Colors.white.withOpacity(0.6) : Colors.white.withOpacity(0.3),
          fontSize: 9,
          fontWeight: i == pts.length - 1 ? FontWeight.w600 : FontWeight.normal,
        )),
        textDirection: TextDirection.ltr,
      )..layout();
      tp.paint(canvas, Offset(x - tp.width / 2, padT + h + 6));
    }

    void drawLine(List<double> vals, Color color) {
      if (vals.every((v) => v == 0)) return;
      final path = Path();
      for (var i = 0; i < vals.length; i++) {
        final x = padL + i / (pts.length - 1) * w;
        final y = padT + h - (vals[i] / maxVal).clamp(0, 1) * h;
        i == 0 ? path.moveTo(x, y) : path.lineTo(x, y);
      }
      canvas.drawPath(path, Paint()
        ..color = color..strokeWidth = 1.8..style = PaintingStyle.stroke
        ..strokeCap = StrokeCap.round..strokeJoin = StrokeJoin.round);
      final li = vals.length - 1;
      final lx = padL + w;
      final ly = padT + h - (vals[li] / maxVal).clamp(0, 1) * h;
      canvas.drawCircle(Offset(lx, ly), 3.5, Paint()..color = color);
    }

    if (selectedLines.contains('__total__'))
      drawLine(pts.map((m) => m.total).toList(), Colors.white);
    for (final cat in allCats) {
      if (selectedLines.contains(cat))
        drawLine(pts.map((m) => m.cats[cat] ?? 0.0).toList(),
            catColors[cat] ?? Colors.white);
    }
  }

  void _drawGrid(Canvas canvas, double w, double h, double padL, double padT, double maxVal) {
    final gridPaint = Paint()
      ..color = Colors.white.withOpacity(0.06)..strokeWidth = 1;
    for (var i = 0; i <= 3; i++) {
      final y = padT + h - (i / 3) * h;
      canvas.drawLine(Offset(padL, y), Offset(padL + w, y), gridPaint);
      final tp = TextPainter(
        text: TextSpan(text: _fmtLabel((i / 3) * maxVal),
            style: TextStyle(color: Colors.white.withOpacity(0.2), fontSize: 9)),
        textDirection: TextDirection.ltr,
      )..layout();
      tp.paint(canvas, Offset(padL - tp.width - 4, y - tp.height / 2));
    }
  }

  @override
  bool shouldRepaint(_LinePainter old) =>
      old.selectedLines != selectedLines ||
          old.months != months ||
          old.weeks != weeks ||
          old.isWeekly != isWeekly;
}

class _LineChip extends StatelessWidget {
  final String label;
  final Color color;
  final bool selected;
  final VoidCallback onTap;

  const _LineChip({required this.label, required this.color,
    required this.selected, required this.onTap});

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 180),
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 7),
        decoration: BoxDecoration(
          color: selected ? color.withOpacity(0.15) : Colors.transparent,
          borderRadius: BorderRadius.circular(20),
          border: Border.all(
            color: selected ? color.withOpacity(0.5) : Colors.white.withOpacity(0.1),
          ),
        ),
        child: Row(mainAxisSize: MainAxisSize.min, children: [
          Container(width: 6, height: 6,
              decoration: BoxDecoration(
                  color: selected ? color : color.withOpacity(0.3),
                  shape: BoxShape.circle)),
          const SizedBox(width: 6),
          Text(label, style: TextStyle(
              color: Colors.white.withOpacity(selected ? 0.9 : 0.4),
              fontSize: 12)),
        ]),
      ),
    );
  }
}

// Daily bars but async (loads its own data)
class _DailyBarsAsync extends StatefulWidget {
  const _DailyBarsAsync();
  @override
  State<_DailyBarsAsync> createState() => _DailyBarsAsyncState();
}

class _DailyBarsAsyncState extends State<_DailyBarsAsync> {
  Map<String, double> _daily = {};

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    final now      = DateTime.now();
    final weekFrom = DateTime(now.year, now.month, now.day - 6)
        .millisecondsSinceEpoch.toString();
    try {
      final txns = await Repo.txns(from: weekFrom);
      final daily = <String, double>{};
      for (var i = 6; i >= 0; i--) {
        final d   = now.subtract(Duration(days: i));
        final key = '${d.day}/${d.month}';
        daily[key] = 0;
      }
      for (final t in txns) {
        if (t['type'] != 'debit') continue;
        final d   = DateTime.fromMillisecondsSinceEpoch(t['timestamp'] as int);
        final key = '${d.day}/${d.month}';
        if (daily.containsKey(key)) {
          daily[key] = (daily[key] ?? 0) + (t['amount'] as num).toDouble();
        }
      }
      setState(() => _daily = daily);
    } catch (_) {}
  }

  @override
  Widget build(BuildContext context) => _DailyBars(daily: _daily);
}

// ══════════════════════════════════════════════════════════════════
// PIE CHART
// ══════════════════════════════════════════════════════════════════

class _PieSection extends StatelessWidget {
  final Map<String, double> cats;
  final double total;
  final String? selected;
  final ValueChanged<String> onSelect;

  const _PieSection({required this.cats, required this.total,
    required this.selected, required this.onSelect});

  @override
  Widget build(BuildContext context) {
    final colors  = _pieColors();
    final entries = cats.entries.toList();

    return LayoutBuilder(builder: (context, constraints) {
      final canvasW = constraints.maxWidth;
      return GestureDetector(
        behavior: HitTestBehavior.opaque,
        onTapUp: (details) {
          final RenderBox box = context.findRenderObject() as RenderBox;
          final local = box.globalToLocal(details.globalPosition);
          const canvasH = 260.0;
          final cx = canvasW / 2, cy = canvasH / 2;
          final dx = local.dx - cx, dy = local.dy - cy;
          final dist = math.sqrt(dx * dx + dy * dy);
          if (dist < 50.0 || dist > 116.0) return;
          var angle = math.atan2(dy, dx) + math.pi / 2;
          if (angle < 0) angle += 2 * math.pi;
          var start = 0.0;
          for (var i = 0; i < entries.length; i++) {
            final sweep = entries[i].value / total * 2 * math.pi;
            if (angle >= start && angle < start + sweep) {
              onSelect(entries[i].key);
              return;
            }
            start += sweep;
          }
        },
        child: SizedBox(
          height: 290,
          child: CustomPaint(
            painter: _PiePainter(
              cats: cats, total: total,
              colors: colors, selected: selected,
              canvasWidth: canvasW,
            ),
            size: Size(canvasW, 260),
            child: Align(
              // pie vertical centre is at 52% of canvas height
              alignment: const Alignment(0.0, 0.08),
              child: selected != null
                  ? Text(
                '${((cats[selected!] ?? 0) / total * 100).toStringAsFixed(1)}%',
                style: const TextStyle(color: Colors.white,
                    fontSize: 24, fontWeight: FontWeight.w200),
              )
                  : const SizedBox.shrink(),
            ),
          ),
        ),
      );
    }); // LayoutBuilder
  }
}

class _PiePainter extends CustomPainter {
  final Map<String, double> cats;
  final double total;
  final List<Color> colors;
  final String? selected;
  final double canvasWidth;

  _PiePainter({required this.cats, required this.total,
    required this.colors, required this.selected, required this.canvasWidth});

  @override
  void paint(Canvas canvas, Size size) {
    final cx      = canvasWidth / 2;
    final cy      = size.height * 0.52;
    const outer   = 100.0;
    const inner   = 60.0;
    const expand  = 8.0;
    const gap     = 0.018;
    const margin  = 6.0; // min margin from screen edge
    var   start   = -math.pi / 2;
    final entries = cats.entries.toList();

    for (var i = 0; i < entries.length; i++) {
      final frac    = entries[i].value / total;
      final sweep   = frac * 2 * math.pi - gap;
      if (sweep <= 0) { start += frac * 2 * math.pi; continue; }
      final color   = colors[i % colors.length];
      final isSel   = selected == entries[i].key;
      final mid     = start + sweep / 2;
      final r       = isSel ? outer + expand : outer;

      final paint = Paint()
        ..color = isSel ? color : color.withOpacity(0.7)
        ..style = PaintingStyle.fill;

      final offX = isSel ? math.cos(mid) * expand : 0.0;
      final offY = isSel ? math.sin(mid) * expand : 0.0;

      final path = Path()
        ..moveTo(cx + offX + inner * math.cos(start + gap / 2),
            cy + offY + inner * math.sin(start + gap / 2))
        ..arcTo(Rect.fromCircle(center: Offset(cx + offX, cy + offY), radius: inner),
            start + gap / 2, sweep, false)
        ..arcTo(Rect.fromCircle(center: Offset(cx + offX, cy + offY), radius: r),
            start + sweep, -sweep, false)
        ..close();

      canvas.drawPath(path, paint);

      _drawLabel(canvas, size, cx + offX, cy + offY, mid, r,
          entries[i].key, frac, color, isSel,
          '₹${_fmtLabel(entries[i].value)}',
          canvasWidth, margin);

      start += frac * 2 * math.pi;
    }
  }

  void _drawLabel(Canvas canvas, Size size, double cx, double cy,
      double mid, double outerR, String label, double frac,
      Color color, bool isSel, String amount,
      double canvasW, double margin) {
    if (frac < 0.04) return;

    const lineStart = 10.0;
    const lineLen   = 20.0;
    const dotR      = 2.0;
    const maxLabelW = 68.0;

    final x1 = cx + (outerR + lineStart) * math.cos(mid);
    final y1 = cy + (outerR + lineStart) * math.sin(mid);
    final x2 = cx + (outerR + lineStart + lineLen) * math.cos(mid);
    final y2 = cy + (outerR + lineStart + lineLen) * math.sin(mid);

    final linePaint = Paint()
      ..color = color.withOpacity(isSel ? 0.9 : 0.4)
      ..strokeWidth = 1.0
      ..style = PaintingStyle.stroke;

    canvas.drawLine(Offset(x1, y1), Offset(x2, y2), linePaint);
    canvas.drawCircle(Offset(x2, y2), dotR,
        Paint()..color = color.withOpacity(isSel ? 1.0 : 0.45));

    final isRight = math.cos(mid) >= 0;

    final namePainter = TextPainter(
      text: TextSpan(text: label, style: TextStyle(
        color: Colors.white.withOpacity(isSel ? 1.0 : 0.6),
        fontSize: 10,
        fontWeight: isSel ? FontWeight.w600 : FontWeight.normal,
      )),
      textDirection: TextDirection.ltr,
    )..layout(maxWidth: maxLabelW);

    final amtPainter = TextPainter(
      text: TextSpan(text: amount, style: TextStyle(
        color: Colors.white.withOpacity(isSel ? 0.7 : 0.35),
        fontSize: 9,
      )),
      textDirection: TextDirection.ltr,
    )..layout(maxWidth: maxLabelW);

    final totalH = namePainter.height + 2 + amtPainter.height;
    final startY = y2 - totalH / 2;

    // Clamp x so label never goes outside screen edges
    double nx, ax;
    if (isRight) {
      nx = x2 + dotR + 5;
      ax = x2 + dotR + 5;
      // Clamp right edge
      final maxX = canvasW - margin;
      if (nx + namePainter.width > maxX) nx = maxX - namePainter.width;
      if (ax + amtPainter.width > maxX)  ax = maxX - amtPainter.width;
    } else {
      nx = x2 - dotR - 5 - namePainter.width;
      ax = x2 - dotR - 5 - amtPainter.width;
      // Clamp left edge
      if (nx < margin) nx = margin;
      if (ax < margin) ax = margin;
    }

    // Smart Y: clamp to canvas, prefer direction with more space
    final labelH = namePainter.height + 2 + amtPainter.height;
    final spaceAbove = y2;
    final spaceBelow = size.height - y2;
    double sy = y2 - labelH / 2; // centered default
    if (sy < 4) {
      // Not enough space above — shift down
      sy = spaceBelow > spaceAbove ? y2 + 4 : 4.0;
    } else if (sy + labelH > size.height - 4) {
      // Not enough space below — shift up
      sy = spaceAbove > spaceBelow ? y2 - labelH - 4 : size.height - labelH - 4;
    }
    sy = sy.clamp(4.0, size.height - labelH - 4);

    namePainter.paint(canvas, Offset(nx, sy));
    amtPainter.paint(canvas, Offset(ax, sy + namePainter.height + 2));
  }

  @override
  bool shouldRepaint(_PiePainter old) =>
      old.selected != selected || old.cats != cats;
}

class _DailyBars extends StatelessWidget {
  final Map<String, double> daily;
  const _DailyBars({required this.daily});

  @override
  Widget build(BuildContext context) {
    final max = daily.values.fold(0.0, (a, b) => a > b ? a : b);
    final days = ['Mon', 'Tue', 'Wed', 'Thu', 'Fri', 'Sat', 'Sun'];
    final now  = DateTime.now();
    final entries = daily.entries.toList();

    return Container(
      padding: const EdgeInsets.fromLTRB(16, 20, 16, 16),
      decoration: BoxDecoration(
        color: const Color(0xFF1C1C1E),
        borderRadius: BorderRadius.circular(16),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.end,
        children: entries.asMap().entries.map((e) {
          final idx    = e.key;
          final amount = e.value.value;
          final pct    = max > 0 ? amount / max : 0.0;
          final dayIdx = (now.weekday - 1 - (6 - idx)) % 7;
          final label  = days[dayIdx.clamp(0, 6)];
          final isToday = idx == entries.length - 1;

          return Expanded(
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 3),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  if (amount > 0)
                    Padding(
                      padding: const EdgeInsets.only(bottom: 4),
                      child: Text('₹${_fmtShort(amount)}',
                          style: TextStyle(
                              color: Colors.white.withOpacity(0.3),
                              fontSize: 8)),
                    ),
                  AnimatedContainer(
                    duration: Duration(milliseconds: 300 + idx * 50),
                    curve: Curves.easeOutCubic,
                    height: 80 * pct + 4,
                    decoration: BoxDecoration(
                      color: isToday
                          ? Colors.white.withOpacity(0.7)
                          : Colors.white.withOpacity(0.2),
                      borderRadius: BorderRadius.circular(4),
                    ),
                  ),
                  const SizedBox(height: 8),
                  Text(label, style: TextStyle(
                      color: isToday
                          ? Colors.white.withOpacity(0.7)
                          : Colors.white.withOpacity(0.25),
                      fontSize: 10,
                      fontWeight: isToday ? FontWeight.w600 : FontWeight.normal)),
                ],
              ),
            ),
          );
        }).toList(),
      ),
    );
  }
}

// ══════════════════════════════════════════════════════════════════
// CATEGORY COMPARISON ROW
// ══════════════════════════════════════════════════════════════════

class _CatComparison extends StatelessWidget {
  final String category;
  final double thisAmount, lastAmount, pct;
  const _CatComparison({required this.category, required this.thisAmount,
    required this.lastAmount, required this.pct});

  @override
  Widget build(BuildContext context) {
    final isUp  = pct > 0;
    final hasLast = lastAmount > 0;

    return Container(
      margin: const EdgeInsets.only(bottom: 10),
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
      decoration: BoxDecoration(
        color: const Color(0xFF1C1C1E),
        borderRadius: BorderRadius.circular(12),
      ),
      child: Row(children: [
        Expanded(child: Text(category, style: const TextStyle(
            color: Colors.white, fontSize: 14, fontWeight: FontWeight.w400))),
        Text('₹${_fmt(thisAmount)}', style: TextStyle(
            color: Colors.white.withOpacity(0.6), fontSize: 13)),
        if (hasLast) ...[
          const SizedBox(width: 8),
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 3),
            decoration: BoxDecoration(
              color: isUp
                  ? const Color(0xFFFF453A).withOpacity(0.08)
                  : const Color(0xFF30D158).withOpacity(0.08),
              borderRadius: BorderRadius.circular(6),
            ),
            child: Text(
              '${isUp ? '↑' : '↓'} ${pct.abs().toStringAsFixed(0)}%',
              style: TextStyle(
                color: isUp
                    ? const Color(0xFFFF453A).withOpacity(0.8)
                    : const Color(0xFF30D158).withOpacity(0.8),
                fontSize: 11, fontWeight: FontWeight.w500,
              ),
            ),
          ),
        ],
      ]),
    );
  }
}

// ══════════════════════════════════════════════════════════════════
// HOME SCREEN WIDGETS
// ══════════════════════════════════════════════════════════════════

class _CatRow extends StatelessWidget {
  final String category;
  final double amount, total;
  final bool selected;
  const _CatRow({required this.category, required this.amount,
    required this.total, required this.selected});

  @override
  Widget build(BuildContext context) {
    final pct = total > 0 ? (amount / total).clamp(0.0, 1.0) : 0.0;
    return Padding(
      padding: const EdgeInsets.only(bottom: 20),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Row(children: [
          Expanded(child: Text(category, style: TextStyle(
              color: Colors.white.withOpacity(selected ? 1.0 : 0.7),
              fontSize: 14,
              fontWeight: selected ? FontWeight.w500 : FontWeight.w400))),
          Text('₹${_fmt(amount)}', style: TextStyle(
              color: Colors.white.withOpacity(selected ? 0.85 : 0.5),
              fontSize: 14, fontWeight: FontWeight.w500)),
        ]),
        const SizedBox(height: 8),
        ClipRRect(
          borderRadius: BorderRadius.circular(2),
          child: LinearProgressIndicator(
            value: pct, minHeight: 2,
            backgroundColor: Colors.white.withOpacity(0.06),
            valueColor: AlwaysStoppedAnimation<Color>(
                Colors.white.withOpacity(selected ? 1.0 : 0.35)),
          ),
        ),
      ]),
    );
  }
}

class _EmptyDonut extends StatelessWidget {
  const _EmptyDonut();

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      height: 200,
      child: Center(
        child: CustomPaint(
          painter: _EmptyDonutPainter(),
          size: const Size(200, 200),
        ),
      ),
    );
  }
}

class _EmptyDonutPainter extends CustomPainter {
  @override
  void paint(Canvas canvas, Size size) {
    final cx = size.width / 2, cy = size.height / 2;
    const outer = 90.0, inner = 54.0;
    final paint = Paint()
      ..color = Colors.white.withOpacity(0.08)
      ..style = PaintingStyle.fill;
    final path = Path()
      ..addOval(Rect.fromCircle(center: Offset(cx, cy), radius: outer))
      ..addOval(Rect.fromCircle(center: Offset(cx, cy), radius: inner));
    path.fillType = PathFillType.evenOdd;
    canvas.drawPath(path, paint);
  }

  @override
  bool shouldRepaint(_EmptyDonutPainter old) => false;
}

class _CatBars extends StatelessWidget {
  final Map<String, double> cats;
  final double total;
  final String? selected;
  final ValueChanged<String> onSelect;

  const _CatBars({required this.cats, required this.total,
    required this.selected, required this.onSelect});

  @override
  Widget build(BuildContext context) {
    final entries = cats.entries.toList();
    return Column(
      children: entries.map((e) {
        final isSelected = selected == e.key;
        final isHidden   = selected != null && !isSelected;
        return GestureDetector(
          behavior: HitTestBehavior.opaque,
          onTap: () => onSelect(e.key),
          child: AnimatedOpacity(
            duration: const Duration(milliseconds: 300),
            curve: Curves.easeInOut,
            opacity: isHidden ? 0.0 : 1.0,
            child: ClipRect(
              child: AnimatedAlign(
                duration: const Duration(milliseconds: 350),
                curve: Curves.easeInOutCubic,
                alignment: Alignment.topCenter,
                heightFactor: isHidden ? 0.0 : 1.0,
                child: _CatRow(
                  category: e.key,
                  amount: e.value,
                  total: total,
                  selected: isSelected,
                ),
              ),
            ),
          ),
        );
      }).toList(),
    );
  }
}

class _TxnTile extends StatelessWidget {
  final Map<String, dynamic> txn;
  final bool expanded;
  final VoidCallback onTap;
  const _TxnTile({required this.txn, required this.expanded, required this.onTap});

  @override
  Widget build(BuildContext context) {
    final isDebit  = txn['type'] == 'debit';
    final amount   = (txn['amount'] as num).toDouble();
    final date     = DateTime.fromMillisecondsSinceEpoch(txn['timestamp'] as int);
    final cat      = txn['category'] as String? ?? 'Misc';
    final ref      = txn['ref_number'] as String? ?? '';
    final payeeKey = txn['payee_key']  as String? ?? '';

    return GestureDetector(
      behavior: HitTestBehavior.opaque,
      onTap: onTap,
      child: Padding(
        padding: const EdgeInsets.fromLTRB(24, 0, 24, 0),
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Padding(
            padding: const EdgeInsets.symmetric(vertical: 14),
            child: Row(children: [
              Container(
                width: 36, height: 36,
                decoration: BoxDecoration(
                  color: isDebit
                      ? const Color(0xFFFF453A).withOpacity(0.1)
                      : const Color(0xFF30D158).withOpacity(0.1),
                  borderRadius: BorderRadius.circular(10),
                ),
                child: Icon(
                  isDebit ? Icons.keyboard_arrow_up : Icons.keyboard_arrow_down,
                  size: 22,
                  color: isDebit
                      ? const Color(0xFFFF453A).withOpacity(0.8)
                      : const Color(0xFF30D158).withOpacity(0.8),
                ),
              ),
              const SizedBox(width: 14),
              Expanded(child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(txn['merchant_name'], style: const TextStyle(
                      color: Colors.white, fontSize: 15, fontWeight: FontWeight.w400)),
                  const SizedBox(height: 3),
                  Row(children: [
                    Text(cat, style: TextStyle(
                        color: Colors.white.withOpacity(0.28), fontSize: 11)),
                    Text('  ·  ', style: TextStyle(
                        color: Colors.white.withOpacity(0.15), fontSize: 11)),
                    Text(_fmtDate(date), style: TextStyle(
                        color: Colors.white.withOpacity(0.28), fontSize: 11)),
                  ]),
                ],
              )),
              Text('${isDebit ? '-' : '+'}₹${_fmt(amount)}',
                  style: TextStyle(
                    color: isDebit
                        ? const Color(0xFFFF453A)
                        : const Color(0xFF30D158),
                    fontSize: 15, fontWeight: FontWeight.w500,
                  )),
            ]),
          ),
          ClipRect(
            child: AnimatedAlign(
              duration: const Duration(milliseconds: 300),
              curve: Curves.easeInOutCubic,
              alignment: Alignment.topCenter,
              heightFactor: expanded ? 1.0 : 0.0,
              child: AnimatedOpacity(
                duration: const Duration(milliseconds: 250),
                opacity: expanded ? 1.0 : 0.0,
                child: Padding(
                  padding: const EdgeInsets.only(left: 50, bottom: 14),
                  child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                    _DetailRow(label: 'Ref',   value: ref),
                    const SizedBox(height: 6),
                    _DetailRow(label: 'Payee', value: payeeKey),
                  ]),
                ),
              ),
            ),
          ),
          Divider(height: 1, color: Colors.white.withOpacity(0.04), indent: 50),
        ]),
      ),
    );
  }
}

class _DetailRow extends StatelessWidget {
  final String label, value;
  const _DetailRow({required this.label, required this.value});

  @override
  Widget build(BuildContext context) {
    return Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
      SizedBox(width: 44, child: Text(label, style: TextStyle(
          color: Colors.white.withOpacity(0.25), fontSize: 11,
          fontWeight: FontWeight.w600, letterSpacing: 0.5))),
      Expanded(child: Text(value, style: TextStyle(
          color: Colors.white.withOpacity(0.4),
          fontSize: 11, fontFamily: 'monospace'))),
    ]);
  }
}

class _SectionLabel extends StatelessWidget {
  final String text;
  const _SectionLabel(this.text);
  @override
  Widget build(BuildContext context) {
    return Text(text, style: TextStyle(fontSize: 11, letterSpacing: 2,
        color: Colors.white.withOpacity(0.25), fontWeight: FontWeight.w600));
  }
}

// ══════════════════════════════════════════════════════════════════
// HELPERS
// ══════════════════════════════════════════════════════════════════

List<Color> _pieColors() => const [
  Color(0xFF7B8CDE), Color(0xFF56C596), Color(0xFFE8A838),
  Color(0xFFE06C75), Color(0xFF97C3F0), Color(0xFFB39DDB),
  Color(0xFF80CBC4), Color(0xFFFFCC80),
];

String _fmt(double a) {
  if (a >= 100000) return '${(a / 100000).toStringAsFixed(1)}L';
  if (a >= 1000)   return '${(a / 1000).toStringAsFixed(1)}K';
  return a.toStringAsFixed(0);
}

String _fmtLabel(double a) {
  if (a >= 100000) return (a / 100000).toStringAsFixed(1) + 'L';
  if (a >= 1000) return (a / 1000).toStringAsFixed(1) + 'K';
  return a.toStringAsFixed(0);
}

String _fmtShort(double a) {
  if (a >= 1000) return '${(a / 1000).toStringAsFixed(1)}K';
  return a.toStringAsFixed(0);
}

String _fmtDate(DateTime d) {
  final now   = DateTime.now();
  final today = DateTime(now.year, now.month, now.day);
  final dDay  = DateTime(d.year, d.month, d.day);
  final h     = d.hour == 0 ? 12 : d.hour > 12 ? d.hour - 12 : d.hour;
  final m     = d.minute.toString().padLeft(2, '0');
  final ap    = d.hour >= 12 ? 'PM' : 'AM';
  final time  = '$h:$m $ap';
  if (dDay == today) return 'Today $time';
  if (dDay == today.subtract(const Duration(days: 1))) return 'Yesterday $time';
  const mo = ['Jan','Feb','Mar','Apr','May','Jun',
    'Jul','Aug','Sep','Oct','Nov','Dec'];
  return '${d.day} ${mo[d.month - 1]}, $time';
}