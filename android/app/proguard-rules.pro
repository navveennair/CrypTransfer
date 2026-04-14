# Flutter embedding — must be kept for plugin registration
-keep class io.flutter.app.** { *; }
-keep class io.flutter.plugin.** { *; }
-keep class io.flutter.util.** { *; }
-keep class io.flutter.view.** { *; }
-keep class io.flutter.** { *; }
-keep class io.flutter.plugins.** { *; }

# Firebase / Google Play Services
-keep class com.google.firebase.** { *; }
-keep class com.google.android.gms.** { *; }
-dontwarn com.google.android.gms.**

# PointyCastle / Bouncy Castle (used by pointycastle Dart plugin via JNI on some targets)
-keep class org.bouncycastle.** { *; }
-dontwarn org.bouncycastle.**

# Kotlin stdlib
-keep class kotlin.** { *; }
-dontwarn kotlin.**
-keepclassmembers class **$WhenMappings { <fields>; }

# Prevent stripping of serialisation-sensitive classes
-keepattributes *Annotation*
-keepattributes Signature
-keepattributes Exceptions
