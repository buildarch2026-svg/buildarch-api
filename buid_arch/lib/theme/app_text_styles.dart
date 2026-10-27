import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';

import 'app_colors.dart';

/// Typography from DESIGN.md. Letter spacing is converted from em to px.
class AppTextStyles {
  AppTextStyles._();

  // Brand wordmark / card title use Poppins (as in the login design).
  static TextStyle brandTitle = GoogleFonts.poppins(
    fontSize: 30,
    fontWeight: FontWeight.w700,
    height: 1.25,
    letterSpacing: 30 * 0.16,
    color: AppColors.surface,
  );

  static TextStyle cardTitle = GoogleFonts.poppins(
    fontSize: 22,
    fontWeight: FontWeight.w700,
    height: 1.25,
    color: AppColors.onSurface,
  );

  // Epilogue (headings)
  static TextStyle headlineSm = GoogleFonts.epilogue(
    fontSize: 18,
    fontWeight: FontWeight.w600,
    height: 24 / 18,
    color: AppColors.onSurface,
  );

  // Inter (UI + body)
  static TextStyle titleMd = GoogleFonts.inter(
    fontSize: 16,
    fontWeight: FontWeight.w600,
    height: 22 / 16,
    color: AppColors.onSurface,
  );

  static TextStyle bodyMd = GoogleFonts.inter(
    fontSize: 14,
    fontWeight: FontWeight.w400,
    height: 20 / 14,
    letterSpacing: 14 * 0.01,
    color: AppColors.onSurface,
  );

  static TextStyle bodySm = GoogleFonts.inter(
    fontSize: 12,
    fontWeight: FontWeight.w400,
    height: 16 / 12,
    letterSpacing: 12 * 0.02,
    color: AppColors.onSurface,
  );

  static TextStyle labelTechnical = GoogleFonts.inter(
    fontSize: 10,
    fontWeight: FontWeight.w500,
    height: 12 / 10,
    letterSpacing: 10 * 0.08,
    color: AppColors.outline,
  );
}
