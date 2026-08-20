# R8 / ProGuard rules for the MiDoctor Android app.
#
# The Flutter Gradle plugin already contributes rules for the engine and for
# plugins that ship consumer rules (firebase_*, google_sign_in, etc.). What
# follows covers the cases those do not, plus defensive keeps for reflection.

# ---------------------------------------------------------------------------
# Flutter engine
# ---------------------------------------------------------------------------
-keep class io.flutter.app.** { *; }
-keep class io.flutter.plugin.** { *; }
-keep class io.flutter.util.** { *; }
-keep class io.flutter.view.** { *; }
-keep class io.flutter.** { *; }
-keep class io.flutter.plugins.** { *; }

# ---------------------------------------------------------------------------
# Firebase / Google Play services
# Firebase model classes are instantiated reflectively from JSON.
# ---------------------------------------------------------------------------
-keep class com.google.firebase.** { *; }
-keep class com.google.android.gms.** { *; }
-dontwarn com.google.firebase.**
-dontwarn com.google.android.gms.**

# Keep the no-arg constructors Firebase needs to deserialize into model types.
-keepclassmembers class * {
    @com.google.firebase.database.PropertyName <methods>;
}

# ---------------------------------------------------------------------------
# Kotlin
# ---------------------------------------------------------------------------
-keep class kotlin.Metadata { *; }
-dontwarn kotlin.**

# ---------------------------------------------------------------------------
# Keep annotations and generic signatures so reflection-based JSON still works.
# ---------------------------------------------------------------------------
-keepattributes *Annotation*
-keepattributes Signature
-keepattributes InnerClasses
-keepattributes EnclosingMethod

# ---------------------------------------------------------------------------
# Strip logging from release builds. This is a PHI control, not an optimisation:
# it guarantees no clinical data reaches logcat on a shipped build.
# ---------------------------------------------------------------------------
-assumenosideeffects class android.util.Log {
    public static *** v(...);
    public static *** d(...);
    public static *** i(...);
    public static *** w(...);
    public static *** e(...);
}

# ---------------------------------------------------------------------------
# Keep line numbers for readable crash reports, but hide the original file name.
# ---------------------------------------------------------------------------
-keepattributes SourceFile,LineNumberTable
-renamesourcefileattribute SourceFile

# ---------------------------------------------------------------------------
# Play Core / deferred components.
#
# The Flutter engine ships PlayStoreDeferredComponentManager and
# FlutterPlayStoreSplitApplication, which reference com.google.android.play.core.*.
# This app does not use deferred components, so that library is not on the
# classpath and R8 fails with "Missing classes detected".
#
# -dontwarn (not -keep) is the correct fix: the classes are genuinely absent, so
# there is nothing to keep. The referencing code paths are never executed.
# ---------------------------------------------------------------------------
-dontwarn com.google.android.play.core.**
-keep class io.flutter.embedding.engine.deferredcomponents.** { *; }
