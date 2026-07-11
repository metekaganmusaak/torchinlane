import 'package:test/test.dart';
import 'package:torchinlane/src/project/flutter_project.dart';

void main() {
  group('ProjectVersion.parse', () {
    test('parses valid version string', () {
      final v = ProjectVersion.parse('1.0.16+57');
      expect(v.major, 1);
      expect(v.minor, 0);
      expect(v.patch, 16);
      expect(v.build, 57);
      expect(v.toString(), '1.0.16+57');
    });

    test('throws on malformed version', () {
      expect(() => ProjectVersion.parse('1.0.16'), throwsFormatException);
      expect(() => ProjectVersion.parse('not-a-version'), throwsFormatException);
    });
  });
}
