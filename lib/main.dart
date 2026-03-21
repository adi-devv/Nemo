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
  String     _range            = 'This Month';
  String?    _selectedCategory;
  int?       _expandedTxnId;
  bool       _loading          = true;
  bool       _showPie          = true;
  DateTime?  _customFrom;
  DateTime?  _customTo;

  final _ranges = ['This Week', 'This Month', 'Last Month', 'All Time', 'Custom'];

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
      'Custom' => (
      _customFrom?.millisecondsSinceEpoch.toString(),
      _customTo != null
          ? DateTime(_customTo!.year, _customTo!.month, _customTo!.day + 1)
          .millisecondsSinceEpoch.toString()
          : null,
      ),
      _ => (null, null),
    };
  }

  // Label shown in the header button when Custom is active
  String get _rangeLabel {
    if (_range == 'Custom' && _customFrom != null) {
      final f = _customFrom!;
      final t = _customTo ?? _customFrom!;
      const months = ['Jan','Feb','Mar','Apr','May','Jun',
        'Jul','Aug','Sep','Oct','Nov','Dec'];
      if (f.year == t.year && f.month == t.month && f.day == t.day) {
        return '${f.day} ${months[f.month - 1]}';
      }
      if (f.year == t.year) {
        return '${f.day} ${months[f.month - 1]} \u2013 ${t.day} ${months[t.month - 1]}';
      }
      return '${f.day} ${months[f.month - 1]} ${f.year} \u2013 ${t.day} ${months[t.month - 1]} ${t.year}';
    }
    return _range;
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
    _loadTxns();
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
                        Text(_rangeLabel, style: TextStyle(fontSize: 12,
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
            if (!_loading)
              Padding(
                padding: const EdgeInsets.fromLTRB(24, 20, 24, 0),
                child: Text(
                  _totals.isNotEmpty ? '₹${_fmt(_spent)}' : '—',
                  style: TextStyle(
                      fontSize: 40,
                      fontWeight: FontWeight.w200,
                      color: _totals.isNotEmpty
                          ? Colors.white
                          : Colors.white.withOpacity(0.15),
                      letterSpacing: -1.5),
                ),
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

            // ── Sticky "RECENT" label ──
            if (!_loading && _txns.isNotEmpty)
              Padding(
                padding: const EdgeInsets.fromLTRB(24, 24, 24, 12),
                child: Text('RECENT', style: TextStyle(
                    fontSize: 11, letterSpacing: 2,
                    color: Colors.white.withOpacity(0.2),
                    fontWeight: FontWeight.w600)),
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
                  padding: const EdgeInsets.only(top: 0, bottom: 48),
                  itemCount: _txns.length,
                  itemBuilder: (_, i) {
                    final txn = _txns[i];
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
      builder: (sheetCtx) => Padding(
        padding: const EdgeInsets.fromLTRB(24, 20, 24, 40),
        child: Column(mainAxisSize: MainAxisSize.min, children: [
          Container(width: 36, height: 4,
              decoration: BoxDecoration(color: Colors.white24,
                  borderRadius: BorderRadius.circular(2))),
          const SizedBox(height: 20),
          ..._ranges.map((r) {
            final isCurrent = r == _range;
            return GestureDetector(
              onTap: () async {
                if (r == 'Custom') {
                  Navigator.pop(sheetCtx);
                  final now = DateTime.now();
                  final picked = await showDialog<DateTimeRange>(
                    context: context,
                    builder: (_) => _DateRangeDialog(
                      initial: (_customFrom != null && _customTo != null)
                          ? DateTimeRange(start: _customFrom!, end: _customTo!)
                          : DateTimeRange(
                          start: DateTime(now.year, now.month, 1),
                          end: now),
                      firstDate: DateTime(now.year - 3),
                      lastDate: now,
                    ),
                  );
                  if (picked == null) return;

                  setState(() {
                    _range      = 'Custom';
                    _customFrom = picked.start;
                    _customTo   = picked.end;
                  });
                  _load();
                } else {
                  setState(() => _range = r);
                  Navigator.pop(sheetCtx);
                  _load();
                }
              },
              child: Container(
                width: double.infinity,
                padding: const EdgeInsets.symmetric(vertical: 16),
                decoration: BoxDecoration(
                    border: Border(bottom: BorderSide(
                        color: Colors.white.withOpacity(0.06)))),
                child: Row(children: [
                  Expanded(child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(r, style: TextStyle(
                          color: isCurrent ? Colors.white : Colors.white.withOpacity(0.45),
                          fontSize: 16,
                          fontWeight: isCurrent ? FontWeight.w500 : FontWeight.normal)),
                      // Show selected custom range below the label
                      if (r == 'Custom' && _range == 'Custom' && _customFrom != null) ...[
                        const SizedBox(height: 3),
                        Text(_rangeLabel,
                            style: TextStyle(
                                color: Colors.white.withOpacity(0.35),
                                fontSize: 12)),
                      ],
                    ],
                  )),
                  if (isCurrent) const Icon(Icons.check, color: Colors.white, size: 16)
                  else if (r == 'Custom')
                    Icon(Icons.calendar_today_outlined, size: 14,
                        color: Colors.white.withOpacity(0.25)),
                ]),
              ),
            );
          }),
        ]),
      ),
    );
  }

}

// ══════════════════════════════════════════════════════════════════
// COMPACT DATE RANGE DIALOG
// ══════════════════════════════════════════════════════════════════

class _DateRangeDialog extends StatefulWidget {
  final DateTimeRange initial;
  final DateTime firstDate;
  final DateTime lastDate;
  const _DateRangeDialog({
    required this.initial,
    required this.firstDate,
    required this.lastDate,
  });

  @override
  State<_DateRangeDialog> createState() => _DateRangeDialogState();
}

class _DateRangeDialogState extends State<_DateRangeDialog> {
  late DateTime _viewMonth; // which month is displayed
  DateTime? _from;
  DateTime? _to;
  bool _pickingFrom = true; // true = next tap sets from, false = sets to

  @override
  void initState() {
    super.initState();
    _from      = widget.initial.start;
    _to        = widget.initial.end;
    _viewMonth = DateTime(widget.initial.end.year, widget.initial.end.month);
  }

  static const _mo = ['Jan','Feb','Mar','Apr','May','Jun',
    'Jul','Aug','Sep','Oct','Nov','Dec'];
  static const _wd = ['M','T','W','T','F','S','S'];

  bool _canApply() => _from != null && _to != null && !_to!.isBefore(_from!);

  void _onDayTap(DateTime d) {
    setState(() {
      if (_pickingFrom) {
        _from      = d;
        _to        = null;
        _pickingFrom = false;
      } else {
        if (d.isBefore(_from!)) {
          // Tapped earlier than from — restart
          _from      = d;
          _to        = null;
        } else {
          _to        = d;
          _pickingFrom = true;
        }
      }
    });
  }

  bool _inRange(DateTime d) {
    if (_from == null || _to == null) return false;
    return !d.isBefore(_from!) && !d.isAfter(_to!);
  }

  bool _isFrom(DateTime d) =>
      _from != null && _isSameDay(d, _from!);

  bool _isTo(DateTime d) =>
      _to != null && _isSameDay(d, _to!);

  bool _isSameDay(DateTime a, DateTime b) =>
      a.year == b.year && a.month == b.month && a.day == b.day;

  bool _isToday(DateTime d) => _isSameDay(d, DateTime.now());

  bool _isDisabled(DateTime d) =>
      d.isBefore(widget.firstDate) || d.isAfter(widget.lastDate);

  String _fmtChip(DateTime? d) {
    if (d == null) return '—';
    return '${d.day} ${_mo[d.month - 1]} ${d.year}';
  }

  void _prevMonth() {
    setState(() {
      _viewMonth = DateTime(_viewMonth.year, _viewMonth.month - 1);
    });
  }

  void _nextMonth() {
    final next = DateTime(_viewMonth.year, _viewMonth.month + 1);
    if (next.isAfter(DateTime(widget.lastDate.year, widget.lastDate.month))) return;
    setState(() { _viewMonth = next; });
  }

  @override
  Widget build(BuildContext context) {
    // Build the day grid
    final firstOfMonth = DateTime(_viewMonth.year, _viewMonth.month, 1);
    // Monday = 0 offset
    final startOffset  = (firstOfMonth.weekday - 1) % 7;
    final daysInMonth  = DateTime(_viewMonth.year, _viewMonth.month + 1, 0).day;
    final totalCells   = startOffset + daysInMonth;
    final rows         = (totalCells / 7).ceil();

    return Dialog(
      backgroundColor: const Color(0xFF1C1C1E),
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
      insetPadding: const EdgeInsets.symmetric(horizontal: 24, vertical: 48),
      child: Padding(
        padding: const EdgeInsets.fromLTRB(20, 20, 20, 16),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [

            // ── From / To chips ──
            Row(children: [
              _RangeChip(
                label: 'FROM',
                value: _fmtChip(_from),
                active: _pickingFrom,
                onTap: () => setState(() => _pickingFrom = true),
              ),
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 8),
                child: Icon(Icons.arrow_forward,
                    size: 14, color: Colors.white.withOpacity(0.2)),
              ),
              _RangeChip(
                label: 'TO',
                value: _fmtChip(_to),
                active: !_pickingFrom,
                onTap: () => setState(() { _pickingFrom = false; }),
              ),
            ]),

            const SizedBox(height: 18),

            // ── Month nav ──
            Row(children: [
              GestureDetector(
                onTap: _prevMonth,
                child: Container(
                  width: 32, height: 32,
                  decoration: BoxDecoration(
                    color: Colors.white.withOpacity(0.06),
                    borderRadius: BorderRadius.circular(8),
                  ),
                  child: Icon(Icons.chevron_left,
                      size: 18, color: Colors.white.withOpacity(0.5)),
                ),
              ),
              Expanded(
                child: Text(
                  '${_mo[_viewMonth.month - 1]} ${_viewMonth.year}',
                  textAlign: TextAlign.center,
                  style: const TextStyle(
                      color: Colors.white, fontSize: 14,
                      fontWeight: FontWeight.w500, letterSpacing: 0.3),
                ),
              ),
              GestureDetector(
                onTap: _nextMonth,
                child: Container(
                  width: 32, height: 32,
                  decoration: BoxDecoration(
                    color: Colors.white.withOpacity(0.06),
                    borderRadius: BorderRadius.circular(8),
                  ),
                  child: Icon(Icons.chevron_right,
                      size: 18, color: Colors.white.withOpacity(0.5)),
                ),
              ),
            ]),

            const SizedBox(height: 14),

            // ── Weekday headers ──
            Row(
              children: _wd.map((d) => Expanded(
                child: Text(d,
                    textAlign: TextAlign.center,
                    style: TextStyle(
                        fontSize: 11, fontWeight: FontWeight.w600,
                        color: Colors.white.withOpacity(0.2),
                        letterSpacing: 0.5)),
              )).toList(),
            ),

            const SizedBox(height: 6),

            // ── Day grid ──
            ...List.generate(rows, (row) {
              return Padding(
                padding: const EdgeInsets.only(bottom: 2),
                child: Row(
                  children: List.generate(7, (col) {
                    final cellIdx = row * 7 + col;
                    final dayNum  = cellIdx - startOffset + 1;

                    if (dayNum < 1 || dayNum > daysInMonth) {
                      return const Expanded(child: SizedBox(height: 36));
                    }

                    final d        = DateTime(_viewMonth.year, _viewMonth.month, dayNum);
                    final disabled = _isDisabled(d);
                    final isFrom   = _isFrom(d);
                    final isTo     = _isTo(d);
                    final inRange  = _inRange(d);
                    final today    = _isToday(d);
                    final isEndpoint = isFrom || isTo;

                    // Range highlight: full row strip behind the day circle
                    final bool rangeLeft  = inRange && !isFrom && col > 0;
                    final bool rangeRight = inRange && !isTo  && col < 6;

                    return Expanded(
                      child: GestureDetector(
                        onTap: disabled ? null : () => _onDayTap(d),
                        child: Stack(
                          alignment: Alignment.center,
                          children: [
                            // Range band
                            if (inRange)
                              Row(children: [
                                Expanded(
                                  child: Container(
                                    height: 32,
                                    color: rangeLeft
                                        ? Colors.white.withOpacity(0.08)
                                        : Colors.transparent,
                                  ),
                                ),
                                Expanded(
                                  child: Container(
                                    height: 32,
                                    color: rangeRight
                                        ? Colors.white.withOpacity(0.08)
                                        : Colors.transparent,
                                  ),
                                ),
                              ]),
                            // Day circle
                            Container(
                              width: 32, height: 32,
                              decoration: BoxDecoration(
                                color: isEndpoint
                                    ? Colors.white
                                    : Colors.transparent,
                                shape: BoxShape.circle,
                                border: today && !isEndpoint
                                    ? Border.all(
                                    color: Colors.white.withOpacity(0.25),
                                    width: 1)
                                    : null,
                              ),
                              child: Center(
                                child: Text(
                                  '$dayNum',
                                  style: TextStyle(
                                    fontSize: 13,
                                    fontWeight: isEndpoint
                                        ? FontWeight.w600
                                        : FontWeight.w400,
                                    color: isEndpoint
                                        ? Colors.black
                                        : disabled
                                        ? Colors.white.withOpacity(0.15)
                                        : inRange
                                        ? Colors.white.withOpacity(0.9)
                                        : today
                                        ? Colors.white
                                        : Colors.white.withOpacity(0.6),
                                  ),
                                ),
                              ),
                            ),
                          ],
                        ),
                      ),
                    );
                  }),
                ),
              );
            }),

            const SizedBox(height: 16),

            // ── Hint + Apply ──
            Row(children: [
              Expanded(
                child: Text(
                  _pickingFrom ? 'Tap a start date' : 'Tap an end date',
                  style: TextStyle(
                      fontSize: 11, color: Colors.white.withOpacity(0.25)),
                ),
              ),
              GestureDetector(
                onTap: _canApply()
                    ? () => Navigator.pop(
                    context, DateTimeRange(start: _from!, end: _to!))
                    : null,
                child: AnimatedContainer(
                  duration: const Duration(milliseconds: 180),
                  padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 9),
                  decoration: BoxDecoration(
                    color: _canApply() ? Colors.white : Colors.white.withOpacity(0.1),
                    borderRadius: BorderRadius.circular(20),
                  ),
                  child: Text('Apply',
                      style: TextStyle(
                        fontSize: 13, fontWeight: FontWeight.w600,
                        color: _canApply() ? Colors.black : Colors.white.withOpacity(0.2),
                      )),
                ),
              ),
            ]),
          ],
        ),
      ),
    );
  }
}

class _RangeChip extends StatelessWidget {
  final String label, value;
  final bool active;
  final VoidCallback onTap;
  const _RangeChip({
    required this.label, required this.value,
    required this.active, required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return Expanded(
      child: GestureDetector(
        onTap: onTap,
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 150),
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
          decoration: BoxDecoration(
            color: active
                ? Colors.white.withOpacity(0.08)
                : Colors.transparent,
            borderRadius: BorderRadius.circular(10),
            border: Border.all(
              color: active
                  ? Colors.white.withOpacity(0.25)
                  : Colors.white.withOpacity(0.08),
            ),
          ),
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Text(label, style: TextStyle(
                fontSize: 9, letterSpacing: 1,
                fontWeight: FontWeight.w700,
                color: Colors.white.withOpacity(active ? 0.5 : 0.25))),
            const SizedBox(height: 2),
            Text(value, style: TextStyle(
                fontSize: 12, fontWeight: FontWeight.w500,
                color: Colors.white.withOpacity(active ? 0.9 : 0.45))),
          ]),
        ),
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
  String _view = 'current';

  List<_MonthData> _months       = [];
  List<_WeekData>  _weeks        = [];
  int              _monthsInData = 0;
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

      final monthFrom = DateTime(now.year, now.month, 1).millisecondsSinceEpoch.toString();
      final monthTxns = await Repo.txns(from: monthFrom);
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

      List<_MonthData> pool;
      switch (_view) {
        case '3':  pool = allMonths.sublist(9);  break;
        case '6':  pool = allMonths.sublist(6);  break;
        case '12': pool = allMonths;             break;
        default:   pool = [allMonths.last];      break;
      }
      int firstWithData = pool.indexWhere((m) => m.total > 0);
      final months = firstWithData < 0 ? pool : pool.sublist(firstWithData);

      setState(() {
        _months        = months;
        _weeks         = weeks;
        _monthsInData  = monthsWithData;
        _allCategories = allCats;
        _loading       = false;
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
              child: const _DailyBarsAsync(),
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
    final pts = weeks;
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
      for (var i = 0; i < vals.length; i++) {
        if (vals[i] == 0) { penDown = false; continue; }
        final x = pts.length == 1 ? padL + w / 2 : padL + i / (pts.length - 1) * w;
        final y = padT + h - (vals[i] / maxVal).clamp(0, 1) * h;
        if (!penDown) { path.moveTo(x, y); penDown = true; }
        else path.lineTo(x, y);
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
    final pts = months;
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

// ══════════════════════════════════════════════════════════════════
// DAILY BARS (async, category-aware)
// ══════════════════════════════════════════════════════════════════

class _DailyBarsAsync extends StatefulWidget {
  const _DailyBarsAsync();
  @override
  State<_DailyBarsAsync> createState() => _DailyBarsAsyncState();
}

class _DailyBarsAsyncState extends State<_DailyBarsAsync> {
  Map<String, double>              _daily     = {};
  Map<String, Map<String, double>> _dailyCats = {};
  List<String>                     _allCats   = [];
  final Set<String>                _selected  = {};

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
      final txns   = await Repo.txns(from: weekFrom);
      final daily  = <String, double>{};
      final catMap = <String, Map<String, double>>{};
      final catSet = <String>{};

      for (var i = 6; i >= 0; i--) {
        final d   = now.subtract(Duration(days: i));
        final key = '${d.day}/${d.month}';
        daily[key]  = 0;
        catMap[key] = {};
      }

      for (final t in txns) {
        if (t['type'] != 'debit') continue;
        final d   = DateTime.fromMillisecondsSinceEpoch(t['timestamp'] as int);
        final key = '${d.day}/${d.month}';
        if (!daily.containsKey(key)) continue;
        final amt = (t['amount'] as num).toDouble();
        final cat = t['category'] as String? ?? 'Misc';
        daily[key] = (daily[key] ?? 0) + amt;
        catMap[key]![cat] = (catMap[key]![cat] ?? 0) + amt;
        catSet.add(cat);
      }

      setState(() {
        _daily     = daily;
        _dailyCats = catMap;
        _allCats   = catSet.toList();
      });
    } catch (_) {}
  }

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        // Category chip row
        if (_allCats.isNotEmpty)
          SingleChildScrollView(
            scrollDirection: Axis.horizontal,
            child: Row(
              children: _allCats.asMap().entries.map((e) {
                final colors = _pieColors();
                final color  = colors[e.key % colors.length];
                final sel    = _selected.contains(e.value);
                return Padding(
                  padding: const EdgeInsets.only(right: 8, bottom: 12),
                  child: _LineChip(
                    label: e.value,
                    color: color,
                    selected: sel,
                    onTap: () => setState(() {
                      if (sel) _selected.remove(e.value);
                      else     _selected.add(e.value);
                    }),
                  ),
                );
              }).toList(),
            ),
          ),
        // Bar chart
        _DailyBars(
          daily:     _daily,
          dailyCats: _dailyCats,
          allCats:   _allCats,
          selected:  _selected,
        ),
      ],
    );
  }
}

class _DailyBars extends StatelessWidget {
  final Map<String, double>              daily;
  final Map<String, Map<String, double>> dailyCats;
  final List<String>                     allCats;
  final Set<String>                      selected;

  const _DailyBars({
    required this.daily,
    required this.dailyCats,
    required this.allCats,
    required this.selected,
  });

  @override
  Widget build(BuildContext context) {
    final showCats   = selected.isNotEmpty;
    final activeCats = showCats ? allCats.where(selected.contains).toList() : <String>[];
    final colors     = _pieColors();

    double max = 0;
    for (final entry in daily.entries) {
      final val = showCats
          ? activeCats.fold(0.0, (s, c) => s + (dailyCats[entry.key]?[c] ?? 0))
          : entry.value;
      if (val > max) max = val;
    }
    if (max == 0) max = 1;

    final days    = ['Mon', 'Tue', 'Wed', 'Thu', 'Fri', 'Sat', 'Sun'];
    final now     = DateTime.now();
    final entries = daily.entries.toList();

    return Container(
      // maxH(80) + label slot(16) + gap(8) + day label(12) + vert padding(16+16) = 148
      height: 148,
      padding: const EdgeInsets.symmetric(horizontal: 16),
      decoration: BoxDecoration(
        color: const Color(0xFF1C1C1E),
        borderRadius: BorderRadius.circular(16),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.end,
        children: entries.asMap().entries.map((e) {
          final idx     = e.key;
          final dayKey  = e.value.key;
          final isToday = idx == entries.length - 1;
          final dayIdx  = (now.weekday - 1 - (6 - idx)) % 7;
          final label   = days[dayIdx.clamp(0, 6)];
          final total   = showCats
              ? activeCats.fold(0.0, (s, c) => s + (dailyCats[dayKey]?[c] ?? 0))
              : daily[dayKey] ?? 0;

          return Expanded(
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 3),
              child: _DailyBarColumn(
                key: ValueKey(dayKey),
                total:      total,
                max:        max,
                dayKey:     dayKey,
                label:      label,
                isToday:    isToday,
                showCats:   showCats,
                activeCats: activeCats,
                allCats:    allCats,
                dailyCats:  dailyCats,
                colors:     colors,
              ),
            ),
          );
        }).toList(),
      ),
    );
  }
}

// Each bar column is stateful so TweenAnimationBuilder has stable identity
// and correctly interpolates from its previous value on every rebuild.
class _DailyBarColumn extends StatefulWidget {
  final double              total;
  final double              max;
  final String              dayKey;
  final String              label;
  final bool                isToday;
  final bool                showCats;
  final List<String>        activeCats;
  final List<String>        allCats;
  final Map<String, Map<String, double>> dailyCats;
  final List<Color>         colors;

  const _DailyBarColumn({
    super.key,
    required this.total,
    required this.max,
    required this.dayKey,
    required this.label,
    required this.isToday,
    required this.showCats,
    required this.activeCats,
    required this.allCats,
    required this.dailyCats,
    required this.colors,
  });

  @override
  State<_DailyBarColumn> createState() => _DailyBarColumnState();
}

class _DailyBarColumnState extends State<_DailyBarColumn> {
  static const maxH  = 80.0;
  static const dur   = Duration(milliseconds: 350);
  static const curve = Curves.easeOutCubic;

  @override
  Widget build(BuildContext context) {
    final targetH = maxH * (widget.total / widget.max).clamp(0.0, 1.0);

    return Column(
      mainAxisAlignment: MainAxisAlignment.end,
      children: [
        // Fixed slot: bar + label live here, clipped so segments never overflow
        ClipRect(
          child: SizedBox(
            height: maxH + 16, // 16px headroom for the floating label
            child: TweenAnimationBuilder<double>(
              tween: Tween(end: targetH),
              duration: dur,
              curve: curve,
              builder: (_, animH, __) {
                return Stack(
                  alignment: Alignment.bottomCenter,
                  children: [
                    // Bar (stacked or single)
                    Positioned(
                      bottom: 0, left: 0, right: 0,
                      child: widget.showCats && widget.activeCats.length > 1
                          ? _buildStacked(animH)
                          : _buildSingle(animH),
                    ),
                    // Amount label tracks bar top
                    if (widget.total > 0)
                      Positioned(
                        bottom: animH + 2,
                        left: 0, right: 0,
                        child: Text(
                          '₹${_fmtShort(widget.total)}',
                          textAlign: TextAlign.center,
                          style: TextStyle(
                            color: Colors.white.withOpacity(0.3),
                            fontSize: 8,
                          ),
                        ),
                      ),
                  ],
                );
              },
            ),
          ),
        ),
        const SizedBox(height: 8),
        Text(widget.label, style: TextStyle(
          color: widget.isToday
              ? Colors.white.withOpacity(0.7)
              : Colors.white.withOpacity(0.25),
          fontSize: 10,
          fontWeight: widget.isToday ? FontWeight.w600 : FontWeight.normal,
        )),
        const SizedBox(height: 16),
      ],
    );
  }

  Widget _buildSingle(double animH) {
    final barColor = (widget.showCats && widget.activeCats.isNotEmpty)
        ? widget.colors[widget.allCats.indexOf(widget.activeCats.first) % widget.colors.length]
        : Colors.white;
    return Container(
      height: animH,
      decoration: BoxDecoration(
        color: widget.isToday
            ? barColor.withOpacity(0.7)
            : barColor.withOpacity(0.25),
        borderRadius: BorderRadius.circular(4),
      ),
    );
  }

  Widget _buildStacked(double animH) {
    // Proportion each segment off the *target* total so ratios stay stable;
    // the whole stack scales via animH.
    return SizedBox(
      width: double.infinity,
      height: animH,
      child: Column(
        mainAxisAlignment: MainAxisAlignment.end,
        children: widget.activeCats.asMap().entries.map((ce) {
          final catAmt = widget.dailyCats[widget.dayKey]?[ce.value] ?? 0;
          final segH   = widget.total > 0
              ? (animH * (catAmt / widget.total)).clamp(0.0, animH)
              : 0.0;
          final catIdx = widget.allCats.indexOf(ce.value);
          final color  = widget.colors[catIdx % widget.colors.length];
          final isTop  = ce.key == 0;
          return SizedBox(
            width: double.infinity,
            height: segH,
            child: DecoratedBox(
              decoration: BoxDecoration(
                color: widget.isToday
                    ? color.withOpacity(0.85)
                    : color.withOpacity(0.55),
                borderRadius: isTop
                    ? const BorderRadius.vertical(top: Radius.circular(4))
                    : BorderRadius.zero,
              ),
            ),
          );
        }).toList(),
      ),
    );
  }
}

// ══════════════════════════════════════════════════════════════════
// PIE CHART
// ══════════════════════════════════════════════════════════════════

class _PieSection extends StatefulWidget {
  final Map<String, double> cats;
  final double total;
  final String? selected;
  final ValueChanged<String> onSelect;

  const _PieSection({super.key, required this.cats, required this.total,
    required this.selected, required this.onSelect});

  @override
  State<_PieSection> createState() => _PieSectionState();
}

class _PieSectionState extends State<_PieSection>
    with SingleTickerProviderStateMixin {
  late AnimationController _ctrl;
  late Animation<double> _anim;

  @override
  void initState() {
    super.initState();
    _ctrl = AnimationController(
        vsync: this, duration: const Duration(milliseconds: 700));
    _anim = CurvedAnimation(parent: _ctrl, curve: Curves.easeOutCubic);
    _ctrl.forward();
  }

  @override
  void didUpdateWidget(_PieSection old) {
    super.didUpdateWidget(old);
    if (old.cats != widget.cats) _ctrl.forward(from: 0);
  }

  @override
  void dispose() {
    _ctrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final colors  = _pieColors();
    final entries = widget.cats.entries.toList();

    return LayoutBuilder(builder: (context, constraints) {
      final canvasW = constraints.maxWidth;
      return Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // ── Donut ──
          GestureDetector(
            behavior: HitTestBehavior.opaque,
            onTapUp: (details) {
              final box = context.findRenderObject() as RenderBox;
              final local = box.globalToLocal(details.globalPosition);
              const donutH = 220.0;
              final cx = canvasW / 2, cy = donutH / 2;
              final dx = local.dx - cx, dy = local.dy - cy;
              final dist = math.sqrt(dx * dx + dy * dy);
              if (dist < 52.0 || dist > 108.0) return;
              var angle = math.atan2(dy, dx) + math.pi / 2;
              if (angle < 0) angle += 2 * math.pi;
              var start = 0.0;
              for (var i = 0; i < entries.length; i++) {
                final sweep = entries[i].value / widget.total * 2 * math.pi;
                if (angle >= start && angle < start + sweep) {
                  widget.onSelect(entries[i].key);
                  return;
                }
                start += sweep;
              }
            },
            child: SizedBox(
              height: 220,
              child: AnimatedBuilder(
                animation: _anim,
                builder: (_, __) => CustomPaint(
                  painter: _PiePainter(
                    cats: widget.cats,
                    total: widget.total,
                    colors: colors,
                    selected: widget.selected,
                    progress: _anim.value,
                    canvasWidth: canvasW,
                  ),
                  size: Size(canvasW, 220),
                  child: Center(
                    child: AnimatedSwitcher(
                      duration: const Duration(milliseconds: 220),
                      child: widget.selected != null
                          ? _PieCenter(
                        key: ValueKey(widget.selected),
                        pct: (widget.cats[widget.selected!] ?? 0) / widget.total,
                      )
                          : const _PieCenterTotal(
                        key: ValueKey('__total__'),
                      ),
                    ),
                  ),
                ),
              ),
            ),
          ),

          const SizedBox(height: 16),

          // ── Legend rows ──
          // FIXED: bar width increased from 72 → 120 (longer, all equal length)
          // FIXED: amount label shifted right via left padding inside its SizedBox
          ...entries.asMap().entries.map((e) {
            final color  = colors[e.key % colors.length];
            final isSel  = widget.selected == e.value.key;
            final isNone = widget.selected == null;
            final pct    = e.value.value / widget.total;

            return GestureDetector(
              behavior: HitTestBehavior.opaque,
              onTap: () => widget.onSelect(e.value.key),
              child: AnimatedOpacity(
                duration: const Duration(milliseconds: 200),
                opacity: (isNone || isSel) ? 1.0 : 0.3,
                child: Padding(
                  padding: const EdgeInsets.symmetric(vertical: 7),
                  child: Row(children: [
                    AnimatedContainer(
                      duration: const Duration(milliseconds: 200),
                      width: isSel ? 10 : 7,
                      height: isSel ? 10 : 7,
                      decoration: BoxDecoration(
                          color: color, shape: BoxShape.circle),
                    ),
                    const SizedBox(width: 10),
                    // Name — always same width so bar stays aligned
                    Expanded(
                      child: Text(e.value.key,
                          style: TextStyle(
                            color: Colors.white.withOpacity(isSel ? 1.0 : 0.65),
                            fontSize: 13,
                            fontWeight: isSel ? FontWeight.w500 : FontWeight.w400,
                          )),
                    ),
                    // Bar — FIXED: width 72 → 120 so bars are visibly longer & equal
                    SizedBox(
                      width: 120,
                      child: ClipRRect(
                        borderRadius: BorderRadius.circular(2),
                        child: LinearProgressIndicator(
                          value: pct,
                          minHeight: 2,
                          backgroundColor: Colors.white.withOpacity(0.06),
                          valueColor: AlwaysStoppedAnimation<Color>(
                              color.withOpacity(isSel ? 0.9 : 0.5)),
                        ),
                      ),
                    ),
                    // FIXED: increased gap from 12 → 20 to shift amount label right
                    const SizedBox(width: 20),
                    // Amount — fixed width, right-aligned
                    SizedBox(
                      width: 64,
                      child: AnimatedSwitcher(
                        duration: const Duration(milliseconds: 180),
                        child: Text(
                          isSel && _fmtExact(e.value.value) != _fmt(e.value.value)
                              ? '₹${_fmtExact(e.value.value)}'
                              : '₹${_fmt(e.value.value)}',
                          key: ValueKey(isSel && _fmtExact(e.value.value) != _fmt(e.value.value)),
                          textAlign: TextAlign.right,
                          style: TextStyle(
                            color: Colors.white.withOpacity(isSel ? 0.85 : 0.4),
                            fontSize: 12,
                            fontWeight: FontWeight.w500,
                          ),
                        ),
                      ),
                    ),
                  ]),
                ),
              ),
            );
          }),
          const SizedBox(height: 8),
        ],
      );
    });
  }
}

class _PieCenter extends StatelessWidget {
  final double pct;
  const _PieCenter({super.key, required this.pct});

  @override
  Widget build(BuildContext context) {
    return Text(
      '${(pct * 100).toStringAsFixed(1)}%',
      style: const TextStyle(
          color: Colors.white, fontSize: 26, fontWeight: FontWeight.w200,
          letterSpacing: -1),
    );
  }
}

class _PieCenterTotal extends StatelessWidget {
  const _PieCenterTotal({super.key});

  @override
  Widget build(BuildContext context) => const SizedBox.shrink();
}

class _PiePainter extends CustomPainter {
  final Map<String, double> cats;
  final double total;
  final List<Color> colors;
  final String? selected;
  final double progress;
  final double canvasWidth;

  _PiePainter({required this.cats, required this.total, required this.colors,
    required this.selected, required this.progress, required this.canvasWidth});

  @override
  void paint(Canvas canvas, Size size) {
    final cx      = canvasWidth / 2;
    final cy      = size.height / 2;
    const outer   = 96.0;
    const inner   = 58.0;
    const expand  = 10.0;
    const gap     = 0.022;
    var   start   = -math.pi / 2;
    final entries = cats.entries.toList();
    final hasSel  = selected != null;

    // Only apply gaps when there are multiple segments; a single segment
    // (or one segment dominating 100%) should be a seamless full ring.
    final isSingle = entries.length == 1;

    for (var i = 0; i < entries.length; i++) {
      final frac      = entries[i].value / total;
      final full      = frac * 2 * math.pi;
      final actualGap = isSingle ? 0.0 : gap;
      final sweep     = (full * progress) - actualGap;
      if (sweep <= 0) { start += full * progress; continue; }

      final color   = colors[i % colors.length];
      final isSel   = selected == entries[i].key;
      final mid     = start + sweep / 2;
      final expand_ = isSel ? expand : 0.0;
      final offX    = math.cos(mid) * expand_;
      final offY    = math.sin(mid) * expand_;
      final r       = isSel ? outer + expand : outer;

      final opacity = hasSel ? (isSel ? 1.0 : 0.28) : 0.88;
      final paint   = Paint()
        ..color = color.withOpacity(opacity)
        ..style  = PaintingStyle.fill;

      // For a full ring (single segment), use addOval+addOval with evenOdd
      // so it's a perfect seamless donut with no path join artifacts.
      if (isSingle) {
        final path = Path()
          ..addOval(Rect.fromCircle(center: Offset(cx + offX, cy + offY), radius: r))
          ..addOval(Rect.fromCircle(center: Offset(cx + offX, cy + offY), radius: inner));
        path.fillType = PathFillType.evenOdd;
        canvas.drawPath(path, paint);
        if (isSel) {
          canvas.drawPath(path,
              Paint()..color = Colors.white.withOpacity(0.07)..style = PaintingStyle.fill);
        }
        start += full * progress;
        continue;
      }

      final path = Path()
        ..moveTo(cx + offX + inner * math.cos(start + actualGap / 2),
            cy + offY + inner * math.sin(start + actualGap / 2))
        ..arcTo(Rect.fromCircle(center: Offset(cx + offX, cy + offY), radius: inner),
            start + actualGap / 2, sweep - actualGap / 2, false)
        ..arcTo(Rect.fromCircle(center: Offset(cx + offX, cy + offY), radius: r),
            start + sweep - actualGap / 2, -(sweep - actualGap / 2), false)
        ..close();

      canvas.drawPath(path, paint);

      if (isSel) {
        canvas.drawPath(path,
            Paint()..color = Colors.white.withOpacity(0.07)..style = PaintingStyle.fill);
      }

      start += full * progress;
    }
  }

  @override
  bool shouldRepaint(_PiePainter old) =>
      old.selected != selected || old.cats != cats || old.progress != progress;
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
    final isUp    = pct > 0;
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

class _EmptyDonut extends StatefulWidget {
  const _EmptyDonut();
  @override
  State<_EmptyDonut> createState() => _EmptyDonutState();
}

class _EmptyDonutState extends State<_EmptyDonut>
    with SingleTickerProviderStateMixin {
  late AnimationController _ctrl;
  late Animation<double> _pulse;

  @override
  void initState() {
    super.initState();
    _ctrl = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 2400),
    )..repeat(reverse: true);
    _pulse = CurvedAnimation(parent: _ctrl, curve: Curves.easeInOut);
  }

  @override
  void dispose() {
    _ctrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      height: 220,
      child: LayoutBuilder(builder: (_, constraints) {
        final canvasW = constraints.maxWidth;
        return AnimatedBuilder(
          animation: _pulse,
          builder: (_, __) => CustomPaint(
            painter: _EmptyDonutPainter(pulse: _pulse.value, canvasWidth: canvasW),
            size: Size(canvasW, 220),
            child: Center(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Icon(Icons.receipt_long_outlined,
                      size: 18,
                      color: Colors.white.withOpacity(0.12 + _pulse.value * 0.06)),
                  const SizedBox(height: 6),
                  Text('No data',
                      style: TextStyle(
                        fontSize: 11,
                        letterSpacing: 0.5,
                        color: Colors.white.withOpacity(0.18 + _pulse.value * 0.08),
                        fontWeight: FontWeight.w400,
                      )),
                ],
              ),
            ),
          ),
        );
      }),
    );
  }
}

class _EmptyDonutPainter extends CustomPainter {
  final double pulse;
  final double canvasWidth;
  const _EmptyDonutPainter({required this.pulse, required this.canvasWidth});

  @override
  void paint(Canvas canvas, Size size) {
    final cx = canvasWidth / 2;   // matches _PiePainter: cx = canvasWidth / 2
    final cy = size.height / 2;   // matches _PiePainter: cy = size.height / 2
    const outer = 96.0, inner = 58.0;
    const mid   = (outer + inner) / 2;
    const thick = outer - inner; // full ring thickness

    // ── Filled ring (very faint, pulses slightly) ──
    final fillOpacity = 0.04 + pulse * 0.02;
    final fillPath = Path()
      ..addOval(Rect.fromCircle(center: Offset(cx, cy), radius: outer))
      ..addOval(Rect.fromCircle(center: Offset(cx, cy), radius: inner));
    fillPath.fillType = PathFillType.evenOdd;
    canvas.drawPath(fillPath,
        Paint()..color = Colors.white.withOpacity(fillOpacity)..style = PaintingStyle.fill);

    // ── Dashed ring on the mid-radius ──
    const dashCount  = 24;
    const dashAngle  = (2 * math.pi) / dashCount;
    const dashFrac   = 0.55; // fraction of each slot that is filled
    final dashPaint  = Paint()
      ..color       = Colors.white.withOpacity(0.10 + pulse * 0.06)
      ..style       = PaintingStyle.stroke
      ..strokeWidth = thick * 0.22
      ..strokeCap   = StrokeCap.round;

    for (var i = 0; i < dashCount; i++) {
      final startAngle = i * dashAngle - math.pi / 2;
      final sweepAngle = dashAngle * dashFrac;
      canvas.drawArc(
        Rect.fromCircle(center: Offset(cx, cy), radius: mid),
        startAngle,
        sweepAngle,
        false,
        dashPaint,
      );
    }

    // ── Single bright arc accent (about 1/6 of the ring) that pulses position ──
    final accentStart = -math.pi / 2 + pulse * math.pi * 0.4;
    const accentSweep = math.pi / 3.2;
    canvas.drawArc(
      Rect.fromCircle(center: Offset(cx, cy), radius: mid),
      accentStart,
      accentSweep,
      false,
      Paint()
        ..color       = Colors.white.withOpacity(0.20 + pulse * 0.12)
        ..style       = PaintingStyle.stroke
        ..strokeWidth = thick * 0.28
        ..strokeCap   = StrokeCap.round,
    );
  }

  @override
  bool shouldRepaint(_EmptyDonutPainter old) => old.pulse != pulse || old.canvasWidth != canvasWidth;
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
  if (a >= 100000) {
    final v = a / 100000;
    return '${v == v.truncate() ? v.toStringAsFixed(0) : v.toStringAsFixed(1)}L';
  }
  if (a >= 1000) {
    final v = a / 1000;
    return '${v == v.truncate() ? v.toStringAsFixed(0) : v.toStringAsFixed(1)}K';
  }
  return a.toStringAsFixed(0);
}

// Exact amount formatted with commas: 2,340 or 1,23,456
String _fmtExact(double a) {
  final n = a.toStringAsFixed(0);
  if (n.length <= 3) return n;
  // Indian numbering: last 3 then groups of 2
  final rev = n.split('').reversed.toList();
  final buf = <String>[];
  for (var i = 0; i < rev.length; i++) {
    if (i == 3 || (i > 3 && (i - 3) % 2 == 0)) buf.add(',');
    buf.add(rev[i]);
  }
  return buf.reversed.join();
}

String _fmtLabel(double a) {
  if (a >= 100000) {
    final v = a / 100000;
    return '${v == v.truncate() ? v.toStringAsFixed(0) : v.toStringAsFixed(1)}L';
  }
  if (a >= 1000) {
    final v = a / 1000;
    return '${v == v.truncate() ? v.toStringAsFixed(0) : v.toStringAsFixed(1)}K';
  }
  return a.toStringAsFixed(0);
}

String _fmtShort(double a) {
  if (a >= 1000) {
    final v = a / 1000;
    return '${v == v.truncate() ? v.toStringAsFixed(0) : v.toStringAsFixed(1)}K';
  }
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