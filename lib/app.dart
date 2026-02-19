import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_screenutil/flutter_screenutil.dart';

import 'core/theme/setall_theme.dart';
import 'core/router/app_router.dart';
import 'core/providers/theme_mode_provider.dart';
import 'core/utils/scaling_utility.dart';

class SetAllApp extends ConsumerWidget {
  const SetAllApp({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final themeMode = ref.watch(themeModeProvider);

    return MaterialApp.router(
      title: 'SetAll',
      debugShowCheckedModeBanner: false,
      theme: SetAllTheme.light,
      darkTheme: SetAllTheme.dark,
      themeMode: themeMode,
      routerConfig: AppRouter.create(),
      builder: (context, child) {
        return ScreenUtilInit(
          designSize: const Size(ScalingUtility.designWidth, ScalingUtility.designHeight),
          minTextAdapt: true,
          splitScreenMode: true,
          builder: (_, _) {
            ScalingUtility.init(context);
            final theme = Theme.of(context);
            return Container(
              color: theme.colorScheme.surface,
              child: child ?? Center(
                child: CircularProgressIndicator(color: theme.colorScheme.primary),
              ),
            );
          },
        );
      },
    );
  }
}
