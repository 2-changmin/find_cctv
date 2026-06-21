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
  const SuspiciousBox({
    required this.x,
    required this.y,
    required this.w,
    required this.h,
    required this.score,
  });

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
    for (var y = math.max(0, y0 - 2); y <= math.min(height - 1, y1 + 2); y += 1) {
      for (var x = math.max(0, x0 - 2); x <= math.min(width - 1, x1 + 2); x += 1) {
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
      boxes[key] = SuspiciousBox(x: x, y: y, w: boxWidth, h: boxHeight, score: score);
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
        if (count >= 4 && area <= 220 && boxWidth <= 22 && boxHeight <= 22 && contrast > 20) {
          final score = 0.5 + math.min(0.35, contrast / 110) - circularityPenalty(boxWidth, boxHeight);
          if (score >= 0.52) addCandidate(minX, minY, boxWidth, boxHeight, score);
        }
      } else {
        final ringContrast = contrast * -1;
        if (count >= 8 && area <= 340 && boxWidth <= 30 && boxHeight <= 30 && ringContrast > 24) {
          final score = 0.47 + math.min(0.35, ringContrast / 120) - circularityPenalty(boxWidth, boxHeight);
          if (score >= 0.5) addCandidate(minX, minY, boxWidth, boxHeight, score);
        }
      }
    }
  }

  visitComponents(bright, visitedBright, true);
  visitComponents(dark, visitedDark, false);
  final result = boxes.values.toList()..sort((a, b) => b.score.compareTo(a.score));
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
        colorScheme: ColorScheme.fromSeed(seedColor: const Color(0xff6f94d9)),
      ),
      home: const SafeLensHome(),
    );
  }
}

class _Palette {
  static const bgTop = Color(0xffdfe7f6);
  static const bgBottom = Color(0xffedf3f8);
  static const surface = Color(0xfff7f9fd);
  static const line = Color(0xffc8d3e4);
  static const text = Color(0xff26324b);
  static const subText = Color(0xff6d7890);
  static const chipBg = Color(0xffd8f0ee);
  static const primaryStart = Color(0xff8daee6);
  static const primaryEnd = Color(0xff88cfcc);
  static const danger = Color(0xffcf4550);
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
  List<SuspiciousBox> _liveBoxes = [];
  Size? _liveSourceSize;
  bool _cameraOn = false;
  bool _torchOn = false;
  bool _processingFrame = false;
  DateTime? _lastFrameScanAt;
  int _selectedHour = 0;
  int _selectedMinute = 0;

  @override
  void initState() {
    super.initState();
    final now = DateTime.now();
    _selectedHour = now.hour;
    _selectedMinute = (now.minute ~/ 5) * 5;
    _syncSelectedTimeToText();
  }

  @override
  void dispose() {
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
    final resized = decoded.width > 900 ? img.copyResize(decoded, width: 900) : decoded;
    final codec = await ui.instantiateImageCodec(Uint8List.fromList(img.encodePng(resized)));
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

  void _syncSelectedTimeToText() {
    final hour = _selectedHour.toString().padLeft(2, '0');
    final minute = _selectedMinute.toString().padLeft(2, '0');
    _timeController.text = '$hour:$minute';
  }

  void _onHourChanged(int? value) {
    if (value == null) return;
    setState(() {
      _selectedHour = value;
      if (_selectedHour == 24) {
        _selectedMinute = 0;
      }
      _syncSelectedTimeToText();
    });
  }

  void _onMinuteChanged(int? value) {
    if (value == null) return;
    setState(() {
      _selectedMinute = value;
      _syncSelectedTimeToText();
    });
  }

  Future<void> _startCamera() async {
    try {
      final cameras = await availableCameras();
      final camera = cameras.firstWhere(
        (item) => item.lensDirection == CameraLensDirection.back,
        orElse: () => cameras.first,
      );
      final controller = CameraController(camera, ResolutionPreset.medium, enableAudio: false);
      await controller.initialize();
      setState(() {
        _cameraController = controller;
        _cameraOn = true;
        _liveBoxes = [];
        _liveSourceSize = null;
        _processingFrame = false;
        _lastFrameScanAt = null;
      });
      try {
        await controller.startImageStream(_handleCameraImage);
      } catch (_) {
        _showMessage('실시간 의심 지점 표시는 현재 카메라에서 지원되지 않습니다.');
      }
    } catch (_) {
      _showMessage('카메라 권한 또는 장치 상태를 확인해주세요.');
    }
  }

  Future<void> _stopCamera() async {
    final controller = _cameraController;
    if (controller != null && controller.value.isStreamingImages) {
      await controller.stopImageStream();
    }
    await controller?.dispose();
    setState(() {
      _cameraController = null;
      _liveBoxes = [];
      _liveSourceSize = null;
      _processingFrame = false;
      _lastFrameScanAt = null;
      _cameraOn = false;
      _torchOn = false;
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
      _showMessage('현재 기기에서 플래시 제어를 지원하지 않습니다.');
    }
  }

  void _handleCameraImage(CameraImage frame) {
    final now = DateTime.now();
    final lastScan = _lastFrameScanAt;
    if (_processingFrame || (lastScan != null && now.difference(lastScan).inMilliseconds < 600)) {
      return;
    }
    _processingFrame = true;
    _lastFrameScanAt = now;

    try {
      final image = _cameraImageToAnalysisImage(frame);
      if (image == null) return;
      final nextBoxes = detectSuspiciousSpots(image);
      if (!mounted) return;
      setState(() {
        _liveBoxes = nextBoxes;
        _liveSourceSize = Size(image.width.toDouble(), image.height.toDouble());
      });
    } finally {
      _processingFrame = false;
    }
  }

  img.Image? _cameraImageToAnalysisImage(CameraImage frame) {
    return switch (frame.format.group) {
      ImageFormatGroup.yuv420 => _yPlaneToAnalysisImage(frame),
      ImageFormatGroup.bgra8888 => _bgraToAnalysisImage(frame),
      _ => null,
    };
  }

  img.Image _yPlaneToAnalysisImage(CameraImage frame) {
    final plane = frame.planes.first;
    final sampleStep = math.max(1, (frame.width / 360).ceil());
    final width = frame.width ~/ sampleStep;
    final height = frame.height ~/ sampleStep;
    final output = img.Image(width: width, height: height);

    for (var y = 0; y < height; y += 1) {
      final sourceY = y * sampleStep;
      for (var x = 0; x < width; x += 1) {
        final sourceX = x * sampleStep;
        final value = plane.bytes[sourceY * plane.bytesPerRow + sourceX];
        output.setPixelRgb(x, y, value, value, value);
      }
    }

    return output;
  }

  img.Image _bgraToAnalysisImage(CameraImage frame) {
    final plane = frame.planes.first;
    final bytesPerPixel = plane.bytesPerPixel ?? 4;
    final sampleStep = math.max(1, (frame.width / 360).ceil());
    final width = frame.width ~/ sampleStep;
    final height = frame.height ~/ sampleStep;
    final output = img.Image(width: width, height: height);

    for (var y = 0; y < height; y += 1) {
      final sourceY = y * sampleStep;
      for (var x = 0; x < width; x += 1) {
        final sourceX = x * sampleStep;
        final offset = sourceY * plane.bytesPerRow + sourceX * bytesPerPixel;
        final blue = plane.bytes[offset];
        final green = plane.bytes[offset + 1];
        final red = plane.bytes[offset + 2];
        output.setPixelRgb(x, y, red, green, blue);
      }
    }

    return output;
  }

  void _buildReport() {
    _reportController.text = [
      '[몰래카메라 의심 신고 보조 문안]',
      '1. 발견 시각: ${_timeController.text.isEmpty ? "(미입력)" : _timeController.text}',
      '2. 장소: ${_placeController.text.isEmpty ? "(미입력)" : _placeController.text}',
      '3. 의심 정황:',
      _descController.text.isEmpty ? '(미입력)' : _descController.text,
      '4. 참고 안내:',
      '- AI 분석은 의심 지점을 참고용으로 제시합니다.',
      '- 현장에서는 실시간 스캔 탭에서 렌즈 반사를 직접 확인하세요.',
    ].join('\n');
  }

  Future<void> _saveReport() async {
    if (_reportController.text.trim().isEmpty) {
      _showMessage('먼저 신고 문안을 생성해주세요.');
      return;
    }
    final dir = await getApplicationDocumentsDirectory();
    await File('${dir.path}/safelens_report.txt').writeAsString(_reportController.text);
    _showMessage('safelens_report.txt 파일로 저장했습니다.');
  }

  Future<void> _call112() async {
    final uri = Uri.parse('tel:112');
    if (await canLaunchUrl(uri)) {
      await launchUrl(uri);
    }
  }

  Future<void> _sendSmsReport() async {
    final reportText = _reportController.text.trim();
    if (reportText.isEmpty) {
      _showMessage('먼저 문안 생성 버튼으로 신고 내용을 준비해주세요.');
      return;
    }

    final approved = await showDialog<bool>(
      context: context,
      builder: (dialogContext) {
        return AlertDialog(
          title: const Text('문자 신고 확인'),
          content: const Text(
            '작성한 내용으로 112 문자 신고를 진행합니다.\n\n'
            '허위 신고 또는 장난 신고는 처벌 대상이 될 수 있습니다.\n'
            '내용이 사실에 기반한 신고인지 다시 확인해주세요.',
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.of(dialogContext).pop(false),
              child: const Text('취소'),
            ),
            FilledButton(
              onPressed: () => Navigator.of(dialogContext).pop(true),
              child: const Text('확인 후 진행'),
            ),
          ],
        );
      },
    );

    if (approved != true) return;

    final uri = Uri(
      scheme: 'sms',
      path: '112',
      queryParameters: {'body': reportText},
    );

    if (await canLaunchUrl(uri)) {
      await launchUrl(uri);
    } else {
      _showMessage('문자 앱을 열 수 없습니다. 기기 설정을 확인해주세요.');
    }
  }

  void _openHelpPage() {
    Navigator.of(context).push(
      MaterialPageRoute(builder: (_) => const _HelpPage()),
    );
  }

  void _showMessage(String message) {
    if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(message)));
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.transparent,
      body: Container(
        decoration: const BoxDecoration(
          gradient: LinearGradient(
            begin: Alignment.topLeft,
            end: Alignment.bottomRight,
            colors: [_Palette.bgTop, _Palette.bgBottom],
          ),
        ),
        child: SafeArea(
          child: Column(
            children: [
              const _TopHeader(),
              Expanded(
                child: SingleChildScrollView(
                  padding: const EdgeInsets.fromLTRB(16, 14, 16, 16),
                  child: ConstrainedBox(
                    constraints: const BoxConstraints(maxWidth: 560),
                    child: _tab == 0
                        ? _homeTab()
                        : _tab == 1
                            ? _analysisTab()
                            : _tab == 2
                                ? _scanTab()
                                : _reportTab(),
                  ),
                ),
              ),
              _BottomTabs(selected: _tab, onChanged: (value) => setState(() => _tab = value)),
            ],
          ),
        ),
      ),
    );
  }

  Widget _homeTab() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Container(
          width: 138,
          height: 138,
          padding: const EdgeInsets.all(18),
          decoration: BoxDecoration(
            color: Colors.white.withValues(alpha: 0.55),
            borderRadius: BorderRadius.circular(28),
            boxShadow: const [BoxShadow(color: Color(0x14000000), blurRadius: 16, offset: Offset(0, 8))],
          ),
          child: Image.asset('public/app-icon.png'),
        ),
        const SizedBox(height: 20),
        const Text(
          'SafeLens',
          style: TextStyle(fontSize: 68 / 1.8, fontWeight: FontWeight.w800, color: _Palette.text),
        ),
        const SizedBox(height: 8),
        const Text(
          '사진 분석과 실시간 반사 확인으로 의심 후보를 빠르게 표시합니다.',
          style: TextStyle(fontSize: 18, color: _Palette.subText, height: 1.35),
        ),
        const SizedBox(height: 22),
        _HomeLinkCard(
          icon: Icons.search,
          title: '사진 분석',
          status: _boxes.isEmpty ? '탐지 전' : '탐지 ${_boxes.length}건',
          onTap: () => setState(() => _tab = 1),
          highlighted: true,
        ),
        const SizedBox(height: 12),
        _HomeLinkCard(
          icon: Icons.radio_button_checked,
          title: '실시간 스캔',
          status: _cameraOn ? (_torchOn ? '플래시 켜짐' : '준비됨') : '탐지 전',
          onTap: () => setState(() => _tab = 2),
        ),
        const SizedBox(height: 12),
        _HomeLinkCard(
          icon: Icons.priority_high,
          title: '신고 보조',
          status: _reportController.text.trim().isEmpty ? '문안 생성' : '문안 준비됨',
          onTap: () => setState(() => _tab = 3),
        ),
        const SizedBox(height: 12),
        _HomeLinkCard(
          icon: Icons.volunteer_activism_outlined,
          title: '도움 받기',
          status: '대처 안내',
          onTap: _openHelpPage,
        ),
        const SizedBox(height: 12),
        Container(
          width: double.infinity,
          padding: const EdgeInsets.all(16),
          decoration: BoxDecoration(
            color: Colors.white.withValues(alpha: 0.5),
            borderRadius: BorderRadius.circular(20),
            border: Border.all(color: _Palette.line),
          ),
          child: const Text(
            '앱 결과는 확정 판정이 아니라 신고와 현장 확인을 돕는 참고 정보입니다.',
            style: TextStyle(color: _Palette.subText, fontSize: 16, height: 1.4),
          ),
        ),
      ],
    );
  }

  Widget _analysisTab() {
    return _Panel(
      title: '의심 장소 분석',
      status: _boxes.isEmpty ? '탐지 전' : '탐지 ${_boxes.length}건',
      child: Column(
        children: [
          Row(
            children: [
              Expanded(
                child: _ActionButton(
                  label: '사진 선택',
                  filled: true,
                  onTap: _pickImage,
                ),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: _ActionButton(
                  label: '초기화',
                  onTap: _analysisImage == null ? null : () => setState(() => _boxes = []),
                ),
              ),
            ],
          ),
          const SizedBox(height: 10),
          Row(
            children: [
              Expanded(
                child: _ActionButton(
                  label: '분석',
                  compact: true,
                  filled: true,
                  onTap: _analysisImage == null ? null : _analyzeImage,
                ),
              ),
            ],
          ),
          const SizedBox(height: 12),
          _ImagePreview(image: _previewImage, boxes: _boxes),
          const SizedBox(height: 10),
          Align(
            alignment: Alignment.centerLeft,
            child: Text(
              _boxes.isEmpty ? '사진을 선택한 뒤 분석을 실행하세요.' : '의심 지점 좌표를 확인해 현장 스캔으로 이동하세요.',
              style: const TextStyle(color: _Palette.subText, fontSize: 16),
            ),
          ),
          const SizedBox(height: 8),
          DecoratedBox(
            decoration: BoxDecoration(
              border: Border.all(color: _Palette.line),
              borderRadius: BorderRadius.circular(18),
            ),
            child: SizedBox(
              width: double.infinity,
              child: Padding(
                padding: const EdgeInsets.all(12),
                child: Text(
                  _boxes.isEmpty
                      ? '분석 결과가 여기에 표시됩니다.'
                      : _boxes.asMap().entries.map((e) => '#${e.key + 1} (${e.value.x}, ${e.value.y})').join('  /  '),
                  style: const TextStyle(color: _Palette.subText, fontSize: 16),
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _scanTab() {
    final controller = _cameraController;
    return _Panel(
      title: '실시간 반사 확인',
      status: _cameraOn ? (_torchOn ? '플래시 켜짐' : '카메라 켜짐') : '대기 중',
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text(
            '플래시 반사 후보를 실시간으로 표시합니다. 표시된 지점은 확정 판정이 아니라 확인용 참고 정보입니다.',
            style: TextStyle(color: _Palette.subText, fontSize: 16),
          ),
          const SizedBox(height: 12),
          Row(
            children: [
              Expanded(
                child: _ActionButton(label: '시작', filled: true, onTap: _cameraOn ? null : _startCamera),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: _ActionButton(label: '중지', onTap: _cameraOn ? _stopCamera : null),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: _ActionButton(
                  label: _torchOn ? '플래시 끄기' : '플래시',
                  filled: _torchOn,
                  onTap: _cameraOn ? _toggleFlash : null,
                ),
              ),
            ],
          ),
          const SizedBox(height: 12),
          AspectRatio(
            aspectRatio: controller?.value.aspectRatio ?? 4 / 3,
            child: _PreviewFrame(
              child: controller == null || !controller.value.isInitialized
                  ? const Center(child: Text('카메라 시작 후 이곳에서 반사 확인'))
                  : Stack(
                      fit: StackFit.expand,
                      children: [
                        CameraPreview(controller),
                        CustomPaint(painter: BoxPainter(_liveBoxes, _liveSourceSize)),
                      ],
                    ),
            ),
          ),
          const SizedBox(height: 10),
          Text(
            _cameraOn
                ? (_liveBoxes.isEmpty ? '현재 표시할 의심 후보가 없습니다.' : '실시간 의심 후보 ${_liveBoxes.length}개 표시 중')
                : '카메라를 시작하면 실시간 후보가 화면에 표시됩니다.',
            style: const TextStyle(color: _Palette.subText, fontSize: 15),
          ),
        ],
      ),
    );
  }

  Widget _reportTab() {
    return _Panel(
      title: '신고 보조',
      status: '문안 생성',
      child: Column(
        children: [
          _TimeSelector(
            selectedHour: _selectedHour,
            selectedMinute: _selectedMinute,
            onHourChanged: _onHourChanged,
            onMinuteChanged: _selectedHour == 24 ? null : _onMinuteChanged,
          ),
          _Field(controller: _placeController, hint: '현재 위치 또는 장소'),
          _Field(controller: _descController, hint: '의심 정황', lines: 4),
          Row(
            children: [
              Expanded(
                child: _ActionButton(label: '문안 생성', filled: true, onTap: _buildReport),
              ),
              const SizedBox(width: 8),
              Expanded(
                child: _ActionButton(label: '저장', onTap: _saveReport),
              ),
              const SizedBox(width: 8),
              Expanded(
                child: _ActionButton(label: '문자 신고', onTap: _sendSmsReport),
              ),
              const SizedBox(width: 8),
              Expanded(
                child: SizedBox(
                  height: 54,
                  child: FilledButton(
                    style: FilledButton.styleFrom(
                      backgroundColor: _Palette.danger,
                      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(18)),
                    ),
                    onPressed: _call112,
                    child: const Text('112', style: TextStyle(fontSize: 18, fontWeight: FontWeight.w700)),
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 8),
          const Align(
            alignment: Alignment.centerLeft,
            child: Text(
              '문안 생성 후 문자 신고 또는 112 전화 신고를 선택할 수 있습니다.',
              style: TextStyle(color: _Palette.subText, fontSize: 14),
            ),
          ),
          const SizedBox(height: 8),
          SizedBox(
            width: double.infinity,
            child: _ActionButton(label: '피해 대처 안내 보기', onTap: _openHelpPage),
          ),
          const SizedBox(height: 10),
          _Field(controller: _reportController, hint: '신고 문안', lines: 10, readOnly: true),
        ],
      ),
    );
  }
}

class _TopHeader extends StatelessWidget {
  const _TopHeader();

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.fromLTRB(16, 14, 16, 14),
      color: Colors.white.withValues(alpha: 0.6),
      child: Row(
        children: [
          Container(
            width: 52,
            height: 52,
            decoration: BoxDecoration(
              color: Colors.white,
              borderRadius: BorderRadius.circular(14),
              boxShadow: const [BoxShadow(color: Color(0x22000000), blurRadius: 8, offset: Offset(0, 2))],
            ),
            child: Padding(
              padding: const EdgeInsets.all(6),
              child: Image.asset('public/app-icon.png'),
            ),
          ),
          const SizedBox(width: 12),
          const Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text('SafeLens', style: TextStyle(fontSize: 42 / 1.8, fontWeight: FontWeight.w800, color: _Palette.text)),
                SizedBox(height: 2),
                Text('몰래카메라 의심 위치 탐지 보조', style: TextStyle(fontSize: 16, color: _Palette.subText)),
              ],
            ),
          ),
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 12),
            decoration: BoxDecoration(
              color: _Palette.chipBg,
              borderRadius: BorderRadius.circular(999),
              border: Border.all(color: const Color(0xffa6d8d7), width: 1.6),
            ),
            child: const Text('Private', style: TextStyle(fontSize: 18, color: Color(0xff3f6579))),
          ),
        ],
      ),
    );
  }
}

class _HelpPage extends StatelessWidget {
  const _HelpPage();

  static const _d4uUrl = 'https://d4u.stop.or.kr/main';
  static const _regionUrl = 'https://d4u.stop.or.kr/about/region/info';

  Future<void> _openUrl(String url) async {
    final uri = Uri.parse(url);
    final opened = await launchUrl(uri, mode: LaunchMode.externalApplication);
    if (!opened) {
      await launchUrl(uri);
    }
  }

  Future<void> _call(String phone) async {
    final uri = Uri.parse('tel:$phone');
    if (await canLaunchUrl(uri)) {
      await launchUrl(uri);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.transparent,
      body: Container(
        decoration: const BoxDecoration(
          gradient: LinearGradient(
            begin: Alignment.topLeft,
            end: Alignment.bottomRight,
            colors: [_Palette.bgTop, _Palette.bgBottom],
          ),
        ),
        child: SafeArea(
          child: Column(
            children: [
              const _TopHeader(),
              Expanded(
                child: SingleChildScrollView(
                  padding: const EdgeInsets.fromLTRB(16, 14, 16, 20),
                  child: ConstrainedBox(
                    constraints: const BoxConstraints(maxWidth: 560),
                    child: _Panel(
                      title: '도움 받기',
                      status: '대처 안내',
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          const Text(
                            '불안하거나 피해가 의심될 때 바로 확인할 수 있는 대응 순서입니다.',
                            style: TextStyle(color: _Palette.subText, fontSize: 16, height: 1.4),
                          ),
                          const SizedBox(height: 12),
                          _HelpSection(
                            icon: Icons.emergency_outlined,
                            title: '지금 바로 할 일',
                            items: const [
                              '긴급하거나 위험하면 즉시 112로 신고합니다.',
                              '가능하면 안전한 장소로 이동하고 주변에 도움을 요청합니다.',
                              '가해자와 직접 대면하거나 혼자 삭제를 요구하지 않습니다.',
                            ],
                            actions: [
                              _HelpAction(label: '112 전화', onTap: () => _call('112'), danger: true),
                              _HelpAction(label: '1366 전화', onTap: () => _call('1366')),
                            ],
                          ),
                          _HelpSection(
                            icon: Icons.inventory_2_outlined,
                            title: '증거 보존',
                            items: const [
                              '게시물 URL, 계정명, 업로드 시각, 캡처 화면을 보관합니다.',
                              '가능하면 원본 파일과 화면 녹화도 따로 보관합니다.',
                              '신고나 삭제 요청 전 증거가 사라지지 않도록 먼저 정리합니다.',
                              '불법촬영물을 불필요하게 재전송하거나 공유하지 않습니다.',
                            ],
                          ),
                          _HelpSection(
                            icon: Icons.account_balance_outlined,
                            title: '공공 지원',
                            items: const [
                              '중앙디지털성범죄피해자지원센터에서 상담, 삭제지원, 모니터링, 수사·법률·의료 연계를 받을 수 있습니다.',
                              '여성긴급전화 1366은 365일 24시간 초기 상담을 지원합니다.',
                              '지역 디지털성범죄피해자지원센터도 상담과 삭제 연계를 제공합니다.',
                            ],
                            actions: [
                              _HelpAction(label: '센터 열기', onTap: () => _openUrl(_d4uUrl)),
                              _HelpAction(label: '지역 센터', onTap: () => _openUrl(_regionUrl)),
                            ],
                          ),
                          _HelpSection(
                            icon: Icons.cleaning_services_outlined,
                            title: '삭제 지원',
                            items: const [
                              '우선 공공기관의 삭제지원과 모니터링을 확인합니다.',
                              '민간 삭제 대행 서비스는 비용, 환불 조건, 삭제 가능 범위, 개인정보 제공 범위를 확인해야 합니다.',
                              '앱에서는 이런 서비스를 디지털 장의사 또는 온라인 게시물 삭제 대행으로 안내할 수 있습니다.',
                            ],
                          ),
                          _HelpSection(
                            icon: Icons.favorite_border,
                            title: '법률·심리 지원',
                            items: const [
                              '수사 진행, 법률 상담, 의료 지원, 심리 상담을 함께 요청할 수 있습니다.',
                              '혼자 판단하기 어렵다면 상담기관을 통해 필요한 기관으로 연계받는 방식이 안전합니다.',
                            ],
                          ),
                        ],
                      ),
                    ),
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

class _BottomTabs extends StatelessWidget {
  const _BottomTabs({required this.selected, required this.onChanged});

  final int selected;
  final ValueChanged<int> onChanged;

  @override
  Widget build(BuildContext context) {
    final items = <({IconData icon, String label})>[
      (icon: Icons.home_outlined, label: '홈'),
      (icon: Icons.search, label: '분석'),
      (icon: Icons.radio_button_checked, label: '스캔'),
      (icon: Icons.priority_high, label: '신고'),
    ];

    return Container(
      padding: const EdgeInsets.fromLTRB(12, 10, 12, 16),
      decoration: BoxDecoration(
        color: Colors.white.withValues(alpha: 0.75),
        border: const Border(top: BorderSide(color: Color(0xffd5deeb))),
      ),
      child: Row(
        children: List.generate(items.length, (index) {
          final item = items[index];
          final active = selected == index;
          return Expanded(
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 4),
              child: InkWell(
                borderRadius: BorderRadius.circular(22),
                onTap: () => onChanged(index),
                child: Ink(
                  height: 92,
                  decoration: BoxDecoration(
                    borderRadius: BorderRadius.circular(22),
                    color: active ? null : const Color(0xffeef2f8),
                    gradient: active
                        ? const LinearGradient(colors: [_Palette.primaryStart, _Palette.primaryEnd])
                        : null,
                  ),
                  child: Column(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      Icon(item.icon, size: 28, color: const Color(0xff4f5e7b)),
                      const SizedBox(height: 6),
                      Text(
                        item.label,
                        style: const TextStyle(fontSize: 18, fontWeight: FontWeight.w700, color: Color(0xff4f5e7b)),
                      ),
                    ],
                  ),
                ),
              ),
            ),
          );
        }),
      ),
    );
  }
}

class _HomeLinkCard extends StatelessWidget {
  const _HomeLinkCard({
    required this.icon,
    required this.title,
    required this.status,
    required this.onTap,
    this.highlighted = false,
  });

  final IconData icon;
  final String title;
  final String status;
  final VoidCallback onTap;
  final bool highlighted;

  @override
  Widget build(BuildContext context) {
    return Material(
      color: Colors.transparent,
      child: InkWell(
        borderRadius: BorderRadius.circular(24),
        onTap: onTap,
        child: Ink(
          padding: const EdgeInsets.all(14),
          decoration: BoxDecoration(
            color: Colors.white.withValues(alpha: 0.72),
            borderRadius: BorderRadius.circular(24),
            border: Border.all(
              color: highlighted ? const Color(0xffadc2ea) : _Palette.line,
              width: 1.6,
            ),
          ),
          child: Row(
            children: [
              Container(
                width: 74,
                height: 74,
                decoration: BoxDecoration(
                  gradient: const LinearGradient(colors: [_Palette.primaryStart, _Palette.primaryEnd]),
                  borderRadius: BorderRadius.circular(22),
                ),
                child: Icon(icon, size: 36, color: const Color(0xff2f3b58)),
              ),
              const SizedBox(width: 14),
              Expanded(
                child: Text(
                  title,
                  style: const TextStyle(fontSize: 22, fontWeight: FontWeight.w800, color: _Palette.text),
                ),
              ),
              Text(
                status,
                style: const TextStyle(fontSize: 19, color: _Palette.subText, fontWeight: FontWeight.w700),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _Panel extends StatelessWidget {
  const _Panel({required this.title, required this.status, required this.child});

  final String title;
  final String status;
  final Widget child;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: _Palette.surface,
        borderRadius: BorderRadius.circular(28),
        border: Border.all(color: _Palette.line, width: 1.4),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Expanded(
                child: Text(
                  title,
                  style: const TextStyle(fontSize: 24, fontWeight: FontWeight.w800, color: _Palette.text),
                ),
              ),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
                decoration: BoxDecoration(
                  border: Border.all(color: _Palette.line, width: 1.4),
                  borderRadius: BorderRadius.circular(999),
                ),
                child: Text(
                  status,
                  style: const TextStyle(fontSize: 14, color: _Palette.subText, fontWeight: FontWeight.w700),
                ),
              ),
            ],
          ),
          const SizedBox(height: 14),
          child,
        ],
      ),
    );
  }
}

class _HelpSection extends StatelessWidget {
  const _HelpSection({
    required this.icon,
    required this.title,
    required this.items,
    this.actions = const [],
  });

  final IconData icon;
  final String title;
  final List<String> items;
  final List<_HelpAction> actions;

  @override
  Widget build(BuildContext context) {
    return Container(
      margin: const EdgeInsets.only(bottom: 12),
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: Colors.white.withValues(alpha: 0.62),
        borderRadius: BorderRadius.circular(18),
        border: Border.all(color: _Palette.line),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Container(
                width: 42,
                height: 42,
                decoration: BoxDecoration(
                  gradient: const LinearGradient(colors: [_Palette.primaryStart, _Palette.primaryEnd]),
                  borderRadius: BorderRadius.circular(14),
                ),
                child: Icon(icon, color: _Palette.text),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: Text(
                  title,
                  style: const TextStyle(fontSize: 19, fontWeight: FontWeight.w800, color: _Palette.text),
                ),
              ),
            ],
          ),
          const SizedBox(height: 10),
          for (final item in items)
            Padding(
              padding: const EdgeInsets.only(bottom: 7),
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Padding(
                    padding: EdgeInsets.only(top: 8),
                    child: SizedBox(
                      width: 5,
                      height: 5,
                      child: DecoratedBox(
                        decoration: BoxDecoration(color: _Palette.subText, shape: BoxShape.circle),
                      ),
                    ),
                  ),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Text(
                      item,
                      style: const TextStyle(fontSize: 15, color: _Palette.subText, height: 1.35),
                    ),
                  ),
                ],
              ),
            ),
          if (actions.isNotEmpty) ...[
            const SizedBox(height: 6),
            Wrap(
              spacing: 8,
              runSpacing: 8,
              children: actions,
            ),
          ],
        ],
      ),
    );
  }
}

class _HelpAction extends StatelessWidget {
  const _HelpAction({
    required this.label,
    required this.onTap,
    this.danger = false,
  });

  final String label;
  final VoidCallback onTap;
  final bool danger;

  @override
  Widget build(BuildContext context) {
    return OutlinedButton(
      style: OutlinedButton.styleFrom(
        foregroundColor: danger ? _Palette.danger : _Palette.text,
        side: BorderSide(color: danger ? _Palette.danger : _Palette.line, width: 1.4),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
      ),
      onPressed: onTap,
      child: Text(label, style: const TextStyle(fontWeight: FontWeight.w700)),
    );
  }
}

class _ActionButton extends StatelessWidget {
  const _ActionButton({
    required this.label,
    required this.onTap,
    this.filled = false,
    this.compact = false,
  });

  final String label;
  final VoidCallback? onTap;
  final bool filled;
  final bool compact;

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      height: compact ? 48 : 54,
      child: FilledButton(
        style: FilledButton.styleFrom(
          backgroundColor: filled ? null : Colors.transparent,
          foregroundColor: filled ? _Palette.text : _Palette.subText,
          disabledBackgroundColor: const Color(0xffe5ebf5),
          disabledForegroundColor: const Color(0xff9ba8bd),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(18),
            side: BorderSide(color: filled ? Colors.transparent : _Palette.line, width: 1.5),
          ),
          elevation: 0,
          padding: EdgeInsets.zero,
        ).copyWith(
          backgroundColor: WidgetStateProperty.resolveWith((states) {
            if (states.contains(WidgetState.disabled)) return const Color(0xffe5ebf5);
            if (!filled) return Colors.transparent;
            return null;
          }),
        ),
        onPressed: onTap,
        child: Ink(
          decoration: filled
              ? BoxDecoration(
                  gradient: const LinearGradient(colors: [_Palette.primaryStart, _Palette.primaryEnd]),
                  borderRadius: BorderRadius.circular(18),
                )
              : null,
          child: Center(
            child: Text(label, style: const TextStyle(fontSize: 19, fontWeight: FontWeight.w700)),
          ),
        ),
      ),
    );
  }
}

class _TimeSelector extends StatelessWidget {
  const _TimeSelector({
    required this.selectedHour,
    required this.selectedMinute,
    required this.onHourChanged,
    required this.onMinuteChanged,
  });

  final int selectedHour;
  final int selectedMinute;
  final ValueChanged<int?> onHourChanged;
  final ValueChanged<int?>? onMinuteChanged;

  @override
  Widget build(BuildContext context) {
    final hours = List<int>.generate(25, (index) => index);
    final minutes = List<int>.generate(12, (index) => index * 5);
    final minuteDisabled = onMinuteChanged == null;

    return Padding(
      padding: const EdgeInsets.only(bottom: 10),
      child: Container(
        padding: const EdgeInsets.all(12),
        decoration: BoxDecoration(
          color: Colors.white.withValues(alpha: 0.72),
          borderRadius: BorderRadius.circular(16),
          border: Border.all(color: _Palette.line, width: 1.5),
        ),
        child: Row(
          children: [
            const Text('발견 시각', style: TextStyle(fontSize: 17, color: _Palette.subText)),
            const SizedBox(width: 12),
            Expanded(
              child: DropdownButtonFormField<int>(
                value: selectedHour,
                decoration: _timeInputDecoration('시'),
                items: hours
                    .map((hour) => DropdownMenuItem<int>(
                          value: hour,
                          child: Text(hour.toString().padLeft(2, '0')),
                        ))
                    .toList(),
                onChanged: onHourChanged,
              ),
            ),
            const SizedBox(width: 8),
            Expanded(
              child: DropdownButtonFormField<int>(
                value: minuteDisabled ? 0 : selectedMinute,
                decoration: _timeInputDecoration('분'),
                items: minutes
                    .map((minute) => DropdownMenuItem<int>(
                          value: minute,
                          child: Text(minute.toString().padLeft(2, '0')),
                        ))
                    .toList(),
                onChanged: onMinuteChanged,
              ),
            ),
            if (minuteDisabled) ...[
              const SizedBox(width: 8),
              const Text('(24시는 00분만)', style: TextStyle(fontSize: 12, color: _Palette.subText)),
            ],
          ],
        ),
      ),
    );
  }

  InputDecoration _timeInputDecoration(String suffixText) {
    return InputDecoration(
      isDense: true,
      contentPadding: const EdgeInsets.symmetric(horizontal: 10, vertical: 10),
      suffixText: suffixText,
      filled: true,
      fillColor: Colors.white,
      enabledBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(12),
        borderSide: const BorderSide(color: _Palette.line, width: 1.2),
      ),
      focusedBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(12),
        borderSide: const BorderSide(color: Color(0xff9fb8e8), width: 1.4),
      ),
    );
  }
}

class _Field extends StatelessWidget {
  const _Field({required this.controller, required this.hint, this.lines = 1, this.readOnly = false});

  final TextEditingController controller;
  final String hint;
  final int lines;
  final bool readOnly;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 10),
      child: TextField(
        controller: controller,
        minLines: lines,
        maxLines: lines,
        readOnly: readOnly,
        style: const TextStyle(fontSize: 17, color: _Palette.text),
        decoration: InputDecoration(
          filled: true,
          fillColor: Colors.white.withValues(alpha: 0.72),
          hintText: hint,
          hintStyle: const TextStyle(color: _Palette.subText),
          enabledBorder: OutlineInputBorder(
            borderRadius: BorderRadius.circular(16),
            borderSide: const BorderSide(color: _Palette.line, width: 1.5),
          ),
          focusedBorder: OutlineInputBorder(
            borderRadius: BorderRadius.circular(16),
            borderSide: const BorderSide(color: Color(0xff9fb8e8), width: 1.8),
          ),
        ),
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
        color: Colors.white.withValues(alpha: 0.75),
        border: Border.all(color: _Palette.line, width: 1.5),
        borderRadius: BorderRadius.circular(22),
      ),
      child: ClipRRect(borderRadius: BorderRadius.circular(22), child: child),
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
            ? const Center(
                child: Text('선택한 이미지가 여기에 표시됩니다.', style: TextStyle(color: _Palette.subText)),
              )
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
      Paint(),
    );
    BoxPainter(boxes, Size(image.width.toDouble(), image.height.toDouble())).paint(canvas, size);
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
      final rect = Rect.fromLTWH(box.x * sx, box.y * sy, box.w * sx, box.h * sy);
      canvas.drawRect(rect, stroke);

      final textPainter = TextPainter(
        text: TextSpan(
          text: '의심 ${i + 1}',
          style: const TextStyle(color: Colors.white, fontSize: 12),
        ),
        textDirection: TextDirection.ltr,
      )..layout();

      final top = math.max(0.0, rect.top - 18);
      canvas.drawRect(Rect.fromLTWH(rect.left, top, textPainter.width + 8, 18), labelBg);
      textPainter.paint(canvas, Offset(rect.left + 4, top + 2));
    }
  }

  @override
  bool shouldRepaint(covariant BoxPainter oldDelegate) =>
      boxes != oldDelegate.boxes || sourceSize != oldDelegate.sourceSize;
}
