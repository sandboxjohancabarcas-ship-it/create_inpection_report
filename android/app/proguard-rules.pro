# Disable the most aggressive R8 actions
-dontobfuscate
-dontoptimize

# Preserve your MainActivity and all its members
-keep class com.cabarcas.wartungstool.MainActivity { *; }

# Preserve Flutter and its embedding classes
-keep class io.flutter.app.** { *; }
-keep class io.flutter.plugin.** { *; }
-keep class io.flutter.util.** { *; }
-keep class io.flutter.view.** { *; }
-keep class io.flutter.embedding.** { *; }

# Preserve AppCompat if you are using it
-keep class androidx.appcompat.** { *; }

# Flutter's Play Store Split support (deferred components) references Play Core classes which are not always present.
-dontwarn com.google.android.play.core.**