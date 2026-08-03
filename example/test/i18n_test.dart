import 'package:flutter_test/flutter_test.dart';
import 'package:rwfit_ble_example/i18n.dart';

void main() {
  tearDown(() => setDemoLanguage(DemoLanguage.zh));

  test('returns Chinese text for Chinese language', () {
    setDemoLanguage(DemoLanguage.zh);

    expect(demoTr('扫描设备', 'Scan devices'), '扫描设备');
  });

  test('returns English text for English language', () {
    setDemoLanguage(DemoLanguage.en);

    expect(demoTr('扫描设备', 'Scan devices'), 'Scan devices');
  });
}
