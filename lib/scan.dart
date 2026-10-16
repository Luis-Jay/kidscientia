// scan_screen.dart
import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:mobile_scanner/mobile_scanner.dart';

import 'model_registry.dart';
import 'ar_view_screen.dart';

class ScanScreen extends StatefulWidget {
  const ScanScreen({super.key});

  @override
  State<ScanScreen> createState() => _ScanScreenState();
}

class _ScanScreenState extends State<ScanScreen>
    with SingleTickerProviderStateMixin {
  MobileScannerController? _cameraController;
  late AnimationController _animController;
  late Animation<double> _scanLine;

  bool _isScanned = false;
  bool _isTorchOn = false;
  bool _isDisposed = false;

  @override
  void initState() {
    super.initState();
    _createScannerController();
    _animController = AnimationController(
      vsync: this,
      duration: const Duration(seconds: 2),
    )..repeat(reverse: true);
    _scanLine = CurvedAnimation(
      parent: _animController,
      curve: Curves.easeInOut,
    );
  }

  @override
  void dispose() {
    _isDisposed = true;
    final controller = _cameraController;
    _cameraController = null;
    if (controller != null) {
      unawaited(controller.dispose());
    }
    _animController.dispose();
    super.dispose();
  }

  Future<void> _onDetect(BarcodeCapture capture) async {
    if (_isScanned) return;
    final controller = _cameraController;
    if (controller == null) return;

    final raw = capture.barcodes.firstOrNull?.rawValue;
    if (raw == null) return;

    HapticFeedback.mediumImpact();
    setState(() => _isScanned = true);

    final entry = ModelRegistry.resolve(raw);
    final qrKey = ModelRegistry.normalizeQrValue(raw);

    if (entry != null) {
      await _releaseScannerController();
      if (!mounted || _isDisposed) return;

      // Known model → go straight to AR
      await Navigator.push(context, _arRoute(qrKey));
    } else {
      await _stopScanner(controller);
      if (!mounted || _isDisposed) return;

      debugPrint(
        'Unknown QR raw="$raw" candidates=${ModelRegistry.candidateKeys(raw)}',
      );
      // Unknown QR → show generic result sheet
      await _showUnknownSheet(raw);
    }

    // Resume scanning when we come back
    if (mounted && !_isDisposed) {
      await Future<void>.delayed(const Duration(milliseconds: 500));
      if (!mounted || _isDisposed) return;

      if (_cameraController == null) {
        setState(() {
          _createScannerController();
          _isScanned = false;
          _isTorchOn = false;
        });
      } else {
        setState(() => _isScanned = false);
        await _startScanner(_cameraController!);
      }
    }
  }

  void _createScannerController() {
    _cameraController = MobileScannerController();
  }

  Future<void> _releaseScannerController() async {
    final controller = _cameraController;
    if (controller == null) return;

    setState(() {
      _cameraController = null;
      _isTorchOn = false;
    });

    await WidgetsBinding.instance.endOfFrame;
    if (_isDisposed) return;

    await _stopScanner(controller);

    try {
      await controller.dispose();
    } catch (e) {
      debugPrint('Scanner dispose failed: $e');
    }

    await Future<void>.delayed(const Duration(milliseconds: 400));
  }

  Future<void> _stopScanner(MobileScannerController controller) async {
    try {
      await controller.stop();
    } catch (e) {
      debugPrint('Scanner stop failed: $e');
    }
  }

  Future<void> _startScanner(MobileScannerController controller) async {
    if (!mounted || _isDisposed) return;

    try {
      await controller.start();
    } catch (e) {
      debugPrint('Scanner restart failed: $e');
    }
  }

  PageRoute _arRoute(String qrText) => PageRouteBuilder(
    pageBuilder: (_, anim, __) => ArEarthMapScreen(qrValue: qrText),
    transitionsBuilder: (_, anim, __, child) =>
        FadeTransition(opacity: anim, child: child),
    transitionDuration: const Duration(milliseconds: 600),
  );

  Future<void> _showUnknownSheet(String value) async {
    await showModalBottomSheet(
      context: context,
      backgroundColor: Colors.transparent,
      builder: (_) => _UnknownSheet(value: value),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.black,
      body: Stack(
        children: [
          if (_cameraController != null)
            MobileScanner(controller: _cameraController!, onDetect: _onDetect)
          else
            const ColoredBox(color: Colors.black),
          _ScannerOverlay(scanLine: _scanLine),
          _TopBar(
            isTorchOn: _isTorchOn,
            onBack: () => Navigator.pop(context),
            onTorch: () async {
              final controller = _cameraController;
              if (controller == null) return;

              try {
                await controller.toggleTorch();
              } catch (e) {
                debugPrint('Torch toggle failed: $e');
                return;
              }
              if (!mounted) return;
              setState(() => _isTorchOn = !_isTorchOn);
            },
          ),
          const _BottomHint(),
        ],
      ),
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// Scanner overlay
// ─────────────────────────────────────────────────────────────────────────────
class _ScannerOverlay extends StatelessWidget {
  final Animation<double> scanLine;
  const _ScannerOverlay({required this.scanLine});

  static const double _frame = 260;
  static const double _cLen = 28;
  static const Color _teal = Color(0xFF5BBFBF);

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (ctx, box) {
        final w = box.maxWidth, h = box.maxHeight;
        final lx = (w - _frame) / 2, ty = (h - _frame) / 2;

        return Stack(
          children: [
            _dim(0, 0, w, ty),
            _dim(0, ty + _frame, w, h - ty - _frame),
            _dim(0, ty, lx, _frame),
            _dim(lx + _frame, ty, w - lx - _frame, _frame),
            ..._corners(lx, ty),
            // Subtle inner glow on frame
            Positioned(
              left: lx,
              top: ty,
              child: Container(
                width: _frame,
                height: _frame,
                decoration: BoxDecoration(
                  border: Border.all(color: _teal.withOpacity(0.2), width: 1),
                ),
              ),
            ),
            // Scan line
            AnimatedBuilder(
              animation: scanLine,
              builder: (_, __) {
                final y = ty + 6 + scanLine.value * (_frame - 12);
                return Positioned(
                  left: lx + 10,
                  top: y,
                  width: _frame - 20,
                  height: 2,
                  child: DecoratedBox(
                    decoration: BoxDecoration(
                      gradient: LinearGradient(
                        colors: [
                          Colors.transparent,
                          _teal.withOpacity(0.95),
                          Colors.transparent,
                        ],
                      ),
                      boxShadow: [
                        BoxShadow(
                          color: _teal.withOpacity(0.5),
                          blurRadius: 8,
                          spreadRadius: 2,
                        ),
                      ],
                    ),
                  ),
                );
              },
            ),
          ],
        );
      },
    );
  }

  Widget _dim(double x, double y, double w, double h) => Positioned(
    left: x,
    top: y,
    width: w,
    height: h,
    child: const ColoredBox(color: Color(0xBB000000)),
  );

  List<Widget> _corners(double lx, double ty) => [
    _corner(lx, ty, false, false),
    _corner(lx + _frame - _cLen, ty, true, false),
    _corner(lx, ty + _frame - _cLen, false, true),
    _corner(lx + _frame - _cLen, ty + _frame - _cLen, true, true),
  ];

  Widget _corner(double x, double y, bool fh, bool fv) => Positioned(
    left: x,
    top: y,
    child: Transform(
      alignment: Alignment.center,
      transform: Matrix4.identity()..scale(fh ? -1.0 : 1.0, fv ? -1.0 : 1.0),
      child: SizedBox(
        width: _cLen,
        height: _cLen,
        child: CustomPaint(painter: _CornerPainter()),
      ),
    ),
  );
}

class _CornerPainter extends CustomPainter {
  @override
  void paint(Canvas canvas, Size size) {
    canvas.drawPath(
      Path()
        ..moveTo(0, size.height)
        ..lineTo(0, 0)
        ..lineTo(size.width, 0),
      Paint()
        ..color = const Color(0xFF5BBFBF)
        ..strokeWidth = 4
        ..strokeCap = StrokeCap.round
        ..style = PaintingStyle.stroke,
    );
  }

  @override
  bool shouldRepaint(_) => false;
}

// ─────────────────────────────────────────────────────────────────────────────
// Top bar
// ─────────────────────────────────────────────────────────────────────────────
class _TopBar extends StatelessWidget {
  final bool isTorchOn;
  final VoidCallback onBack, onTorch;
  const _TopBar({
    required this.isTorchOn,
    required this.onBack,
    required this.onTorch,
  });

  @override
  Widget build(BuildContext context) {
    return SafeArea(
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
        child: Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            _CircleButton(
              icon: Icons.arrow_back_ios_new_rounded,
              onTap: onBack,
            ),
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
              decoration: BoxDecoration(
                color: Colors.black.withOpacity(0.45),
                borderRadius: BorderRadius.circular(20),
                border: Border.all(color: Colors.white.withOpacity(0.15)),
              ),
              child: const Text(
                'Scan Flashcard',
                style: TextStyle(
                  color: Colors.white,
                  fontSize: 15,
                  fontWeight: FontWeight.w600,
                  letterSpacing: 0.4,
                ),
              ),
            ),
            _CircleButton(
              icon: isTorchOn
                  ? Icons.flash_on_rounded
                  : Icons.flash_off_rounded,
              iconColor: isTorchOn ? const Color(0xFF5BBFBF) : Colors.white,
              onTap: onTorch,
            ),
          ],
        ),
      ),
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// Bottom hint
// ─────────────────────────────────────────────────────────────────────────────
class _BottomHint extends StatelessWidget {
  const _BottomHint();

  @override
  Widget build(BuildContext context) {
    return Positioned(
      bottom: 60,
      left: 0,
      right: 0,
      child: Column(
        children: [
          const Icon(
            Icons.qr_code_scanner_rounded,
            color: Colors.white54,
            size: 22,
          ),
          const SizedBox(height: 8),
          Text(
            'Point at a flashcard QR code',
            style: TextStyle(
              color: Colors.white.withOpacity(0.65),
              fontSize: 13,
            ),
          ),
          const SizedBox(height: 4),
          Text(
            'The 3D model will appear in AR',
            style: TextStyle(
              color: const Color(0xFF5BBFBF).withOpacity(0.8),
              fontSize: 12,
              fontWeight: FontWeight.w500,
            ),
          ),
        ],
      ),
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// Unknown QR sheet
// ─────────────────────────────────────────────────────────────────────────────
class _UnknownSheet extends StatelessWidget {
  final String value;
  const _UnknownSheet({required this.value});

  @override
  Widget build(BuildContext context) {
    return Container(
      margin: const EdgeInsets.all(16),
      padding: const EdgeInsets.all(24),
      decoration: BoxDecoration(
        color: const Color(0xFF1A1A2E),
        borderRadius: BorderRadius.circular(24),
        border: Border.all(color: Colors.white12),
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Container(
            width: 40,
            height: 4,
            margin: const EdgeInsets.only(bottom: 20),
            decoration: BoxDecoration(
              color: Colors.white24,
              borderRadius: BorderRadius.circular(2),
            ),
          ),
          Container(
            width: 56,
            height: 56,
            decoration: BoxDecoration(
              color: Colors.orange.withOpacity(0.15),
              shape: BoxShape.circle,
              border: Border.all(color: Colors.orange.shade400, width: 2),
            ),
            child: Icon(
              Icons.help_outline_rounded,
              color: Colors.orange.shade400,
              size: 30,
            ),
          ),
          const SizedBox(height: 16),
          const Text(
            'Unknown QR Code',
            style: TextStyle(
              color: Colors.white,
              fontSize: 18,
              fontWeight: FontWeight.w700,
            ),
          ),
          const SizedBox(height: 8),
          Text(
            '"$value"',
            textAlign: TextAlign.center,
            style: TextStyle(
              color: Colors.white.withOpacity(0.55),
              fontSize: 13,
            ),
          ),
          const SizedBox(height: 10),
          Text(
            'This QR code doesn\'t match any flashcard model.',
            textAlign: TextAlign.center,
            style: TextStyle(
              color: Colors.white.withOpacity(0.45),
              fontSize: 12,
            ),
          ),
          const SizedBox(height: 24),
          SizedBox(
            width: double.infinity,
            child: ElevatedButton(
              onPressed: () => Navigator.pop(context),
              style: ElevatedButton.styleFrom(
                backgroundColor: const Color(0xFF5BBFBF),
                foregroundColor: Colors.white,
                elevation: 0,
                padding: const EdgeInsets.symmetric(vertical: 14),
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(12),
                ),
              ),
              child: const Text(
                'Try Again',
                style: TextStyle(fontWeight: FontWeight.w700),
              ),
            ),
          ),
          const SizedBox(height: 8),
        ],
      ),
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// Reusable circle button
// ─────────────────────────────────────────────────────────────────────────────
class _CircleButton extends StatelessWidget {
  final IconData icon;
  final Color iconColor;
  final VoidCallback onTap;
  const _CircleButton({
    required this.icon,
    required this.onTap,
    this.iconColor = Colors.white,
  });

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        width: 44,
        height: 44,
        decoration: BoxDecoration(
          color: Colors.black.withOpacity(0.45),
          shape: BoxShape.circle,
          border: Border.all(color: Colors.white.withOpacity(0.15)),
        ),
        child: Icon(icon, color: iconColor, size: 20),
      ),
    );
  }
}
