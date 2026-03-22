import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'dart:math' as math;

void main() async {
  WidgetsFlutterBinding.ensureInitialized();
  // Pre-load categories from DB so CategoryStore.current is never empty
  // by the time any widget renders.
  await CategoryStore.instance.get();
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
      home: const PermissionScreen(),
    );
  }
}

// ══════════════════════════════════════════════════════════════════
// APP STORE — single source of truth for all data
// ══════════════════════════════════════════════════════════════════

class AppStore extends ChangeNotifier {
  // ── Home screen data ──────────────────────────────────────────
  List<Map<String, dynamic>> txns    = [];
  List<Map<String, dynamic>> pending = [];
  Map<String, double>        totals  = {};

  // Pagination
  static const int pageSize = 20;
  int  _txnOffset    = 0;
  bool hasMore       = false;
  bool loadingMore   = false;

  // Total unfiltered confirmed txn count — used for new-user scan button check
  int totalTxnCount  = 0;

  // Increments on every refresh — used as AnimatedList key to force clean rebuild
  int txnGeneration = 0;

  // Home filter state (owned here so both screens can read spent total)
  String    range     = 'This Month';
  DateTime? customFrom;
  DateTime? customTo;
  String?   selectedCategory;

  // ── Analytics data ────────────────────────────────────────────
  List<_MonthData>  allMonths     = [];   // full 12-month history
  List<_WeekData>   weeks         = [];
  Map<String, Map<String, double>> dailyData = {};
  int               monthsWithData = 0;
  Set<String>       allCategories  = {};

  bool loading = true;

  // ── Date range helpers ────────────────────────────────────────
  (String?, String?) get dateRange {
    final now = DateTime.now();
    return switch (range) {
      'This Week'  => (DateTime(now.year, now.month, now.day - now.weekday + 1)
          .millisecondsSinceEpoch.toString(), null),
      'This Month' => (DateTime(now.year, now.month, 1)
          .millisecondsSinceEpoch.toString(), null),
      'Last Month' => (
      DateTime(now.year, now.month - 1, 1).millisecondsSinceEpoch.toString(),
      DateTime(now.year, now.month, 1).millisecondsSinceEpoch.toString(),
      ),
      'Custom' => (
      customFrom?.millisecondsSinceEpoch.toString(),
      customTo != null
          ? DateTime(customTo!.year, customTo!.month, customTo!.day + 1)
          .millisecondsSinceEpoch.toString()
          : null,
      ),
      _ => (null, null),
    };
  }

  String get rangeLabel {
    if (range == 'Custom' && customFrom != null) {
      final f = customFrom!;
      final t = customTo ?? customFrom!;
      const mo = ['Jan','Feb','Mar','Apr','May','Jun',
        'Jul','Aug','Sep','Oct','Nov','Dec'];
      if (f.year == t.year && f.month == t.month && f.day == t.day)
        return '${f.day} ${mo[f.month - 1]}';
      if (f.year == t.year)
        return '${f.day} ${mo[f.month - 1]} \u2013 ${t.day} ${mo[t.month - 1]}';
      return '${f.day} ${mo[f.month - 1]} ${f.year} \u2013 ${t.day} ${mo[t.month - 1]} ${t.year}';
    }
    return range;
  }

  double get spent {
    final debits  = txns.where((t) => t['type'] == 'debit')
        .fold(0.0, (s, t) => s + (t['amount'] as num).toDouble());
    final credits = txns.where((t) => t['type'] == 'credit')
        .fold(0.0, (s, t) => s + (t['amount'] as num).toDouble());
    return math.max(0.0, debits - credits);
  }

  // ── Refresh — fetches everything at once ─────────────────────
  Future<void> refresh({bool initial = false, bool homeOnly = false}) async {
    if (initial) {
      loading = true;
      notifyListeners();
    }

    final now = DateTime.now();
    final (from, to) = dateRange;
    _txnOffset = 0; // reset pagination on refresh

    try {
      final tFuture     = Repo.txns(
          from: from, to: to, category: selectedCategory,
          limit: pageSize, offset: 0);
      final pFuture     = Repo.txns(status: 'pending', limit: 200, offset: 0);
      final cFuture     = Repo.totals(from: from, to: to);
      // Unfiltered — only needs 4 rows to decide new-user scan button visibility
      final totalFuture = Repo.txns(limit: 4, offset: 0);

      if (!homeOnly) {
        final List<_MonthData> months = [];
        final cats = <String>{};
        for (var i = 11; i >= 0; i--) {
          final rawM = now.month - i;
          final y = rawM <= 0 ? now.year - 1 : now.year;
          final m = rawM <= 0 ? rawM + 12 : rawM;
          final mFrom = DateTime(y, m, 1).millisecondsSinceEpoch.toString();
          final mTo   = DateTime(y, m + 1, 1).millisecondsSinceEpoch.toString();
          final mc    = await Repo.totals(from: mFrom, to: mTo);
          cats.addAll(mc.keys);
          const moLabel = ['Jan','Feb','Mar','Apr','May','Jun',
            'Jul','Aug','Sep','Oct','Nov','Dec'];
          months.add(_MonthData(label: moLabel[m - 1], cats: mc));
        }
        final wFuture = Repo.weeklyTotals(now.year, now.month);
        final dFuture = Repo.dailyTotals(
            DateTime(now.year, now.month, now.day - 6)
                .millisecondsSinceEpoch.toString());
        final rawW = await wFuture;
        final rawD = await dFuture;
        allMonths      = months;
        weeks          = [1,2,3,4].map((wk) =>
            _WeekData(label: 'W$wk', cats: rawW[wk] ?? {})).toList();
        dailyData      = rawD;
        monthsWithData = months.where((m) => m.total > 0).length;
        allCategories  = cats;
      }

      final t = await tFuture;
      final p = await pFuture;
      final c = await cFuture;
      final total = await totalFuture;

      txns          = t;
      pending       = p;
      totals        = c;
      totalTxnCount = total.length;
      hasMore       = t.length == pageSize;
      _txnOffset    = t.length;
      txnGeneration++;
      loading       = false;
      notifyListeners();
    } catch (_) {
      loading = false;
      notifyListeners();
    }
  }

  // Load next page of transactions and append
  Future<void> loadMore() async {
    if (loadingMore || !hasMore) return;
    loadingMore = true;
    notifyListeners();
    final (from, to) = dateRange;
    try {
      final t = await Repo.txns(
          from: from, to: to, category: selectedCategory,
          limit: pageSize, offset: _txnOffset);
      txns       = [...txns, ...t];
      hasMore    = t.length == pageSize;
      _txnOffset += t.length;
    } catch (_) {}
    loadingMore = false;
    notifyListeners();
  }

  // Filtered month list for analytics view picker
  List<_MonthData> monthsForView(String view) {
    List<_MonthData> pool;
    switch (view) {
      case '3':  pool = allMonths.sublist(9);  break;
      case '6':  pool = allMonths.sublist(6);  break;
      case '12': pool = allMonths;             break;
      default:   pool = allMonths.isEmpty ? [] : [allMonths.last]; break;
    }
    final first = pool.indexWhere((m) => m.total > 0);
    return first < 0 ? pool : pool.sublist(first);
  }
}

// ── Provider ─────────────────────────────────────────────────────

class AppStoreProvider extends InheritedNotifier<AppStore> {
  const AppStoreProvider({super.key, required AppStore store, required super.child})
      : super(notifier: store);

  static AppStore of(BuildContext context) =>
      context.dependOnInheritedWidgetOfExactType<AppStoreProvider>()!.notifier!;
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
// ROOT SCREEN
// ══════════════════════════════════════════════════════════════════

class RootScreen extends StatefulWidget {
  const RootScreen({super.key});
  @override
  State<RootScreen> createState() => _RootScreenState();
}

class _RootScreenState extends State<RootScreen> with WidgetsBindingObserver {
  final _store = AppStore();
  int _tab = 0;

  static const _eventCh = MethodChannel('com.hisaab.app/events');
  AppLifecycleState? _lastLifecycle;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _eventCh.setMethodCallHandler((call) async {
      if (call.method == 'txn_saved') _store.refresh();
    });
    _store.refresh(initial: true);
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _store.dispose();
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed &&
        _lastLifecycle == AppLifecycleState.paused) {
      _store.refresh();
    }
    _lastLifecycle = state;
  }

  @override
  Widget build(BuildContext context) {
    return AppStoreProvider(
      store: _store,
      child: Scaffold(
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
    String status = 'confirmed',
    int limit = 20, int offset = 0,
  }) async {
    final r = await _ch.invokeMethod<List>('getTransactions', {
      'from': from, 'to': to, 'category': category,
      'status': status, 'limit': limit, 'offset': offset,
    });
    return r?.map((e) => Map<String, dynamic>.from(e as Map)).toList() ?? [];
  }

  static Future<Map<String, double>> totals({String? from, String? to}) async {
    final r = await _ch.invokeMethod<Map>('getCategoryTotals', {'from': from, 'to': to});
    return r?.map((k, v) => MapEntry(k.toString(), (v as num).toDouble())) ?? {};
  }

  static Future<Map<int, Map<String, double>>> weeklyTotals(int year, int month) async {
    final r = await _ch.invokeMethod<Map>('getWeeklyTotals', {'year': year, 'month': month});
    if (r == null) return {};
    return r.map((k, v) {
      final cats = (v as Map).map((ck, cv) =>
          MapEntry(ck.toString(), (cv as num).toDouble()));
      return MapEntry(int.parse(k.toString()), cats);
    });
  }

  static Future<Map<String, Map<String, double>>> dailyTotals(String from) async {
    final r = await _ch.invokeMethod<Map>('getDailyTotals', {'from': from});
    if (r == null) return {};
    return r.map((k, v) {
      final cats = (v as Map).map((ck, cv) =>
          MapEntry(ck.toString(), (cv as num).toDouble()));
      return MapEntry(k.toString(), cats);
    });
  }

  static Future<Map<String, dynamic>> saveCash({
    required double amount,
    required String merchantName,
    required String category,
    required String type,
  }) async {
    final r = await _ch.invokeMethod<Map>('saveCashTransaction', {
      'amount': amount,
      'merchant_name': merchantName,
      'category': category,
      'type': type,
    });
    return r != null ? Map<String, dynamic>.from(r) : {};
  }

  static Future<void> confirmTxn({
    required int id,
    required String payeeKey,
    required String merchantName,
    required String category,
    String? linkedPayeeKey,
  }) async {
    await _ch.invokeMethod('confirmTransaction', {
      'id': id,
      'payee_key': payeeKey,
      'merchant_name': merchantName,
      'category': category,
      'linked_payee_key': linkedPayeeKey,
    });
  }

  static Future<void> deleteTxn(int id) async {
    await _ch.invokeMethod('deleteTransaction', {'id': id});
  }

  static Future<void> updateCategory(int id, String category) async {
    await _ch.invokeMethod('updateCategory', {'id': id, 'category': category});
  }

  static Future<void> updateVendorCategory(String payeeKey, String category) async {
    await _ch.invokeMethod('updateVendorCategory', {
      'payee_key': payeeKey,
      'category': category,
    });
  }

  /// Returns categories sorted by usage frequency (most used first).
  static Future<List<String>> categoryFrequency() async {
    final r = await _ch.invokeMethod<List>('getCategoryFrequency');
    return r?.map((e) => e.toString()).toList() ?? [];
  }

  static Future<void> addUserCategory(String name) async {
    await _ch.invokeMethod('addUserCategory', {'name': name});
  }

  static Future<Map<String, dynamic>> scanInbox(String fromTs) async {
    final r = await _ch.invokeMethod<Map>('scanInbox', {'from': fromTs});
    return r != null ? Map<String, dynamic>.from(r) : {};
  }

  static Future<void> saveScanGroup({
    required String payeeKey,
    required String name,
    required String category,
    required List<Map<String, dynamic>> txns,
  }) async {
    await _ch.invokeMethod('saveScanGroup', {
      'payee_key': payeeKey,
      'name':      name,
      'category':  category,
      'txns':      txns,
    });
  }
}

// ══════════════════════════════════════════════════════════════════
// CATEGORY STORE — single source of truth for categories
// ══════════════════════════════════════════════════════════════════

class CategoryStore {
  CategoryStore._();
  static final CategoryStore instance = CategoryStore._();

  // In-memory cache of the DB result. Null = not yet loaded.
  List<String>? _cats;

  /// Returns the full category list from DB (frequency-sorted, defaults +
  /// user cats always present, Misc always last).
  Future<List<String>> get() async {
    if (_cats != null) return List<String>.from(_cats!);
    _cats = await Repo.categoryFrequency();
    return List<String>.from(_cats!);
  }

  /// Synchronous read — returns empty list if not yet loaded.
  /// Callers must handle the empty case; do not add a fallback here.
  List<String> get current => _cats != null ? List<String>.from(_cats!) : [];

  /// Persist a user-typed category to DB and update the cache optimistically.
  /// The DB write is async but errors are surfaced via the returned Future —
  /// callers that can await should do so; UI callbacks can call unawaited().
  Future<void> add(String cat) async {
    cat = cat.trim();
    if (cat.isEmpty) return;
    // Optimistically insert into cache so UI reflects change immediately
    if (_cats != null && !_cats!.contains(cat)) {
      final miscIdx = _cats!.indexOf('Misc');
      if (miscIdx >= 0) _cats!.insert(miscIdx, cat);
      else _cats!.add(cat);
    }
    // Persist to DB — single source of truth
    await Repo.addUserCategory(cat);
  }

  /// Ensure a category is visible in the current session cache without
  /// persisting (used for old/rare txn categories that already exist in DB
  /// but may not appear in the top frequency list yet).
  void ensure(String cat) {
    cat = cat.trim();
    if (cat.isEmpty || _cats == null) return;
    if (_cats!.contains(cat)) return;
    final miscIdx = _cats!.indexOf('Misc');
    if (miscIdx >= 0) _cats!.insert(miscIdx, cat);
    else _cats!.add(cat);
  }

  /// Invalidate so next get() re-fetches from DB.
  void invalidate() => _cats = null;
}


// ══════════════════════════════════════════════════════════════════
// HOME SCREEN
// ══════════════════════════════════════════════════════════════════

class HomeScreen extends StatefulWidget {
  const HomeScreen({super.key});
  @override
  State<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends State<HomeScreen>
    with SingleTickerProviderStateMixin {
  int?  _expandedTxnId;
  bool  _showPie = true;

  late TabController  _tabCtrl;
  late PageController _pageCtrl;

  final _ranges = ['This Week', 'This Month', 'Last Month', 'All Time', 'Custom'];

  @override
  void initState() {
    super.initState();
    _tabCtrl  = TabController(length: 2, vsync: this);
    _pageCtrl = PageController();
    _tabCtrl.addListener(() {
      if (_tabCtrl.indexIsChanging) {
        _pageCtrl.animateToPage(_tabCtrl.index,
            duration: const Duration(milliseconds: 300), curve: Curves.easeInOut);
      }
    });
  }

  @override
  void dispose() {
    _tabCtrl.dispose();
    _pageCtrl.dispose();
    super.dispose();
  }

  void _toggleCategory(String cat) {
    final store = AppStoreProvider.of(context);
    store.selectedCategory = store.selectedCategory == cat ? null : cat;
    _expandedTxnId = null;
    store.refresh();
  }

  void _toggleTxn(int id) =>
      setState(() => _expandedTxnId = _expandedTxnId == id ? null : id);

  Future<void> _deleteTxn(int id, List<Map<String, dynamic>> txns) async {
    await Repo.deleteTxn(id);
    AppStoreProvider.of(context).refresh(homeOnly: true);
  }

  void _showCashSheet(BuildContext context) {
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: const Color(0xFF141414),
      shape: const RoundedRectangleBorder(
          borderRadius: BorderRadius.vertical(top: Radius.circular(22))),
      builder: (ctx) => _CashEntrySheet(
          onSaved: () => AppStoreProvider.of(context).refresh()),
    );
  }

  @override
  Widget build(BuildContext context) {
    final store   = AppStoreProvider.of(context);
    final txns    = store.txns;
    final pending = store.pending;
    final totals  = store.totals;
    final total   = totals.values.fold(0.0, (a, b) => a + b);

    return Scaffold(
      backgroundColor: const Color(0xFF0A0A0A),
      floatingActionButton: (!store.loading && store.totalTxnCount < 4)
          ? FloatingActionButton(
        onPressed: () => _showScanSheet(context),
        backgroundColor: const Color(0xFF1C1C1E),
        elevation: 0,
        shape: const CircleBorder(),
        child: Icon(Icons.manage_search,
            color: Colors.white.withOpacity(0.7), size: 22),
      )
          : null,
      body: SafeArea(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // ── Header ──
            Padding(
              padding: const EdgeInsets.fromLTRB(24, 32, 24, 0),
              child: Row(children: [
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
                      size: 15, color: Colors.white.withOpacity(0.4),
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
                      Text(store.rangeLabel, style: TextStyle(fontSize: 12,
                          color: Colors.white.withOpacity(0.5), letterSpacing: 0.2)),
                      const SizedBox(width: 4),
                      Icon(Icons.expand_more, size: 14,
                          color: Colors.white.withOpacity(0.3)),
                    ]),
                  ),
                ),
              ]),
            ),
            // ── Total ──
            if (!store.loading)
              Padding(
                padding: const EdgeInsets.fromLTRB(24, 20, 24, 0),
                child: Text(
                  totals.isNotEmpty ? '₹${_fmt(store.spent)}' : '—',
                  style: TextStyle(
                      fontSize: 40, fontWeight: FontWeight.w200,
                      color: totals.isNotEmpty
                          ? Colors.white : Colors.white.withOpacity(0.15),
                      letterSpacing: -1.5),
                ),
              ),
            // ── Chart ──
            if (!store.loading)
              Padding(
                padding: const EdgeInsets.fromLTRB(24, 12, 24, 0),
                child: _showPie
                    ? totals.isNotEmpty
                    ? _PieSection(cats: totals, total: total,
                    selected: store.selectedCategory, onSelect: _toggleCategory)
                    : const _EmptyDonut()
                    : totals.isNotEmpty
                    ? _CatBars(cats: totals, total: total,
                    selected: store.selectedCategory, onSelect: _toggleCategory)
                    : const SizedBox.shrink(),
              ),
            // ── Tabs + Cash ──
            if (!store.loading) ...[
              Padding(
                padding: const EdgeInsets.fromLTRB(24, 24, 24, 0),
                child: Row(children: [
                  _TabPill(label: 'Recent',  index: 0, ctrl: _tabCtrl),
                  const SizedBox(width: 8),
                  _TabPill(label: 'Pending', index: 1, ctrl: _tabCtrl,
                      badge: pending.length),
                  const Spacer(),
                  GestureDetector(
                    onTap: () => _showCashSheet(context),
                    child: Container(
                      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 7),
                      decoration: BoxDecoration(
                        border: Border.all(color: Colors.white.withOpacity(0.1)),
                        borderRadius: BorderRadius.circular(20),
                      ),
                      child: Row(mainAxisSize: MainAxisSize.min, children: [
                        Icon(Icons.add, size: 12,
                            color: Colors.white.withOpacity(0.4)),
                        const SizedBox(width: 4),
                        Text('Cash', style: TextStyle(
                            fontSize: 12, color: Colors.white.withOpacity(0.4))),
                      ]),
                    ),
                  ),
                ]),
              ),
              const SizedBox(height: 12),
            ],
            // ── Lists ──
            Expanded(
              child: store.loading
                  ? const Center(child: CircularProgressIndicator(
                  color: Colors.white24, strokeWidth: 1))
                  : PageView(
                controller: _pageCtrl,
                onPageChanged: (i) {
                  if (_tabCtrl.index != i) _tabCtrl.animateTo(i);
                },
                children: [
                  // Recent
                  txns.isEmpty
                      ? Center(child: Text('No transactions',
                      style: TextStyle(
                          color: Colors.white.withOpacity(0.2), fontSize: 15)))
                      : AnimatedList(
                    key: ValueKey(store.txnGeneration),
                    padding: EdgeInsets.only(
                        bottom: store.hasMore ? 0 : 80),
                    initialItemCount: txns.length + (store.hasMore ? 1 : 0),
                    itemBuilder: (_, i, anim) {
                      // Load more button as last item
                      if (i == txns.length) {
                        return Padding(
                          padding: const EdgeInsets.fromLTRB(24, 8, 24, 80),
                          child: GestureDetector(
                            onTap: () => store.loadMore(),
                            child: Container(
                              width: double.infinity,
                              padding: const EdgeInsets.symmetric(vertical: 14),
                              decoration: BoxDecoration(
                                border: Border.all(
                                    color: Colors.white.withOpacity(0.08)),
                                borderRadius: BorderRadius.circular(12),
                              ),
                              child: Center(
                                child: store.loadingMore
                                    ? SizedBox(width: 14, height: 14,
                                    child: CircularProgressIndicator(
                                        strokeWidth: 1.5,
                                        color: Colors.white.withOpacity(0.3)))
                                    : Text('Load more',
                                    style: TextStyle(
                                        color: Colors.white.withOpacity(0.35),
                                        fontSize: 13)),
                              ),
                            ),
                          ),
                        );
                      }
                      if (i >= txns.length) return const SizedBox.shrink();
                      final txn = txns[i];
                      final id  = txn['id'] as int;
                      return SlideTransition(
                        position: Tween<Offset>(
                          begin: const Offset(0, 0.2), end: Offset.zero,
                        ).animate(CurvedAnimation(
                            parent: anim, curve: Curves.easeOutQuart)),
                        child: FadeTransition(
                          opacity: CurvedAnimation(
                              parent: anim, curve: Curves.easeOut),
                          child: _TxnTile(
                            txn: txn,
                            expanded: _expandedTxnId == id,
                            onTap: () => _toggleTxn(id),
                            onDeleted: () => _deleteTxn(id, txns),
                            onCategoryChanged: () =>
                                AppStoreProvider.of(context).refresh(),
                          ),
                        ),
                      );
                    },
                  ),
                  // Pending
                  pending.isEmpty
                      ? Center(child: Text('No pending items',
                      style: TextStyle(
                          color: Colors.white.withOpacity(0.2), fontSize: 15)))
                      : ListView.builder(
                    padding: const EdgeInsets.fromLTRB(24, 4, 24, 80),
                    itemCount: pending.length,
                    itemBuilder: (_, i) => _PendingTile(
                      txn: pending[i],
                      onResolved: () => AppStoreProvider.of(context).refresh(homeOnly: true),
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  void _showScanSheet(BuildContext context) {
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: const Color(0xFF141414),
      shape: const RoundedRectangleBorder(
          borderRadius: BorderRadius.vertical(top: Radius.circular(22))),
      builder: (ctx) => _ScanSheet(
        onDone: () => AppStoreProvider.of(context).refresh(),
      ),
    );
  }

  void _showRangePicker(BuildContext context) {
    final store = AppStoreProvider.of(context);
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
            final isCurrent = r == store.range;
            return GestureDetector(
              onTap: () async {
                if (r == 'Custom') {
                  Navigator.pop(sheetCtx);
                  final now = DateTime.now();
                  final picked = await showDialog<DateTimeRange>(
                    context: context,
                    builder: (_) => _DateRangeDialog(
                      initial: (store.customFrom != null && store.customTo != null)
                          ? DateTimeRange(
                          start: store.customFrom!, end: store.customTo!)
                          : DateTimeRange(
                          start: DateTime(now.year, now.month, 1), end: now),
                      firstDate: DateTime(now.year - 3),
                      lastDate: now,
                    ),
                  );
                  if (picked == null) return;
                  store.range      = 'Custom';
                  store.customFrom = picked.start;
                  store.customTo   = picked.end;
                  store.refresh();
                } else {
                  store.range = r;
                  Navigator.pop(sheetCtx);
                  store.refresh();
                }
              },
              child: Container(
                width: double.infinity,
                padding: const EdgeInsets.symmetric(vertical: 16),
                decoration: BoxDecoration(border: Border(bottom: BorderSide(
                    color: Colors.white.withOpacity(0.06)))),
                child: Row(children: [
                  Expanded(child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(r, style: TextStyle(
                          color: isCurrent
                              ? Colors.white : Colors.white.withOpacity(0.45),
                          fontSize: 16,
                          fontWeight: isCurrent
                              ? FontWeight.w500 : FontWeight.normal)),
                      if (r == 'Custom' && store.range == 'Custom' &&
                          store.customFrom != null) ...[
                        const SizedBox(height: 3),
                        Text(store.rangeLabel,
                            style: TextStyle(
                                color: Colors.white.withOpacity(0.35),
                                fontSize: 12)),
                      ],
                    ],
                  )),
                  if (isCurrent)
                    const Icon(Icons.check, color: Colors.white, size: 16)
                  else if (r == 'Custom')
                    Icon(Icons.calendar_today_outlined,
                        size: 14, color: Colors.white.withOpacity(0.25)),
                ]),
              ),
            );
          }),
        ]),
      ),
    );
  }
}


// ── Tab pill widget ──────────────────────────────────────────────

class _TabPill extends StatelessWidget {
  final String label;
  final int index;
  final TabController ctrl;
  final int badge;
  const _TabPill({required this.label, required this.index,
    required this.ctrl, this.badge = 0});

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: ctrl,
      builder: (_, __) {
        final selected = ctrl.index == index;
        return GestureDetector(
          onTap: () => ctrl.animateTo(index),
          child: AnimatedContainer(
            duration: const Duration(milliseconds: 200),
            padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 7),
            decoration: BoxDecoration(
              color: selected ? Colors.white.withOpacity(0.09) : Colors.transparent,
              borderRadius: BorderRadius.circular(20),
              border: Border.all(
                color: selected
                    ? Colors.white.withOpacity(0.2)
                    : Colors.white.withOpacity(0.07),
              ),
            ),
            child: Row(mainAxisSize: MainAxisSize.min, children: [
              Text(label, style: TextStyle(
                  fontSize: 12,
                  color: Colors.white.withOpacity(selected ? 0.85 : 0.35),
                  fontWeight: selected ? FontWeight.w500 : FontWeight.normal,
                  letterSpacing: 0.2)),
              if (badge > 0) ...[
                const SizedBox(width: 6),
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                  decoration: BoxDecoration(
                    color: const Color(0xFFFF9F0A).withOpacity(0.18),
                    borderRadius: BorderRadius.circular(10),
                  ),
                  child: Text('$badge', style: const TextStyle(
                      fontSize: 10, color: Color(0xFFFF9F0A),
                      fontWeight: FontWeight.w600)),
                ),
              ],
            ]),
          ),
        );
      },
    );
  }
}

// ══════════════════════════════════════════════════════════════════
// PENDING TILE — inline resolve UI
// ══════════════════════════════════════════════════════════════════

class _PendingTile extends StatefulWidget {
  final Map<String, dynamic> txn;
  final VoidCallback onResolved;
  const _PendingTile({required this.txn, required this.onResolved});

  @override
  State<_PendingTile> createState() => _PendingTileState();
}

class _PendingTileState extends State<_PendingTile> {
  bool _expanded = false;
  final _nameCtrl = TextEditingController();
  String _selectedCat = 'Misc';
  bool _saving = false;

  List<String> _cats = [];

  @override
  void initState() {
    super.initState();
    _nameCtrl.text = widget.txn['merchant_name'] as String? ?? '';
    final existing = widget.txn['category'] as String? ?? '';
    _loadCats(existing);
  }

  Future<void> _loadCats(String existing) async {
    if (existing.isNotEmpty && existing != 'Misc') {
      CategoryStore.instance.ensure(existing);
    }
    final cats = await CategoryStore.instance.get();
    if (!mounted) return;
    setState(() {
      _cats = cats;
      if (existing.isNotEmpty && existing != 'Misc') {
        _selectedCat = existing;
      } else {
        _selectedCat = _cats.isNotEmpty ? _cats.first : 'Misc';
      }
    });
  }

  @override
  void dispose() {
    _nameCtrl.dispose();
    super.dispose();
  }

  Future<void> _save() async {
    final name = _nameCtrl.text.trim();
    if (name.isEmpty) return;
    setState(() => _saving = true);
    await Repo.confirmTxn(
      id: widget.txn['id'] as int,
      payeeKey: widget.txn['payee_key'] as String,
      merchantName: name,
      category: _selectedCat,
    );
    CategoryStore.instance.invalidate();
    widget.onResolved();
  }

  Future<void> _dismiss() async {
    final ok = await showDialog<bool>(
      context: context,
      barrierColor: Colors.black.withOpacity(0.6),
      builder: (_) => Dialog(
        backgroundColor: Colors.transparent,
        elevation: 0,
        child: Container(
          padding: const EdgeInsets.all(24),
          decoration: BoxDecoration(
            color: const Color(0xFF1C1C1E),
            borderRadius: BorderRadius.circular(20),
            border: Border.all(color: Colors.white.withOpacity(0.06)),
          ),
          child: Column(mainAxisSize: MainAxisSize.min, children: [
            Container(
              width: 48, height: 48,
              decoration: BoxDecoration(
                color: const Color(0xFFFF453A).withOpacity(0.1),
                shape: BoxShape.circle,
              ),
              child: const Icon(Icons.delete_outline,
                  color: Color(0xFFFF453A), size: 22),
            ),
            const SizedBox(height: 16),
            const Text('Dismiss transaction',
                style: TextStyle(color: Colors.white, fontSize: 16,
                    fontWeight: FontWeight.w500)),
            const SizedBox(height: 8),
            Text("This can't be undone.",
                textAlign: TextAlign.center,
                style: TextStyle(color: Colors.white.withOpacity(0.35),
                    fontSize: 13, height: 1.4)),
            const SizedBox(height: 24),
            Row(children: [
              Expanded(
                child: GestureDetector(
                  onTap: () => Navigator.pop(_, false),
                  child: Container(
                    padding: const EdgeInsets.symmetric(vertical: 13),
                    decoration: BoxDecoration(
                      color: Colors.white.withOpacity(0.06),
                      borderRadius: BorderRadius.circular(12),
                    ),
                    child: Center(child: Text('Cancel',
                        style: TextStyle(
                            color: Colors.white.withOpacity(0.5),
                            fontSize: 14))),
                  ),
                ),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: GestureDetector(
                  onTap: () => Navigator.pop(_, true),
                  child: Container(
                    padding: const EdgeInsets.symmetric(vertical: 13),
                    decoration: BoxDecoration(
                      color: const Color(0xFFFF453A).withOpacity(0.12),
                      borderRadius: BorderRadius.circular(12),
                      border: Border.all(
                          color: const Color(0xFFFF453A).withOpacity(0.3)),
                    ),
                    child: const Center(child: Text('Dismiss',
                        style: TextStyle(color: Color(0xFFFF453A),
                            fontSize: 14, fontWeight: FontWeight.w500))),
                  ),
                ),
              ),
            ]),
          ]),
        ),
      ),
    );
    if (ok == true) {
      await Repo.deleteTxn(widget.txn['id'] as int);
      widget.onResolved();
    }
  }

  @override
  Widget build(BuildContext context) {
    final isDebit = widget.txn['type'] == 'debit';
    final amount  = (widget.txn['amount'] as num).toDouble();
    final date    = DateTime.fromMillisecondsSinceEpoch(widget.txn['timestamp'] as int);
    final payeeKey = widget.txn['payee_key'] as String? ?? '';

    return Container(
      margin: const EdgeInsets.only(bottom: 10),
      decoration: BoxDecoration(
        color: const Color(0xFF141414),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: const Color(0xFFFF9F0A).withOpacity(0.12)),
      ),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        // Header row
        GestureDetector(
          onTap: () => setState(() => _expanded = !_expanded),
          child: Padding(
            padding: const EdgeInsets.fromLTRB(16, 14, 16, 14),
            child: Row(children: [
              Container(
                width: 34, height: 34,
                decoration: BoxDecoration(
                  color: const Color(0xFFFF9F0A).withOpacity(0.1),
                  borderRadius: BorderRadius.circular(10),
                ),
                child: Icon(Icons.schedule_outlined,
                    size: 16, color: const Color(0xFFFF9F0A).withOpacity(0.7)),
              ),
              const SizedBox(width: 12),
              Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                Text(
                  payeeKey.length > 28 ? '${payeeKey.substring(0, 28)}…' : payeeKey,
                  style: TextStyle(
                      color: Colors.white.withOpacity(0.7), fontSize: 13),
                ),
                const SizedBox(height: 2),
                Text(_fmtDate(date), style: TextStyle(
                    color: Colors.white.withOpacity(0.25), fontSize: 11)),
              ])),
              Text('${isDebit ? '−' : '+'}₹${_fmt(amount)}',
                  style: TextStyle(
                    color: isDebit
                        ? const Color(0xFFFF453A)
                        : const Color(0xFF30D158),
                    fontSize: 14, fontWeight: FontWeight.w500,
                  )),
              const SizedBox(width: 8),
              Icon(
                _expanded ? Icons.keyboard_arrow_up : Icons.keyboard_arrow_down,
                size: 18, color: Colors.white.withOpacity(0.25),
              ),
            ]),
          ),
        ),

        // Expandable resolve form
        ClipRect(
          child: AnimatedAlign(
            duration: const Duration(milliseconds: 280),
            curve: Curves.easeInOutCubic,
            alignment: Alignment.topCenter,
            heightFactor: _expanded ? 1.0 : 0.0,
            child: Padding(
              padding: const EdgeInsets.fromLTRB(16, 0, 16, 16),
              child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                // Name field
                TextField(
                  controller: _nameCtrl,
                  style: const TextStyle(color: Colors.white, fontSize: 14),
                  decoration: InputDecoration(
                    hintText: 'Merchant name',
                    hintStyle: TextStyle(color: Colors.white.withOpacity(0.2),
                        fontSize: 14),
                    filled: true,
                    fillColor: const Color(0xFF1C1C1E),
                    border: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(10),
                      borderSide: BorderSide.none,
                    ),
                    contentPadding: const EdgeInsets.symmetric(
                        horizontal: 14, vertical: 11),
                  ),
                ),
                const SizedBox(height: 10),
                // Category chips
                SingleChildScrollView(
                  scrollDirection: Axis.horizontal,
                  child: Row(
                    children: _cats.map((cat) {
                      final sel = _selectedCat == cat;
                      return GestureDetector(
                        onTap: () => setState(() => _selectedCat = cat),
                        child: AnimatedContainer(
                          duration: const Duration(milliseconds: 160),
                          margin: const EdgeInsets.only(right: 8),
                          padding: const EdgeInsets.symmetric(
                              horizontal: 13, vertical: 7),
                          decoration: BoxDecoration(
                            color: sel ? Colors.white : const Color(0xFF1C1C1E),
                            borderRadius: BorderRadius.circular(20),
                          ),
                          child: Text(cat, style: TextStyle(
                              fontSize: 12,
                              color: sel ? Colors.black
                                  : Colors.white.withOpacity(0.45))),
                        ),
                      );
                    }).toList(),
                  ),
                ),
                const SizedBox(height: 14),
                // Buttons
                Row(children: [
                  Expanded(
                    child: GestureDetector(
                      onTap: _dismiss,
                      child: Container(
                        padding: const EdgeInsets.symmetric(vertical: 11),
                        decoration: BoxDecoration(
                          border: Border.all(
                              color: Colors.white.withOpacity(0.1)),
                          borderRadius: BorderRadius.circular(12),
                        ),
                        child: Center(child: Text('Dismiss',
                            style: TextStyle(
                                color: Colors.white.withOpacity(0.35),
                                fontSize: 13))),
                      ),
                    ),
                  ),
                  const SizedBox(width: 10),
                  Expanded(
                    child: GestureDetector(
                      onTap: _saving ? null : _save,
                      child: Container(
                        padding: const EdgeInsets.symmetric(vertical: 11),
                        decoration: BoxDecoration(
                          color: Colors.white,
                          borderRadius: BorderRadius.circular(12),
                        ),
                        child: Center(child: _saving
                            ? const SizedBox(width: 14, height: 14,
                            child: CircularProgressIndicator(
                                strokeWidth: 1.5, color: Colors.black))
                            : const Text('Save',
                            style: TextStyle(color: Colors.black,
                                fontSize: 13, fontWeight: FontWeight.w600))),
                      ),
                    ),
                  ),
                ]),
              ]),
            ),
          ),
        ),
      ]),
    );
  }
}

// ══════════════════════════════════════════════════════════════════
// CASH ENTRY BOTTOM SHEET
// ══════════════════════════════════════════════════════════════════

class _CashEntrySheet extends StatefulWidget {
  final VoidCallback onSaved;
  const _CashEntrySheet({required this.onSaved});

  @override
  State<_CashEntrySheet> createState() => _CashEntrySheetState();
}

class _CashEntrySheetState extends State<_CashEntrySheet> {
  final _amtCtrl      = TextEditingController();
  final _nameCtrl     = TextEditingController();
  final _newCatCtrl   = TextEditingController();
  String _type        = 'debit';
  String _cat         = 'Misc';
  bool   _saving      = false;
  bool   _addingCat   = false;

  List<String> _cats = [];

  @override
  void initState() {
    super.initState();
    _loadCats();
  }

  Future<void> _loadCats() async {
    final cats = await CategoryStore.instance.get();
    if (!mounted) return;
    setState(() {
      _cats = cats;
      _cat  = _cats.isNotEmpty ? _cats.first : 'Misc';
    });
  }

  @override
  void dispose() {
    _amtCtrl.dispose();
    _nameCtrl.dispose();
    _newCatCtrl.dispose();
    super.dispose();
  }

  Future<void> _save() async {
    final amt  = double.tryParse(_amtCtrl.text.trim());
    final name = _nameCtrl.text.trim();
    if (amt == null || amt <= 0 || name.isEmpty) return;
    setState(() => _saving = true);
    await Repo.saveCash(
        amount: amt, merchantName: name, category: _cat, type: _type);
    CategoryStore.instance.invalidate();
    widget.onSaved();
    if (mounted) Navigator.pop(context);
  }

  void _confirmNewCat() {
    final val = _newCatCtrl.text.trim();
    if (val.isEmpty) return;
    unawaited(CategoryStore.instance.add(val));
    setState(() {
      if (!_cats.contains(val)) _cats.add(val);
      _cat       = val;
      _addingCat = false;
      _newCatCtrl.clear();
    });
  }

  @override
  Widget build(BuildContext context) {
    final amtColor = _type == 'debit'
        ? const Color(0xFFFF453A)
        : const Color(0xFF30D158);

    return Padding(
      padding: EdgeInsets.only(bottom: MediaQuery.of(context).viewInsets.bottom),
      child: SafeArea(
        child: Padding(
          padding: const EdgeInsets.fromLTRB(22, 20, 22, 22),
          child: Column(mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start, children: [

                // Handle
                Center(child: Container(width: 32, height: 3,
                    decoration: BoxDecoration(color: Colors.white12,
                        borderRadius: BorderRadius.circular(2)))),
                const SizedBox(height: 22),

                // ── Type toggle + Amount on same row ──
                Row(crossAxisAlignment: CrossAxisAlignment.center, children: [
                  // Paid out / Received toggle
                  GestureDetector(
                    onTap: () => setState(() =>
                    _type = _type == 'debit' ? 'credit' : 'debit'),
                    child: AnimatedContainer(
                      duration: const Duration(milliseconds: 180),
                      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 7),
                      decoration: BoxDecoration(
                        color: amtColor.withOpacity(0.1),
                        borderRadius: BorderRadius.circular(20),
                        border: Border.all(color: amtColor.withOpacity(0.3)),
                      ),
                      child: Row(mainAxisSize: MainAxisSize.min, children: [
                        Text(_type == 'debit' ? '−' : '+',
                            style: TextStyle(fontSize: 13, color: amtColor,
                                fontWeight: FontWeight.w600)),
                        const SizedBox(width: 4),
                        Text(_type == 'debit' ? 'Paid' : 'Received',
                            style: TextStyle(fontSize: 12, color: amtColor)),
                      ]),
                    ),
                  ),
                  const SizedBox(width: 12),
                  // ₹ symbol as plain text
                  Text('₹', style: TextStyle(
                      fontSize: 22, color: Colors.white.withOpacity(0.35),
                      fontWeight: FontWeight.w300)),
                  const SizedBox(width: 6),
                  // Amount field — no prefix, just numbers
                  Expanded(
                    child: TextField(
                      controller: _amtCtrl,
                      keyboardType: const TextInputType.numberWithOptions(decimal: true),
                      autofocus: true,
                      style: const TextStyle(color: Colors.white, fontSize: 22,
                          fontWeight: FontWeight.w300),
                      decoration: InputDecoration(
                        hintText: '0',
                        hintStyle: TextStyle(
                            color: Colors.white.withOpacity(0.12), fontSize: 22),
                        border: InputBorder.none,
                        isDense: true,
                        contentPadding: EdgeInsets.zero,
                      ),
                    ),
                  ),
                ]),

                const SizedBox(height: 18),
                Divider(color: Colors.white.withOpacity(0.06), height: 1),
                const SizedBox(height: 18),

                // ── Name field ──
                TextField(
                  controller: _nameCtrl,
                  style: const TextStyle(color: Colors.white, fontSize: 15),
                  textCapitalization: TextCapitalization.words,
                  decoration: InputDecoration(
                    hintText: 'Merchant',
                    hintStyle: TextStyle(color: Colors.white.withOpacity(0.2),
                        fontSize: 15),
                    filled: true,
                    fillColor: const Color(0xFF181818),
                    border: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(12),
                      borderSide: BorderSide.none,
                    ),
                    contentPadding: const EdgeInsets.symmetric(
                        horizontal: 14, vertical: 13),
                  ),
                ),
                const SizedBox(height: 10),

                // ── Category dropdown ──
                GestureDetector(
                  onTap: () => _showCatPicker(context),
                  child: Container(
                    width: double.infinity,
                    padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 13),
                    decoration: BoxDecoration(
                      color: const Color(0xFF181818),
                      borderRadius: BorderRadius.circular(12),
                    ),
                    child: Row(children: [
                      Expanded(child: Text(_cat,
                          style: const TextStyle(color: Colors.white, fontSize: 15))),
                      Icon(Icons.expand_more, size: 18,
                          color: Colors.white.withOpacity(0.3)),
                    ]),
                  ),
                ),

                const SizedBox(height: 20),

                // ── Save button ──
                SizedBox(
                  width: double.infinity,
                  child: GestureDetector(
                    onTap: _saving ? null : _save,
                    child: Container(
                      padding: const EdgeInsets.symmetric(vertical: 14),
                      decoration: BoxDecoration(
                        color: Colors.white,
                        borderRadius: BorderRadius.circular(14),
                      ),
                      child: Center(child: _saving
                          ? const SizedBox(width: 16, height: 16,
                          child: CircularProgressIndicator(
                              strokeWidth: 1.5, color: Colors.black))
                          : const Text('Save', style: TextStyle(
                          color: Colors.black,
                          fontWeight: FontWeight.w600, fontSize: 15))),
                    ),
                  ),
                ),
              ]),
        ),
      ),
    );
  }

  void _showCatPicker(BuildContext context) {
    showModalBottomSheet(
      context: context,
      backgroundColor: const Color(0xFF141414),
      shape: const RoundedRectangleBorder(
          borderRadius: BorderRadius.vertical(top: Radius.circular(20))),
      isScrollControlled: true,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setInner) => Padding(
          padding: EdgeInsets.only(
              bottom: MediaQuery.of(ctx).viewInsets.bottom),
          child: Padding(
            padding: const EdgeInsets.fromLTRB(24, 20, 24, 36),
            child: Column(mainAxisSize: MainAxisSize.min, children: [
              Container(width: 32, height: 3,
                  decoration: BoxDecoration(color: Colors.white12,
                      borderRadius: BorderRadius.circular(2))),
              const SizedBox(height: 20),

              // Existing categories
              ..._cats.map((cat) => GestureDetector(
                onTap: () {
                  setState(() => _cat = cat);
                  Navigator.pop(ctx);
                },
                child: Container(
                  width: double.infinity,
                  padding: const EdgeInsets.symmetric(vertical: 15),
                  decoration: BoxDecoration(
                      border: Border(bottom: BorderSide(
                          color: Colors.white.withOpacity(0.05)))),
                  child: Row(children: [
                    Expanded(child: Text(cat, style: TextStyle(
                        color: _cat == cat
                            ? Colors.white
                            : Colors.white.withOpacity(0.5),
                        fontSize: 15,
                        fontWeight: _cat == cat
                            ? FontWeight.w500 : FontWeight.normal))),
                    if (_cat == cat)
                      const Icon(Icons.check, color: Colors.white, size: 16),
                  ]),
                ),
              )),

              const SizedBox(height: 12),

              // Add new category inline
              if (_addingCat)
                Row(children: [
                  Expanded(
                    child: TextField(
                      controller: _newCatCtrl,
                      autofocus: true,
                      textCapitalization: TextCapitalization.words,
                      style: const TextStyle(color: Colors.white, fontSize: 14),
                      decoration: InputDecoration(
                        hintText: 'Category name',
                        hintStyle: TextStyle(
                            color: Colors.white.withOpacity(0.2), fontSize: 14),
                        filled: true,
                        fillColor: const Color(0xFF1C1C1E),
                        border: OutlineInputBorder(
                          borderRadius: BorderRadius.circular(10),
                          borderSide: BorderSide.none,
                        ),
                        contentPadding: const EdgeInsets.symmetric(
                            horizontal: 14, vertical: 11),
                      ),
                      onSubmitted: (_) {
                        _confirmNewCat();
                        Navigator.pop(ctx);
                      },
                    ),
                  ),
                  const SizedBox(width: 10),
                  GestureDetector(
                    onTap: () {
                      _confirmNewCat();
                      Navigator.pop(ctx);
                    },
                    child: Container(
                      padding: const EdgeInsets.symmetric(
                          horizontal: 16, vertical: 11),
                      decoration: BoxDecoration(
                        color: Colors.white,
                        borderRadius: BorderRadius.circular(10),
                      ),
                      child: const Text('Add', style: TextStyle(
                          color: Colors.black, fontWeight: FontWeight.w600,
                          fontSize: 13)),
                    ),
                  ),
                ])
              else
                GestureDetector(
                  onTap: () => setInner(() => _addingCat = true),
                  child: Row(children: [
                    Icon(Icons.add, size: 16,
                        color: Colors.white.withOpacity(0.35)),
                    const SizedBox(width: 8),
                    Text('New category', style: TextStyle(
                        color: Colors.white.withOpacity(0.35), fontSize: 14)),
                  ]),
                ),
            ]),
          ),
        ),
      ),
    ).whenComplete(() => setState(() => _addingCat = false));
  }
}

// ══════════════════════════════════════════════════════════════════
// SCAN SHEET
// ══════════════════════════════════════════════════════════════════

class _ScanSheet extends StatefulWidget {
  final VoidCallback onDone;
  const _ScanSheet({required this.onDone});
  @override
  State<_ScanSheet> createState() => _ScanSheetState();
}

class _ScanSheetState extends State<_ScanSheet> {
  // States: idle → scanning → reviewing → done
  String _state = 'idle';
  int    _knownCount = 0;

  // Groups returned from scan — each is a map with payee_key, payee_hint,
  // is_refund, count, total, txns
  List<Map<String, dynamic>> _groups = [];
  int _currentGroup = 0;

  // Per-group form state
  final _nameCtrl    = TextEditingController();
  final _newCatCtrl  = TextEditingController();
  String _cat        = 'Misc';
  bool   _saving     = false;
  bool   _addingCat  = false;

  // Single shared list from CategoryStore — no local copy needed
  List<String> _cats = [];

  // Cached final import count so _buildDone doesn't recompute after state clears
  int _importedCount = 0;

  // Selected days back — default 30, max 30
  int _daysBack = 30;

  @override
  void initState() {
    super.initState();
    _loadCats();
  }

  Future<void> _loadCats() async {
    final cats = await CategoryStore.instance.get();
    if (!mounted) return;
    setState(() {
      _cats = cats;
      _cat  = _cats.isNotEmpty ? _cats.first : 'Misc';
    });
  }

  @override
  void dispose() {
    _nameCtrl.dispose();
    _newCatCtrl.dispose();
    super.dispose();
  }

  Future<void> _startScan() async {
    setState(() => _state = 'scanning');
    final from = DateTime.now()
        .subtract(Duration(days: _daysBack))
        .millisecondsSinceEpoch
        .toString();
    final result = await Repo.scanInbox(from);
    final knownCount = result['known_count'] as int? ?? 0;
    final rawGroups  = result['unknown_groups'] as List? ?? [];
    final groups     = rawGroups
        .map((g) => Map<String, dynamic>.from(g as Map))
        .toList();

    if (groups.isEmpty) {
      _knownCount    = knownCount;
      _importedCount = knownCount;
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (!mounted) return;
        setState(() => _state = 'done');
        Future.delayed(const Duration(milliseconds: 280), () {
          if (mounted) widget.onDone();
        });
      });
      return;
    }

    setState(() {
      _knownCount    = knownCount;
      _groups        = groups;
      _currentGroup  = 0;
      _state         = 'reviewing';
    });
    _loadGroup(0);
  }

  void _loadGroup(int idx) {
    final g = _groups[idx];
    final hint = g['payee_hint'] as String? ?? '';
    _nameCtrl.text = hint;
    _cat           = _cats.isNotEmpty ? _cats.first : 'Misc';
    _addingCat     = false;
    _newCatCtrl.clear();
  }

  Future<void> _saveGroup() async {
    final name = _nameCtrl.text.trim();
    if (name.isEmpty) return;
    setState(() => _saving = true);

    final g       = _groups[_currentGroup];
    final rawTxns = (g['txns'] as List)
        .map((t) => Map<String, dynamic>.from(t as Map))
        .toList();
    final cat = (_addingCat && _newCatCtrl.text.trim().isNotEmpty)
        ? _newCatCtrl.text.trim()
        : _cat;
    // Persist new category into the shared store so all pickers see it
    unawaited(CategoryStore.instance.add(cat));
    if (!_cats.contains(cat)) setState(() => _cats.add(cat));

    await Repo.saveScanGroup(
      payeeKey: g['payee_key'] as String,
      name:     name,
      category: cat,
      txns:     rawTxns,
    );
    CategoryStore.instance.invalidate(); // re-sort by frequency on next load

    final next = _currentGroup + 1;
    if (next >= _groups.length) {
      // Keep _saving=true — the reviewing widget is about to fade out,
      // clearing it causes a one-frame "Save →" flash before the transition.
      final count = _knownCount + _groups.length;
      _importedCount = count;
      // Wait one frame so the spinner is the last thing shown before fade-out.
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (!mounted) return;
        setState(() => _state = 'done');
        // Refresh home after the transition has started (260 ms duration).
        Future.delayed(const Duration(milliseconds: 280), () {
          if (mounted) widget.onDone();
        });
      });
    } else {
      setState(() { _currentGroup = next; _saving = false; });
      _loadGroup(next);
    }
  }

  void _skipGroup() {
    final next = _currentGroup + 1;
    if (next >= _groups.length) {
      _importedCount = _knownCount + _currentGroup;
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (!mounted) return;
        setState(() => _state = 'done');
        Future.delayed(const Duration(milliseconds: 280), () {
          if (mounted) widget.onDone();
        });
      });
    } else {
      setState(() => _currentGroup = next);
      _loadGroup(next);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: EdgeInsets.only(bottom: MediaQuery.of(context).viewInsets.bottom),
      child: SafeArea(
        child: AnimatedSwitcher(
          duration: const Duration(milliseconds: 260),
          child: switch (_state) {
            'idle'      => _buildIdle(),
            'scanning'  => _buildScanning(),
            'reviewing' => _buildReviewing(),
            _           => _buildDone(),
          },
        ),
      ),
    );
  }

  // ── Idle ──────────────────────────────────────────────────────

  Widget _buildIdle() {
    return Padding(
      key: const ValueKey('idle'),
      padding: const EdgeInsets.fromLTRB(24, 20, 24, 36),
      child: Column(mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start, children: [

            Center(child: Container(width: 32, height: 3,
                decoration: BoxDecoration(color: Colors.white12,
                    borderRadius: BorderRadius.circular(2)))),
            const SizedBox(height: 28),

            Text('SCAN INBOX', style: TextStyle(
                fontSize: 11, letterSpacing: 3,
                color: Colors.white.withOpacity(0.25),
                fontWeight: FontWeight.w600)),
            const SizedBox(height: 10),
            Text('Imports UPI transactions\nyou may have missed.',
                style: TextStyle(
                    color: Colors.white.withOpacity(0.55),
                    fontSize: 15, height: 1.5)),

            const SizedBox(height: 28),

            // Days back — slider
            Row(children: [
              Text('Last', style: TextStyle(
                  color: Colors.white.withOpacity(0.35), fontSize: 13)),
              const SizedBox(width: 8),
              Text('$_daysBack day${_daysBack == 1 ? '' : 's'}',
                  style: const TextStyle(color: Colors.white,
                      fontSize: 13, fontWeight: FontWeight.w500)),
              const Spacer(),
              Text(
                    () {
                  final from = DateTime.now().subtract(Duration(days: _daysBack));
                  const mo = ['Jan','Feb','Mar','Apr','May','Jun',
                    'Jul','Aug','Sep','Oct','Nov','Dec'];
                  return 'from ${from.day} ${mo[from.month - 1]}';
                }(),
                style: TextStyle(
                    color: Colors.white.withOpacity(0.35), fontSize: 12),
              ),
            ]),
            const SizedBox(height: 8),
            SliderTheme(
              data: SliderTheme.of(context).copyWith(
                activeTrackColor: Colors.white.withOpacity(0.7),
                inactiveTrackColor: Colors.white.withOpacity(0.1),
                thumbColor: Colors.white,
                overlayColor: Colors.white.withOpacity(0.08),
                trackHeight: 2,
                thumbShape: const RoundSliderThumbShape(enabledThumbRadius: 7),
                overlayShape: const RoundSliderOverlayShape(overlayRadius: 16),
              ),
              child: Slider(
                value: _daysBack.toDouble(),
                min: 1,
                max: 30,
                divisions: 29,
                onChanged: (v) => setState(() => _daysBack = v.round()),
              ),
            ),

            const SizedBox(height: 24),

            SizedBox(
              width: double.infinity,
              child: GestureDetector(
                onTap: _startScan,
                child: Container(
                  padding: const EdgeInsets.symmetric(vertical: 15),
                  decoration: BoxDecoration(
                      color: Colors.white,
                      borderRadius: BorderRadius.circular(14)),
                  child: const Center(child: Text('Scan',
                      style: TextStyle(color: Colors.black,
                          fontWeight: FontWeight.w600, fontSize: 15))),
                ),
              ),
            ),
          ]),
    );
  }

  // ── Scanning ──────────────────────────────────────────────────

  Widget _buildScanning() {
    return Padding(
      key: const ValueKey('scanning'),
      padding: const EdgeInsets.symmetric(vertical: 56, horizontal: 24),
      child: Column(mainAxisSize: MainAxisSize.min, children: [
        SizedBox(
          width: 28, height: 28,
          child: CircularProgressIndicator(
              color: Colors.white.withOpacity(0.2), strokeWidth: 1.5),
        ),
        const SizedBox(height: 20),
        Text('Reading messages',
            style: TextStyle(
                color: Colors.white.withOpacity(0.35), fontSize: 13,
                letterSpacing: 0.2)),
      ]),
    );
  }

  // ── Reviewing ─────────────────────────────────────────────────

  Widget _buildReviewing() {
    final g        = _groups[_currentGroup];
    final count    = g['count'] as int;
    final total    = (g['total'] as num).toDouble();
    final isRefund = g['is_refund'] as bool? ?? false;
    final hint     = g['payee_hint'] as String? ?? g['payee_key'] as String;

    return Padding(
      key: ValueKey('reviewing_$_currentGroup'),
      padding: const EdgeInsets.fromLTRB(24, 20, 24, 32),
      child: Column(mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start, children: [

            // Handle + progress
            Row(children: [
              const Spacer(),
              Center(child: Container(width: 32, height: 3,
                  decoration: BoxDecoration(color: Colors.white12,
                      borderRadius: BorderRadius.circular(2)))),
              const Spacer(),
              Text('${_currentGroup + 1} / ${_groups.length}',
                  style: TextStyle(
                      color: Colors.white.withOpacity(0.2),
                      fontSize: 11, letterSpacing: 0.5)),
            ]),
            const SizedBox(height: 24),

            // Amount + count
            Row(crossAxisAlignment: CrossAxisAlignment.end, children: [
              Text('₹${_fmtExact(total)}',
                  style: const TextStyle(color: Colors.white,
                      fontSize: 28, fontWeight: FontWeight.w200,
                      letterSpacing: -1)),
              const SizedBox(width: 10),
              Padding(
                padding: const EdgeInsets.only(bottom: 4),
                child: Text('$count txn${count == 1 ? '' : 's'}',
                    style: TextStyle(
                        color: Colors.white.withOpacity(0.28), fontSize: 13)),
              ),
              if (isRefund) ...[
                const Spacer(),
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                  decoration: BoxDecoration(
                    color: const Color(0xFF0D2B1A),
                    borderRadius: BorderRadius.circular(20),
                    border: Border.all(color: const Color(0xFF1C4D2E)),
                  ),
                  child: const Text('↩ refund',
                      style: TextStyle(color: Color(0xFF30D158), fontSize: 11)),
                ),
              ],
            ]),

            const SizedBox(height: 4),
            Text(hint, style: TextStyle(
                color: Colors.white.withOpacity(0.25),
                fontSize: 11, fontFamily: 'monospace')),

            Divider(height: 28, color: Colors.white.withOpacity(0.06)),

            // Name field — no autofocus
            TextField(
              controller: _nameCtrl,
              textCapitalization: TextCapitalization.words,
              style: const TextStyle(color: Colors.white, fontSize: 15),
              decoration: InputDecoration(
                hintText: 'Merchant',
                hintStyle: TextStyle(
                    color: Colors.white.withOpacity(0.18), fontSize: 15),
                filled: true,
                fillColor: const Color(0xFF181818),
                border: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(12),
                  borderSide: BorderSide.none,
                ),
                contentPadding: const EdgeInsets.symmetric(
                    horizontal: 16, vertical: 13),
              ),
            ),
            const SizedBox(height: 12),

            // Category — inline scrollable chips
            SingleChildScrollView(
              scrollDirection: Axis.horizontal,
              child: Row(
                children: [
                  ..._cats.map((cat) {
                    final sel = _cat == cat && !_addingCat;
                    return GestureDetector(
                      onTap: () => setState(() {
                        _cat = cat; _addingCat = false;
                      }),
                      child: AnimatedContainer(
                        duration: const Duration(milliseconds: 160),
                        margin: const EdgeInsets.only(right: 8),
                        padding: const EdgeInsets.symmetric(
                            horizontal: 14, vertical: 8),
                        decoration: BoxDecoration(
                          color: sel ? Colors.white : const Color(0xFF1C1C1E),
                          borderRadius: BorderRadius.circular(20),
                        ),
                        child: Text(cat, style: TextStyle(
                            fontSize: 13,
                            color: sel
                                ? Colors.black
                                : Colors.white.withOpacity(0.45))),
                      ),
                    );
                  }),
                  // Custom category input chip
                  _addingCat
                      ? Container(
                    margin: const EdgeInsets.only(right: 8),
                    width: 120,
                    padding: const EdgeInsets.symmetric(horizontal: 10),
                    decoration: BoxDecoration(
                      color: Colors.white.withOpacity(0.1),
                      borderRadius: BorderRadius.circular(20),
                    ),
                    child: TextField(
                      controller: _newCatCtrl,
                      autofocus: true,
                      textCapitalization: TextCapitalization.words,
                      style: const TextStyle(
                          color: Colors.white, fontSize: 13),
                      decoration: InputDecoration(
                        hintText: 'Category',
                        hintStyle: TextStyle(
                            color: Colors.white.withOpacity(0.25),
                            fontSize: 13),
                        border: InputBorder.none,
                        isDense: true,
                        contentPadding:
                        const EdgeInsets.symmetric(vertical: 8),
                      ),
                      onSubmitted: (v) {
                        final val = v.trim();
                        if (val.isNotEmpty) {
                          unawaited(CategoryStore.instance.add(val));
                          setState(() {
                            if (!_cats.contains(val)) _cats.add(val);
                            _cat = val;
                          });
                        }
                        setState(() => _addingCat = false);
                      },
                    ),
                  )
                      : GestureDetector(
                    onTap: () => setState(() {
                      _addingCat = true;
                      _newCatCtrl.clear();
                    }),
                    child: Container(
                      margin: const EdgeInsets.only(right: 8),
                      padding: const EdgeInsets.symmetric(
                          horizontal: 14, vertical: 8),
                      decoration: BoxDecoration(
                        color: const Color(0xFF1C1C1E),
                        borderRadius: BorderRadius.circular(20),
                      ),
                      child: Text('+ Other', style: TextStyle(
                          fontSize: 13,
                          color: Colors.white.withOpacity(0.3))),
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 18),

            // Actions
            Row(children: [
              GestureDetector(
                onTap: _skipGroup,
                child: Text('Skip', style: TextStyle(
                    color: Colors.white.withOpacity(0.25),
                    fontSize: 14)),
              ),
              const Spacer(),
              GestureDetector(
                onTap: _saving ? null : _saveGroup,
                child: Container(
                  padding: const EdgeInsets.symmetric(
                      horizontal: 28, vertical: 12),
                  decoration: BoxDecoration(
                      color: Colors.white,
                      borderRadius: BorderRadius.circular(22)),
                  child: _saving
                      ? const SizedBox(width: 14, height: 14,
                      child: CircularProgressIndicator(
                          strokeWidth: 1.5, color: Colors.black))
                      : Text(
                      _currentGroup == _groups.length - 1
                          ? 'Save' : 'Save  →',
                      style: const TextStyle(color: Colors.black,
                          fontWeight: FontWeight.w600, fontSize: 14)),
                ),
              ),
            ]),
          ]),
    );
  }

  void _showCatPicker(BuildContext context) {
    showModalBottomSheet(
      context: context,
      backgroundColor: const Color(0xFF141414),
      shape: const RoundedRectangleBorder(
          borderRadius: BorderRadius.vertical(top: Radius.circular(20))),
      isScrollControlled: true,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setInner) => Padding(
          padding: EdgeInsets.only(
              bottom: MediaQuery.of(ctx).viewInsets.bottom),
          child: Padding(
            padding: const EdgeInsets.fromLTRB(24, 20, 24, 36),
            child: Column(mainAxisSize: MainAxisSize.min, children: [
              Container(width: 32, height: 3,
                  decoration: BoxDecoration(color: Colors.white12,
                      borderRadius: BorderRadius.circular(2))),
              const SizedBox(height: 20),
              ..._cats.map((cat) => GestureDetector(
                onTap: () {
                  setState(() { _cat = cat; _addingCat = false; });
                  Navigator.pop(ctx);
                },
                child: Container(
                  width: double.infinity,
                  padding: const EdgeInsets.symmetric(vertical: 15),
                  decoration: BoxDecoration(border: Border(bottom: BorderSide(
                      color: Colors.white.withOpacity(0.05)))),
                  child: Row(children: [
                    Expanded(child: Text(cat, style: TextStyle(
                        color: _cat == cat
                            ? Colors.white
                            : Colors.white.withOpacity(0.5),
                        fontSize: 15,
                        fontWeight: _cat == cat
                            ? FontWeight.w500 : FontWeight.normal))),
                    if (_cat == cat)
                      const Icon(Icons.check, color: Colors.white, size: 16),
                  ]),
                ),
              )),
              const SizedBox(height: 12),
              if (_addingCat)
                Row(children: [
                  Expanded(
                    child: TextField(
                      controller: _newCatCtrl,
                      autofocus: true,
                      textCapitalization: TextCapitalization.words,
                      style: const TextStyle(
                          color: Colors.white, fontSize: 14),
                      decoration: InputDecoration(
                        hintText: 'Category name',
                        hintStyle: TextStyle(
                            color: Colors.white.withOpacity(0.2),
                            fontSize: 14),
                        filled: true,
                        fillColor: const Color(0xFF1C1C1E),
                        border: OutlineInputBorder(
                          borderRadius: BorderRadius.circular(10),
                          borderSide: BorderSide.none,
                        ),
                        contentPadding: const EdgeInsets.symmetric(
                            horizontal: 14, vertical: 11),
                      ),
                      onSubmitted: (val) {
                        final v = val.trim();
                        if (v.isEmpty) return;
                        unawaited(CategoryStore.instance.add(v));
                        setState(() {
                          if (!_cats.contains(v)) _cats.add(v);
                          _cat = v;
                          _addingCat = false;
                        });
                        Navigator.pop(ctx);
                      },
                    ),
                  ),
                  const SizedBox(width: 10),
                  GestureDetector(
                    onTap: () {
                      final v = _newCatCtrl.text.trim();
                      if (v.isEmpty) return;
                      unawaited(CategoryStore.instance.add(v));
                      setState(() {
                        if (!_cats.contains(v)) _cats.add(v);
                        _cat = v;
                        _addingCat = false;
                      });
                      Navigator.pop(ctx);
                    },
                    child: Container(
                      padding: const EdgeInsets.symmetric(
                          horizontal: 16, vertical: 11),
                      decoration: BoxDecoration(
                          color: Colors.white,
                          borderRadius: BorderRadius.circular(10)),
                      child: const Text('Add', style: TextStyle(
                          color: Colors.black,
                          fontWeight: FontWeight.w600,
                          fontSize: 13)),
                    ),
                  ),
                ])
              else
                GestureDetector(
                  onTap: () => setInner(() => _addingCat = true),
                  child: Row(children: [
                    Icon(Icons.add, size: 16,
                        color: Colors.white.withOpacity(0.35)),
                    const SizedBox(width: 8),
                    Text('New category', style: TextStyle(
                        color: Colors.white.withOpacity(0.35),
                        fontSize: 14)),
                  ]),
                ),
            ]),
          ),
        ),
      ),
    );
  }

  // ── Done ──────────────────────────────────────────────────────

  Widget _buildDone() {
    final imported = _importedCount;
    return Padding(
      key: const ValueKey('done'),
      padding: const EdgeInsets.fromLTRB(24, 36, 24, 44),
      child: Column(mainAxisSize: MainAxisSize.min, children: [
        Text(imported == 0 ? '—' : '$imported',
            style: TextStyle(
                color: imported > 0
                    ? Colors.white : Colors.white.withOpacity(0.2),
                fontSize: 48, fontWeight: FontWeight.w200,
                letterSpacing: -2)),
        const SizedBox(height: 6),
        Text(
          imported == 0
              ? 'Nothing new found'
              : 'transaction${imported == 1 ? '' : 's'} imported',
          style: TextStyle(
              color: Colors.white.withOpacity(0.3), fontSize: 13),
        ),
        const SizedBox(height: 32),
        SizedBox(
          width: double.infinity,
          child: GestureDetector(
            onTap: () => Navigator.pop(context),
            child: Container(
              padding: const EdgeInsets.symmetric(vertical: 14),
              decoration: BoxDecoration(
                  color: Colors.white,
                  borderRadius: BorderRadius.circular(14)),
              child: const Center(child: Text('Done',
                  style: TextStyle(color: Colors.black,
                      fontWeight: FontWeight.w600, fontSize: 15))),
            ),
          ),
        ),
      ]),
    );
  }
}

// ══════════════════════════════════════════════════════════════════
// DATE RANGE DIALOG (unchanged)
// ══════════════════════════════════════════════════════════════════

class _DateRangeDialog extends StatefulWidget {
  final DateTimeRange initial;
  final DateTime firstDate;
  final DateTime lastDate;
  const _DateRangeDialog({required this.initial, required this.firstDate, required this.lastDate});

  @override
  State<_DateRangeDialog> createState() => _DateRangeDialogState();
}

class _DateRangeDialogState extends State<_DateRangeDialog> {
  late DateTime _viewMonth;
  DateTime? _from;
  DateTime? _to;
  bool _pickingFrom = true;

  @override
  void initState() {
    super.initState();
    _from      = widget.initial.start;
    _to        = widget.initial.end;
    _viewMonth = DateTime(widget.initial.end.year, widget.initial.end.month);
  }

  static const _mo = ['Jan','Feb','Mar','Apr','May','Jun','Jul','Aug','Sep','Oct','Nov','Dec'];
  static const _wd = ['M','T','W','T','F','S','S'];

  bool _canApply() => _from != null && _to != null && !_to!.isBefore(_from!);

  void _onDayTap(DateTime d) {
    setState(() {
      if (_pickingFrom) {
        _from = d; _to = null; _pickingFrom = false;
      } else {
        if (d.isBefore(_from!)) { _from = d; _to = null; }
        else { _to = d; _pickingFrom = true; }
      }
    });
  }

  bool _inRange(DateTime d) => _from != null && _to != null && !d.isBefore(_from!) && !d.isAfter(_to!);
  bool _isFrom(DateTime d)  => _from != null && _isSameDay(d, _from!);
  bool _isTo(DateTime d)    => _to   != null && _isSameDay(d, _to!);
  bool _isSameDay(DateTime a, DateTime b) => a.year == b.year && a.month == b.month && a.day == b.day;
  bool _isToday(DateTime d)    => _isSameDay(d, DateTime.now());
  bool _isDisabled(DateTime d) => d.isBefore(widget.firstDate) || d.isAfter(widget.lastDate);
  String _fmtChip(DateTime? d) => d == null ? '—' : '${d.day} ${_mo[d.month - 1]} ${d.year}';

  @override
  Widget build(BuildContext context) {
    final firstOfMonth = DateTime(_viewMonth.year, _viewMonth.month, 1);
    final startOffset  = (firstOfMonth.weekday - 1) % 7;
    final daysInMonth  = DateTime(_viewMonth.year, _viewMonth.month + 1, 0).day;
    final rows         = ((startOffset + daysInMonth) / 7).ceil();

    return Dialog(
      backgroundColor: const Color(0xFF1C1C1E),
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
      insetPadding: const EdgeInsets.symmetric(horizontal: 24, vertical: 48),
      child: Padding(
        padding: const EdgeInsets.fromLTRB(20, 20, 20, 16),
        child: Column(mainAxisSize: MainAxisSize.min, children: [
          Row(children: [
            _RangeChip(label: 'FROM', value: _fmtChip(_from), active: _pickingFrom,
                onTap: () => setState(() => _pickingFrom = true)),
            Padding(padding: const EdgeInsets.symmetric(horizontal: 8),
                child: Icon(Icons.arrow_forward, size: 14,
                    color: Colors.white.withOpacity(0.2))),
            _RangeChip(label: 'TO', value: _fmtChip(_to), active: !_pickingFrom,
                onTap: () => setState(() => _pickingFrom = false)),
          ]),
          const SizedBox(height: 18),
          Row(children: [
            GestureDetector(
              onTap: () => setState(() => _viewMonth = DateTime(_viewMonth.year, _viewMonth.month - 1)),
              child: Container(width: 32, height: 32,
                  decoration: BoxDecoration(color: Colors.white.withOpacity(0.06),
                      borderRadius: BorderRadius.circular(8)),
                  child: Icon(Icons.chevron_left, size: 18, color: Colors.white.withOpacity(0.5))),
            ),
            Expanded(child: Text('${_mo[_viewMonth.month - 1]} ${_viewMonth.year}',
                textAlign: TextAlign.center,
                style: const TextStyle(color: Colors.white, fontSize: 14,
                    fontWeight: FontWeight.w500))),
            GestureDetector(
              onTap: () {
                final next = DateTime(_viewMonth.year, _viewMonth.month + 1);
                if (!next.isAfter(DateTime(widget.lastDate.year, widget.lastDate.month)))
                  setState(() => _viewMonth = next);
              },
              child: Container(width: 32, height: 32,
                  decoration: BoxDecoration(color: Colors.white.withOpacity(0.06),
                      borderRadius: BorderRadius.circular(8)),
                  child: Icon(Icons.chevron_right, size: 18, color: Colors.white.withOpacity(0.5))),
            ),
          ]),
          const SizedBox(height: 14),
          Row(children: _wd.map((d) => Expanded(child: Text(d,
              textAlign: TextAlign.center,
              style: TextStyle(fontSize: 11, fontWeight: FontWeight.w600,
                  color: Colors.white.withOpacity(0.2))))).toList()),
          const SizedBox(height: 6),
          ...List.generate(rows, (row) => Padding(
            padding: const EdgeInsets.only(bottom: 2),
            child: Row(children: List.generate(7, (col) {
              final dayNum = row * 7 + col - startOffset + 1;
              if (dayNum < 1 || dayNum > daysInMonth) return const Expanded(child: SizedBox(height: 36));
              final d          = DateTime(_viewMonth.year, _viewMonth.month, dayNum);
              final disabled   = _isDisabled(d);
              final isFrom     = _isFrom(d);
              final isTo       = _isTo(d);
              final inRange    = _inRange(d);
              final today      = _isToday(d);
              final isEndpoint = isFrom || isTo;
              return Expanded(
                child: GestureDetector(
                  onTap: disabled ? null : () => _onDayTap(d),
                  child: Stack(alignment: Alignment.center, children: [
                    if (inRange) Row(children: [
                      Expanded(child: Container(height: 32,
                          color: (!isFrom && col > 0) ? Colors.white.withOpacity(0.08) : Colors.transparent)),
                      Expanded(child: Container(height: 32,
                          color: (!isTo && col < 6) ? Colors.white.withOpacity(0.08) : Colors.transparent)),
                    ]),
                    Container(
                      width: 32, height: 32,
                      decoration: BoxDecoration(
                        color: isEndpoint ? Colors.white : Colors.transparent,
                        shape: BoxShape.circle,
                        border: today && !isEndpoint ? Border.all(
                            color: Colors.white.withOpacity(0.25)) : null,
                      ),
                      child: Center(child: Text('$dayNum', style: TextStyle(
                        fontSize: 13,
                        fontWeight: isEndpoint ? FontWeight.w600 : FontWeight.w400,
                        color: isEndpoint ? Colors.black
                            : disabled ? Colors.white.withOpacity(0.15)
                            : inRange ? Colors.white.withOpacity(0.9)
                            : Colors.white.withOpacity(0.6),
                      ))),
                    ),
                  ]),
                ),
              );
            })),
          )),
          const SizedBox(height: 16),
          Row(children: [
            Expanded(child: Text(_pickingFrom ? 'Tap a start date' : 'Tap an end date',
                style: TextStyle(fontSize: 11, color: Colors.white.withOpacity(0.25)))),
            GestureDetector(
              onTap: _canApply()
                  ? () => Navigator.pop(context, DateTimeRange(start: _from!, end: _to!))
                  : null,
              child: AnimatedContainer(
                duration: const Duration(milliseconds: 180),
                padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 9),
                decoration: BoxDecoration(
                  color: _canApply() ? Colors.white : Colors.white.withOpacity(0.1),
                  borderRadius: BorderRadius.circular(20),
                ),
                child: Text('Apply', style: TextStyle(
                    fontSize: 13, fontWeight: FontWeight.w600,
                    color: _canApply() ? Colors.black : Colors.white.withOpacity(0.2))),
              ),
            ),
          ]),
        ]),
      ),
    );
  }
}

class _RangeChip extends StatelessWidget {
  final String label, value;
  final bool active;
  final VoidCallback onTap;
  const _RangeChip({required this.label, required this.value, required this.active, required this.onTap});

  @override
  Widget build(BuildContext context) {
    return Expanded(
      child: GestureDetector(
        onTap: onTap,
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 150),
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
          decoration: BoxDecoration(
            color: active ? Colors.white.withOpacity(0.08) : Colors.transparent,
            borderRadius: BorderRadius.circular(10),
            border: Border.all(
                color: active ? Colors.white.withOpacity(0.25) : Colors.white.withOpacity(0.08)),
          ),
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Text(label, style: TextStyle(fontSize: 9, letterSpacing: 1, fontWeight: FontWeight.w700,
                color: Colors.white.withOpacity(active ? 0.5 : 0.25))),
            const SizedBox(height: 2),
            Text(value, style: TextStyle(fontSize: 12, fontWeight: FontWeight.w500,
                color: Colors.white.withOpacity(active ? 0.9 : 0.45))),
          ]),
        ),
      ),
    );
  }
}

// ══════════════════════════════════════════════════════════════════
// ANALYTICS SCREEN (unchanged from original)
// ══════════════════════════════════════════════════════════════════

// ══════════════════════════════════════════════════════════════════
// ANALYTICS SCREEN
// ══════════════════════════════════════════════════════════════════

class AnalyticsScreen extends StatefulWidget {
  const AnalyticsScreen({super.key});
  @override
  State<AnalyticsScreen> createState() => _AnalyticsScreenState();
}

class _AnalyticsScreenState extends State<AnalyticsScreen> {
  String _view = 'current';
  final Set<String> _selectedLines = {'__total__'};

  void _showMonthPicker(BuildContext context) {
    final store = AppStoreProvider.of(context);
    final opts  = <String>['current'];
    if (store.monthsWithData > 1) opts.add('3');
    if (store.monthsWithData > 3) opts.add('6');
    if (store.monthsWithData > 6) opts.add('12');
    final labels = {
      'current': 'This Month (Weekly)', '3': 'Last 3 months',
      '6': 'Last 6 months', '12': 'Last 12 months',
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
            onTap: () { setState(() => _view = v); Navigator.pop(context); },
            child: Container(
              width: double.infinity,
              padding: const EdgeInsets.symmetric(vertical: 16),
              decoration: BoxDecoration(border: Border(bottom: BorderSide(
                  color: Colors.white.withOpacity(0.06)))),
              child: Row(children: [
                Expanded(child: Text(labels[v]!, style: TextStyle(
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
    final store   = AppStoreProvider.of(context);
    final months  = store.monthsForView(_view);
    final weeks   = store.weeks;
    final allCats = store.allCategories;

    return Scaffold(
      backgroundColor: const Color(0xFF0A0A0A),
      body: SafeArea(
        child: store.loading
            ? const Center(child: CircularProgressIndicator(
            color: Colors.white24, strokeWidth: 1))
            : Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(24, 32, 24, 0),
            child: Row(children: [
              Text('ANALYTICS', style: TextStyle(fontSize: 11, letterSpacing: 4,
                  color: Colors.white.withOpacity(0.25), fontWeight: FontWeight.w600)),
              const Spacer(),
              GestureDetector(
                onTap: () => _showMonthPicker(context),
                child: Container(
                  padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 7),
                  decoration: BoxDecoration(
                      border: Border.all(color: Colors.white.withOpacity(0.12)),
                      borderRadius: BorderRadius.circular(20)),
                  child: Row(mainAxisSize: MainAxisSize.min, children: [
                    Text(_view == 'current' ? 'This Month' : 'Last $_view months',
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
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 24),
            child: _LineGraph(months: months, weeks: weeks,
                selectedLines: _selectedLines, isWeekly: _view == 'current'),
          ),
          const SizedBox(height: 24),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 24),
            child: SingleChildScrollView(
              scrollDirection: Axis.horizontal,
              child: Row(children: [
                _LineChip(label: 'Total', color: Colors.white,
                    selected: _selectedLines.contains('__total__'),
                    onTap: () => setState(() {
                      if (_selectedLines.contains('__total__'))
                        _selectedLines.remove('__total__');
                      else _selectedLines.add('__total__');
                    })),
                const SizedBox(width: 8),
                ...allCats.toList().asMap().entries.map((e) {
                  final colors = _pieColors();
                  final color  = colors[e.key % colors.length];
                  final sel    = _selectedLines.contains(e.value);
                  return Padding(
                    padding: const EdgeInsets.only(right: 8),
                    child: _LineChip(label: e.value, color: color, selected: sel,
                        onTap: () => setState(() {
                          if (sel) _selectedLines.remove(e.value);
                          else     _selectedLines.add(e.value);
                        })),
                  );
                }),
              ]),
            ),
          ),
          const SizedBox(height: 28),
          Padding(padding: const EdgeInsets.symmetric(horizontal: 24),
              child: _SectionLabel('LAST 7 DAYS')),
          const SizedBox(height: 12),
          Padding(padding: const EdgeInsets.symmetric(horizontal: 24),
              child: _DailyBars(dailyData: store.dailyData)),
          if (months.length >= 2) ...[
            const SizedBox(height: 28),
            Padding(padding: const EdgeInsets.symmetric(horizontal: 24),
                child: _SectionLabel('vs LAST MONTH')),
            const SizedBox(height: 12),
            Expanded(
              child: ListView(
                padding: const EdgeInsets.fromLTRB(24, 0, 24, 48),
                children: () {
                  final thisMonth = months.last;
                  final lastMonth = months[months.length - 2];
                  return thisMonth.cats.entries.map((e) {
                    final last = lastMonth.cats[e.key] ?? 0;
                    final diff = e.value - last;
                    final pct  = last > 0 ? diff / last * 100 : 0.0;
                    return _CatComparison(category: e.key,
                        thisAmount: e.value, lastAmount: last, pct: pct);
                  }).toList();
                }(),
              ),
            ),
          ] else const Spacer(),
        ]),
      ),
    );
  }
}

// ══════════════════════════════════════════════════════════════════
// ALL CHART / UI WIDGETS BELOW — identical to original
// ══════════════════════════════════════════════════════════════════

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
        painter: _LinePainter(months: months, weeks: weeks, isWeekly: isWeekly,
            selectedLines: selectedLines, allCats: allCats, catColors: catColors),
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

  _LinePainter({required this.months, required this.weeks, required this.isWeekly,
    required this.selectedLines, required this.allCats, required this.catColors});

  @override
  void paint(Canvas canvas, Size size) {
    const padL = 36.0, padR = 12.0, padT = 8.0, padB = 24.0;
    final w = size.width - padL - padR;
    final h = size.height - padT - padB;
    if (isWeekly) _paintWeekly(canvas, w, h, padL, padT);
    else          _paintMonthly(canvas, w, h, padL, padT);
  }

  void _paintWeekly(Canvas canvas, double w, double h, double padL, double padT) {
    final pts = weeks;
    if (pts.isEmpty) return;
    double maxVal = 0;
    for (final wk in pts) {
      if (selectedLines.contains('__total__') && wk.total > maxVal) maxVal = wk.total;
      for (final cat in allCats)
        if (selectedLines.contains(cat) && (wk.cats[cat] ?? 0) > maxVal) maxVal = wk.cats[cat]!;
    }
    if (maxVal == 0) maxVal = 1;
    _drawGrid(canvas, w, h, padL, padT, maxVal);
    for (var i = 0; i < pts.length; i++) {
      final x  = pts.length == 1 ? padL + w / 2 : padL + i / (pts.length - 1) * w;
      final tp = TextPainter(
        text: TextSpan(text: pts[i].label, style: TextStyle(
            color: i == pts.length - 1 ? Colors.white.withOpacity(0.6) : Colors.white.withOpacity(0.25),
            fontSize: 9, fontWeight: i == pts.length - 1 ? FontWeight.w600 : FontWeight.normal)),
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
        if (!penDown) { path.moveTo(x, y); penDown = true; } else path.lineTo(x, y);
        canvas.drawCircle(Offset(x, y), 3.0, Paint()..color = color);
      }
      canvas.drawPath(path, Paint()..color = color..strokeWidth = 1.8
        ..style = PaintingStyle.stroke..strokeCap = StrokeCap.round..strokeJoin = StrokeJoin.round);
    }
    if (selectedLines.contains('__total__')) drawLine(pts.map((wk) => wk.total).toList(), Colors.white);
    for (final cat in allCats)
      if (selectedLines.contains(cat))
        drawLine(pts.map((wk) => wk.cats[cat] ?? 0.0).toList(), catColors[cat] ?? Colors.white);
  }

  void _paintMonthly(Canvas canvas, double w, double h, double padL, double padT) {
    final pts = months;
    if (pts.length < 2) return;
    double maxVal = 0;
    for (final m in pts) {
      if (selectedLines.contains('__total__') && m.total > maxVal) maxVal = m.total;
      for (final cat in allCats)
        if (selectedLines.contains(cat) && (m.cats[cat] ?? 0) > maxVal) maxVal = m.cats[cat]!;
    }
    if (maxVal == 0) maxVal = 1;
    _drawGrid(canvas, w, h, padL, padT, maxVal);
    for (var i = 0; i < pts.length; i++) {
      final x  = padL + i / (pts.length - 1) * w;
      final tp = TextPainter(
        text: TextSpan(text: pts[i].label, style: TextStyle(
            color: i == pts.length - 1 ? Colors.white.withOpacity(0.6) : Colors.white.withOpacity(0.3),
            fontSize: 9, fontWeight: i == pts.length - 1 ? FontWeight.w600 : FontWeight.normal)),
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
      canvas.drawPath(path, Paint()..color = color..strokeWidth = 1.8
        ..style = PaintingStyle.stroke..strokeCap = StrokeCap.round..strokeJoin = StrokeJoin.round);
      final lx = padL + w;
      final ly = padT + h - (vals.last / maxVal).clamp(0, 1) * h;
      canvas.drawCircle(Offset(lx, ly), 3.5, Paint()..color = color);
    }
    if (selectedLines.contains('__total__')) drawLine(pts.map((m) => m.total).toList(), Colors.white);
    for (final cat in allCats)
      if (selectedLines.contains(cat))
        drawLine(pts.map((m) => m.cats[cat] ?? 0.0).toList(), catColors[cat] ?? Colors.white);
  }

  void _drawGrid(Canvas canvas, double w, double h, double padL, double padT, double maxVal) {
    final gridPaint = Paint()..color = Colors.white.withOpacity(0.06)..strokeWidth = 1;
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
      old.selectedLines != selectedLines || old.months != months ||
          old.weeks != weeks || old.isWeekly != isWeekly;
}

class _LineChip extends StatelessWidget {
  final String label;
  final Color color;
  final bool selected;
  final VoidCallback onTap;
  const _LineChip({required this.label, required this.color, required this.selected, required this.onTap});

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
          border: Border.all(color: selected ? color.withOpacity(0.5) : Colors.white.withOpacity(0.1)),
        ),
        child: Row(mainAxisSize: MainAxisSize.min, children: [
          Container(width: 6, height: 6, decoration: BoxDecoration(
              color: selected ? color : color.withOpacity(0.3), shape: BoxShape.circle)),
          const SizedBox(width: 6),
          Text(label, style: TextStyle(color: Colors.white.withOpacity(selected ? 0.9 : 0.4), fontSize: 12)),
        ]),
      ),
    );
  }
}

// _DailyBars — reads pre-fetched data from store, keeps local category filter
class _DailyBars extends StatefulWidget {
  final Map<String, Map<String, double>> dailyData;
  const _DailyBars({required this.dailyData});
  @override
  State<_DailyBars> createState() => _DailyBarsState();
}

class _DailyBarsState extends State<_DailyBars> {
  final Set<String> _selected = {};

  @override
  Widget build(BuildContext context) {
    final now      = DateTime.now();
    final daily    = <String, double>{};
    final catMap   = <String, Map<String, double>>{};
    final catSet   = <String>{};

    // Build ordered 7-day keys
    for (var i = 6; i >= 0; i--) {
      final d   = now.subtract(Duration(days: i));
      final key = '${d.day}/${d.month}';
      daily[key]  = 0;
      catMap[key] = {};
    }
    for (final entry in widget.dailyData.entries) {
      final key = entry.key;
      if (!daily.containsKey(key)) continue;
      double total = 0;
      for (final e in entry.value.entries) {
        catMap[key]![e.key] = e.value;
        total += e.value;
        if (e.value > 0) catSet.add(e.key);
      }
      daily[key] = math.max(0.0, total);
    }
    final allCats = catSet.toList();

    final showCats   = _selected.isNotEmpty;
    final activeCats = showCats ? allCats.where(_selected.contains).toList() : <String>[];
    final colors     = _pieColors();
    double max = 0;
    for (final entry in daily.entries) {
      final val = showCats
          ? activeCats.fold(0.0, (s, c) => s + (catMap[entry.key]?[c] ?? 0))
          : entry.value;
      if (val > max) max = val;
    }
    if (max == 0) max = 1;

    final days    = ['Mon', 'Tue', 'Wed', 'Thu', 'Fri', 'Sat', 'Sun'];
    final entries = daily.entries.toList();

    return Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
      if (allCats.isNotEmpty)
        SingleChildScrollView(
          scrollDirection: Axis.horizontal,
          child: Row(children: allCats.asMap().entries.map((e) {
            final color = colors[e.key % colors.length];
            final sel   = _selected.contains(e.value);
            return Padding(
              padding: const EdgeInsets.only(right: 8, bottom: 12),
              child: _LineChip(label: e.value, color: color, selected: sel,
                  onTap: () => setState(() {
                    if (sel) _selected.remove(e.value);
                    else     _selected.add(e.value);
                  })),
            );
          }).toList()),
        ),
      Container(
        height: 148,
        padding: const EdgeInsets.symmetric(horizontal: 16),
        decoration: BoxDecoration(
            color: const Color(0xFF1C1C1E),
            borderRadius: BorderRadius.circular(16)),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.end,
          children: entries.asMap().entries.map((e) {
            final idx    = e.key;
            final dayKey = e.value.key;
            final isToday = idx == entries.length - 1;
            final dayIdx  = (now.weekday - 1 - (6 - idx)) % 7;
            final label   = days[dayIdx.clamp(0, 6)];
            final total   = showCats
                ? activeCats.fold(0.0, (s, c) => s + (catMap[dayKey]?[c] ?? 0))
                : daily[dayKey] ?? 0;
            return Expanded(
              child: Padding(
                padding: const EdgeInsets.symmetric(horizontal: 3),
                child: _DailyBarColumn(
                  key: ValueKey(dayKey),
                  total: total, max: max,
                  dayKey: dayKey, label: label, isToday: isToday,
                  showCats: showCats, activeCats: activeCats,
                  allCats: allCats, dailyCats: catMap, colors: colors,
                ),
              ),
            );
          }).toList(),
        ),
      ),
    ]);
  }
}

class _DailyBarColumn extends StatefulWidget {
  final double total, max;
  final String dayKey, label;
  final bool isToday, showCats;
  final List<String> activeCats, allCats;
  final Map<String, Map<String, double>> dailyCats;
  final List<Color> colors;
  const _DailyBarColumn({super.key, required this.total, required this.max, required this.dayKey,
    required this.label, required this.isToday, required this.showCats, required this.activeCats,
    required this.allCats, required this.dailyCats, required this.colors});
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
    return Column(mainAxisAlignment: MainAxisAlignment.end, children: [
      ClipRect(
        child: SizedBox(
          height: maxH + 16,
          child: TweenAnimationBuilder<double>(
            tween: Tween(end: targetH), duration: dur, curve: curve,
            builder: (_, animH, __) => Stack(alignment: Alignment.bottomCenter, children: [
              Positioned(bottom: 0, left: 0, right: 0,
                  child: widget.showCats && widget.activeCats.length > 1
                      ? _buildStacked(animH) : _buildSingle(animH)),
              if (widget.total > 0) Positioned(bottom: animH + 2, left: 0, right: 0,
                  child: Text('₹${_fmtShort(widget.total)}', textAlign: TextAlign.center,
                      style: TextStyle(color: Colors.white.withOpacity(0.3), fontSize: 8))),
            ]),
          ),
        ),
      ),
      const SizedBox(height: 8),
      Text(widget.label, style: TextStyle(
          color: widget.isToday ? Colors.white.withOpacity(0.7) : Colors.white.withOpacity(0.25),
          fontSize: 10, fontWeight: widget.isToday ? FontWeight.w600 : FontWeight.normal)),
      const SizedBox(height: 16),
    ]);
  }

  Widget _buildSingle(double animH) {
    final barColor = (widget.showCats && widget.activeCats.isNotEmpty)
        ? widget.colors[widget.allCats.indexOf(widget.activeCats.first) % widget.colors.length]
        : Colors.white;
    return Container(height: animH, decoration: BoxDecoration(
        color: widget.isToday ? barColor.withOpacity(0.7) : barColor.withOpacity(0.25),
        borderRadius: BorderRadius.circular(4)));
  }

  Widget _buildStacked(double animH) {
    return SizedBox(width: double.infinity, height: animH, child: Column(
        mainAxisAlignment: MainAxisAlignment.end,
        children: widget.activeCats.asMap().entries.map((ce) {
          final catAmt = widget.dailyCats[widget.dayKey]?[ce.value] ?? 0;
          final segH   = widget.total > 0 ? (animH * (catAmt / widget.total)).clamp(0.0, animH) : 0.0;
          final catIdx = widget.allCats.indexOf(ce.value);
          final color  = widget.colors[catIdx % widget.colors.length];
          return SizedBox(width: double.infinity, height: segH,
              child: DecoratedBox(decoration: BoxDecoration(
                  color: widget.isToday ? color.withOpacity(0.85) : color.withOpacity(0.55),
                  borderRadius: ce.key == 0
                      ? const BorderRadius.vertical(top: Radius.circular(4))
                      : BorderRadius.zero)));
        }).toList()));
  }
}

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

class _PieSectionState extends State<_PieSection> with SingleTickerProviderStateMixin {
  late AnimationController _ctrl;
  late Animation<double> _anim;
  @override
  void initState() {
    super.initState();
    _ctrl = AnimationController(vsync: this, duration: const Duration(milliseconds: 700));
    _anim = CurvedAnimation(parent: _ctrl, curve: Curves.easeOutCubic);
    _ctrl.forward();
  }
  @override
  void didUpdateWidget(_PieSection old) {
    super.didUpdateWidget(old);
    if (old.cats != widget.cats) _ctrl.forward(from: 0);
  }
  @override
  void dispose() { _ctrl.dispose(); super.dispose(); }

  @override
  Widget build(BuildContext context) {
    final colors  = _pieColors();
    final entries = widget.cats.entries.toList();
    return LayoutBuilder(builder: (context, constraints) {
      final canvasW = constraints.maxWidth;
      return Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        GestureDetector(
          behavior: HitTestBehavior.opaque,
          onTapUp: (details) {
            final box   = context.findRenderObject() as RenderBox;
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
              if (angle >= start && angle < start + sweep) { widget.onSelect(entries[i].key); return; }
              start += sweep;
            }
          },
          child: SizedBox(height: 220, child: AnimatedBuilder(
            animation: _anim,
            builder: (_, __) => CustomPaint(
              painter: _PiePainter(cats: widget.cats, total: widget.total, colors: colors,
                  selected: widget.selected, progress: _anim.value, canvasWidth: canvasW),
              size: Size(canvasW, 220),
              child: Center(child: AnimatedSwitcher(
                duration: const Duration(milliseconds: 220),
                child: widget.selected != null
                    ? _PieCenter(key: ValueKey(widget.selected),
                    pct: (widget.cats[widget.selected!] ?? 0) / widget.total)
                    : const _PieCenterTotal(key: ValueKey('__total__')),
              )),
            ),
          )),
        ),
        const SizedBox(height: 16),
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
                  AnimatedContainer(duration: const Duration(milliseconds: 200),
                      width: isSel ? 10 : 7, height: isSel ? 10 : 7,
                      decoration: BoxDecoration(color: color, shape: BoxShape.circle)),
                  const SizedBox(width: 10),
                  Expanded(child: Text(e.value.key, style: TextStyle(
                      color: Colors.white.withOpacity(isSel ? 1.0 : 0.65), fontSize: 13,
                      fontWeight: isSel ? FontWeight.w500 : FontWeight.w400))),
                  SizedBox(width: 120, child: ClipRRect(borderRadius: BorderRadius.circular(2),
                      child: LinearProgressIndicator(value: pct, minHeight: 2,
                          backgroundColor: Colors.white.withOpacity(0.06),
                          valueColor: AlwaysStoppedAnimation<Color>(
                              color.withOpacity(isSel ? 0.9 : 0.5))))),
                  const SizedBox(width: 20),
                  SizedBox(width: 64, child: AnimatedSwitcher(
                    duration: const Duration(milliseconds: 180),
                    child: Text(
                      isSel ? '₹${_fmtExact(e.value.value)}' : '₹${_fmt(e.value.value)}',
                      key: ValueKey(isSel),
                      textAlign: TextAlign.right,
                      style: TextStyle(
                          color: Colors.white.withOpacity(isSel ? 0.85 : 0.4),
                          fontSize: 12, fontWeight: FontWeight.w500),
                    ),
                  )),
                ]),
              ),
            ),
          );
        }),
        const SizedBox(height: 8),
      ]);
    });
  }
}

class _PieCenter extends StatelessWidget {
  final double pct;
  const _PieCenter({super.key, required this.pct});
  @override
  Widget build(BuildContext context) => Text('${(pct * 100).toStringAsFixed(1)}%',
      style: const TextStyle(color: Colors.white, fontSize: 26,
          fontWeight: FontWeight.w200, letterSpacing: -1));
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
    final cx = canvasWidth / 2, cy = size.height / 2;
    const outer = 96.0, inner = 58.0, expand = 10.0, gap = 0.022;
    var start   = -math.pi / 2;
    final entries = cats.entries.toList();
    final hasSel  = selected != null;
    final isSingle = entries.length == 1;

    for (var i = 0; i < entries.length; i++) {
      final frac      = entries[i].value / total;
      final full      = frac * 2 * math.pi;
      final actualGap = isSingle ? 0.0 : gap;
      final sweep     = (full * progress) - actualGap;
      if (sweep <= 0) { start += full * progress; continue; }

      final color  = colors[i % colors.length];
      final isSel  = selected == entries[i].key;
      final mid    = start + sweep / 2;
      final expand_ = isSel ? expand : 0.0;
      final offX   = math.cos(mid) * expand_;
      final offY   = math.sin(mid) * expand_;
      final r      = isSel ? outer + expand : outer;
      final opacity = hasSel ? (isSel ? 1.0 : 0.28) : 0.88;
      final paint  = Paint()..color = color.withOpacity(opacity)..style = PaintingStyle.fill;

      if (isSingle) {
        final path = Path()
          ..addOval(Rect.fromCircle(center: Offset(cx + offX, cy + offY), radius: r))
          ..addOval(Rect.fromCircle(center: Offset(cx + offX, cy + offY), radius: inner));
        path.fillType = PathFillType.evenOdd;
        canvas.drawPath(path, paint);
        if (isSel) canvas.drawPath(path,
            Paint()..color = Colors.white.withOpacity(0.07)..style = PaintingStyle.fill);
        start += full * progress; continue;
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
      if (isSel) canvas.drawPath(path,
          Paint()..color = Colors.white.withOpacity(0.07)..style = PaintingStyle.fill);
      start += full * progress;
    }
  }

  @override
  bool shouldRepaint(_PiePainter old) =>
      old.selected != selected || old.cats != cats || old.progress != progress;
}

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
      decoration: BoxDecoration(color: const Color(0xFF1C1C1E), borderRadius: BorderRadius.circular(12)),
      child: Row(children: [
        Expanded(child: Text(category, style: const TextStyle(color: Colors.white,
            fontSize: 14, fontWeight: FontWeight.w400))),
        Text('₹${_fmt(thisAmount)}', style: TextStyle(color: Colors.white.withOpacity(0.6), fontSize: 13)),
        if (hasLast) ...[
          const SizedBox(width: 8),
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 3),
            decoration: BoxDecoration(
              color: isUp ? const Color(0xFFFF453A).withOpacity(0.08)
                  : const Color(0xFF30D158).withOpacity(0.08),
              borderRadius: BorderRadius.circular(6),
            ),
            child: Text('${isUp ? '↑' : '↓'} ${pct.abs().toStringAsFixed(0)}%',
                style: TextStyle(
                    color: isUp ? const Color(0xFFFF453A).withOpacity(0.8)
                        : const Color(0xFF30D158).withOpacity(0.8),
                    fontSize: 11, fontWeight: FontWeight.w500)),
          ),
        ],
      ]),
    );
  }
}

class _CatRow extends StatelessWidget {
  final String category;
  final double amount, total;
  final bool selected;
  const _CatRow({required this.category, required this.amount, required this.total, required this.selected});

  @override
  Widget build(BuildContext context) {
    final pct = total > 0 ? (amount / total).clamp(0.0, 1.0) : 0.0;
    return Padding(
      padding: const EdgeInsets.only(bottom: 20),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Row(children: [
          Expanded(child: Text(category, style: TextStyle(
              color: Colors.white.withOpacity(selected ? 1.0 : 0.7), fontSize: 14,
              fontWeight: selected ? FontWeight.w500 : FontWeight.w400))),
          Text('₹${_fmt(amount)}', style: TextStyle(
              color: Colors.white.withOpacity(selected ? 0.85 : 0.5),
              fontSize: 14, fontWeight: FontWeight.w500)),
        ]),
        const SizedBox(height: 8),
        ClipRRect(borderRadius: BorderRadius.circular(2),
            child: LinearProgressIndicator(value: pct, minHeight: 2,
                backgroundColor: Colors.white.withOpacity(0.06),
                valueColor: AlwaysStoppedAnimation<Color>(
                    Colors.white.withOpacity(selected ? 1.0 : 0.35)))),
      ]),
    );
  }
}

class _EmptyDonut extends StatefulWidget {
  const _EmptyDonut();
  @override
  State<_EmptyDonut> createState() => _EmptyDonutState();
}

class _EmptyDonutState extends State<_EmptyDonut> with SingleTickerProviderStateMixin {
  late AnimationController _ctrl;
  late Animation<double> _pulse;
  @override
  void initState() {
    super.initState();
    _ctrl = AnimationController(vsync: this, duration: const Duration(milliseconds: 2400))
      ..repeat(reverse: true);
    _pulse = CurvedAnimation(parent: _ctrl, curve: Curves.easeInOut);
  }
  @override
  void dispose() { _ctrl.dispose(); super.dispose(); }

  @override
  Widget build(BuildContext context) {
    return SizedBox(height: 220, child: LayoutBuilder(builder: (_, constraints) {
      final canvasW = constraints.maxWidth;
      return AnimatedBuilder(animation: _pulse, builder: (_, __) => CustomPaint(
        painter: _EmptyDonutPainter(pulse: _pulse.value, canvasWidth: canvasW),
        size: Size(canvasW, 220),
        child: Center(child: Column(mainAxisSize: MainAxisSize.min, children: [
          Icon(Icons.receipt_long_outlined, size: 18,
              color: Colors.white.withOpacity(0.12 + _pulse.value * 0.06)),
          const SizedBox(height: 6),
          Text('No data', style: TextStyle(fontSize: 11, letterSpacing: 0.5,
              color: Colors.white.withOpacity(0.18 + _pulse.value * 0.08))),
        ])),
      ));
    }));
  }
}

class _EmptyDonutPainter extends CustomPainter {
  final double pulse, canvasWidth;
  const _EmptyDonutPainter({required this.pulse, required this.canvasWidth});

  @override
  void paint(Canvas canvas, Size size) {
    final cx = canvasWidth / 2, cy = size.height / 2;
    const outer = 96.0, inner = 58.0, mid = (outer + inner) / 2, thick = outer - inner;
    final fillPath = Path()
      ..addOval(Rect.fromCircle(center: Offset(cx, cy), radius: outer))
      ..addOval(Rect.fromCircle(center: Offset(cx, cy), radius: inner));
    fillPath.fillType = PathFillType.evenOdd;
    canvas.drawPath(fillPath,
        Paint()..color = Colors.white.withOpacity(0.04 + pulse * 0.02)..style = PaintingStyle.fill);
    const dashCount = 24, dashAngle = (2 * math.pi) / dashCount, dashFrac = 0.55;
    final dashPaint = Paint()
      ..color = Colors.white.withOpacity(0.10 + pulse * 0.06)..style = PaintingStyle.stroke
      ..strokeWidth = thick * 0.22..strokeCap = StrokeCap.round;
    for (var i = 0; i < dashCount; i++) {
      canvas.drawArc(Rect.fromCircle(center: Offset(cx, cy), radius: mid),
          i * dashAngle - math.pi / 2, dashAngle * dashFrac, false, dashPaint);
    }
    canvas.drawArc(Rect.fromCircle(center: Offset(cx, cy), radius: mid),
        -math.pi / 2 + pulse * math.pi * 0.4, math.pi / 3.2, false,
        Paint()..color = Colors.white.withOpacity(0.20 + pulse * 0.12)
          ..style = PaintingStyle.stroke..strokeWidth = thick * 0.28..strokeCap = StrokeCap.round);
  }

  @override
  bool shouldRepaint(_EmptyDonutPainter old) => old.pulse != pulse || old.canvasWidth != canvasWidth;
}

class _CatBars extends StatelessWidget {
  final Map<String, double> cats;
  final double total;
  final String? selected;
  final ValueChanged<String> onSelect;
  const _CatBars({required this.cats, required this.total, required this.selected, required this.onSelect});

  @override
  Widget build(BuildContext context) {
    return Column(children: cats.entries.map((e) {
      final isSelected = selected == e.key;
      final isHidden   = selected != null && !isSelected;
      return GestureDetector(
        behavior: HitTestBehavior.opaque,
        onTap: () => onSelect(e.key),
        child: AnimatedOpacity(
          duration: const Duration(milliseconds: 300), curve: Curves.easeInOut,
          opacity: isHidden ? 0.0 : 1.0,
          child: ClipRect(child: AnimatedAlign(
            duration: const Duration(milliseconds: 350), curve: Curves.easeInOutCubic,
            alignment: Alignment.topCenter, heightFactor: isHidden ? 0.0 : 1.0,
            child: _CatRow(category: e.key, amount: e.value, total: total, selected: isSelected),
          )),
        ),
      );
    }).toList());
  }
}

class _TxnTile extends StatefulWidget {
  final Map<String, dynamic> txn;
  final bool expanded;
  final VoidCallback onTap;
  final VoidCallback? onDeleted;
  final VoidCallback? onCategoryChanged;
  const _TxnTile({required this.txn, required this.expanded,
    required this.onTap, this.onDeleted, this.onCategoryChanged});

  @override
  State<_TxnTile> createState() => _TxnTileState();
}

class _TxnTileState extends State<_TxnTile> {
  late String _cat;

  @override
  void initState() {
    super.initState();
    _cat = widget.txn['category'] as String? ?? 'Misc';
  }

  @override
  void didUpdateWidget(_TxnTile old) {
    super.didUpdateWidget(old);
    // Sync if parent rebuilds with new category
    final newCat = widget.txn['category'] as String? ?? 'Misc';
    if (newCat != _cat) _cat = newCat;
  }

  Future<void> _confirmDelete(BuildContext context) async {
    final ok = await showDialog<bool>(
      context: context,
      barrierColor: Colors.black.withOpacity(0.6),
      builder: (_) => Dialog(
        backgroundColor: Colors.transparent,
        elevation: 0,
        child: Container(
          padding: const EdgeInsets.all(24),
          decoration: BoxDecoration(
            color: const Color(0xFF1C1C1E),
            borderRadius: BorderRadius.circular(20),
            border: Border.all(color: Colors.white.withOpacity(0.06)),
          ),
          child: Column(mainAxisSize: MainAxisSize.min, children: [
            Container(
              width: 48, height: 48,
              decoration: BoxDecoration(
                color: const Color(0xFFFF453A).withOpacity(0.1),
                shape: BoxShape.circle,
              ),
              child: const Icon(Icons.delete_outline,
                  color: Color(0xFFFF453A), size: 22),
            ),
            const SizedBox(height: 16),
            const Text('Delete transaction',
                style: TextStyle(color: Colors.white, fontSize: 16,
                    fontWeight: FontWeight.w500)),
            const SizedBox(height: 8),
            Text("This can't be undone.",
                textAlign: TextAlign.center,
                style: TextStyle(color: Colors.white.withOpacity(0.35),
                    fontSize: 13, height: 1.4)),
            const SizedBox(height: 24),
            Row(children: [
              Expanded(
                child: GestureDetector(
                  onTap: () => Navigator.pop(_, false),
                  child: Container(
                    padding: const EdgeInsets.symmetric(vertical: 13),
                    decoration: BoxDecoration(
                      color: Colors.white.withOpacity(0.06),
                      borderRadius: BorderRadius.circular(12),
                    ),
                    child: Center(child: Text('Cancel',
                        style: TextStyle(color: Colors.white.withOpacity(0.5),
                            fontSize: 14))),
                  ),
                ),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: GestureDetector(
                  onTap: () => Navigator.pop(_, true),
                  child: Container(
                    padding: const EdgeInsets.symmetric(vertical: 13),
                    decoration: BoxDecoration(
                      color: const Color(0xFFFF453A).withOpacity(0.12),
                      borderRadius: BorderRadius.circular(12),
                      border: Border.all(
                          color: const Color(0xFFFF453A).withOpacity(0.3)),
                    ),
                    child: const Center(child: Text('Delete',
                        style: TextStyle(color: Color(0xFFFF453A),
                            fontSize: 14, fontWeight: FontWeight.w500))),
                  ),
                ),
              ),
            ]),
          ]),
        ),
      ),
    );
    if (ok == true) {
      await Repo.deleteTxn(widget.txn['id'] as int);
      widget.onDeleted?.call();
    }
  }


  Future<void> _showEditSheet(BuildContext context) async {
    final nameCtrl   = TextEditingController(
        text: widget.txn['merchant_name'] as String? ?? '');
    final newCatCtrl = TextEditingController();
    // Load from shared store; make sure current cat is included
    CategoryStore.instance.ensure(_cat);
    final List<String> cats = List<String>.from(await CategoryStore.instance.get());
    // Auto-select current category (already assigned to this txn)
    String selectedCat = _cat;
    bool   addingNew   = false;

    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: const Color(0xFF141414),
      shape: const RoundedRectangleBorder(
          borderRadius: BorderRadius.vertical(top: Radius.circular(20))),
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setInner) => Padding(
          padding: EdgeInsets.only(
              bottom: MediaQuery.of(ctx).viewInsets.bottom),
          child: Padding(
            padding: const EdgeInsets.fromLTRB(24, 20, 24, 36),
            child: Column(mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start, children: [
                  Center(child: Container(width: 32, height: 3,
                      decoration: BoxDecoration(color: Colors.white12,
                          borderRadius: BorderRadius.circular(2)))),
                  const SizedBox(height: 20),

                  // Name
                  TextField(
                    controller: nameCtrl,
                    textCapitalization: TextCapitalization.words,
                    style: const TextStyle(color: Colors.white, fontSize: 15),
                    decoration: InputDecoration(
                      hintText: 'Merchant name',
                      hintStyle: TextStyle(
                          color: Colors.white.withOpacity(0.2), fontSize: 15),
                      filled: true,
                      fillColor: const Color(0xFF1C1C1E),
                      border: OutlineInputBorder(
                          borderRadius: BorderRadius.circular(12),
                          borderSide: BorderSide.none),
                      contentPadding: const EdgeInsets.symmetric(
                          horizontal: 16, vertical: 13),
                    ),
                  ),
                  const SizedBox(height: 12),

                  // Category chips inline
                  SingleChildScrollView(
                    scrollDirection: Axis.horizontal,
                    child: Row(children: [
                      ...cats.map((cat) {
                        final sel = selectedCat == cat && !addingNew;
                        return GestureDetector(
                          onTap: () => setInner(() {
                            selectedCat = cat; addingNew = false;
                          }),
                          child: AnimatedContainer(
                            duration: const Duration(milliseconds: 160),
                            margin: const EdgeInsets.only(right: 8),
                            padding: const EdgeInsets.symmetric(
                                horizontal: 14, vertical: 8),
                            decoration: BoxDecoration(
                              color: sel ? Colors.white : const Color(0xFF1C1C1E),
                              borderRadius: BorderRadius.circular(20),
                            ),
                            child: Text(cat, style: TextStyle(
                                fontSize: 13,
                                color: sel ? Colors.black
                                    : Colors.white.withOpacity(0.45))),
                          ),
                        );
                      }),
                      // + Other
                      addingNew
                          ? Container(
                        margin: const EdgeInsets.only(right: 8),
                        width: 110,
                        padding: const EdgeInsets.symmetric(horizontal: 10),
                        decoration: BoxDecoration(
                          color: Colors.white.withOpacity(0.1),
                          borderRadius: BorderRadius.circular(20),
                        ),
                        child: TextField(
                          controller: newCatCtrl,
                          autofocus: true,
                          textCapitalization: TextCapitalization.words,
                          style: const TextStyle(
                              color: Colors.white, fontSize: 13),
                          decoration: InputDecoration(
                            hintText: 'Category',
                            hintStyle: TextStyle(
                                color: Colors.white.withOpacity(0.25),
                                fontSize: 13),
                            border: InputBorder.none,
                            isDense: true,
                            contentPadding:
                            const EdgeInsets.symmetric(vertical: 8),
                          ),
                          onSubmitted: (v) {
                            final val = v.trim();
                            if (val.isNotEmpty) {
                              unawaited(CategoryStore.instance.add(val));
                              if (!cats.contains(val)) cats.add(val);
                            }
                            setInner(() {
                              if (val.isNotEmpty) selectedCat = val;
                              addingNew = false;
                            });
                          },
                        ),
                      )
                          : GestureDetector(
                        onTap: () => setInner(() {
                          addingNew = true; newCatCtrl.clear();
                        }),
                        child: Container(
                          margin: const EdgeInsets.only(right: 8),
                          padding: const EdgeInsets.symmetric(
                              horizontal: 14, vertical: 8),
                          decoration: BoxDecoration(
                            color: const Color(0xFF1C1C1E),
                            borderRadius: BorderRadius.circular(20),
                          ),
                          child: Text('+ Other', style: TextStyle(
                              fontSize: 13,
                              color: Colors.white.withOpacity(0.3))),
                        ),
                      ),
                    ]),
                  ),
                  const SizedBox(height: 20),

                  // Save
                  SizedBox(
                    width: double.infinity,
                    child: GestureDetector(
                      onTap: () async {
                        final name = nameCtrl.text.trim();
                        final cat  = addingNew && newCatCtrl.text.trim().isNotEmpty
                            ? newCatCtrl.text.trim() : selectedCat;
                        Navigator.pop(ctx);
                        if (name.isEmpty) return;

                        final payeeKey = widget.txn['payee_key'] as String? ?? '';
                        final merchant = widget.txn['merchant_name'] as String? ?? payeeKey;

                        final ok = await showDialog<bool>(
                          context: context,
                          barrierColor: Colors.black.withOpacity(0.6),
                          builder: (_) => Dialog(
                            backgroundColor: Colors.transparent, elevation: 0,
                            child: Container(
                              padding: const EdgeInsets.all(24),
                              decoration: BoxDecoration(
                                color: const Color(0xFF1C1C1E),
                                borderRadius: BorderRadius.circular(20),
                                border: Border.all(
                                    color: Colors.white.withOpacity(0.06)),
                              ),
                              child: Column(mainAxisSize: MainAxisSize.min,
                                  children: [
                                    Container(
                                        width: 48, height: 48,
                                        decoration: BoxDecoration(
                                            color: Colors.white.withOpacity(0.07),
                                            shape: BoxShape.circle),
                                        child: Icon(Icons.edit_outlined,
                                            color: Colors.white.withOpacity(0.6),
                                            size: 20)),
                                    const SizedBox(height: 16),
                                    Text('Update "$merchant"',
                                        style: const TextStyle(color: Colors.white,
                                            fontSize: 16,
                                            fontWeight: FontWeight.w500)),
                                    const SizedBox(height: 8),
                                    Text(
                                      'Updates all past and future transactions from this vendor.',
                                      textAlign: TextAlign.center,
                                      style: TextStyle(
                                          color: Colors.white.withOpacity(0.35),
                                          fontSize: 13, height: 1.4),
                                    ),
                                    const SizedBox(height: 24),
                                    Row(children: [
                                      Expanded(child: GestureDetector(
                                        onTap: () => Navigator.pop(_, false),
                                        child: Container(
                                            padding: const EdgeInsets.symmetric(
                                                vertical: 13),
                                            decoration: BoxDecoration(
                                                color: Colors.white.withOpacity(0.06),
                                                borderRadius: BorderRadius.circular(12)),
                                            child: Center(child: Text('Cancel',
                                                style: TextStyle(
                                                    color: Colors.white.withOpacity(0.5),
                                                    fontSize: 14)))),
                                      )),
                                      const SizedBox(width: 10),
                                      Expanded(child: GestureDetector(
                                        onTap: () => Navigator.pop(_, true),
                                        child: Container(
                                            padding: const EdgeInsets.symmetric(
                                                vertical: 13),
                                            decoration: BoxDecoration(
                                                color: Colors.white,
                                                borderRadius: BorderRadius.circular(12)),
                                            child: const Center(child: Text('Update',
                                                style: TextStyle(color: Colors.black,
                                                    fontSize: 14,
                                                    fontWeight: FontWeight.w600)))),
                                      )),
                                    ]),
                                  ]),
                            ),
                          ),
                        );

                        if (ok == true) {
                          setState(() => _cat = cat);
                          await Repo.updateVendorCategory(payeeKey, cat);
                          CategoryStore.instance.invalidate();
                          widget.onCategoryChanged?.call();
                        }
                      },
                      child: Container(
                        padding: const EdgeInsets.symmetric(vertical: 14),
                        decoration: BoxDecoration(
                            color: Colors.white,
                            borderRadius: BorderRadius.circular(14)),
                        child: const Center(child: Text('Save',
                            style: TextStyle(color: Colors.black,
                                fontWeight: FontWeight.w600, fontSize: 15))),
                      ),
                    ),
                  ),
                ]),
          ),
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final isDebit  = widget.txn['type'] == 'debit';
    final amount   = (widget.txn['amount'] as num).toDouble();
    final date     = DateTime.fromMillisecondsSinceEpoch(widget.txn['timestamp'] as int);
    final ref      = widget.txn['ref_number'] as String? ?? '';
    final payeeKey = widget.txn['payee_key']  as String? ?? '';
    final isCash   = widget.txn['is_cash'] == true;

    return GestureDetector(
      behavior: HitTestBehavior.opaque,
      onTap: widget.onTap,
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
                  isCash ? Icons.payments_outlined
                      : isDebit ? Icons.keyboard_arrow_up : Icons.keyboard_arrow_down,
                  size: 22,
                  color: isDebit
                      ? const Color(0xFFFF453A).withOpacity(0.8)
                      : const Color(0xFF30D158).withOpacity(0.8),
                ),
              ),
              const SizedBox(width: 14),
              Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                Text(widget.txn['merchant_name'], style: const TextStyle(
                    color: Colors.white, fontSize: 15, fontWeight: FontWeight.w400)),
                const SizedBox(height: 3),
                Row(children: [
                  Text(_cat, style: TextStyle(
                      color: Colors.white.withOpacity(0.28), fontSize: 11)),
                  Text('  ·  ', style: TextStyle(
                      color: Colors.white.withOpacity(0.15), fontSize: 11)),
                  Text(_fmtDate(date), style: TextStyle(
                      color: Colors.white.withOpacity(0.28), fontSize: 11)),
                  if (isCash) ...[
                    Text('  ·  ', style: TextStyle(
                        color: Colors.white.withOpacity(0.15), fontSize: 11)),
                    Text('cash', style: TextStyle(
                        color: Colors.white.withOpacity(0.2), fontSize: 11)),
                  ],
                ]),
              ])),
              Text('${isDebit ? '−' : '+'}₹${_fmtExact(amount)}',
                  style: TextStyle(
                    color: isDebit ? const Color(0xFFFF453A) : const Color(0xFF30D158),
                    fontSize: 15, fontWeight: FontWeight.w500,
                  )),
            ]),
          ),
          ClipRect(
            child: AnimatedAlign(
              duration: const Duration(milliseconds: 300), curve: Curves.easeInOutCubic,
              alignment: Alignment.topCenter,
              heightFactor: widget.expanded ? 1.0 : 0.0,
              child: AnimatedOpacity(
                duration: const Duration(milliseconds: 250),
                opacity: widget.expanded ? 1.0 : 0.0,
                child: Padding(
                  padding: const EdgeInsets.only(left: 50, bottom: 14),
                  child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
                    Expanded(child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start, children: [
                      _DetailRow(label: 'Ref',   value: ref),
                      const SizedBox(height: 6),
                      _DetailRow(label: 'Payee', value: payeeKey),
                    ])),
                    // Edit (name + category)
                    GestureDetector(
                      onTap: () => _showEditSheet(context),
                      child: Padding(
                        padding: const EdgeInsets.only(right: 12, top: 2),
                        child: Icon(Icons.edit_outlined,
                            size: 17, color: Colors.white.withOpacity(0.2)),
                      ),
                    ),
                    // Delete
                    GestureDetector(
                      onTap: () => _confirmDelete(context),
                      child: Padding(
                        padding: const EdgeInsets.only(right: 4, top: 2),
                        child: Icon(Icons.delete_outline,
                            size: 18, color: Colors.white.withOpacity(0.2)),
                      ),
                    ),
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
          color: Colors.white.withOpacity(0.4), fontSize: 11, fontFamily: 'monospace'))),
    ]);
  }
}

class _SectionLabel extends StatelessWidget {
  final String text;
  const _SectionLabel(this.text);
  @override
  Widget build(BuildContext context) => Text(text, style: TextStyle(fontSize: 11, letterSpacing: 2,
      color: Colors.white.withOpacity(0.25), fontWeight: FontWeight.w600));
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

// Exact amount with decimals if non-zero, Indian comma formatting
String _fmtExact(double a) {
  // Keep up to 2 decimal places, strip trailing zeros
  final withDec = a.toStringAsFixed(2);
  final trimmed = withDec.replaceAll(RegExp(r'\.?0+$'), '');
  final parts   = trimmed.split('.');
  final intPart = parts[0];
  final decPart = parts.length > 1 ? '.${parts[1]}' : '';
  // Indian number formatting on the integer part
  if (intPart.length <= 3) return '$intPart$decPart';
  final rev = intPart.split('').reversed.toList();
  final buf = <String>[];
  for (var i = 0; i < rev.length; i++) {
    if (i == 3 || (i > 3 && (i - 3) % 2 == 0)) buf.add(',');
    buf.add(rev[i]);
  }
  return '${buf.reversed.join()}$decPart';
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
  const mo = ['Jan','Feb','Mar','Apr','May','Jun','Jul','Aug','Sep','Oct','Nov','Dec'];
  return '${d.day} ${mo[d.month - 1]}, $time';
}