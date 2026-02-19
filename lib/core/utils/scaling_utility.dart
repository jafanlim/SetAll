import 'package:flutter/material.dart';
import 'package:flutter_screenutil/flutter_screenutil.dart';

/// Base design size: iPhone 16 Pro (390×844).
/// All fonts, paddings, and radii scale proportionally across iPhone SE, Pro Max, and iPad.
class ScalingUtility {
  ScalingUtility._();

  static const double designWidth = 390.0;
  static const double designHeight = 844.0;

  /// Initialize in app (called from ScreenUtilInit). Use min for text scaling to avoid oversized text on tablets.
  static void init(BuildContext context) {
    ScreenUtil.init(
      context,
      designSize: const Size(designWidth, designHeight),
      minTextAdapt: true,
      splitScreenMode: true,
    );
  }

  // --- Scalable dimensions (setWidth/setSp; no setRadius in ScreenUtil 5, so radius uses setWidth) ---
  static double get spacingXs => ScreenUtil().setWidth(4.0);
  static double get spacingSm => ScreenUtil().setWidth(8.0);
  static double get spacingMd => ScreenUtil().setWidth(16.0);
  static double get spacingLg => ScreenUtil().setWidth(24.0);
  static double get spacingXl => ScreenUtil().setWidth(32.0);

  static double get radiusSm => ScreenUtil().setWidth(8.0);
  static double get radiusMd => ScreenUtil().setWidth(12.0);
  static double get radiusLg => ScreenUtil().setWidth(16.0);
  static double get radiusXl => ScreenUtil().setWidth(24.0);

  static double get fontSizeCaption => ScreenUtil().setSp(12.0);
  static double get fontSizeBody => ScreenUtil().setSp(14.0);
  static double get fontSizeBodyLg => ScreenUtil().setSp(16.0);
  static double get fontSizeTitle => ScreenUtil().setSp(18.0);
  static double get fontSizeTitleLg => ScreenUtil().setSp(20.0);
  static double get fontSizeHeadline => ScreenUtil().setSp(24.0);
  static double get fontSizeDisplay => ScreenUtil().setSp(32.0);
}
