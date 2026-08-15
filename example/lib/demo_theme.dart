import 'package:flutter/material.dart';

abstract final class DemoColors {
  static const background = Color(0xFFF4F7F5);
  static const primary = Color(0xFF0C9B6C);
  static const text = Color(0xFF18221E);
  static const secondaryText = Color(0xFF8A948F);
  static const divider = Color(0xFFEDF0EE);
  static const danger = Color(0xFFD84B4B);
}

ThemeData buildDemoTheme() {
  final scheme = ColorScheme.fromSeed(
    seedColor: DemoColors.primary,
    brightness: Brightness.light,
    surface: Colors.white,
  );
  return ThemeData(
    colorScheme: scheme,
    useMaterial3: true,
    scaffoldBackgroundColor: DemoColors.background,
    dividerColor: DemoColors.divider,
    appBarTheme: const AppBarTheme(
      backgroundColor: DemoColors.background,
      foregroundColor: DemoColors.text,
      surfaceTintColor: Colors.transparent,
      elevation: 0,
    ),
    cardTheme: CardThemeData(
      color: Colors.white,
      surfaceTintColor: Colors.transparent,
      elevation: 0,
      margin: EdgeInsets.zero,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(18)),
    ),
    navigationBarTheme: const NavigationBarThemeData(
      backgroundColor: Colors.white,
      indicatorColor: Color(0x1A0C9B6C),
      labelTextStyle: WidgetStatePropertyAll(TextStyle(fontSize: 12)),
    ),
    inputDecorationTheme: InputDecorationTheme(
      filled: true,
      fillColor: Colors.white,
      border: OutlineInputBorder(
        borderRadius: BorderRadius.circular(16),
        borderSide: BorderSide.none,
      ),
      enabledBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(16),
        borderSide: BorderSide.none,
      ),
    ),
  );
}

class SectionHeading extends StatelessWidget {
  const SectionHeading(this.title, {super.key, this.caption, this.trailing});

  final String title;
  final String? caption;
  final Widget? trailing;

  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.fromLTRB(4, 26, 4, 12),
    child: Row(
      children: [
        Text(
          title,
          style: Theme.of(
            context,
          ).textTheme.titleMedium?.copyWith(fontWeight: FontWeight.w700),
        ),
        if (caption != null) ...[
          const SizedBox(width: 8),
          Expanded(
            child: Text(
              caption!,
              overflow: TextOverflow.ellipsis,
              style: Theme.of(
                context,
              ).textTheme.bodySmall?.copyWith(color: DemoColors.secondaryText),
            ),
          ),
        ] else
          const Spacer(),
        ?trailing,
      ],
    ),
  );
}

class DemoEmptyCard extends StatelessWidget {
  const DemoEmptyCard({
    super.key,
    required this.title,
    required this.message,
    this.action,
  });

  final String title;
  final String message;
  final Widget? action;

  @override
  Widget build(BuildContext context) => Card(
    child: Padding(
      padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 42),
      child: Column(
        children: [
          Text(title, style: const TextStyle(fontWeight: FontWeight.w700)),
          const SizedBox(height: 8),
          Text(
            message,
            textAlign: TextAlign.center,
            style: const TextStyle(color: DemoColors.secondaryText),
          ),
          if (action != null) ...[const SizedBox(height: 20), action!],
        ],
      ),
    ),
  );
}
