import 'package:flutter_test/flutter_test.dart';
import 'package:image/image.dart' as img;
import 'package:safelens_app/main.dart';

void main() {
  test('detects a small bright reflection with surrounding contrast', () {
    final image = img.Image(width: 80, height: 80);
    img.fill(image, color: img.ColorRgb8(90, 90, 90));

    for (var y = 38; y <= 41; y += 1) {
      for (var x = 38; x <= 41; x += 1) {
        image.setPixelRgb(x, y, 255, 255, 255);
      }
    }

    final boxes = detectSuspiciousSpots(image);

    expect(boxes, isNotEmpty);
    expect(boxes.first.x, inInclusiveRange(38, 41));
    expect(boxes.first.y, inInclusiveRange(38, 41));
  });
}
