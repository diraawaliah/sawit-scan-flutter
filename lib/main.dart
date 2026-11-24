import 'dart:async';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:firebase_core/firebase_core.dart';
import 'package:firebase_messaging/firebase_messaging.dart';
import 'package:geolocator/geolocator.dart';
import 'package:image_picker/image_picker.dart';
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';
import 'package:share_plus/share_plus.dart';

import 'classifier.dart';
import 'db.dart';
import 'pages/harvest_calendar_page.dart';
import 'services/api_service.dart';

void main() {
  WidgetsFlutterBinding.ensureInitialized();
  runApp(const SawitApp());
  // Inisialisasi Firebase & FCM di background tanpa memblokir startup aplikasi
  unawaited(_initBackgroundServices());
}

Future<void> _initBackgroundServices() async {
  try {
    await Firebase.initializeApp().timeout(const Duration(seconds: 4));
    final fcmToken = await FirebaseMessaging.instance
        .getToken()
        .timeout(const Duration(seconds: 3));
    if (fcmToken != null) {
      await ApiService.registerDevice(fcmToken)
          .timeout(const Duration(seconds: 3));
    }
  } catch (e) {
    debugPrint('Firebase init background (offline/timeout): $e');
  }
}

// ============================================================================
// REKOMENDASI TINDAKAN & WARNA PER KELAS KEMATANGAN (3 KELAS DATASET)
// ============================================================================
(String, Color) actionFor(String label) {
  final clean = label.trim().toLowerCase().replaceAll('_', ' ');
  if (clean.contains('belum') || clean.contains('mentah')) {
    return ('TUNDA PANEN - TBS Belum Matang', const Color(0xFFC62828));
  } else if (clean.contains('lewat') || clean.contains('busuk')) {
    return ('PANEN SEGERA - TBS Lewat Matang', const Color(0xFFD84315));
  } else if (clean.contains('matang')) {
    return ('PANEN SEKARANG - Kematangan Optimal', const Color(0xFF2E7D32));
  }
  return ('TIDAK YAKIN - Coba Foto Ulang', const Color(0xFF455A64));
}

String fmtTime(String iso) {
  if (iso.length < 16) return iso;
  return iso.substring(0, 16).replaceFirst('T', ' ');
}

// ============================================================================
// WIDGET LOGO APLIKASI (Mendukung Gambar Kustom assets/images/logo.png / Vector)
// ============================================================================
class AppLogo extends StatelessWidget {
  final double size;
  final bool showShadow;
  final bool isLight;

  const AppLogo({
    super.key,
    this.size = 80,
    this.showShadow = true,
    this.isLight = false,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      width: size,
      height: size,
      decoration: BoxDecoration(
        shape: BoxShape.circle,
        gradient: LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: isLight
              ? [const Color(0xFF2E7D32), const Color(0xFF1E5631)]
              : [const Color(0xFF43A047), const Color(0xFF0F3E1F)],
        ),
        boxShadow: showShadow
            ? [
                BoxShadow(
                  color: const Color(0xFF1E5631).withValues(alpha: 0.35),
                  blurRadius: size * 0.2,
                  spreadRadius: size * 0.03,
                  offset: Offset(0, size * 0.08),
                ),
              ]
            : null,
        border: Border.all(
          color: const Color(0xFFA4DE02).withValues(alpha: 0.8),
          width: size * 0.03,
        ),
      ),
      child: ClipOval(
        // Coba memuat gambar logo kustom jika pengguna meletakkannya di assets/images/logo.png
        child: Image.asset(
          'assets/images/logo.png',
          width: size,
          height: size,
          fit: BoxFit.cover,
          errorBuilder: (_, __, ___) => _buildVectorLogo(size),
        ),
      ),
    );
  }

  Widget _buildVectorLogo(double s) {
    return Center(
      child: Stack(
        alignment: Alignment.center,
        children: [
          // Lingkaran aksen sawit oranye
          Container(
            width: s * 0.58,
            height: s * 0.58,
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              color: const Color(0xFFE65100).withValues(alpha: 0.25),
            ),
          ),
          // Ikon helai daun / kelapa sawit
          Icon(
            Icons.spa_rounded,
            size: s * 0.52,
            color: const Color(0xFFA4DE02),
          ),
          // Ikon bidikan AI Scanner
          Icon(
            Icons.center_focus_strong_rounded,
            size: s * 0.68,
            color: Colors.white.withValues(alpha: 0.95),
          ),
        ],
      ),
    );
  }
}

// ============================================================================
// ROOT APP
// ============================================================================
class SawitApp extends StatelessWidget {
  const SawitApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'SawitScan',
      debugShowCheckedModeBanner: false,
      theme: ThemeData(
        useMaterial3: true,
        colorScheme: ColorScheme.fromSeed(
          seedColor: const Color(0xFF1E5631),
          primary: const Color(0xFF1E5631),
          secondary: const Color(0xFF388E3C),
          surface: const Color(0xFFF7F9F6),
        ),
        scaffoldBackgroundColor: const Color(0xFFF3F6F3),
        appBarTheme: const AppBarTheme(
          centerTitle: false,
          elevation: 0,
          backgroundColor: Colors.white,
          foregroundColor: Color(0xFF1E5631),
          surfaceTintColor: Colors.transparent,
          titleTextStyle: TextStyle(
            fontSize: 20,
            fontWeight: FontWeight.bold,
            color: Color(0xFF1E5631),
          ),
        ),
        cardTheme: CardThemeData(
          color: Colors.white,
          elevation: 1,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(16),
            side: BorderSide(color: Colors.grey.shade200),
          ),
        ),
      ),
      home: const SplashScreen(),
    );
  }
}

// ============================================================================
// 1. SPLASH SCREEN GACOR NAN CIAMIK
// ============================================================================
class SplashScreen extends StatefulWidget {
  const SplashScreen({super.key});

  @override
  State<SplashScreen> createState() => _SplashScreenState();
}

class _SplashScreenState extends State<SplashScreen>
    with SingleTickerProviderStateMixin {
  late AnimationController _controller;
  late Animation<double> _scaleAnimation;
  late Animation<double> _fadeAnimation;
  late Animation<double> _slideAnimation;

  String _statusText = 'Menginisialisasi Engine AI...';
  double _progressValue = 0.2;

  @override
  void initState() {
    super.initState();
    _controller = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 900),
    );

    _scaleAnimation = Tween<double>(begin: 0.75, end: 1.0).animate(
      CurvedAnimation(parent: _controller, curve: Curves.easeOutBack),
    );

    _fadeAnimation = Tween<double>(begin: 0.0, end: 1.0).animate(
      CurvedAnimation(parent: _controller, curve: Curves.easeIn),
    );

    _slideAnimation = Tween<double>(begin: 30.0, end: 0.0).animate(
      CurvedAnimation(parent: _controller, curve: Curves.easeOutCubic),
    );

    _controller.forward();
    _startLoadingSequence();
  }

  void _startLoadingSequence() {
    // Inisialisasi visual yang cepat dan mulus
    Timer(const Duration(milliseconds: 300), () {
      if (mounted) {
        setState(() {
          _statusText = 'Menyiapkan Model MobileNetV2 & ResNetV2...';
          _progressValue = 0.60;
        });
      }
    });

    Timer(const Duration(milliseconds: 650), () {
      if (mounted) {
        setState(() {
          _statusText = 'Menghubungkan Database Hasil Panen...';
          _progressValue = 0.90;
        });
      }
    });

    Timer(const Duration(milliseconds: 950), () {
      if (mounted) {
        setState(() {
          _statusText = 'Siap Digunakan!';
          _progressValue = 1.0;
        });
      }
    });

    // Pindah ke Dashboard utama tanpa delay berlebihan
    Timer(const Duration(milliseconds: 1200), _navigateToHome);
  }

  void _navigateToHome() {
    if (!mounted) return;
    Navigator.of(context).pushReplacement(
      PageRouteBuilder(
        transitionDuration: const Duration(milliseconds: 400),
        pageBuilder: (_, __, ___) => const HomePage(),
        transitionsBuilder: (_, anim, __, child) =>
            FadeTransition(opacity: anim, child: child),
      ),
    );
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFF0C2B16),
      body: Stack(
        children: [
          // Background Gradient Deep Jungle
          Container(
            decoration: const BoxDecoration(
              gradient: LinearGradient(
                begin: Alignment.topCenter,
                end: Alignment.bottomCenter,
                colors: [
                  Color(0xFF082211),
                  Color(0xFF103A1E),
                  Color(0xFF1E5631),
                ],
              ),
            ),
          ),

          // Dekorasi Lingkaran Artistik
          Positioned(
            top: -60,
            right: -60,
            child: Container(
              width: 240,
              height: 240,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                color: const Color(0xFFA4DE02).withValues(alpha: 0.08),
              ),
            ),
          ),
          Positioned(
            bottom: -80,
            left: -80,
            child: Container(
              width: 280,
              height: 280,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                color: const Color(0xFFE65100).withValues(alpha: 0.08),
              ),
            ),
          ),

          // Konten Utama Tengah
          SafeArea(
            child: Center(
              child: Padding(
                padding: const EdgeInsets.symmetric(horizontal: 32),
                child: Column(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    const Spacer(),

                    // Logo beranimasi Scale & Fade
                    AnimatedBuilder(
                      animation: _controller,
                      builder: (context, child) {
                        return Transform.scale(
                          scale: _scaleAnimation.value,
                          child: Opacity(
                            opacity: _fadeAnimation.value,
                            child: child,
                          ),
                        );
                      },
                      child: const AppLogo(size: 110, showShadow: true),
                    ),

                    const SizedBox(height: 28),

                    // Judul Aplikasi
                    AnimatedBuilder(
                      animation: _controller,
                      builder: (context, child) {
                        return Transform.translate(
                          offset: Offset(0, _slideAnimation.value),
                          child: Opacity(
                            opacity: _fadeAnimation.value,
                            child: child,
                          ),
                        );
                      },
                      child: Column(
                        children: [
                          Row(
                            mainAxisAlignment: MainAxisAlignment.center,
                            children: [
                              const Text(
                                'SawitScan',
                                style: TextStyle(
                                  fontSize: 34,
                                  fontWeight: FontWeight.w900,
                                  color: Colors.white,
                                  letterSpacing: 0.8,
                                ),
                              ),
                              const SizedBox(width: 6),
                              Container(
                                padding: const EdgeInsets.symmetric(
                                    horizontal: 8, vertical: 3),
                                decoration: BoxDecoration(
                                  color: const Color(0xFFA4DE02),
                                  borderRadius: BorderRadius.circular(8),
                                ),
                                child: const Text(
                                  'AI',
                                  style: TextStyle(
                                    fontSize: 16,
                                    fontWeight: FontWeight.bold,
                                    color: Color(0xFF0C2B16),
                                  ),
                                ),
                              ),
                            ],
                          ),
                          const SizedBox(height: 8),
                          Text(
                            'Sistem Klasifikasi Kematangan TBS Sawit',
                            textAlign: TextAlign.center,
                            style: TextStyle(
                              fontSize: 14,
                              color: Colors.white.withValues(alpha: 0.85),
                              fontWeight: FontWeight.w400,
                              letterSpacing: 0.2,
                            ),
                          ),
                        ],
                      ),
                    ),

                    const Spacer(),

                    // Loading Indicator & Status Bar
                    Column(
                      children: [
                        ClipRRect(
                          borderRadius: BorderRadius.circular(8),
                          child: SizedBox(
                            width: 200,
                            height: 6,
                            child: LinearProgressIndicator(
                              value: _progressValue,
                              backgroundColor:
                                  Colors.white.withValues(alpha: 0.15),
                              valueColor: const AlwaysStoppedAnimation<Color>(
                                Color(0xFFA4DE02),
                              ),
                            ),
                          ),
                        ),
                        const SizedBox(height: 14),
                        AnimatedSwitcher(
                          duration: const Duration(milliseconds: 300),
                          child: Text(
                            _statusText,
                            key: ValueKey(_statusText),
                            style: TextStyle(
                              fontSize: 12,
                              color: Colors.white.withValues(alpha: 0.75),
                            ),
                          ),
                        ),
                      ],
                    ),

                    const SizedBox(height: 36),

                    // Version Tag & Lewati
                    Row(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      children: [
                        Text(
                          'v1.2.0 • Offline Ready',
                          style: TextStyle(
                            fontSize: 11,
                            color: Colors.white.withValues(alpha: 0.5),
                          ),
                        ),
                        TextButton(
                          onPressed: _navigateToHome,
                          style: TextButton.styleFrom(
                            foregroundColor: const Color(0xFFA4DE02),
                            padding: const EdgeInsets.symmetric(horizontal: 12),
                          ),
                          child: const Row(
                            children: [
                              Text('Mulai', style: TextStyle(fontSize: 12)),
                              Icon(Icons.chevron_right, size: 16),
                            ],
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 12),
                  ],
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

// ============================================================================
// DASHBOARD UTAMA DENGAN BOTTOM NAVIGATION BAR
// ============================================================================
class HomePage extends StatefulWidget {
  const HomePage({super.key});

  @override
  State<HomePage> createState() => _HomePageState();
}

class _HomePageState extends State<HomePage> {
  final Classifier clf = Classifier();
  int _tab = 0;
  bool _loading = true;

  @override
  void initState() {
    super.initState();
    clf.load().then((_) {
      if (mounted) setState(() => _loading = false);
    });
  }

  void _showAboutDialog() {
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (_) => const AboutAppSheet(),
    );
  }

  @override
  Widget build(BuildContext context) {
    final pages = <Widget>[
      ScanPage(clf: clf, onModelChanged: () => setState(() {})),
      const HistoryPage(),
      const StatsPage(),
      const HarvestCalendarPage(),
      const HarvestGuidePage(),
    ];

    return Scaffold(
      appBar: _tab == 0
          ? AppBar(
              title: Row(
                children: [
                  const AppLogo(size: 32, showShadow: false),
                  const SizedBox(width: 10),
                  Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      const Text(
                        'SawitScan',
                        style: TextStyle(
                            fontSize: 18, fontWeight: FontWeight.bold),
                      ),
                      Text(
                        'Model: ${clf.currentModel.name}',
                        style: TextStyle(
                          fontSize: 11,
                          color: Colors.grey.shade600,
                          fontWeight: FontWeight.normal,
                        ),
                      ),
                    ],
                  ),
                ],
              ),
              actions: [
                IconButton(
                  tooltip: 'Tentang Aplikasi',
                  icon: const Icon(Icons.info_outline_rounded),
                  onPressed: _showAboutDialog,
                ),
              ],
            )
          : null,
      body: _loading
          ? const Center(
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  CircularProgressIndicator(color: Color(0xFF1E5631)),
                  SizedBox(height: 16),
                  Text('Memuat model AI...',
                      style: TextStyle(fontWeight: FontWeight.bold)),
                ],
              ),
            )
          : pages[_tab],
      bottomNavigationBar: NavigationBar(
        selectedIndex: _tab,
        onDestinationSelected: (i) => setState(() => _tab = i),
        destinations: const [
          NavigationDestination(
            icon: Icon(Icons.document_scanner_outlined),
            selectedIcon: Icon(Icons.document_scanner_rounded),
            label: 'Pindai',
          ),
          NavigationDestination(
            icon: Icon(Icons.history_outlined),
            selectedIcon: Icon(Icons.history_rounded),
            label: 'Riwayat',
          ),
          NavigationDestination(
            icon: Icon(Icons.analytics_outlined),
            selectedIcon: Icon(Icons.analytics_rounded),
            label: 'Statistik',
          ),
          NavigationDestination(
            icon: Icon(Icons.calendar_month_outlined),
            selectedIcon: Icon(Icons.calendar_month_rounded),
            label: 'Kalender',
          ),
          NavigationDestination(
            icon: Icon(Icons.menu_book_outlined),
            selectedIcon: Icon(Icons.menu_book_rounded),
            label: 'Panduan Mutu',
          ),
        ],
      ),
    );
  }
}

// ============================================================================
// 2. HALAMAN PINDAI (DENGAN PEMILIH MODEL MOBILENETV2 VS RESNETV2)
// ============================================================================
class ScanPage extends StatefulWidget {
  final Classifier clf;
  final VoidCallback onModelChanged;

  const ScanPage({
    super.key,
    required this.clf,
    required this.onModelChanged,
  });

  @override
  State<ScanPage> createState() => _ScanPageState();
}

class _ScanPageState extends State<ScanPage> {
  final _block = TextEditingController(text: 'Blok A-01');
  final _picker = ImagePicker();
  File? _file;
  Prediction? _pred;
  int? _scanId;
  String? _corrected;
  bool _busy = false;
  Map<String, int> _today = {};

  @override
  void initState() {
    super.initState();
    _loadToday();
  }

  @override
  void dispose() {
    _block.dispose();
    super.dispose();
  }

  Future<void> _loadToday() async {
    final rows = await AppDb.all();
    final d = DateTime.now().toIso8601String().substring(0, 10);
    final m = <String, int>{};
    for (final r in rows) {
      if ((r['created'] as String).startsWith(d)) {
        final l = effLabel(r);
        m[l] = (m[l] ?? 0) + 1;
      }
    }
    if (mounted) setState(() => _today = m);
  }

  Future<Position?> _gps() async {
    try {
      if (!await Geolocator.isLocationServiceEnabled()) return null;
      var perm = await Geolocator.checkPermission();
      if (perm == LocationPermission.denied) {
        perm = await Geolocator.requestPermission();
      }
      if (perm == LocationPermission.denied ||
          perm == LocationPermission.deniedForever) {
        return null;
      }
      return await Geolocator.getCurrentPosition(
        locationSettings: const LocationSettings(
          accuracy: LocationAccuracy.medium,
          timeLimit: Duration(seconds: 5),
        ),
      );
    } catch (_) {
      return null;
    }
  }

  void _msg(String t) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text(t), duration: const Duration(seconds: 4)),
    );
  }

  void _showModelPickerSheet() {
    showModalBottomSheet(
      context: context,
      backgroundColor: Colors.transparent,
      builder: (context) {
        return Container(
          decoration: const BoxDecoration(
            color: Colors.white,
            borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
          ),
          padding: const EdgeInsets.all(20),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Center(
                child: Container(
                  width: 44,
                  height: 5,
                  decoration: BoxDecoration(
                    color: Colors.grey.shade300,
                    borderRadius: BorderRadius.circular(10),
                  ),
                ),
              ),
              const SizedBox(height: 16),
              const Text(
                'Pilih Model AI Pembanding',
                style: TextStyle(
                  fontSize: 18,
                  fontWeight: FontWeight.bold,
                  color: Color(0xFF1E5631),
                ),
              ),
              const SizedBox(height: 6),
              Text(
                'Pilih arsitektur jaringan saraf untuk menguji akurasi dan kecepatan inferensi TBS.',
                style: TextStyle(fontSize: 12, color: Colors.grey.shade600),
              ),
              const SizedBox(height: 16),
              for (final m in kAvailableModels) ...[
                _buildModelOptionTile(m),
                const SizedBox(height: 10),
              ],
            ],
          ),
        );
      },
    );
  }

  Widget _buildModelOptionTile(ModelInfo m) {
    final isSelected = widget.clf.currentModel.id == m.id;
    return InkWell(
      onTap: () async {
        Navigator.pop(context);
        setState(() => _busy = true);
        final ok = await widget.clf.switchModel(m);
        widget.onModelChanged();
        if (mounted) {
          setState(() => _busy = false);
          if (ok) {
            _msg('Model aktif: ${m.name}');
          } else {
            _msg('Info: ${widget.clf.loadError}');
          }
        }
      },
      borderRadius: BorderRadius.circular(14),
      child: Container(
        padding: const EdgeInsets.all(14),
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(14),
          color: isSelected
              ? const Color(0xFF1E5631).withValues(alpha: 0.08)
              : Colors.grey.shade50,
          border: Border.all(
            color: isSelected ? const Color(0xFF1E5631) : Colors.grey.shade300,
            width: isSelected ? 2 : 1,
          ),
        ),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Container(
              padding: const EdgeInsets.all(10),
              decoration: BoxDecoration(
                color:
                    isSelected ? const Color(0xFF1E5631) : Colors.grey.shade200,
                borderRadius: BorderRadius.circular(10),
              ),
              child: Icon(
                m.id == 'mobilenet_v2' ? Icons.speed : Icons.psychology_rounded,
                color: isSelected ? Colors.white : Colors.grey.shade700,
                size: 24,
              ),
            ),
            const SizedBox(width: 14),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      Text(
                        m.name,
                        style: const TextStyle(
                          fontSize: 16,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                      const SizedBox(width: 8),
                      Container(
                        padding: const EdgeInsets.symmetric(
                            horizontal: 6, vertical: 2),
                        decoration: BoxDecoration(
                          color: isSelected
                              ? const Color(0xFF2E7D32)
                              : Colors.grey.shade300,
                          borderRadius: BorderRadius.circular(6),
                        ),
                        child: Text(
                          m.latencyBadge,
                          style: TextStyle(
                            fontSize: 10,
                            fontWeight: FontWeight.bold,
                            color: isSelected ? Colors.white : Colors.black87,
                          ),
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 4),
                  Text(
                    m.architecture,
                    style: TextStyle(
                      fontSize: 12,
                      fontWeight: FontWeight.w600,
                      color: Colors.grey.shade800,
                    ),
                  ),
                  const SizedBox(height: 2),
                  Text(
                    m.description,
                    style: TextStyle(fontSize: 11, color: Colors.grey.shade600),
                  ),
                ],
              ),
            ),
            if (isSelected)
              const Icon(Icons.check_circle, color: Color(0xFF1E5631)),
          ],
        ),
      ),
    );
  }

  Future<void> _pick(ImageSource source) async {
    if (!widget.clf.ready) {
      _msg(
          'Model ${widget.clf.currentModel.name} belum siap: ${widget.clf.loadError ?? "Pastikan file .tflite ada."}');
      return;
    }
    try {
      final x = await _picker.pickImage(
          source: source, imageQuality: 90, maxWidth: 1600);
      if (x == null) return;
      setState(() => _busy = true);

      final bytes = await x.readAsBytes();
      final pred = await widget.clf.predict(bytes);

      final dir = await getApplicationDocumentsDirectory();
      final saved =
          p.join(dir.path, 'scan_${DateTime.now().millisecondsSinceEpoch}.jpg');
      await File(x.path).copy(saved);

      final pos = await _gps();
      final id = await AppDb.insert({
        'path': saved,
        'label': pred.uncertain ? 'Tidak yakin' : pred.label,
        'confidence': pred.confidence,
        'block': _block.text.trim().isEmpty ? '-' : _block.text.trim(),
        'lat': pos?.latitude,
        'lng': pos?.longitude,
        'created': DateTime.now().toIso8601String(),
        'corrected': null,
        'model': widget.clf.currentModel.name,
      });

      if (!mounted) return;
      setState(() {
        _file = File(saved);
        _pred = pred;
        _scanId = id;
        _corrected = null;
      });
      await _loadToday();
    } catch (e) {
      _msg('Gagal memproses: $e');
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final pred = _pred;
    return ListView(
      padding: const EdgeInsets.all(16),
      children: [
        // ---------------- MODEL SELECTOR HEADER ----------------
        Container(
          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
          decoration: BoxDecoration(
            color: Colors.white,
            borderRadius: BorderRadius.circular(14),
            border: Border.all(color: Colors.grey.shade200),
          ),
          child: Row(
            children: [
              Container(
                padding: const EdgeInsets.all(8),
                decoration: BoxDecoration(
                  color: const Color(0xFF1E5631).withValues(alpha: 0.1),
                  borderRadius: BorderRadius.circular(10),
                ),
                child: const Icon(
                  Icons.psychology_alt_rounded,
                  color: Color(0xFF1E5631),
                  size: 22,
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const Text(
                      'Model AI Aktif:',
                      style: TextStyle(fontSize: 11, color: Colors.grey),
                    ),
                    Text(
                      widget.clf.currentModel.name,
                      style: const TextStyle(
                        fontSize: 15,
                        fontWeight: FontWeight.bold,
                        color: Color(0xFF1E5631),
                      ),
                    ),
                  ],
                ),
              ),
              OutlinedButton.icon(
                onPressed: _showModelPickerSheet,
                icon: const Icon(Icons.swap_horiz_rounded, size: 16),
                label:
                    const Text('Ganti Model', style: TextStyle(fontSize: 12)),
                style: OutlinedButton.styleFrom(
                  foregroundColor: const Color(0xFF1E5631),
                  side: const BorderSide(color: Color(0xFF1E5631)),
                  padding:
                      const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
                  visualDensity: VisualDensity.compact,
                ),
              ),
            ],
          ),
        ),

        const SizedBox(height: 12),

        // Peringatan jika file TFLite masih 0 byte / belum siap
        if (widget.clf.loadError != null)
          Container(
            margin: const EdgeInsets.only(bottom: 12),
            padding: const EdgeInsets.all(12),
            decoration: BoxDecoration(
              color: Colors.amber.shade50,
              borderRadius: BorderRadius.circular(10),
              border: Border.all(color: Colors.amber.shade400),
            ),
            child: Row(
              children: [
                const Icon(Icons.warning_amber_rounded,
                    color: Colors.orange, size: 28),
                const SizedBox(width: 10),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        'Status Model (${widget.clf.currentModel.name}):',
                        style: const TextStyle(
                            fontSize: 12, fontWeight: FontWeight.bold),
                      ),
                      const SizedBox(height: 2),
                      Text(
                        widget.clf.loadError!,
                        style:
                            const TextStyle(fontSize: 12, color: Colors.brown),
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),

        // Input Blok / Pemanen
        TextField(
          controller: _block,
          decoration: InputDecoration(
            labelText: 'Blok / Nama Pemanen',
            prefixIcon: const Icon(Icons.grid_view_rounded),
            border: OutlineInputBorder(borderRadius: BorderRadius.circular(12)),
            filled: true,
            fillColor: Colors.white,
            contentPadding:
                const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
          ),
        ),

        const SizedBox(height: 12),

        // Tombol Kamera & Galeri
        Row(
          children: [
            Expanded(
              child: FilledButton.icon(
                style: FilledButton.styleFrom(
                  backgroundColor: const Color(0xFF1E5631),
                  minimumSize: const Size.fromHeight(56),
                  shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(14)),
                ),
                onPressed: _busy ? null : () => _pick(ImageSource.camera),
                icon: const Icon(Icons.camera_alt_rounded),
                label: const Text('Buka Kamera',
                    style:
                        TextStyle(fontSize: 16, fontWeight: FontWeight.bold)),
              ),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: OutlinedButton.icon(
                style: OutlinedButton.styleFrom(
                  minimumSize: const Size.fromHeight(56),
                  shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(14)),
                  side: const BorderSide(color: Color(0xFF1E5631), width: 1.5),
                  foregroundColor: const Color(0xFF1E5631),
                ),
                onPressed: _busy ? null : () => _pick(ImageSource.gallery),
                icon: const Icon(Icons.photo_library_rounded),
                label: const Text('Dari Galeri',
                    style:
                        TextStyle(fontSize: 16, fontWeight: FontWeight.bold)),
              ),
            ),
          ],
        ),

        const SizedBox(height: 14),

        // Ringkasan Hari Ini
        if (_today.isNotEmpty) ...[
          Container(
            padding: const EdgeInsets.all(12),
            decoration: BoxDecoration(
              color: Colors.white,
              borderRadius: BorderRadius.circular(14),
              border: Border.all(color: Colors.grey.shade200),
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Row(
                  children: [
                    Icon(Icons.today_rounded,
                        size: 16, color: Color(0xFF1E5631)),
                    SizedBox(width: 6),
                    Text(
                      'Pemindaian Hari Ini',
                      style:
                          TextStyle(fontWeight: FontWeight.bold, fontSize: 13),
                    ),
                  ],
                ),
                const SizedBox(height: 8),
                Wrap(
                  spacing: 8,
                  runSpacing: 4,
                  children: _today.entries.map((e) {
                    final (_, col) = actionFor(e.key);
                    return Chip(
                      label: Text('${e.key}: ${e.value}',
                          style: TextStyle(
                              color: col,
                              fontWeight: FontWeight.bold,
                              fontSize: 12)),
                      backgroundColor: col.withValues(alpha: 0.1),
                      side: BorderSide(color: col.withValues(alpha: 0.3)),
                      visualDensity: VisualDensity.compact,
                    );
                  }).toList(),
                ),
              ],
            ),
          ),
          const SizedBox(height: 12),
        ],

        if (_busy)
          const Padding(
            padding: EdgeInsets.symmetric(vertical: 24),
            child: Center(
              child: Column(
                children: [
                  CircularProgressIndicator(color: Color(0xFF1E5631)),
                  SizedBox(height: 12),
                  Text('Menganalisis kematangan TBS...',
                      style: TextStyle(fontWeight: FontWeight.w600)),
                ],
              ),
            ),
          ),

        if (_file != null)
          ClipRRect(
            borderRadius: BorderRadius.circular(16),
            child: Image.file(_file!, height: 260, fit: BoxFit.cover),
          ),

        if (pred != null) ...[
          const SizedBox(height: 14),
          _resultCard(pred),
        ],
      ],
    );
  }

  Widget _resultCard(Prediction pred) {
    final shown = _corrected ?? (pred.uncertain ? 'Tidak yakin' : pred.label);
    final (action, color) = actionFor(shown);
    final sorted = pred.scores.entries.toList()
      ..sort((a, b) => b.value.compareTo(a.value));

    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // Banner Rekomendasi Panen
            Container(
              width: double.infinity,
              padding: const EdgeInsets.symmetric(vertical: 16, horizontal: 14),
              decoration: BoxDecoration(
                color: color,
                borderRadius: BorderRadius.circular(12),
                boxShadow: [
                  BoxShadow(
                    color: color.withValues(alpha: 0.3),
                    blurRadius: 8,
                    offset: const Offset(0, 4),
                  ),
                ],
              ),
              child: Text(
                action,
                textAlign: TextAlign.center,
                style: const TextStyle(
                  color: Colors.white,
                  fontSize: 18,
                  fontWeight: FontWeight.w900,
                  letterSpacing: 0.3,
                ),
              ),
            ),

            const SizedBox(height: 14),

            // Badge Model & Kecepatan Inferensi
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Row(
                  children: [
                    Icon(Icons.memory, size: 16, color: Colors.grey.shade700),
                    const SizedBox(width: 4),
                    Text(
                      'Model: ${pred.modelName}',
                      style: TextStyle(
                          fontSize: 12,
                          color: Colors.grey.shade700,
                          fontWeight: FontWeight.bold),
                    ),
                  ],
                ),
                if (pred.inferenceTimeMs > 0)
                  Container(
                    padding:
                        const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                    decoration: BoxDecoration(
                      color: Colors.green.shade50,
                      borderRadius: BorderRadius.circular(6),
                      border: Border.all(color: Colors.green.shade300),
                    ),
                    child: Row(
                      children: [
                        const Icon(Icons.timer_outlined,
                            size: 12, color: Colors.green),
                        const SizedBox(width: 4),
                        Text(
                          '${pred.inferenceTimeMs} ms',
                          style: const TextStyle(
                              fontSize: 11,
                              fontWeight: FontWeight.bold,
                              color: Colors.green),
                        ),
                      ],
                    ),
                  ),
              ],
            ),

            const Divider(height: 20),

            Text(
              pred.uncertain && _corrected == null
                  ? 'Tebakan: ${pred.label} (${(pred.confidence * 100).toStringAsFixed(1)}%)'
                  : 'Klasifikasi: $shown'
                      '${_corrected == null ? ' (${(pred.confidence * 100).toStringAsFixed(1)}%)' : ' (Koreksi Pengguna)'}',
              style: const TextStyle(fontSize: 16, fontWeight: FontWeight.bold),
            ),

            const SizedBox(height: 12),

            // Distribusi Probabilitas 5 Kelas
            for (final e in sorted)
              Padding(
                padding: const EdgeInsets.symmetric(vertical: 3),
                child: Row(
                  children: [
                    SizedBox(
                      width: 115,
                      child: Text(
                        e.key,
                        style: TextStyle(
                          fontSize: 13,
                          fontWeight: e.key == shown
                              ? FontWeight.bold
                              : FontWeight.normal,
                        ),
                      ),
                    ),
                    Expanded(
                      child: ClipRRect(
                        borderRadius: BorderRadius.circular(4),
                        child: LinearProgressIndicator(
                          value: e.value,
                          minHeight: 8,
                          color: actionFor(e.key).$2,
                          backgroundColor: Colors.grey.shade200,
                        ),
                      ),
                    ),
                    SizedBox(
                      width: 48,
                      child: Text(
                        '${(e.value * 100).toStringAsFixed(0)}%',
                        textAlign: TextAlign.right,
                        style: const TextStyle(
                            fontSize: 12, fontWeight: FontWeight.bold),
                      ),
                    ),
                  ],
                ),
              ),

            // Peringatan Kualitas Foto
            for (final w in pred.warnings)
              Padding(
                padding: const EdgeInsets.only(top: 10),
                child: Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const Icon(Icons.warning_amber_rounded,
                        color: Colors.orange, size: 20),
                    const SizedBox(width: 8),
                    Expanded(
                      child: Text(
                        w,
                        style: TextStyle(
                            fontSize: 12, color: Colors.orange.shade900),
                      ),
                    ),
                  ],
                ),
              ),

            const Divider(height: 24),

            // Fitur Koreksi
            DropdownButtonFormField<String>(
              isExpanded: true,
              initialValue: _corrected,
              decoration: InputDecoration(
                labelText: 'Koreksi Hasil (Bila Kurang Akurat)',
                prefixIcon: const Icon(Icons.edit_note_rounded),
                border:
                    OutlineInputBorder(borderRadius: BorderRadius.circular(10)),
                contentPadding:
                    const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
              ),
              hint: const Text('Pilih kelas sebenarnya untuk pelatihan ulang',
                  style: TextStyle(fontSize: 12)),
              items: kClassNames
                  .map((c) => DropdownMenuItem(value: c, child: Text(c)))
                  .toList(),
              onChanged: (v) async {
                if (v == null || _scanId == null) return;
                await AppDb.correct(_scanId!, v);
                if (!mounted) return;
                setState(() => _corrected = v);
                _loadToday();
              },
            ),
          ],
        ),
      ),
    );
  }
}

// ============================================================================
// 3. RIWAYAT PEMINDAIAN (DENGAN PENCARIAN & FILTER KELAS)
// ============================================================================
class HistoryPage extends StatefulWidget {
  const HistoryPage({super.key});

  @override
  State<HistoryPage> createState() => _HistoryPageState();
}

class _HistoryPageState extends State<HistoryPage> {
  List<DbRow> _rows = [];
  bool _loading = true;
  String _filterClass = 'Semua';
  final _searchController = TextEditingController();

  @override
  void initState() {
    super.initState();
    _load();
  }

  @override
  void dispose() {
    _searchController.dispose();
    super.dispose();
  }

  Future<void> _load() async {
    final r = await AppDb.all();
    if (mounted) {
      setState(() {
        _rows = r;
        _loading = false;
      });
    }
  }

  String _csvCell(Object? v) {
    final s = (v ?? '').toString().replaceAll('"', '""');
    return '"$s"';
  }

  Future<void> _export() async {
    if (_rows.isEmpty) return;
    try {
      final b = StringBuffer(
          'id,waktu,blok,hasil_model,koreksi,keyakinan,model_ai,lat,lng\n');
      for (final r in _rows) {
        b.writeln([
          r['id'],
          r['created'],
          r['block'],
          r['label'],
          r['corrected'],
          r['confidence'],
          r['model'] ?? 'MobileNetV2',
          r['lat'],
          r['lng'],
        ].map(_csvCell).join(','));
      }
      final dir = await getTemporaryDirectory();
      final f = File(p.join(dir.path, 'riwayat_sawit.csv'));
      await f.writeAsString(b.toString());
      await Share.shareXFiles([XFile(f.path)],
          text: 'Data Riwayat Pemindaian TBS SawitScan');
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context)
          .showSnackBar(SnackBar(content: Text('Gagal ekspor: $e')));
    }
  }

  @override
  Widget build(BuildContext context) {
    final query = _searchController.text.trim().toLowerCase();
    final filtered = _rows.where((r) {
      final label = effLabel(r);
      final block = (r['block'] ?? '').toString().toLowerCase();
      final matchClass = _filterClass == 'Semua' ? true : label == _filterClass;
      final matchSearch = query.isEmpty
          ? true
          : block.contains(query) || label.toLowerCase().contains(query);
      return matchClass && matchSearch;
    }).toList();

    return Scaffold(
      appBar: AppBar(
        title: const Text('Riwayat Pemindaian'),
        actions: [
          IconButton(
            onPressed: _export,
            icon: const Icon(Icons.ios_share_rounded),
            tooltip: 'Ekspor ke CSV',
          ),
        ],
      ),
      body: Column(
        children: [
          // Search & Filter Bar
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 8, 16, 4),
            child: TextField(
              controller: _searchController,
              onChanged: (_) => setState(() {}),
              decoration: InputDecoration(
                hintText: 'Cari berdasarkan blok atau kelas...',
                prefixIcon: const Icon(Icons.search_rounded),
                suffixIcon: _searchController.text.isNotEmpty
                    ? IconButton(
                        icon: const Icon(Icons.clear),
                        onPressed: () {
                          _searchController.clear();
                          setState(() {});
                        },
                      )
                    : null,
                contentPadding: const EdgeInsets.symmetric(vertical: 10),
                filled: true,
                fillColor: Colors.white,
                border: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(12),
                  borderSide: BorderSide(color: Colors.grey.shade300),
                ),
              ),
            ),
          ),

          // Filter Chips
          SingleChildScrollView(
            scrollDirection: Axis.horizontal,
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
            child: Row(
              children: ['Semua', ...kClassNames].map((c) {
                final isSelected = _filterClass == c;
                return Padding(
                  padding: const EdgeInsets.only(right: 6),
                  child: ChoiceChip(
                    label: Text(c,
                        style: TextStyle(
                            fontSize: 12,
                            color: isSelected ? Colors.white : Colors.black87)),
                    selected: isSelected,
                    selectedColor: const Color(0xFF1E5631),
                    onSelected: (val) {
                      if (val) setState(() => _filterClass = c);
                    },
                  ),
                );
              }).toList(),
            ),
          ),

          const Divider(height: 1),

          Expanded(
            child: _loading
                ? const Center(child: CircularProgressIndicator())
                : filtered.isEmpty
                    ? Center(
                        child: Column(
                          mainAxisAlignment: MainAxisAlignment.center,
                          children: [
                            Icon(Icons.history_toggle_off_rounded,
                                size: 54, color: Colors.grey.shade400),
                            const SizedBox(height: 12),
                            Text(
                              _rows.isEmpty
                                  ? 'Belum ada riwayat pemindaian.'
                                  : 'Tidak ditemukan data yang cocok.',
                              style: TextStyle(color: Colors.grey.shade600),
                            ),
                          ],
                        ),
                      )
                    : ListView.separated(
                        padding: const EdgeInsets.symmetric(vertical: 8),
                        itemCount: filtered.length,
                        separatorBuilder: (_, __) =>
                            const Divider(height: 1, indent: 80),
                        itemBuilder: (context, i) {
                          final r = filtered[i];
                          final label = effLabel(r);
                          final (_, color) = actionFor(label);
                          final conf =
                              ((r['confidence'] as num?) ?? 0).toDouble() * 100;
                          final hasGps = r['lat'] != null && r['lng'] != null;
                          final modelName = r['model'] ?? 'MobileNetV2';

                          return ListTile(
                            leading: ClipRRect(
                              borderRadius: BorderRadius.circular(10),
                              child: Image.file(
                                File(r['path'] as String),
                                width: 58,
                                height: 58,
                                fit: BoxFit.cover,
                                errorBuilder: (_, __, ___) => Container(
                                  width: 58,
                                  height: 58,
                                  color: Colors.grey.shade200,
                                  child:
                                      const Icon(Icons.broken_image, size: 28),
                                ),
                              ),
                            ),
                            title: Row(
                              children: [
                                Text(
                                  r['corrected'] != null
                                      ? '$label (koreksi)'
                                      : label,
                                  style: TextStyle(
                                    color: color,
                                    fontWeight: FontWeight.bold,
                                    fontSize: 15,
                                  ),
                                ),
                                const SizedBox(width: 8),
                                Container(
                                  padding: const EdgeInsets.symmetric(
                                      horizontal: 5, vertical: 1.5),
                                  decoration: BoxDecoration(
                                    color: Colors.grey.shade100,
                                    borderRadius: BorderRadius.circular(4),
                                    border:
                                        Border.all(color: Colors.grey.shade300),
                                  ),
                                  child: Text(
                                    modelName.toString(),
                                    style: TextStyle(
                                      fontSize: 10,
                                      color: Colors.grey.shade700,
                                      fontWeight: FontWeight.w600,
                                    ),
                                  ),
                                ),
                              ],
                            ),
                            subtitle: Padding(
                              padding: const EdgeInsets.only(top: 4),
                              child: Text(
                                '${r['block']} • ${fmtTime(r['created'] as String)}\n'
                                'Akurasi ${conf.toStringAsFixed(0)}%'
                                '${hasGps ? ' • GPS: ${(r['lat'] as num).toStringAsFixed(4)}, ${(r['lng'] as num).toStringAsFixed(4)}' : ''}',
                                style: const TextStyle(fontSize: 12),
                              ),
                            ),
                            isThreeLine: true,
                            trailing: PopupMenuButton<String>(
                              onSelected: (v) async {
                                final id = r['id'] as int;
                                if (v == '__hapus') {
                                  await AppDb.remove(id);
                                } else {
                                  await AppDb.correct(id, v);
                                }
                                _load();
                              },
                              itemBuilder: (_) => [
                                for (final c in kClassNames)
                                  PopupMenuItem(
                                      value: c, child: Text('Koreksi ke: $c')),
                                const PopupMenuItem(
                                  value: '__hapus',
                                  child: Text('Hapus Data',
                                      style: TextStyle(color: Colors.red)),
                                ),
                              ],
                            ),
                          );
                        },
                      ),
          ),
        ],
      ),
    );
  }
}

// ============================================================================
// 4. STATISTIK & ANALITIK KEMATANGAN
// ============================================================================
class StatsPage extends StatefulWidget {
  const StatsPage({super.key});

  @override
  State<StatsPage> createState() => _StatsPageState();
}

class _StatsPageState extends State<StatsPage> {
  List<DbRow> _rows = [];
  bool _loading = true;

  @override
  void initState() {
    super.initState();
    AppDb.all().then((r) {
      if (mounted) {
        setState(() {
          _rows = r;
          _loading = false;
        });
      }
    });
  }

  @override
  Widget build(BuildContext context) {
    final byClass = <String, int>{};
    final byBlock = <String, Map<String, int>>{};
    final byModel = <String, int>{};

    for (final r in _rows) {
      final l = effLabel(r);
      byClass[l] = (byClass[l] ?? 0) + 1;
      final b = (r['block'] ?? '-') as String;
      final m = byBlock.putIfAbsent(b, () => {});
      m[l] = (m[l] ?? 0) + 1;
      final model = (r['model'] ?? 'MobileNetV2') as String;
      byModel[model] = (byModel[model] ?? 0) + 1;
    }

    final total = _rows.length;
    final corrected = _rows.where((r) => r['corrected'] != null).length;
    final matangCount = byClass['Matang'] ?? 0;
    final optimalRate = total > 0 ? (matangCount / total * 100) : 0.0;

    return Scaffold(
      appBar: AppBar(title: const Text('Statistik & Analisis Panen')),
      body: _loading
          ? const Center(child: CircularProgressIndicator())
          : total == 0
              ? const Center(
                  child: Text('Belum ada data pemindaian untuk dianalisis.'))
              : ListView(
                  padding: const EdgeInsets.all(16),
                  children: [
                    // Summary KPI Cards
                    Row(
                      children: [
                        Expanded(
                          child: _buildMetricCard(
                            title: 'Total Pindai',
                            value: '$total',
                            icon: Icons.qr_code_scanner_rounded,
                            color: const Color(0xFF1E5631),
                          ),
                        ),
                        const SizedBox(width: 12),
                        Expanded(
                          child: _buildMetricCard(
                            title: 'Fraksi Matang',
                            value: '${optimalRate.toStringAsFixed(1)}%',
                            icon: Icons.check_circle_rounded,
                            color: const Color(0xFF2E7D32),
                          ),
                        ),
                      ],
                    ),

                    const SizedBox(height: 12),

                    Row(
                      children: [
                        Expanded(
                          child: _buildMetricCard(
                            title: 'Koreksi Manual',
                            value: '$corrected',
                            icon: Icons.edit_note_rounded,
                            color: Colors.orange.shade800,
                          ),
                        ),
                        const SizedBox(width: 12),
                        Expanded(
                          child: _buildMetricCard(
                            title: 'Akurasi AI',
                            value: total > 0
                                ? '${((total - corrected) / total * 100).toStringAsFixed(1)}%'
                                : '0%',
                            icon: Icons.psychology_rounded,
                            color: Colors.teal.shade800,
                          ),
                        ),
                      ],
                    ),

                    const SizedBox(height: 20),

                    // Card Distribusi Kelas
                    Card(
                      child: Padding(
                        padding: const EdgeInsets.all(16),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            const Text(
                              'Distribusi Kematangan Buah',
                              style: TextStyle(
                                fontSize: 16,
                                fontWeight: FontWeight.bold,
                                color: Color(0xFF1E5631),
                              ),
                            ),
                            const SizedBox(height: 14),
                            for (final c in kClassNames) ...[
                              Builder(builder: (context) {
                                final count = byClass[c] ?? 0;
                                final pct = total > 0 ? count / total : 0.0;
                                final (_, col) = actionFor(c);
                                return Padding(
                                  padding:
                                      const EdgeInsets.symmetric(vertical: 4),
                                  child: Column(
                                    crossAxisAlignment:
                                        CrossAxisAlignment.start,
                                    children: [
                                      Row(
                                        mainAxisAlignment:
                                            MainAxisAlignment.spaceBetween,
                                        children: [
                                          Text(c,
                                              style: TextStyle(
                                                  fontWeight: count > 0
                                                      ? FontWeight.bold
                                                      : FontWeight.normal)),
                                          Text(
                                            '$count TBS (${(pct * 100).toStringAsFixed(0)}%)',
                                            style: TextStyle(
                                                fontSize: 12,
                                                fontWeight: FontWeight.bold,
                                                color: col),
                                          ),
                                        ],
                                      ),
                                      const SizedBox(height: 4),
                                      ClipRRect(
                                        borderRadius: BorderRadius.circular(4),
                                        child: LinearProgressIndicator(
                                          value: pct,
                                          color: col,
                                          backgroundColor: Colors.grey.shade100,
                                          minHeight: 10,
                                        ),
                                      ),
                                    ],
                                  ),
                                );
                              }),
                            ],
                          ],
                        ),
                      ),
                    ),

                    const SizedBox(height: 14),

                    // Model Usage Breakdown
                    Card(
                      child: Padding(
                        padding: const EdgeInsets.all(16),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            const Text(
                              'Perbandingan Pemakaian Model AI',
                              style: TextStyle(
                                fontSize: 15,
                                fontWeight: FontWeight.bold,
                                color: Color(0xFF1E5631),
                              ),
                            ),
                            const SizedBox(height: 10),
                            for (final entry in byModel.entries) ...[
                              Row(
                                mainAxisAlignment:
                                    MainAxisAlignment.spaceBetween,
                                children: [
                                  Row(
                                    children: [
                                      Icon(
                                        entry.key.contains('ResNet')
                                            ? Icons.psychology_rounded
                                            : Icons.speed,
                                        size: 16,
                                        color: const Color(0xFF1E5631),
                                      ),
                                      const SizedBox(width: 6),
                                      Text(entry.key,
                                          style: const TextStyle(
                                              fontWeight: FontWeight.w600)),
                                    ],
                                  ),
                                  Text(
                                    '${entry.value} kali (${(entry.value / total * 100).toStringAsFixed(0)}%)',
                                    style: const TextStyle(
                                        fontWeight: FontWeight.bold),
                                  ),
                                ],
                              ),
                              const SizedBox(height: 6),
                            ],
                          ],
                        ),
                      ),
                    ),

                    const SizedBox(height: 14),

                    // Data Berdasarkan Blok
                    Card(
                      child: Padding(
                        padding: const EdgeInsets.all(16),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            const Text(
                              'Sebaran Panen Per Blok',
                              style: TextStyle(
                                fontSize: 15,
                                fontWeight: FontWeight.bold,
                                color: Color(0xFF1E5631),
                              ),
                            ),
                            const SizedBox(height: 8),
                            for (final e in byBlock.entries)
                              Padding(
                                padding:
                                    const EdgeInsets.symmetric(vertical: 4),
                                child: Container(
                                  padding: const EdgeInsets.all(10),
                                  decoration: BoxDecoration(
                                    color: Colors.grey.shade50,
                                    borderRadius: BorderRadius.circular(8),
                                  ),
                                  child: Column(
                                    crossAxisAlignment:
                                        CrossAxisAlignment.start,
                                    children: [
                                      Text(e.key,
                                          style: const TextStyle(
                                              fontWeight: FontWeight.bold)),
                                      const SizedBox(height: 4),
                                      Text(
                                        e.value.entries
                                            .map((x) => '${x.key}: ${x.value}')
                                            .join('  •  '),
                                        style: TextStyle(
                                            fontSize: 12,
                                            color: Colors.grey.shade700),
                                      ),
                                    ],
                                  ),
                                ),
                              ),
                          ],
                        ),
                      ),
                    ),
                  ],
                ),
    );
  }

  Widget _buildMetricCard({
    required String title,
    required String value,
    required IconData icon,
    required Color color,
  }) {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: Colors.grey.shade200),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(icon, color: color, size: 28),
          const SizedBox(height: 10),
          Text(
            value,
            style: TextStyle(
              fontSize: 22,
              fontWeight: FontWeight.w900,
              color: color,
            ),
          ),
          const SizedBox(height: 2),
          Text(
            title,
            style: TextStyle(fontSize: 12, color: Colors.grey.shade600),
          ),
        ],
      ),
    );
  }
}

// ============================================================================
// 5. FITUR EDUKASI & INFORMATIF: PANDUAN FRAKSI TBS & KALKULATOR MUTU PKS
// ============================================================================
class HarvestGuidePage extends StatefulWidget {
  const HarvestGuidePage({super.key});

  @override
  State<HarvestGuidePage> createState() => _HarvestGuidePageState();
}

class _HarvestGuidePageState extends State<HarvestGuidePage>
    with SingleTickerProviderStateMixin {
  late TabController _tabController;

  // Controller untuk Kalkulator Refaksi
  final _tonaseController = TextEditingController(text: '3000');
  final _mentahController = TextEditingController(text: '2');
  final _panjangController = TextEditingController(text: '3');
  final _lewatMatangController = TextEditingController(text: '4');

  double _totalDendaKg = 0;
  double _tonaseBersih = 3000;
  String _gradePks = 'Grade A (Mutu Utama)';

  @override
  void initState() {
    super.initState();
    _tabController = TabController(length: 2, vsync: this);
    _hitungRefaksi();
  }

  @override
  void dispose() {
    _tabController.dispose();
    _tonaseController.dispose();
    _mentahController.dispose();
    _panjangController.dispose();
    _lewatMatangController.dispose();
    super.dispose();
  }

  void _hitungRefaksi() {
    final tonase = double.tryParse(_tonaseController.text) ?? 0;
    final pctMentah = double.tryParse(_mentahController.text) ?? 0;
    final pctPanjang = double.tryParse(_panjangController.text) ?? 0;

    // Standar PKS:
    // Buah mentah denda potongan berat ~50% dari bobot buah mentah
    // Tangkai panjang denda potongan ~1% per persen kelebihan
    final dendaMentahKg = tonase * (pctMentah / 100) * 0.50;
    final dendaPanjangKg = tonase * (pctPanjang / 100) * 0.20;
    final totalDenda = dendaMentahKg + dendaPanjangKg;
    final bersih = (tonase - totalDenda).clamp(0.0, double.infinity);

    String grade = 'Grade A (Mutu Utama)';
    if (pctMentah > 5 || pctPanjang > 5) {
      grade = 'Grade C (Denda Tinggi / Berisiko Tolak)';
    } else if (pctMentah > 2 || pctPanjang > 3) {
      grade = 'Grade B (Standar Penerimaan)';
    }

    setState(() {
      _totalDendaKg = totalDenda;
      _tonaseBersih = bersih;
      _gradePks = grade;
    });
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Panduan & Kalkulator Mutu'),
        bottom: TabBar(
          controller: _tabController,
          labelColor: const Color(0xFF1E5631),
          unselectedLabelColor: Colors.grey,
          indicatorColor: const Color(0xFF1E5631),
          tabs: const [
            Tab(icon: Icon(Icons.menu_book_rounded), text: 'Standar Fraksi'),
            Tab(icon: Icon(Icons.calculate_rounded), text: 'Kalkulator PKS'),
          ],
        ),
      ),
      body: TabBarView(
        controller: _tabController,
        children: [
          // TAB 1: PANDUAN FRAKSI TBS STANDAR SNI
          _buildGuideTab(),

          // TAB 2: KALKULATOR REFASKI PKS
          _buildCalculatorTab(),
        ],
      ),
    );
  }

  Widget _buildGuideTab() {
    final fraksiList = [
      {
        'title': 'Belum Matang (Unripe - Fraksi 00 & 0)',
        'color': const Color(0xFFC62828),
        'ciri':
            'Warna hitam pekat hingga ungu gelap kehitaman. Buah keras, 0% hingga kurang dari 12.5% buah luar membrondol lepas alami di piringan pohon.',
        'rendemen': '14% - 18% (Rendemen Minyak Rendah)',
        'alb': '< 1.8% (Asam Lemak Bebas Rendah)',
        'status':
            'TUNDA PANEN - Dilarang panen. Berpotensi terkena potongan refaksi berat (denda hingga 50%) di PKS. Tunggu 3-7 hari ke depan.',
      },
      {
        'title': 'Matang (Ripe - Fraksi 1 & 2)',
        'color': const Color(0xFF2E7D32),
        'ciri':
            'Warna oranye kemerahan mengkilap segar merata. Minimal 5 brondolan lepas alami di piringan (12.5% - 50% buah luar membrondol).',
        'rendemen': '22% - 26% (PUNCAK OPTIMAL MAKSIMAL)',
        'alb': '1.5% - 2.5% (Standar Kualitas Mutu Ekspor CPO SNI)',
        'status':
            'TARGET PANEN UTAMA - Kualitas TBS terbaik Grade A dengan harga jual dan rendemen minyak tertinggi di PKS.',
      },
      {
        'title': 'Lewat Matang (Overripe - Fraksi 3+)',
        'color': const Color(0xFFD84315),
        'ciri':
            'Warna merah tua kehitaman atau kusam. Lebih dari 50% brondolan lepas ke tanah atau buah mulai terlepas dari spikelet tandan buah.',
        'rendemen': '18% - 22% (Rendemen mulai menyusut)',
        'alb': '> 3.5% (Kadar Asam Lemak Bebas meningkat cepat)',
        'status':
            'PRIORITAS OLAH - Segera angkut dan olah di PKS dalam waktu < 24 jam agar ALB tidak rusak dan terhindar dari denda busuk.',
      },
    ];

    return ListView(
      padding: const EdgeInsets.all(16),
      children: [
        Container(
          padding: const EdgeInsets.all(14),
          decoration: BoxDecoration(
            color: const Color(0xFF1E5631).withValues(alpha: 0.08),
            borderRadius: BorderRadius.circular(12),
            border: Border.all(
                color: const Color(0xFF1E5631).withValues(alpha: 0.2)),
          ),
          child: const Row(
            children: [
              Icon(Icons.verified_rounded, color: Color(0xFF1E5631)),
              SizedBox(width: 10),
              Expanded(
                child: Text(
                  'Standar Fraksi TBS mengacu pada ketentuan Pusat Penelitian Kelapa Sawit (PPKS) & SNI 01-3922-1995.',
                  style: TextStyle(fontSize: 12, fontWeight: FontWeight.w600),
                ),
              ),
            ],
          ),
        ),
        const SizedBox(height: 14),
        for (final f in fraksiList) ...[
          Card(
            child: Padding(
              padding: const EdgeInsets.all(16),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      Container(
                        width: 12,
                        height: 12,
                        decoration: BoxDecoration(
                          shape: BoxShape.circle,
                          color: f['color'] as Color,
                        ),
                      ),
                      const SizedBox(width: 8),
                      Text(
                        f['title'] as String,
                        style: TextStyle(
                          fontSize: 16,
                          fontWeight: FontWeight.bold,
                          color: f['color'] as Color,
                        ),
                      ),
                    ],
                  ),
                  const Divider(height: 18),
                  Text('• Ciri Visual: ${f['ciri']}',
                      style: const TextStyle(fontSize: 13)),
                  const SizedBox(height: 6),
                  Row(
                    children: [
                      Expanded(
                        child: Text('• Rendemen CPO: ${f['rendemen']}',
                            style: const TextStyle(
                                fontSize: 13, fontWeight: FontWeight.w600)),
                      ),
                      Expanded(
                        child: Text('• ALB / FFA: ${f['alb']}',
                            style: const TextStyle(
                                fontSize: 13, fontWeight: FontWeight.w600)),
                      ),
                    ],
                  ),
                  const SizedBox(height: 8),
                  Container(
                    padding:
                        const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
                    decoration: BoxDecoration(
                      color: (f['color'] as Color).withValues(alpha: 0.1),
                      borderRadius: BorderRadius.circular(6),
                    ),
                    child: Text(
                      'Tindakan: ${f['status']}',
                      style: TextStyle(
                        fontSize: 12,
                        fontWeight: FontWeight.bold,
                        color: f['color'] as Color,
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ),
          const SizedBox(height: 8),
        ],
      ],
    );
  }

  Widget _buildCalculatorTab() {
    return ListView(
      padding: const EdgeInsets.all(16),
      children: [
        const Text(
          'Simulasi Potongan Refaksi & Mutu Panen',
          style: TextStyle(
            fontSize: 16,
            fontWeight: FontWeight.bold,
            color: Color(0xFF1E5631),
          ),
        ),
        const SizedBox(height: 4),
        Text(
          'Hitung estimasi potongan berat (refaksi) oleh Pabrik Kelapa Sawit (PKS) berdasarkan persentase kematangan TBS.',
          style: TextStyle(fontSize: 12, color: Colors.grey.shade600),
        ),
        const SizedBox(height: 16),

        TextField(
          controller: _tonaseController,
          keyboardType: TextInputType.number,
          decoration: const InputDecoration(
            labelText: 'Total Tonase / Berat TBS (Kg)',
            prefixIcon: Icon(Icons.scale_rounded),
            border: OutlineInputBorder(),
          ),
          onChanged: (_) => _hitungRefaksi(),
        ),
        const SizedBox(height: 12),

        Row(
          children: [
            Expanded(
              child: TextField(
                controller: _mentahController,
                keyboardType: TextInputType.number,
                decoration: const InputDecoration(
                  labelText: '% Buah Belum Matang',
                  suffixText: '%',
                  border: OutlineInputBorder(),
                ),
                onChanged: (_) => _hitungRefaksi(),
              ),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: TextField(
                controller: _panjangController,
                keyboardType: TextInputType.number,
                decoration: const InputDecoration(
                  labelText: '% Tangkai Panjang',
                  suffixText: '%',
                  border: OutlineInputBorder(),
                ),
                onChanged: (_) => _hitungRefaksi(),
              ),
            ),
          ],
        ),

        const SizedBox(height: 20),

        // Hasil Simulasi Card
        Container(
          padding: const EdgeInsets.all(18),
          decoration: BoxDecoration(
            color: Colors.white,
            borderRadius: BorderRadius.circular(16),
            border: Border.all(color: const Color(0xFF1E5631), width: 1.5),
            boxShadow: [
              BoxShadow(
                color: Colors.black.withValues(alpha: 0.05),
                blurRadius: 10,
                offset: const Offset(0, 4),
              ),
            ],
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  const Text('Klasifikasi Mutu:',
                      style: TextStyle(fontSize: 13, color: Colors.grey)),
                  Container(
                    padding:
                        const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                    decoration: BoxDecoration(
                      color: _gradePks.contains('Grade A')
                          ? Colors.green.shade100
                          : Colors.orange.shade100,
                      borderRadius: BorderRadius.circular(8),
                    ),
                    child: Text(
                      _gradePks,
                      style: TextStyle(
                        fontSize: 12,
                        fontWeight: FontWeight.bold,
                        color: _gradePks.contains('Grade A')
                            ? Colors.green.shade900
                            : Colors.orange.shade900,
                      ),
                    ),
                  ),
                ],
              ),
              const Divider(height: 20),
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  const Text('Estimasi Potongan Refaksi:'),
                  Text(
                    '-${_totalDendaKg.toStringAsFixed(1)} Kg',
                    style: const TextStyle(
                        fontSize: 16,
                        fontWeight: FontWeight.bold,
                        color: Colors.red),
                  ),
                ],
              ),
              const SizedBox(height: 8),
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  const Text('Tonase Bersih Diterima PKS:'),
                  Text(
                    '${_tonaseBersih.toStringAsFixed(1)} Kg',
                    style: const TextStyle(
                      fontSize: 18,
                      fontWeight: FontWeight.w900,
                      color: Color(0xFF1E5631),
                    ),
                  ),
                ],
              ),
            ],
          ),
        ),
      ],
    );
  }
}

// ============================================================================
// 6. BOTTOM SHEET / DIALOG "TENTANG APLIKASI"
// ============================================================================
class AboutAppSheet extends StatelessWidget {
  const AboutAppSheet({super.key});

  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: const BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.vertical(top: Radius.circular(28)),
      ),
      padding: const EdgeInsets.fromLTRB(24, 16, 24, 32),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Center(
            child: Container(
              width: 44,
              height: 5,
              decoration: BoxDecoration(
                color: Colors.grey.shade300,
                borderRadius: BorderRadius.circular(10),
              ),
            ),
          ),
          const SizedBox(height: 20),

          // Header Logo & Nama Aplikasi
          Center(
            child: Column(
              children: [
                const AppLogo(size: 80, showShadow: true),
                const SizedBox(height: 12),
                const Text(
                  'SawitScan',
                  style: TextStyle(
                    fontSize: 22,
                    fontWeight: FontWeight.w900,
                    color: Color(0xFF1E5631),
                  ),
                ),
                Text(
                  'Aplikasi Cerdas Penilai Kematangan TBS Sawit (v1.2.0)',
                  style: TextStyle(fontSize: 12, color: Colors.grey.shade600),
                ),
              ],
            ),
          ),

          const SizedBox(height: 20),
          const Divider(),
          const SizedBox(height: 8),

          const Text(
            'Tentang Aplikasi',
            style: TextStyle(fontSize: 15, fontWeight: FontWeight.bold),
          ),
          const SizedBox(height: 6),
          Text(
            'SawitScan dirancang khusus untuk mandor kebun, pemanen, dan pemeriksa mutu (grading) TBS sawit. '
            'Aplikasi ini memproses citra tandan buah segar menggunakan arsitektur Deep Learning (MobileNetV2 & ResNetV2) '
            'secara 100% offline langsung pada perangkat Anda tanpa memerlukan koneksi internet di kebun.',
            style: TextStyle(
                fontSize: 13, color: Colors.grey.shade800, height: 1.4),
          ),

          const SizedBox(height: 16),

          const Text(
            'Fitur Utama:',
            style: TextStyle(fontSize: 14, fontWeight: FontWeight.bold),
          ),
          const SizedBox(height: 6),
          _buildFeatureBullet(Icons.check_circle_outline,
              'Klasifikasi 3 kelas kematangan TBS (Belum Matang, Matang, Lewat Matang).'),
          _buildFeatureBullet(Icons.speed,
              'Pemilihan Model AI Pembanding (MobileNetV2 cepat vs ResNetV2 berfitur dalam).'),
          _buildFeatureBullet(Icons.calendar_month_outlined,
              'Kalender tanam & estimasi siklus panen perdana (+30 bulan) dengan dukungan offline.'),
          _buildFeatureBullet(Icons.location_on_outlined,
              'Perekaman titik koordinat GPS & nama blok kebun otomatis.'),
          _buildFeatureBullet(Icons.menu_book_outlined,
              'Panduan Standar Fraksi PPKS/SNI & Kalkulator Denda Refaksi Pabrik.'),
          _buildFeatureBullet(Icons.image_outlined,
              'Dukungan kustomisasi logo aplikasi (letakkan di assets/images/logo.png).'),

          const SizedBox(height: 16),

          Container(
            padding: const EdgeInsets.all(12),
            decoration: BoxDecoration(
              color: Colors.grey.shade100,
              borderRadius: BorderRadius.circular(10),
            ),
            child: Row(
              children: [
                const Icon(Icons.shield_outlined,
                    size: 20, color: Color(0xFF1E5631)),
                const SizedBox(width: 8),
                Expanded(
                  child: Text(
                    'Peringatan Pertanian: Prediksi AI berfungsi sebagai alat bantu pendukung keputusan (decision support). '
                    'Kondisi pencahayaan dan kebersihan lensa kamera mempengaruhi presisi.',
                    style: TextStyle(fontSize: 11, color: Colors.grey.shade700),
                  ),
                ),
              ],
            ),
          ),

          const SizedBox(height: 16),

          SizedBox(
            width: double.infinity,
            child: FilledButton(
              style: FilledButton.styleFrom(
                backgroundColor: const Color(0xFF1E5631),
                shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(12)),
              ),
              onPressed: () => Navigator.pop(context),
              child: const Text('Tutup'),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildFeatureBullet(IconData icon, String text) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 2.5),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(icon, size: 16, color: const Color(0xFF1E5631)),
          const SizedBox(width: 8),
          Expanded(
            child: Text(text, style: const TextStyle(fontSize: 12.5)),
          ),
        ],
      ),
    );
  }
}
