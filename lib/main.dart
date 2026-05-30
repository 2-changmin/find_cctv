import 'dart:async';
import 'dart:io';
import 'dart:math' as math;
import 'dart:typed_data';
import 'dart:ui' as ui;

import 'package:camera/camera.dart';
import 'package:flutter/material.dart';
import 'package:image/image.dart' as img;
import 'package:image_picker/image_picker.dart';
import 'package:path_provider/path_provider.dart';
import 'package:url_launcher/url_launcher.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  runApp(const SafeLensApp());
}

class SuspiciousBox {
  const SuspiciousBox(
      {required this.x,
      required this.y,
      required this.w,
      required this.h,
      required this.score});

  final int x;
  final int y;
  final int w;
  final int h;
  final double score;
}

List<SuspiciousBox> detectSuspiciousSpots(img.Image source) {
  final width = source.width;
  final height = source.height;
  final total = width * height;
  final bright = Uint8List(total);
  final dark = Uint8List(total);
  final visitedBright = Uint8List(total);
  final visitedDark = Uint8List(total);
  final lum = Float32List(total);

  for (var y = 0; y < height; y += 1) {
    for (var x = 0; x < width; x += 1) {
      final pixel = source.getPixel(x, y);
      final value = (pixel.r + pixel.g + pixel.b) / 3;
      final index = y * width + x;
      lum[index] = value.toDouble();
      if (value >= 242) bright[index] = 1;
      if (value <= 42) dark[index] = 1;
    }
  }

  final boxes = <String, SuspiciousBox>{};
  final directions = [-1, 1, -width, width];

  double getRingContrast(int x0, int y0, int x1, int y1, double objectMean) {
    var ringSum = 0.0;
    var ringCount = 0;
    for (var y = math.max(0, y0 - 2);
        y <= math.min(height - 1, y1 + 2);
        y += 1) {
      for (var x = math.max(0, x0 - 2);
          x <= math.min(width - 1, x1 + 2);
          x += 1) {
        if (x >= x0 && x <= x1 && y >= y0 && y <= y1) continue;
        ringSum += lum[y * width + x];
        ringCount += 1;
      }
    }
    if (ringCount == 0) return 0;
    return objectMean - ringSum / ringCount;
  }

  void addCandidate(int x, int y, int boxWidth, int boxHeight, double score) {
    final key = '${(x / 8).round()}-${(y / 8).round()}';
    final previous = boxes[key];
    if (previous == null || previous.score < score) {
      boxes[key] =
          SuspiciousBox(x: x, y: y, w: boxWidth, h: boxHeight, score: score);
    }
  }

  double circularityPenalty(int boxWidth, int boxHeight) {
    final aspect = boxWidth > boxHeight
        ? boxWidth / math.max(1, boxHeight)
        : boxHeight / math.max(1, boxWidth);
    return math.max(0, aspect - 1.8) * 0.25;
  }

  void visitComponents(Uint8List mask, Uint8List visited, bool isBright) {
    for (var i = 0; i < total; i += 1) {
      if (mask[i] == 0 || visited[i] == 1) continue;
      final queue = <int>[i];
      visited[i] = 1;
      var minX = width;
      var minY = height;
      var maxX = 0;
      var maxY = 0;
      var count = 0;
      var sumL = 0.0;

      while (queue.isNotEmpty) {
        final current = queue.removeLast();
        final x = current % width;
        final y = current ~/ width;
        minX = math.min(minX, x);
        minY = math.min(minY, y);
        maxX = math.max(maxX, x);
        maxY = math.max(maxY, y);
        count += 1;
        sumL += lum[current];

        for (final direction in directions) {
          final next = current + direction;
          if (next < 0 || next >= total) continue;
          if (((next % width) - x).abs() > 1) continue;
          if (mask[next] == 1 && visited[next] == 0) {
            visited[next] = 1;
            queue.add(next);
          }
        }
      }

      final boxWidth = maxX - minX + 1;
      final boxHeight = maxY - minY + 1;
      final area = boxWidth * boxHeight;
      final meanL = sumL / count;
      final contrast = getRingContrast(minX, minY, maxX, maxY, meanL);

      if (isBright) {
        if (count >= 4 &&
            area <= 220 &&
            boxWidth <= 22 &&
            boxHeight <= 22 &&
            contrast > 20) {
          final score = 0.5 +
              math.min(0.35, contrast / 110) -
              circularityPenalty(boxWidth, boxHeight);
          if (score >= 0.52) {
            addCandidate(minX, minY, boxWidth, boxHeight, score);
          }
        }
      } else {
        final ringContrast = contrast * -1;
        if (count >= 8 &&
            area <= 340 &&
            boxWidth <= 30 &&
            boxHeight <= 30 &&
            ringContrast > 24) {
          final score = 0.47 +
              math.min(0.35, ringContrast / 120) -
              circularityPenalty(boxWidth, boxHeight);
          if (score >= 0.5) {
            addCandidate(minX, minY, boxWidth, boxHeight, score);
          }
        }
      }
    }
  }

  visitComponents(bright, visitedBright, true);
  visitComponents(dark, visitedDark, false);
  final result = boxes.values.toList()
    ..sort((a, b) => b.score.compareTo(a.score));
  return result.take(8).toList();
}

class SafeLensApp extends StatelessWidget {
  const SafeLensApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      debugShowCheckedModeBanner: false,
      title: 'SafeLens',
      theme: ThemeData(
        useMaterial3: true,
        colorScheme: ColorScheme.fromSeed(seedColor: const Color(0xff1d6fff)),
      ),
      home: const SafeLensHome(),
    );
  }
}

class SafeLensHome extends StatefulWidget {
  const SafeLensHome({super.key});

  @override
  State<SafeLensHome> createState() => _SafeLensHomeState();
}

class _SafeLensHomeState extends State<SafeLensHome> {
  final _picker = ImagePicker();
  final _timeController = TextEditingController();
  final _placeController = TextEditingController();
  final _descController = TextEditingController();
  final _reportController = TextEditingController();
  int _tab = 0;
  ui.Image? _previewImage;
  img.Image? _analysisImage;
  List<SuspiciousBox> _boxes = [];
  CameraController? _cameraController;
  Timer? _scanTimer;
  bool _cameraOn = false;
  bool _torchOn = false;
  List<SuspiciousBox> _liveBoxes = [];
  Size? _liveImageSize;

  @override
  void dispose() {
    _scanTimer?.cancel();
    _cameraController?.dispose();
    _timeController.dispose();
    _placeController.dispose();
    _descController.dispose();
    _reportController.dispose();
    super.dispose();
  }

  Future<void> _pickImage() async {
    final file = await _picker.pickImage(source: ImageSource.gallery);
    if (file == null) return;
    final bytes = await file.readAsBytes();
    final decoded = img.decodeImage(bytes);
    if (decoded == null) return;
    final resized =
        decoded.width > 900 ? img.copyResize(decoded, width: 900) : decoded;
    final codec = await ui
        .instantiateImageCodec(Uint8List.fromList(img.encodePng(resized)));
    final frame = await codec.getNextFrame();
    setState(() {
      _analysisImage = resized;
      _previewImage = frame.image;
      _boxes = [];
    });
  }

  void _analyzeImage() {
    final image = _analysisImage;
    if (image == null) return;
    setState(() => _boxes = detectSuspiciousSpots(image));
  }

  Future<void> _startCamera() async {
    try {
      final cameras = await availableCameras();
      final camera = cameras.firstWhere(
        (item) => item.lensDirection == CameraLensDirection.back,
        orElse: () => cameras.first,
      );
      final controller =
          CameraController(camera, ResolutionPreset.medium, enableAudio: false);
      await controller.initialize();
      setState(() {
        _cameraController = controller;
        _cameraOn = true;
      });
      _scanTimer = Timer.periodic(
          const Duration(milliseconds: 700), (_) => _scanCameraFrame());
    } catch (_) {
      _showMessage('카메라 접근 권한이 필요합니다.');
    }
  }

  Future<void> _scanCameraFrame() async {
    final controller = _cameraController;
    if (controller == null ||
        !controller.value.isInitialized ||
        controller.value.isTakingPicture) {
      return;
    }
    try {
      final picture = await controller.takePicture();
      final bytes = await File(picture.path).readAsBytes();
      final decoded = img.decodeImage(bytes);
      if (decoded == null || !mounted) return;
      final resized =
          decoded.width > 900 ? img.copyResize(decoded, width: 900) : decoded;
      setState(() {
        _liveBoxes = detectSuspiciousSpots(resized);
        _liveImageSize =
            Size(resized.width.toDouble(), resized.height.toDouble());
      });
    } catch (_) {}
  }

  Future<void> _stopCamera() async {
    _scanTimer?.cancel();
    _scanTimer = null;
    await _cameraController?.dispose();
    setState(() {
      _cameraController = null;
      _cameraOn = false;
      _torchOn = false;
      _liveBoxes = [];
      _liveImageSize = null;
    });
  }

  Future<void> _toggleFlash() async {
    final controller = _cameraController;
    if (controller == null) return;
    try {
      final next = !_torchOn;
      await controller.setFlashMode(next ? FlashMode.torch : FlashMode.off);
      setState(() => _torchOn = next);
    } catch (_) {
      _showMessage('이 기기는 플래시 제어를 지원하지 않습니다.');
    }
  }

  void _buildReport() {
    _reportController.text = [
      '[몰래카메라 의심 신고 보조 문안]',
      '1. 발견 일시: ${_timeController.text.isEmpty ? "(미입력)" : _timeController.text}',
      '2. 장소: ${_placeController.text.isEmpty ? "(미입력)" : _placeController.text}',
      '3. 의심 정황:',
      _descController.text.isEmpty ? '(미입력)' : _descController.text,
      '4. 앱 분석 안내:',
      '- AI 분석은 의심 지점을 제시했으나 확정 판정은 아님',
      '- 렌즈 반사 확인 모드로 현장 추가 확인 진행',
    ].join('\n');
  }

  Future<void> _saveReport() async {
    if (_reportController.text.trim().isEmpty) {
      _showMessage('먼저 신고 문안을 생성해주세요.');
      return;
    }
    final dir = await getApplicationDocumentsDirectory();
    await File('${dir.path}/safelens_report.txt')
        .writeAsString(_reportController.text);
    _showMessage('safelens_report.txt로 저장했습니다.');
  }

  Future<void> _call112() async {
    final uri = Uri.parse('tel:112');
    if (await canLaunchUrl(uri)) {
      await launchUrl(uri);
    }
  }

  void _showMessage(String message) {
    if (mounted) {
      ScaffoldMessenger.of(context)
          .showSnackBar(SnackBar(content: Text(message)));
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: Container(
        decoration: const BoxDecoration(
          gradient: LinearGradient(
            begin: Alignment.topLeft,
            end: Alignment.bottomRight,
            colors: [Color(0xff070b17), Color(0xff0f1b39)],
          ),
        ),
        child: SafeArea(
          child: Center(
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 520),
              child: Column(
                children: [
                  const _SafeLensBar(),
                  Expanded(
                    child: SingleChildScrollView(
                      padding: const EdgeInsets.all(12),
                      child: IndexedStack(
                          index: _tab,
                          children: [_analysisTab(), _scanTab(), _reportTab()]),
                    ),
                  ),
                  _BottomTabs(
                      selected: _tab,
                      onChanged: (value) => setState(() => _tab = value)),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }

  Widget _analysisTab() {
    return _Panel(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const _SectionTitle('의심 장소 분석'),
          SizedBox(
              width: double.infinity,
              child: OutlinedButton(
                  onPressed: _pickImage, child: const Text('이미지 선택'))),
          const SizedBox(height: 12),
          Row(
            children: [
              Expanded(
                  child: FilledButton(
                      onPressed: _analysisImage == null ? null : _analyzeImage,
                      child: const Text('AI 분석'))),
              const SizedBox(width: 8),
              Expanded(
                  child: OutlinedButton(
                      onPressed: _analysisImage == null
                          ? null
                          : () => setState(() => _boxes = []),
                      child: const Text('초기화'))),
            ],
          ),
          const SizedBox(height: 12),
          _ImagePreview(image: _previewImage, boxes: _boxes),
          const SizedBox(height: 10),
          Text(_boxes.isEmpty
              ? '의심 지점이 없거나 식별되지 않았습니다.'
              : '의심 지점 ${_boxes.length}개가 표시되었습니다.'),
          for (var i = 0; i < _boxes.length; i += 1)
            Text('#${i + 1} 좌표 (${_boxes[i].x}, ${_boxes[i].y})'),
        ],
      ),
    );
  }

  Widget _scanTab() {
    final controller = _cameraController;
    return _Panel(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const _SectionTitle('렌즈 반사 확인'),
          Row(
            children: [
              Expanded(
                  child: FilledButton(
                      onPressed: _cameraOn ? null : _startCamera,
                      child: const Text('시작'))),
              const SizedBox(width: 8),
              Expanded(
                  child: OutlinedButton(
                      onPressed: _cameraOn ? _stopCamera : null,
                      child: const Text('중지'))),
              const SizedBox(width: 8),
              Expanded(
                  child: FilledButton.tonal(
                      onPressed: _cameraOn ? _toggleFlash : null,
                      child: Text(_torchOn ? '플래시 끄기' : '플래시'))),
            ],
          ),
          const SizedBox(height: 12),
          AspectRatio(
            aspectRatio: controller?.value.aspectRatio ?? 4 / 3,
            child: _PreviewFrame(
              child: controller == null || !controller.value.isInitialized
                  ? const Center(child: Text('카메라 대기 중'))
                  : Stack(fit: StackFit.expand, children: [
                      CameraPreview(controller),
                      CustomPaint(
                          painter: BoxPainter(_liveBoxes, _liveImageSize))
                    ]),
            ),
          ),
        ],
      ),
    );
  }

  Widget _reportTab() {
    return _Panel(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const _SectionTitle('신고 보조'),
          _Field(controller: _timeController, hint: '발견 일시'),
          _Field(controller: _placeController, hint: '장소'),
          _Field(controller: _descController, hint: '의심 정황', lines: 4),
          Row(
            children: [
              Expanded(
                  child: FilledButton(
                      onPressed: _buildReport, child: const Text('문안 생성'))),
              const SizedBox(width: 8),
              Expanded(
                  child: OutlinedButton(
                      onPressed: _saveReport, child: const Text('저장'))),
              const SizedBox(width: 8),
              Expanded(
                  child: FilledButton(
                      style: FilledButton.styleFrom(
                          backgroundColor: const Color(0xffdc3545)),
                      onPressed: _call112,
                      child: const Text('112'))),
            ],
          ),
          const SizedBox(height: 12),
          _Field(
              controller: _reportController,
              hint: '신고 문안',
              lines: 9,
              readOnly: true),
        ],
      ),
    );
  }
}

class _SafeLensBar extends StatelessWidget {
  const _SafeLensBar();

  @override
  Widget build(BuildContext context) {
    return Container(
      height: 72,
      padding: const EdgeInsets.symmetric(horizontal: 16),
      color: const Color(0xee081025),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Row(children: [
            ClipRRect(
                borderRadius: BorderRadius.circular(8),
                child:
                    Image.asset('public/app-icon.png', width: 30, height: 30)),
            const SizedBox(width: 10),
            const Text('SafeLens',
                style: TextStyle(
                    color: Color(0xffeef4ff), fontWeight: FontWeight.w700)),
          ]),
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 5),
            decoration: BoxDecoration(
                color: const Color(0x3312d8fa),
                border: Border.all(color: const Color(0x7312d8fa)),
                borderRadius: BorderRadius.circular(999)),
            child: const Text('Private Scan',
                style: TextStyle(color: Color(0xffeef4ff), fontSize: 12)),
          ),
        ],
      ),
    );
  }
}

class _BottomTabs extends StatelessWidget {
  const _BottomTabs({required this.selected, required this.onChanged});
  final int selected;
  final ValueChanged<int> onChanged;

  @override
  Widget build(BuildContext context) {
    return Container(
      height: 78,
      padding: const EdgeInsets.fromLTRB(16, 10, 16, 10),
      color: const Color(0xee081025),
      child: Row(children: [
        _TabButton(
            label: '⌕', active: selected == 0, onTap: () => onChanged(0)),
        const SizedBox(width: 14),
        _TabButton(
            label: '◉', active: selected == 1, onTap: () => onChanged(1)),
        const SizedBox(width: 14),
        _TabButton(
            label: '🚨', active: selected == 2, onTap: () => onChanged(2)),
      ]),
    );
  }
}

class _TabButton extends StatelessWidget {
  const _TabButton(
      {required this.label, required this.active, required this.onTap});
  final String label;
  final bool active;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return Expanded(
      child: SizedBox(
        height: 46,
        child: DecoratedBox(
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(14),
            gradient: active
                ? const LinearGradient(
                    colors: [Color(0xff1d6fff), Color(0xff00b6ff)])
                : null,
            color: active ? null : Colors.white.withValues(alpha: 0.08),
          ),
          child: InkWell(
            borderRadius: BorderRadius.circular(14),
            onTap: onTap,
            child: Center(
                child: Text(label,
                    style: TextStyle(
                        fontSize: 22,
                        color:
                            active ? Colors.white : const Color(0xffbed2ff)))),
          ),
        ),
      ),
    );
  }
}

class _Panel extends StatelessWidget {
  const _Panel({required this.child});
  final Widget child;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: const Color(0xe0f5f8ff),
        border: Border.all(color: const Color(0x6baabfde)),
        borderRadius: BorderRadius.circular(22),
        boxShadow: const [
          BoxShadow(
              color: Color(0x3d08193d), blurRadius: 34, offset: Offset(0, 14))
        ],
      ),
      child: child,
    );
  }
}

class _SectionTitle extends StatelessWidget {
  const _SectionTitle(this.text);
  final String text;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 10),
      child: Text(text,
          style: const TextStyle(fontSize: 17, fontWeight: FontWeight.w700)),
    );
  }
}

class _Field extends StatelessWidget {
  const _Field(
      {required this.controller,
      required this.hint,
      this.lines = 1,
      this.readOnly = false});
  final TextEditingController controller;
  final String hint;
  final int lines;
  final bool readOnly;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: TextField(
        controller: controller,
        minLines: lines,
        maxLines: lines,
        readOnly: readOnly,
        decoration: InputDecoration(
            filled: true,
            fillColor: Colors.white,
            hintText: hint,
            border:
                OutlineInputBorder(borderRadius: BorderRadius.circular(12))),
      ),
    );
  }
}

class _PreviewFrame extends StatelessWidget {
  const _PreviewFrame({required this.child});
  final Widget child;

  @override
  Widget build(BuildContext context) {
    return DecoratedBox(
      decoration: BoxDecoration(
          color: const Color(0xffeef4ff),
          border: Border.all(color: const Color(0xffb9c9e2)),
          borderRadius: BorderRadius.circular(16)),
      child: ClipRRect(borderRadius: BorderRadius.circular(16), child: child),
    );
  }
}

class _ImagePreview extends StatelessWidget {
  const _ImagePreview({required this.image, required this.boxes});
  final ui.Image? image;
  final List<SuspiciousBox> boxes;

  @override
  Widget build(BuildContext context) {
    final current = image;
    return _PreviewFrame(
      child: AspectRatio(
        aspectRatio: current == null ? 4 / 3 : current.width / current.height,
        child: current == null
            ? const Center(child: Text('이미지 대기 중'))
            : CustomPaint(painter: ImageBoxPainter(current, boxes)),
      ),
    );
  }
}

class ImageBoxPainter extends CustomPainter {
  const ImageBoxPainter(this.image, this.boxes);
  final ui.Image image;
  final List<SuspiciousBox> boxes;

  @override
  void paint(Canvas canvas, Size size) {
    canvas.drawImageRect(
        image,
        Rect.fromLTWH(0, 0, image.width.toDouble(), image.height.toDouble()),
        Rect.fromLTWH(0, 0, size.width, size.height),
        Paint());
    BoxPainter(boxes, Size(image.width.toDouble(), image.height.toDouble()))
        .paint(canvas, size);
  }

  @override
  bool shouldRepaint(covariant ImageBoxPainter oldDelegate) =>
      image != oldDelegate.image || boxes != oldDelegate.boxes;
}

class BoxPainter extends CustomPainter {
  const BoxPainter(this.boxes, this.sourceSize);
  final List<SuspiciousBox> boxes;
  final Size? sourceSize;

  @override
  void paint(Canvas canvas, Size size) {
    final source = sourceSize;
    if (source == null || source.width == 0 || source.height == 0) return;
    final sx = size.width / source.width;
    final sy = size.height / source.height;
    final stroke = Paint()
      ..color = const Color(0xfffacc15)
      ..style = PaintingStyle.stroke
      ..strokeWidth = 2;
    final labelBg = Paint()..color = const Color(0xffbe123c);

    for (var i = 0; i < boxes.length; i += 1) {
      final box = boxes[i];
      final rect =
          Rect.fromLTWH(box.x * sx, box.y * sy, box.w * sx, box.h * sy);
      canvas.drawRect(rect, stroke);
      final textPainter = TextPainter(
        text: TextSpan(
            text: '의심 ${i + 1}',
            style: const TextStyle(color: Colors.white, fontSize: 12)),
        textDirection: TextDirection.ltr,
      )..layout();
      final top = math.max(0.0, rect.top - 18);
      canvas.drawRect(
          Rect.fromLTWH(rect.left, top, textPainter.width + 8, 18), labelBg);
      textPainter.paint(canvas, Offset(rect.left + 4, top + 2));
    }
  }

  @override
  bool shouldRepaint(covariant BoxPainter oldDelegate) =>
      boxes != oldDelegate.boxes || sourceSize != oldDelegate.sourceSize;
}
