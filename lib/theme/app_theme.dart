import 'package:flutter/material.dart';
import 'app_colors.dart';

class AppTheme {
  static ThemeData lightTheme = ThemeData(
    useMaterial3: true,

    scaffoldBackgroundColor: AppColors.white,

    primaryColor: AppColors.primary,

    colorScheme: const ColorScheme.light(
      primary: AppColors.primary,
      secondary: AppColors.primaryDark,
      surface: AppColors.white,
      error: AppColors.error,
    ),

    appBarTheme: const AppBarTheme(
      backgroundColor: AppColors.white,
      foregroundColor: AppColors.darkBrown,
      elevation: 0,
      centerTitle: false,
      titleTextStyle: TextStyle(
        color: AppColors.darkBrown,
        fontSize: 22,
        fontWeight: FontWeight.bold,
      ),
    ),

    textTheme: const TextTheme(
      displayLarge: TextStyle(
        color: AppColors.darkBrown,
        fontWeight: FontWeight.bold,
      ),
      displayMedium: TextStyle(
        color: AppColors.darkBrown,
        fontWeight: FontWeight.bold,
      ),
      titleLarge: TextStyle(
        color: AppColors.darkBrown,
        fontWeight: FontWeight.bold,
      ),
      bodyLarge: TextStyle(
        color: AppColors.darkBrown,
      ),
      bodyMedium: TextStyle(
        color: AppColors.grey,
      ),
    ),

    elevatedButtonTheme:
    ElevatedButtonThemeData(
      style: ElevatedButton.styleFrom(
        backgroundColor:
        AppColors.primary,
        foregroundColor:
        AppColors.white,
        elevation: 0,
        shape:
        RoundedRectangleBorder(
          borderRadius:
          BorderRadius.circular(
              16),
        ),
        padding:
        const EdgeInsets.symmetric(
          horizontal: 20,
          vertical: 15,
        ),
      ),
    ),

    outlinedButtonTheme:
    OutlinedButtonThemeData(
      style: OutlinedButton.styleFrom(
        foregroundColor:
        AppColors.primaryDark,
        side: const BorderSide(
          color: AppColors.primaryDark,
          width: 0.5,
        ),
        shape:
        RoundedRectangleBorder(
          borderRadius:
          BorderRadius.circular(
              16),
        ),
      ),
    ),

    inputDecorationTheme:
    InputDecorationTheme(
      filled: true,
      fillColor: AppColors.primary,

      hintStyle: const TextStyle(
        color: AppColors.grey,
      ),

      labelStyle: const TextStyle(
        color: AppColors.white,
      ),

      border:
      OutlineInputBorder(
        borderRadius:
        BorderRadius.circular(
            14),
        borderSide:
        BorderSide.none,
      ),

      enabledBorder:
      OutlineInputBorder(
        borderRadius:
        BorderRadius.circular(
            14),
        borderSide:
        BorderSide.none,
      ),

      focusedBorder:
      OutlineInputBorder(
        borderRadius:
        BorderRadius.circular(
            14),
        borderSide:
        const BorderSide(
          color:
          AppColors.primary,
          width: 2,
        ),
      ),

    ),

    cardTheme: CardThemeData(
      color: AppColors.white,
      elevation: 5,
      shadowColor:
      Colors.black12,
      shape:
      RoundedRectangleBorder(
        borderRadius:
        BorderRadius.circular(
            25),
      ),
    ),

    bottomNavigationBarTheme:
    const BottomNavigationBarThemeData(
      backgroundColor:
      AppColors.white,
      selectedItemColor:
      AppColors.primary,
      unselectedItemColor:
      AppColors.darkBrown,
      type:
      BottomNavigationBarType.fixed,
      elevation: 0,
    ),

  );
}