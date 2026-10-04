import 'package:flutter_test/flutter_test.dart';
import 'package:test_capture/core/models.dart';

void main() {
  test('item survives a JSON round trip', () {
    final it = CaptureItem(
      id: newId(),
      title: 'Shop button',
      note: 'Tap does nothing',
      priority: Priority.high,
      project: 'GameX',
      tags: ['ui'],
      media: [MediaFile(fileName: '01_shot.png', kind: MediaKind.image, size: 10)],
    );
    final back = CaptureItem.fromJson(it.toJson());
    expect(back.title, 'Shop button');
    expect(back.priority, Priority.high);
    expect(back.media.single.fileName, '01_shot.png');
  });

  test('media kind and safe names', () {
    expect(mediaKindFor('clip.MP4'), MediaKind.video);
    expect(mediaKindFor('shot.png'), MediaKind.image);
    expect(safeFileName('../evil name.png'), '.._evil_name.png');
  });
}
