import 'package:flutter/material.dart';

enum DemoLanguage { zh, en }

DemoLanguage _activeLanguage = DemoLanguage.zh;

void setDemoLanguage(DemoLanguage language) => _activeLanguage = language;

String demoTr(String zh, String en) =>
    _activeLanguage == DemoLanguage.zh ? zh : en;

DemoLanguage detectSystemLanguage() {
  final code = WidgetsBinding.instance.platformDispatcher.locale.languageCode;
  return code.toLowerCase() == 'zh' ? DemoLanguage.zh : DemoLanguage.en;
}

class DemoI18n extends InheritedWidget {
  const DemoI18n({
    super.key,
    required this.language,
    required this.onToggleLanguage,
    required super.child,
  });

  final DemoLanguage language;
  final VoidCallback onToggleLanguage;

  static DemoI18n of(BuildContext context) {
    final result = context.dependOnInheritedWidgetOfExactType<DemoI18n>();
    assert(result != null, 'DemoI18n is missing from the widget tree');
    return result!;
  }

  @override
  bool updateShouldNotify(DemoI18n oldWidget) => language != oldWidget.language;
}

extension DemoI18nContext on BuildContext {
  DemoLanguage get language => DemoI18n.of(this).language;

  void toggleLanguage() => DemoI18n.of(this).onToggleLanguage();
}
