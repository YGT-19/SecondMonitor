import 'dart:async';
import 'dart:convert';
import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:web_socket_channel/web_socket_channel.dart';

/// Uygulama genelinde tema modunu tutan global notifier.
final ValueNotifier<ThemeMode> themeModeNotifier =
ValueNotifier(ThemeMode.dark);

const _seedColor = Color(0xFF6366F1);

// ---------------------------------------------------------------------------
// Kalıcı (cihazda saklanan) uygulama ayarları
// ---------------------------------------------------------------------------
class AppSettings {
  AppSettings._();

  static SharedPreferences? _prefs;

  static final ValueNotifier<double> quality = ValueNotifier(65);
  static final ValueNotifier<double> scale = ValueNotifier(0.8);
  static final ValueNotifier<double> fps = ValueNotifier(24);
  static final ValueNotifier<bool> showCursor = ValueNotifier(true);
  static final ValueNotifier<double> doubleTapWindowMs = ValueNotifier(220);
  static final ValueNotifier<double> scrollSensitivity = ValueNotifier(1.0);

  static Future<void> load() async {
    _prefs = await SharedPreferences.getInstance();
    quality.value = _prefs!.getDouble('quality') ?? 65;
    scale.value = _prefs!.getDouble('scale') ?? 0.8;
    fps.value = _prefs!.getDouble('fps') ?? 24;
    showCursor.value = _prefs!.getBool('showCursor') ?? true;
    doubleTapWindowMs.value = _prefs!.getDouble('doubleTapWindowMs') ?? 220;
    scrollSensitivity.value = _prefs!.getDouble('scrollSensitivity') ?? 1.0;

    final modeIndex = _prefs!.getInt('themeMode');
    if (modeIndex != null && modeIndex < ThemeMode.values.length) {
      themeModeNotifier.value = ThemeMode.values[modeIndex];
    }
    themeModeNotifier.addListener(() {
      _prefs?.setInt('themeMode', themeModeNotifier.value.index);
    });
  }

  static void setQuality(double v) {
    quality.value = v;
    _prefs?.setDouble('quality', v);
  }

  static void setScale(double v) {
    scale.value = v;
    _prefs?.setDouble('scale', v);
  }

  static void setFps(double v) {
    fps.value = v;
    _prefs?.setDouble('fps', v);
  }

  static void setShowCursor(bool v) {
    showCursor.value = v;
    _prefs?.setBool('showCursor', v);
  }

  static void setDoubleTapWindow(double v) {
    doubleTapWindowMs.value = v;
    _prefs?.setDouble('doubleTapWindowMs', v);
  }

  static void setScrollSensitivity(double v) {
    scrollSensitivity.value = v;
    _prefs?.setDouble('scrollSensitivity', v);
  }

  /// Bağlantı kurulduğunda bilgisayara gönderilecek başlangıç ayarları.
  static Map<String, dynamic> toConfigMessage() {
    return {
      'type': 'config',
      'quality': quality.value.round(),
      'scale': double.parse(scale.value.toStringAsFixed(2)),
      'fps': fps.value.round(),
    };
  }
}

void main() async {
  WidgetsFlutterBinding.ensureInitialized();
  await AppSettings.load();
  runApp(const RemoteScreenApp());
}

class RemoteScreenApp extends StatelessWidget {
  const RemoteScreenApp({super.key});

  @override
  Widget build(BuildContext context) {
    return ValueListenableBuilder<ThemeMode>(
      valueListenable: themeModeNotifier,
      builder: (context, mode, _) {
        return MaterialApp(
          title: 'Uzaktan Ekran Kontrol',
          debugShowCheckedModeBanner: false,
          themeMode: mode,
          theme: ThemeData(
            useMaterial3: true,
            brightness: Brightness.light,
            colorSchemeSeed: _seedColor,
            scaffoldBackgroundColor: const Color(0xFFF4F5FA),
          ),
          darkTheme: ThemeData(
            useMaterial3: true,
            brightness: Brightness.dark,
            colorSchemeSeed: _seedColor,
            scaffoldBackgroundColor: const Color(0xFF0F1117),
          ),
          home: const ConnectScreen(),
        );
      },
    );
  }
}

// ---------------------------------------------------------------------------
// Bağlantı ekranı
// ---------------------------------------------------------------------------
class ConnectScreen extends StatefulWidget {
  const ConnectScreen({super.key});

  @override
  State<ConnectScreen> createState() => _ConnectScreenState();
}

class _ConnectScreenState extends State<ConnectScreen> {
  final _ipController = TextEditingController(text: '192.168.1.');
  final _portController = TextEditingController(text: '8765');
  bool _connecting = false;
  String? _error;

  void _connect() {
    final ip = _ipController.text.trim();
    final port = _portController.text.trim();
    if (ip.isEmpty || port.isEmpty) {
      setState(() => _error = 'IP ve port boş olamaz');
      return;
    }

    setState(() {
      _connecting = true;
      _error = null;
    });

    final uri = Uri.parse('ws://$ip:$port');
    try {
      final channel = WebSocketChannel.connect(uri);
      // Bağlanır bağlanmaz Ayarlar sayfasındaki görüntü kalitesi
      // tercihlerini bilgisayara bildiriyoruz.
      channel.sink.add(jsonEncode(AppSettings.toConfigMessage()));

      Navigator.push(
        context,
        MaterialPageRoute(builder: (_) => RemoteScreenView(channel: channel)),
      ).then((_) {
        if (mounted) setState(() => _connecting = false);
      });
    } catch (e) {
      setState(() {
        _connecting = false;
        _error = 'Bağlanılamadı: $e';
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final isDark = Theme.of(context).brightness == Brightness.dark;

    return Scaffold(
      body: Container(
        decoration: BoxDecoration(
          gradient: LinearGradient(
            begin: Alignment.topCenter,
            end: Alignment.bottomCenter,
            colors: isDark
                ? const [Color(0xFF1A1E29), Color(0xFF0F1117)]
                : const [Colors.white, Color(0xFFF4F5FA)],
          ),
        ),
        child: SafeArea(
          child: Stack(
            children: [
              Positioned(
                top: 4,
                right: 4,
                child: IconButton(
                  icon: Icon(Icons.settings_outlined,
                      color: scheme.onSurface.withOpacity(0.6)),
                  tooltip: 'Ayarlar',
                  onPressed: () => Navigator.push(
                    context,
                    MaterialPageRoute(builder: (_) => const SettingsScreen()),
                  ),
                ),
              ),
              Center(
                child: SingleChildScrollView(
                  padding: const EdgeInsets.symmetric(horizontal: 28),
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Container(
                        width: 84,
                        height: 84,
                        decoration: BoxDecoration(
                          shape: BoxShape.circle,
                          gradient: LinearGradient(
                            colors: [_seedColor, _seedColor.withOpacity(0.7)],
                          ),
                          boxShadow: [
                            BoxShadow(
                              color: _seedColor.withOpacity(0.35),
                              blurRadius: 28,
                              spreadRadius: 2,
                            ),
                          ],
                        ),
                        child: const Icon(Icons.desktop_windows_rounded,
                            color: Colors.white, size: 40),
                      ),
                      const SizedBox(height: 20),
                      Text(
                        'Uzaktan Ekran Kontrol',
                        style: TextStyle(
                          color: scheme.onSurface,
                          fontSize: 22,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                      const SizedBox(height: 6),
                      Text(
                        'Bilgisayarınla aynı WiFi ağına bağlan',
                        style: TextStyle(color: scheme.onSurface.withOpacity(0.55)),
                      ),
                      const SizedBox(height: 32),
                      Container(
                        padding: const EdgeInsets.all(20),
                        decoration: BoxDecoration(
                          color: scheme.surfaceContainerHighest
                              .withOpacity(isDark ? 0.4 : 0.7),
                          borderRadius: BorderRadius.circular(20),
                          border: Border.all(color: scheme.outline.withOpacity(0.2)),
                        ),
                        child: Column(
                          children: [
                            _buildField(context, _ipController, 'Bilgisayar IP adresi',
                                Icons.lan_outlined, 'örn: 192.168.1.23'),
                            const SizedBox(height: 14),
                            _buildField(context, _portController, 'Port',
                                Icons.numbers_rounded, '8765'),
                            const SizedBox(height: 20),
                            if (_error != null)
                              Container(
                                margin: const EdgeInsets.only(bottom: 14),
                                padding: const EdgeInsets.all(10),
                                decoration: BoxDecoration(
                                  color: Colors.red.withOpacity(0.1),
                                  borderRadius: BorderRadius.circular(10),
                                ),
                                child: Row(
                                  children: [
                                    const Icon(Icons.error_outline,
                                        color: Colors.redAccent, size: 18),
                                    const SizedBox(width: 8),
                                    Expanded(
                                      child: Text(
                                        _error!,
                                        style: const TextStyle(
                                            color: Colors.redAccent, fontSize: 13),
                                      ),
                                    ),
                                  ],
                                ),
                              ),
                            SizedBox(
                              width: double.infinity,
                              height: 50,
                              child: ElevatedButton(
                                style: ElevatedButton.styleFrom(
                                  backgroundColor: scheme.primary,
                                  foregroundColor: scheme.onPrimary,
                                  shape: RoundedRectangleBorder(
                                      borderRadius: BorderRadius.circular(14)),
                                  elevation: 0,
                                ),
                                onPressed: _connecting ? null : _connect,
                                child: _connecting
                                    ? SizedBox(
                                  width: 22,
                                  height: 22,
                                  child: CircularProgressIndicator(
                                      strokeWidth: 2.4,
                                      color: scheme.onPrimary),
                                )
                                    : Row(
                                  mainAxisAlignment: MainAxisAlignment.center,
                                  children: const [
                                    Text(
                                      'Bağlan',
                                      style: TextStyle(
                                          fontSize: 16,
                                          fontWeight: FontWeight.w600),
                                    ),
                                    SizedBox(width: 8),
                                    Icon(Icons.arrow_forward_rounded, size: 18),
                                  ],
                                ),
                              ),
                            ),
                          ],
                        ),
                      ),
                      const SizedBox(height: 16),
                      Text(
                        'İpucu: Bu ekranda dik kalabilirsin, bağlandıktan\nsonra uygulama otomatik yatay moda geçecek.',
                        textAlign: TextAlign.center,
                        style: TextStyle(
                            color: scheme.onSurface.withOpacity(0.4), fontSize: 12),
                      ),
                    ],
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildField(BuildContext context, TextEditingController controller,
      String label, IconData icon, String hint) {
    final scheme = Theme.of(context).colorScheme;
    return TextField(
      controller: controller,
      style: TextStyle(color: scheme.onSurface),
      keyboardType: TextInputType.number,
      decoration: InputDecoration(
        labelText: label,
        hintText: hint,
        hintStyle: TextStyle(color: scheme.onSurface.withOpacity(0.3)),
        labelStyle: TextStyle(color: scheme.onSurface.withOpacity(0.55)),
        prefixIcon: Icon(icon, color: scheme.onSurface.withOpacity(0.55), size: 20),
        filled: true,
        fillColor: scheme.onSurface.withOpacity(0.05),
        border: OutlineInputBorder(
          borderRadius: BorderRadius.circular(12),
          borderSide: BorderSide.none,
        ),
        enabledBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(12),
          borderSide: BorderSide.none,
        ),
        focusedBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(12),
          borderSide: BorderSide(color: scheme.primary),
        ),
      ),
    );
  }
}

// ---------------------------------------------------------------------------
// Ayarlar ekranı
// ---------------------------------------------------------------------------
class SettingsScreen extends StatelessWidget {
  const SettingsScreen({super.key});

  Widget _sectionTitle(BuildContext context, String text) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(20, 20, 20, 6),
      child: Text(
        text,
        style: TextStyle(
          fontSize: 12,
          fontWeight: FontWeight.w600,
          letterSpacing: 0.6,
          color: Theme.of(context).colorScheme.onSurface.withOpacity(0.5),
        ),
      ),
    );
  }

  Widget _sliderTile(
      BuildContext context, {
        required String label,
        required String valueText,
        required double value,
        required double min,
        required double max,
        required ValueChanged<double> onChanged,
      }) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 2),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Text(label),
              Text(
                valueText,
                style: TextStyle(
                  color: Theme.of(context).colorScheme.primary,
                  fontWeight: FontWeight.w600,
                ),
              ),
            ],
          ),
          SliderTheme(
            data: SliderTheme.of(context).copyWith(trackHeight: 3),
            child: Slider(value: value, min: min, max: max, onChanged: onChanged),
          ),
        ],
      ),
    );
  }

  Widget _themeOption(BuildContext context, ThemeMode current, ThemeMode value,
      String label, IconData icon) {
    final selected = current == value;
    final scheme = Theme.of(context).colorScheme;
    return ListTile(
      leading:
      Icon(icon, color: selected ? scheme.primary : scheme.onSurface.withOpacity(0.6)),
      title: Text(label),
      trailing: selected ? Icon(Icons.check_rounded, color: scheme.primary) : null,
      onTap: () => themeModeNotifier.value = value,
    );
  }

  Widget _presetChip(BuildContext context, String label, VoidCallback onTap) {
    return ActionChip(label: Text(label), onPressed: onTap);
  }

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;

    return Scaffold(
      appBar: AppBar(title: const Text('Ayarlar')),
      body: ListView(
        padding: const EdgeInsets.only(bottom: 28),
        children: [
          _sectionTitle(context, 'GÖRÜNÜM'),
          ValueListenableBuilder<ThemeMode>(
            valueListenable: themeModeNotifier,
            builder: (context, mode, _) => Column(
              children: [
                _themeOption(context, mode, ThemeMode.system, 'Sistem',
                    Icons.brightness_auto_rounded),
                _themeOption(
                    context, mode, ThemeMode.light, 'Açık', Icons.light_mode_rounded),
                _themeOption(
                    context, mode, ThemeMode.dark, 'Koyu', Icons.dark_mode_rounded),
              ],
            ),
          ),
          const Divider(height: 24),

          _sectionTitle(context, 'GÖRÜNTÜ KALİTESİ VE PERFORMANS'),
          Padding(
            padding: const EdgeInsets.fromLTRB(20, 0, 20, 6),
            child: Text(
              'Bağlandığında bilgisayara gönderilir ve anında uygulanır.',
              style: TextStyle(fontSize: 12, color: scheme.onSurface.withOpacity(0.45)),
            ),
          ),
          ValueListenableBuilder<double>(
            valueListenable: AppSettings.quality,
            builder: (context, v, _) => _sliderTile(
              context,
              label: 'Görüntü kalitesi',
              valueText: v.round().toString(),
              value: v,
              min: 20,
              max: 90,
              onChanged: AppSettings.setQuality,
            ),
          ),
          ValueListenableBuilder<double>(
            valueListenable: AppSettings.scale,
            builder: (context, v, _) => _sliderTile(
              context,
              label: 'Çözünürlük',
              valueText: '${(v * 100).round()}%',
              value: v,
              min: 0.4,
              max: 0.95,
              onChanged: AppSettings.setScale,
            ),
          ),
          ValueListenableBuilder<double>(
            valueListenable: AppSettings.fps,
            builder: (context, v, _) => _sliderTile(
              context,
              label: 'Hedef FPS',
              valueText: v.round().toString(),
              value: v,
              min: 10,
              max: 30,
              onChanged: AppSettings.setFps,
            ),
          ),
          Padding(
            padding: const EdgeInsets.fromLTRB(20, 6, 20, 0),
            child: Wrap(
              spacing: 8,
              runSpacing: 8,
              children: [
                _presetChip(context, 'Hız önceliği', () {
                  AppSettings.setQuality(45);
                  AppSettings.setScale(0.6);
                  AppSettings.setFps(30);
                }),
                _presetChip(context, 'Dengeli', () {
                  AppSettings.setQuality(65);
                  AppSettings.setScale(0.8);
                  AppSettings.setFps(24);
                }),
                _presetChip(context, 'Kalite önceliği', () {
                  AppSettings.setQuality(85);
                  AppSettings.setScale(0.95);
                  AppSettings.setFps(18);
                }),
              ],
            ),
          ),
          const Divider(height: 32),

          _sectionTitle(context, 'KONTROL DAVRANIŞI'),
          ValueListenableBuilder<bool>(
            valueListenable: AppSettings.showCursor,
            builder: (context, v, _) => SwitchListTile(
              title: const Text('Fare imlecini göster'),
              subtitle: const Text('Bilgisayardaki imleci ekranda göster'),
              value: v,
              onChanged: AppSettings.setShowCursor,
            ),
          ),
          ValueListenableBuilder<double>(
            valueListenable: AppSettings.doubleTapWindowMs,
            builder: (context, v, _) => _sliderTile(
              context,
              label: 'Çift tıklama süresi',
              valueText: '${v.round()} ms',
              value: v,
              min: 120,
              max: 400,
              onChanged: AppSettings.setDoubleTapWindow,
            ),
          ),
          ValueListenableBuilder<double>(
            valueListenable: AppSettings.scrollSensitivity,
            builder: (context, v, _) => _sliderTile(
              context,
              label: 'Kaydırma hassasiyeti',
              valueText: '${v.toStringAsFixed(1)}x',
              value: v,
              min: 0.5,
              max: 2.5,
              onChanged: AppSettings.setScrollSensitivity,
            ),
          ),
          const SizedBox(height: 12),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 20),
            child: Text(
              'Uzaktan Ekran Kontrol — v1.1',
              style: TextStyle(fontSize: 12, color: scheme.onSurface.withOpacity(0.4)),
            ),
          ),
        ],
      ),
    );
  }
}

// ---------------------------------------------------------------------------
// Ekran görüntüsü + dokunma kontrolü ekranı
// ---------------------------------------------------------------------------
class RemoteScreenView extends StatefulWidget {
  final WebSocketChannel channel;
  const RemoteScreenView({super.key, required this.channel});

  @override
  State<RemoteScreenView> createState() => _RemoteScreenViewState();
}

class _RemoteScreenViewState extends State<RemoteScreenView> {
  Uint8List? _frame;
  double? _remoteW;
  double? _remoteH;

  // Bilgisayardaki gerçek fare imleci konumu (0-1 normalize)
  Offset? _cursorNorm;

  // Tek parmak sürükleme takibi
  bool _dragStarted = false;
  Offset? _gestureStartLocal;
  static const double _dragThreshold = 6.0;

  // İki parmakla kaydırma takibi
  Offset? _lastFocalPoint;

  // Gecikmesiz tek tık + akıllı çift tık algılama
  Timer? _tapTimer;
  Offset? _pendingTapPos;
  static const double _doubleTapSlop = 30.0;

  // Sanal klavye için ekran dışında tutulan gizli metin alanı
  static const String _kbPlaceholder = ' ';
  final TextEditingController _kbController =
  TextEditingController(text: _kbPlaceholder);
  final FocusNode _kbFocusNode = FocusNode();

  @override
  void initState() {
    super.initState();

    _kbController.selection =
    const TextSelection.collapsed(offset: _kbPlaceholder.length);
    _kbController.addListener(_onKeyboardTextChanged);
    _kbFocusNode.addListener(() => setState(() {}));

    SystemChrome.setPreferredOrientations([
      DeviceOrientation.landscapeLeft,
      DeviceOrientation.landscapeRight,
    ]);
    SystemChrome.setEnabledSystemUIMode(SystemUiMode.immersiveSticky);

    widget.channel.stream.listen(
          (data) {
        if (data is String) {
          try {
            final msg = jsonDecode(data);
            if (msg['type'] == 'info') {
              setState(() {
                _remoteW = (msg['width'] as num).toDouble();
                _remoteH = (msg['height'] as num).toDouble();
              });
            } else if (msg['type'] == 'cursor') {
              setState(() {
                _cursorNorm = Offset(
                  (msg['x'] as num).toDouble(),
                  (msg['y'] as num).toDouble(),
                );
              });
            }
          } catch (_) {
            // bozuk JSON, görmezden gel
          }
        } else if (data is List<int>) {
          setState(() => _frame = Uint8List.fromList(data));
        }
      },
      onError: (e) => debugPrint('WS hata: $e'),
      onDone: () {
        if (mounted) Navigator.of(context).maybePop();
      },
    );
  }

  void _send(Map<String, dynamic> msg) {
    widget.channel.sink.add(jsonEncode(msg));
  }

  /// Tek tıkı hemen göndermek yerine Ayarlar'da belirlenen kısa bir süre
  /// bekletir; bu süre içinde aynı yere ikinci dokunuş gelirse
  /// "double_tap" olarak gönderir.
  void _handleTapUp(Offset pos, Rect rect) {
    final hasPendingTap = _tapTimer != null && _tapTimer!.isActive;
    if (hasPendingTap &&
        _pendingTapPos != null &&
        (pos - _pendingTapPos!).distance < _doubleTapSlop) {
      _tapTimer!.cancel();
      _tapTimer = null;
      _pendingTapPos = null;
      final n = _normalize(pos, rect);
      _send({'type': 'double_tap', 'x': n.dx, 'y': n.dy});
      return;
    }

    _pendingTapPos = pos;
    final windowMs = AppSettings.doubleTapWindowMs.value.round();
    _tapTimer = Timer(Duration(milliseconds: windowMs), () {
      final n = _normalize(pos, rect);
      _send({'type': 'tap', 'x': n.dx, 'y': n.dy});
      _pendingTapPos = null;
    });
  }

  void _onKeyboardTextChanged() {
    final text = _kbController.text;
    if (text.length > _kbPlaceholder.length) {
      final added = text.substring(_kbPlaceholder.length);
      for (var i = 0; i < added.length; i++) {
        final char = added[i];
        _send({'type': 'key', 'key': char == '\n' ? 'enter' : char});
      }
      _resetKeyboardField();
    } else if (text.length < _kbPlaceholder.length) {
      _send({'type': 'key', 'key': 'backspace'});
      _resetKeyboardField();
    }
  }

  void _resetKeyboardField() {
    _kbController.value = const TextEditingValue(
      text: _kbPlaceholder,
      selection: TextSelection.collapsed(offset: _kbPlaceholder.length),
    );
  }

  void _toggleKeyboard() {
    if (_kbFocusNode.hasFocus) {
      _kbFocusNode.unfocus();
    } else {
      FocusScope.of(context).requestFocus(_kbFocusNode);
    }
  }

  /// Telefon ekranı ile bilgisayar ekranının en/boy oranı farklı olabileceği
  /// için görüntünün bozulmadan sığacağı dikdörtgeni hesaplar.
  Rect _imageRect(Size container) {
    final aspect = (_remoteW != null && _remoteH != null && _remoteH! > 0)
        ? _remoteW! / _remoteH!
        : 16 / 9;
    final containerAspect = container.width / container.height;

    double w, h;
    if (containerAspect > aspect) {
      h = container.height;
      w = h * aspect;
    } else {
      w = container.width;
      h = w / aspect;
    }

    final dx = (container.width - w) / 2;
    final dy = (container.height - h) / 2;
    return Rect.fromLTWH(dx, dy, w, h);
  }

  Offset _normalize(Offset local, Rect rect) {
    final cx = local.dx.clamp(rect.left, rect.right);
    final cy = local.dy.clamp(rect.top, rect.bottom);
    final dx = (cx - rect.left) / rect.width;
    final dy = (cy - rect.top) / rect.height;
    return Offset(dx.clamp(0, 1), dy.clamp(0, 1));
  }

  @override
  void dispose() {
    SystemChrome.setPreferredOrientations([]);
    SystemChrome.setEnabledSystemUIMode(SystemUiMode.edgeToEdge);
    _tapTimer?.cancel();
    _kbController.dispose();
    _kbFocusNode.dispose();
    widget.channel.sink.close();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.black,
      body: LayoutBuilder(
        builder: (context, constraints) {
          final size = Size(constraints.maxWidth, constraints.maxHeight);
          final rect = _imageRect(size);

          return Stack(
            children: [
              GestureDetector(
                behavior: HitTestBehavior.opaque,
                onTapUp: (d) => _handleTapUp(d.localPosition, rect),
                onLongPressStart: (d) {
                  final n = _normalize(d.localPosition, rect);
                  _send({'type': 'right_tap', 'x': n.dx, 'y': n.dy});
                },
                onScaleStart: (d) {
                  _gestureStartLocal = d.localFocalPoint;
                  _dragStarted = false;
                  _lastFocalPoint = d.focalPoint;
                },
                onScaleUpdate: (d) {
                  if (d.pointerCount >= 2) {
                    if (_lastFocalPoint != null) {
                      final deltaY = d.focalPoint.dy - _lastFocalPoint!.dy;
                      if (deltaY.abs() > 1) {
                        final sensitivity = AppSettings.scrollSensitivity.value;
                        _send({
                          'type': 'scroll',
                          'dy': (deltaY / 4 * sensitivity).round(),
                        });
                      }
                    }
                    _lastFocalPoint = d.focalPoint;
                    return;
                  }

                  if (!_dragStarted) {
                    final start = _gestureStartLocal ?? d.localFocalPoint;
                    final moved = (d.localFocalPoint - start).distance;
                    if (moved < _dragThreshold) return;
                    _dragStarted = true;
                    final n = _normalize(start, rect);
                    _send({'type': 'drag_start', 'x': n.dx, 'y': n.dy});
                  }
                  final n = _normalize(d.localFocalPoint, rect);
                  _send({'type': 'drag_move', 'x': n.dx, 'y': n.dy});
                },
                onScaleEnd: (d) {
                  if (_dragStarted) {
                    _send({'type': 'drag_end'});
                  }
                  _dragStarted = false;
                  _gestureStartLocal = null;
                  _lastFocalPoint = null;
                },
                child: Stack(
                  fit: StackFit.expand,
                  children: [
                    Container(color: Colors.black),
                    if (_frame != null)
                      Positioned.fromRect(
                        rect: rect,
                        child: Image.memory(
                          _frame!,
                          gaplessPlayback: true,
                          fit: BoxFit.fill,
                        ),
                      )
                    else
                      const Center(
                        child: Column(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            CircularProgressIndicator(color: Colors.white54),
                            SizedBox(height: 12),
                            Text(
                              'Görüntü bekleniyor...',
                              style: TextStyle(color: Colors.white54),
                            ),
                          ],
                        ),
                      ),

                    // Bilgisayardaki gerçek fare imlecinin gösterimi
                    ValueListenableBuilder<bool>(
                      valueListenable: AppSettings.showCursor,
                      builder: (context, show, _) {
                        if (!show || _cursorNorm == null || _frame == null) {
                          return const SizedBox.shrink();
                        }
                        return Positioned(
                          left: rect.left + _cursorNorm!.dx * rect.width - 11,
                          top: rect.top + _cursorNorm!.dy * rect.height - 11,
                          child: const IgnorePointer(child: _CursorDot()),
                        );
                      },
                    ),
                  ],
                ),
              ),

              // Klavye yazımını yakalamak için ekran dışında tutulan,
              // görünmez minik metin alanı. Sadece odak (focus) almak için var.
              Positioned(
                left: -200,
                top: -200,
                child: SizedBox(
                  width: 1,
                  height: 1,
                  child: TextField(
                    controller: _kbController,
                    focusNode: _kbFocusNode,
                    autocorrect: false,
                    enableSuggestions: false,
                    showCursor: false,
                    style: const TextStyle(color: Colors.transparent, fontSize: 1),
                    cursorColor: Colors.transparent,
                    decoration: const InputDecoration(border: InputBorder.none),
                  ),
                ),
              ),

              // Üst durum çubuğu: bağlantı durumu + kapatma butonu
              Positioned(
                top: 10,
                left: 10,
                right: 10,
                child: SafeArea(
                  child: Row(
                    children: [
                      Container(
                        padding: const EdgeInsets.symmetric(
                            horizontal: 10, vertical: 6),
                        decoration: BoxDecoration(
                          color: Colors.black.withOpacity(0.55),
                          borderRadius: BorderRadius.circular(20),
                        ),
                        child: Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            Container(
                              width: 8,
                              height: 8,
                              decoration: const BoxDecoration(
                                color: Colors.greenAccent,
                                shape: BoxShape.circle,
                              ),
                            ),
                            const SizedBox(width: 6),
                            const Text(
                              'Bağlı',
                              style: TextStyle(color: Colors.white, fontSize: 12),
                            ),
                          ],
                        ),
                      ),
                      const Spacer(),
                      InkWell(
                        onTap: () => Navigator.of(context).maybePop(),
                        borderRadius: BorderRadius.circular(20),
                        child: Container(
                          padding: const EdgeInsets.all(8),
                          decoration: BoxDecoration(
                            color: Colors.black.withOpacity(0.55),
                            shape: BoxShape.circle,
                          ),
                          child: const Icon(Icons.close_rounded,
                              color: Colors.white, size: 18),
                        ),
                      ),
                    ],
                  ),
                ),
              ),

              // Sağ altta klavyeyi aç/kapat butonu
              Positioned(
                bottom: 16,
                right: 16,
                child: SafeArea(
                  child: InkWell(
                    onTap: _toggleKeyboard,
                    borderRadius: BorderRadius.circular(28),
                    child: Container(
                      padding: const EdgeInsets.all(14),
                      decoration: BoxDecoration(
                        color: _kbFocusNode.hasFocus
                            ? const Color(0xFF6366F1)
                            : Colors.black.withOpacity(0.55),
                        shape: BoxShape.circle,
                      ),
                      child: const Icon(
                        Icons.keyboard_rounded,
                        color: Colors.white,
                        size: 22,
                      ),
                    ),
                  ),
                ),
              ),
            ],
          );
        },
      ),
    );
  }
}

/// Modern, sade bir nokta + hafif "spot" halkası şeklinde fare imleci.
class _CursorDot extends StatelessWidget {
  const _CursorDot();

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      width: 22,
      height: 22,
      child: Stack(
        alignment: Alignment.center,
        children: [
          Container(
            width: 22,
            height: 22,
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              color: _seedColor.withOpacity(0.16),
            ),
          ),
          Container(
            width: 10,
            height: 10,
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              color: Colors.white,
              border: Border.all(color: Colors.black.withOpacity(0.45), width: 1.2),
              boxShadow: [
                BoxShadow(
                  color: Colors.black.withOpacity(0.25),
                  blurRadius: 3,
                  offset: const Offset(0, 1),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}