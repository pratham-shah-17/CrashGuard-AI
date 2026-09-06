# ─── Flutter engine ──────────────────────────────────────────────────────────
-keep class io.flutter.** { *; }
-keep class io.flutter.embedding.** { *; }
-keep class io.flutter.plugin.** { *; }
-keep class io.flutter.util.** { *; }
-keep class io.flutter.view.** { *; }

# ─── Play Core / deferred components ─────────────────────────────────────────
# Flutter's FlutterPlayStoreSplitApplication references Play Core classes for
# dynamic feature delivery.  This project uses --split-per-abi (build-time ABI
# splits), NOT Play Store dynamic delivery, so these classes are never reached
# at runtime.  Suppress R8 "Missing class" errors without adding the full
# play-core dependency.
-dontwarn com.google.android.play.core.**
-keep class com.google.android.play.core.splitcompat.** { *; }
-keep class com.google.android.play.core.splitinstall.** { *; }
-keep class com.google.android.play.core.tasks.** { *; }

# ─── Annotation-processor internals (shaded into runtime classpath) ───────────
# Some transitive dependencies (AutoValue, javapoet) shade annotation-processor
# classes into their JARs. These are compile-time only; suppress R8 errors.
-dontwarn javax.lang.model.**
-dontwarn javax.annotation.processing.**
-dontwarn autovalue.shaded.**
-dontwarn com.google.auto.value.**

# ─── Dart/Flutter JNI bridge ─────────────────────────────────────────────────
-keepclassmembers class * {
    native <methods>;
}
-keepattributes *Annotation*
-keepattributes Signature
-keepattributes SourceFile,LineNumberTable

# ─── Firebase ─────────────────────────────────────────────────────────────────
-keep class com.google.firebase.** { *; }
-keep class com.google.android.gms.** { *; }
-dontwarn com.google.firebase.**
-dontwarn com.google.android.gms.**

# ─── OkHttp / Okio (used by supabase_flutter, powersync) ────────────────────
-dontwarn okhttp3.**
-dontwarn okio.**
-keep class okhttp3.** { *; }
-keep class okio.** { *; }

# ─── Kotlin ──────────────────────────────────────────────────────────────────
-dontwarn kotlin.**
-keep class kotlin.** { *; }
-keep class kotlin.Metadata { *; }
-keepclassmembers class **$WhenMappings { <fields>; }
-keepclassmembers class kotlin.Lazy { *; }

# ─── Kotlinx coroutines ──────────────────────────────────────────────────────
-dontwarn kotlinx.coroutines.**
-keepnames class kotlinx.coroutines.internal.MainDispatcherFactory {}
-keepnames class kotlinx.coroutines.CoroutineExceptionHandler {}

# ─── PowerSync / SQLite ──────────────────────────────────────────────────────
-keep class com.powersync.** { *; }
-dontwarn com.powersync.**

# ─── ObjectBox (flutter_map_tile_caching backend) ────────────────────────────
-keep class io.objectbox.** { *; }
-dontwarn io.objectbox.**

# ─── flutter_background_service ──────────────────────────────────────────────
-keep class id.flutter.flutter_background_service.** { *; }

# ─── flutter_blue_plus / BLE ─────────────────────────────────────────────────
-keep class com.pauldemarco.flutter_blue.** { *; }
-dontwarn com.pauldemarco.flutter_blue.**

# ─── permission_handler ──────────────────────────────────────────────────────
-keep class com.baseflow.permissionhandler.** { *; }

# ─── MediaPipe / LiteRT (flutter_gemma) ──────────────────────────────────────
-keep class com.google.mediapipe.** { *; }
-keep class com.google.ai.edge.** { *; }
-dontwarn com.google.mediapipe.**
-dontwarn com.google.ai.edge.**

# ─── Gson (keep type-token generics for Supabase JSON deserialisation) ────────
-keepattributes EnclosingMethod
-keep class * implements com.google.gson.TypeAdapterFactory
-keep class * implements com.google.gson.JsonSerializer
-keep class * implements com.google.gson.JsonDeserializer

# ─── Prevent stripping enum values ───────────────────────────────────────────
-keepclassmembers enum * { *; }

# ─── Crash reporter / stack trace symbolication ──────────────────────────────
# (Dart symbols are stripped by --obfuscate + --split-debug-info, not R8.
#  These rules keep the Java/Kotlin side readable if you use Firebase Crashlytics.)
-keepattributes SourceFile,LineNumberTable
-renamesourcefileattribute SourceFile
