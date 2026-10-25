import 'package:flutter/material.dart';

/// Палитра цветов приложения для светлой и темной тем (Material 3 AI Workspace).
class AppColors {
  const AppColors._();

  // Акцентные цвета (Indigo / Violet AI Brand)
  static const Color primaryLight = Color(0xFF4F46E5);
  static const Color primaryDark = Color(0xFF818CF8);

  static const Color secondaryLight = Color(0xFF0EA5E9);
  static const Color secondaryDark = Color(0xFF38BDF8);

  // Поверхности (Light)
  static const Color backgroundLight = Color(0xFFF8FAFC);
  static const Color surfaceLight = Color(0xFFFFFFFF);
  static const Color sidebarLight = Color(0xFFF1F5F9);
  static const Color borderLight = Color(0xFFE2E8F0);

  // Поверхности (Dark)
  static const Color backgroundDark = Color(0xFF0B0F19);
  static const Color surfaceDark = Color(0xFF111827);
  static const Color sidebarDark = Color(0xFF1E293B);
  static const Color borderDark = Color(0xFF334155);

  // Семантические статусы
  static const Color success = Color(0xFF10B981);
  static const Color warning = Color(0xFFF59E0B);
  static const Color error = Color(0xFFEF4444);
}
