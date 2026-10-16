import 'package:arcore_flutter_plugin/arcore_flutter_plugin.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:vector_math/vector_math_64.dart' as vector64;

import 'model_registry.dart';

class ArEarthMapScreen extends StatefulWidget {
  final String qrValue;

  const ArEarthMapScreen({super.key, required this.qrValue});

  @override
  State<ArEarthMapScreen> createState() => _ArEarthMapScreenState();
}

class _ArEarthMapScreenState extends State<ArEarthMapScreen> {
  ArCoreController? _arController;
  ModelEntry? _modelEntry;
  bool _isLoading = true;
  bool _isPlaced = false;
  bool _showInstructions = true;
  bool _isClosing = false;
  bool _showInfoCard = false;

  @override
  void initState() {
    super.initState();
    _modelEntry = ModelRegistry.resolve(widget.qrValue);
    if (_modelEntry != null) {
      _preloadModel(_modelEntry!.assetPath);
    } else {
      setState(() => _isLoading = false);
    }
  }

  Future<void> _preloadModel(String assetPath) async {
    try {
      await rootBundle.load(assetPath);
    } catch (e) {
      debugPrint("⚠️ Failed to preload model: $e");
    } finally {
      if (mounted) setState(() => _isLoading = false);
    }
  }

  void _onArViewCreated(ArCoreController controller) {
    if (_isClosing) {
      return;
    }

    _arController = controller;
    controller.onPlaneTap = _onPlaneTap;
  }

  Future<void> _onPlaneTap(List<ArCoreHitTestResult> hits) async {
    if (_isPlaced || hits.isEmpty || _modelEntry == null) return;

    final hit = hits.first;
    final position = hit.pose.translation + vector64.Vector3(0, 0.05, 0);

    final node = ArCoreReferenceNode(
      name: "DynamicModel",
      objectUrl: _modelEntry!.assetPath,
      position: position,
      rotation: hit.pose.rotation,
      scale: vector64.Vector3(0.3, 0.3, 0.3),
    );

    try {
      await _arController?.addArCoreNodeWithAnchor(node);
      if (mounted) {
        setState(() {
          _isPlaced = true;
          _showInfoCard = true;
        });
      }
    } catch (e) {
      debugPrint("🔴 Failed to place model: $e");
    }
  }

  @override
  void dispose() {
    _detachArController();
    SystemChrome.setEnabledSystemUIMode(SystemUiMode.edgeToEdge);
    super.dispose();
  }

  void _detachArController() {
    final controller = _arController;
    if (controller == null) return;

    controller.onPlaneTap = null;
    controller.onNodeTap = null;
    controller.onError = null;
    controller.onPlaneDetected = null;
    controller.onTrackingImage = null;
    try {
      controller.dispose();
    } catch (e) {
      debugPrint('AR controller dispose failed: $e');
    }
    _arController = null;
  }

  bool _handleBackNavigation() {
    if (_isClosing) return false;

    _isClosing = true;
    _detachArController();
    return true;
  }

  void _startArSession() {
    if (_isClosing) return;
    setState(() => _showInstructions = false);
  }

  @override
  Widget build(BuildContext context) {
    return PopScope(
      canPop: false,
      onPopInvokedWithResult: (didPop, result) {
        if (didPop) return;
        if (_handleBackNavigation() && mounted) {
          Navigator.of(context).pop();
        }
      },
      child: Scaffold(
        appBar: AppBar(
          leading: IconButton(
            icon: const Icon(Icons.arrow_back),
            onPressed: () {
              if (_handleBackNavigation() && mounted) {
                Navigator.of(context).pop();
              }
            },
          ),
          title: Text(_modelEntry?.displayName ?? "Model Not Found"),
          centerTitle: true,
        ),
        body: _modelEntry == null
            ? const Center(
                child: Text(
                  "No model registered for this QR code.",
                  style: TextStyle(fontSize: 16),
                ),
              )
            : Stack(
                children: [
                  if (!_isClosing && !_showInstructions && !_isLoading)
                    ArCoreView(
                      onArCoreViewCreated: _onArViewCreated,
                      enablePlaneRenderer: true,
                      enableTapRecognizer: true,
                    )
                  else
                    const ColoredBox(color: Colors.black),
                  if (_isLoading)
                    Container(
                      color: Colors.black.withValues(alpha: 0.45),
                      child: const Center(
                        child: Column(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            CircularProgressIndicator(color: Colors.white),
                            SizedBox(height: 16),
                            Text(
                              "Loading model…",
                              style: TextStyle(
                                color: Colors.white,
                                fontSize: 16,
                              ),
                            ),
                          ],
                        ),
                      ),
                    )
                  else if (_showInstructions)
                    _InstructionsOverlay(
                      modelName: _modelEntry!.displayName,
                      onStart: _startArSession,
                    )
                  else if (!_isPlaced)
                    Positioned(
                      bottom: 40,
                      left: 24,
                      right: 24,
                      child: Container(
                        padding: const EdgeInsets.symmetric(
                          horizontal: 20,
                          vertical: 14,
                        ),
                        decoration: BoxDecoration(
                          color: Colors.black.withValues(alpha: 0.60),
                          borderRadius: BorderRadius.circular(16),
                          border: Border.all(
                            color: const Color(
                              0xFF5BBFBF,
                            ).withValues(alpha: 0.5),
                          ),
                        ),
                        child: const Row(
                          children: [
                            Icon(
                              Icons.touch_app_rounded,
                              color: Color(0xFF5BBFBF),
                              size: 22,
                            ),
                            SizedBox(width: 12),
                            Expanded(
                              child: Text(
                                "Slowly move your camera around until you see white dots, then tap on them to place the model.",
                                style: TextStyle(
                                  color: Colors.white,
                                  fontSize: 13,
                                ),
                              ),
                            ),
                          ],
                        ),
                      ),
                    ),
                  if (_isPlaced && !_isLoading)
                    _ModelInfoOverlay(
                      modelEntry: _modelEntry!,
                      visible: _showInfoCard,
                      onToggle: () =>
                          setState(() => _showInfoCard = !_showInfoCard),
                    ),
                ],
              ),
      ),
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// Info card shown once the model has been placed, with a floating
// toggle button to show/hide it so it doesn't permanently block the view.
// ─────────────────────────────────────────────────────────────────────────────
class _ModelInfoOverlay extends StatelessWidget {
  final ModelEntry modelEntry;
  final bool visible;
  final VoidCallback onToggle;

  const _ModelInfoOverlay({
    required this.modelEntry,
    required this.visible,
    required this.onToggle,
  });

  static const _teal = Color(0xFF5BBFBF);

  @override
  Widget build(BuildContext context) {
    return Positioned(
      left: 0,
      right: 0,
      bottom: 0,
      child: SafeArea(
        top: false,
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 20),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.end,
            children: [
              AnimatedSize(
                duration: const Duration(milliseconds: 220),
                curve: Curves.easeOut,
                alignment: Alignment.bottomCenter,
                child: visible ? _buildCard() : const SizedBox.shrink(),
              ),
              const SizedBox(height: 12),
              _ToggleButton(visible: visible, onTap: onToggle),
              const SizedBox(height: 16),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildCard() {
    return Container(
      width: double.infinity,
      margin: const EdgeInsets.only(bottom: 4),
      padding: const EdgeInsets.fromLTRB(20, 18, 16, 20),
      decoration: BoxDecoration(
        color: const Color(0xFF14201F).withValues(alpha: 0.92),
        borderRadius: BorderRadius.circular(22),
        border: Border.all(color: _teal.withValues(alpha: 0.55), width: 1.5),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.35),
            blurRadius: 16,
            offset: const Offset(0, 6),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(modelEntry.emoji, style: const TextStyle(fontSize: 34)),
              const SizedBox(width: 12),
              Expanded(
                child: Padding(
                  padding: const EdgeInsets.only(top: 4),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        modelEntry.displayName,
                        style: const TextStyle(
                          color: Colors.white,
                          fontSize: 19,
                          fontWeight: FontWeight.w800,
                        ),
                      ),
                      const SizedBox(height: 2),
                      Text(
                        modelEntry.category.label,
                        style: TextStyle(
                          color: _teal,
                          fontSize: 12,
                          fontWeight: FontWeight.w700,
                          letterSpacing: 0.6,
                        ),
                      ),
                    ],
                  ),
                ),
              ),
              GestureDetector(
                onTap: onToggle,
                child: Icon(
                  Icons.close_rounded,
                  color: Colors.white.withValues(alpha: 0.55),
                  size: 22,
                ),
              ),
            ],
          ),
          const SizedBox(height: 12),
          Text(
            modelEntry.description,
            style: TextStyle(
              color: Colors.white.withValues(alpha: 0.85),
              fontSize: 14,
              height: 1.5,
            ),
          ),
        ],
      ),
    );
  }
}

class _ToggleButton extends StatelessWidget {
  final bool visible;
  final VoidCallback onTap;

  const _ToggleButton({required this.visible, required this.onTap});

  static const _teal = Color(0xFF5BBFBF);

  @override
  Widget build(BuildContext context) {
    if (visible) return const SizedBox.shrink();
    return GestureDetector(
      onTap: onTap,
      child: Container(
        width: 48,
        height: 48,
        decoration: BoxDecoration(
          color: _teal,
          shape: BoxShape.circle,
          boxShadow: [
            BoxShadow(
              color: Colors.black.withValues(alpha: 0.3),
              blurRadius: 10,
              offset: const Offset(0, 4),
            ),
          ],
        ),
        child: const Icon(
          Icons.info_outline_rounded,
          color: Colors.white,
          size: 24,
        ),
      ),
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// Full-screen instruction overlay shown before AR begins
// ─────────────────────────────────────────────────────────────────────────────
class _InstructionsOverlay extends StatelessWidget {
  final String modelName;
  final VoidCallback onStart;

  const _InstructionsOverlay({required this.modelName, required this.onStart});

  static const _teal = Color(0xFF5BBFBF);

  @override
  Widget build(BuildContext context) {
    return Container(
      color: Colors.black.withValues(alpha: 0.88),
      child: SafeArea(
        child: SingleChildScrollView(
          padding: const EdgeInsets.symmetric(horizontal: 28, vertical: 20),
          child: Column(
            children: [
              // Icon badge
              Container(
                width: 64,
                height: 64,
                decoration: BoxDecoration(
                  color: _teal.withValues(alpha: 0.15),
                  shape: BoxShape.circle,
                  border: Border.all(color: _teal, width: 2),
                ),
                child: const Icon(
                  Icons.view_in_ar_rounded,
                  color: _teal,
                  size: 32,
                ),
              ),
              const SizedBox(height: 14),
              const Text(
                "Get Ready for AR",
                style: TextStyle(
                  color: Colors.white,
                  fontSize: 22,
                  fontWeight: FontWeight.w800,
                  letterSpacing: 0.3,
                ),
              ),
              const SizedBox(height: 4),
              Text(
                "You're about to view: $modelName",
                textAlign: TextAlign.center,
                style: TextStyle(
                  color: Colors.white.withValues(alpha: 0.55),
                  fontSize: 13,
                ),
              ),
              const SizedBox(height: 24),

              // Step cards
              _StepCard(
                step: "1",
                icon: Icons.accessibility_new_rounded,
                title: "Stand up & clear the area",
                description:
                    "Get off your chair and make sure there's enough open space around you for the best experience.",
              ),
              const SizedBox(height: 10),
              _StepCard(
                step: "2",
                icon: Icons.videocam_rounded,
                title: "Slowly move your camera",
                description:
                    "Point your phone at a flat surface like a table or floor and move it around slowly. White dots will appear — that means the surface is detected.",
              ),
              const SizedBox(height: 10),
              _StepCard(
                step: "3",
                icon: Icons.touch_app_rounded,
                title: "Tap the white dots",
                description:
                    "Once you see the white dots, tap on them to reveal the $modelName in AR right on that surface.",
              ),

              const SizedBox(height: 24),
              SizedBox(
                width: double.infinity,
                child: ElevatedButton(
                  onPressed: onStart,
                  style: ElevatedButton.styleFrom(
                    backgroundColor: _teal,
                    foregroundColor: Colors.white,
                    elevation: 0,
                    padding: const EdgeInsets.symmetric(vertical: 15),
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(14),
                    ),
                  ),
                  child: const Text(
                    "I'm Ready — Start AR",
                    style: TextStyle(fontSize: 15, fontWeight: FontWeight.w700),
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _StepCard extends StatelessWidget {
  final String step;
  final IconData icon;
  final String title;
  final String description;

  const _StepCard({
    required this.step,
    required this.icon,
    required this.title,
    required this.description,
  });

  static const _teal = Color(0xFF5BBFBF);

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: Colors.white.withValues(alpha: 0.06),
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: Colors.white.withValues(alpha: 0.10)),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Step number circle
          Container(
            width: 32,
            height: 32,
            decoration: BoxDecoration(
              color: _teal.withValues(alpha: 0.2),
              shape: BoxShape.circle,
              border: Border.all(color: _teal.withValues(alpha: 0.6)),
            ),
            child: Center(
              child: Text(
                step,
                style: const TextStyle(
                  color: _teal,
                  fontSize: 13,
                  fontWeight: FontWeight.w800,
                ),
              ),
            ),
          ),
          const SizedBox(width: 14),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Icon(icon, color: _teal, size: 16),
                    const SizedBox(width: 6),
                    Text(
                      title,
                      style: const TextStyle(
                        color: Colors.white,
                        fontSize: 14,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 4),
                Text(
                  description,
                  style: TextStyle(
                    color: Colors.white.withValues(alpha: 0.60),
                    fontSize: 12,
                    height: 1.45,
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}
