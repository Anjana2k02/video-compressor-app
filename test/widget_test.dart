import 'package:compressor/main.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  testWidgets('shows the lightweight optimizer home screen', (tester) async {
    await tester.pumpWidget(const VideoOptimizerApp());

    expect(find.text('StoryFit'), findsOneWidget);
    expect(find.text('Light video optimizer'), findsOneWidget);
    expect(find.text('Instagram Story'), findsOneWidget);
    expect(find.text('WhatsApp Status'), findsOneWidget);
  });
}
