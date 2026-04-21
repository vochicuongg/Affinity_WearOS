# Flutter wrapper
-keep class io.flutter.app.** { *; }
-keep class io.flutter.plugin.**  { *; }
-keep class io.flutter.util.**  { *; }
-keep class io.flutter.view.**  { *; }
-keep class io.flutter.**  { *; }
-keep class io.flutter.plugins.**  { *; }

# Wear OS missing classes referenced by flutterwear plugin
-dontwarn com.google.android.wearable.compat.**
-keep class com.google.android.wearable.compat.** { *; }

# General missing classes warning suppression for release
-dontwarn androidx.**
-dontwarn android.support.**
-dontwarn com.google.android.play.core.**
