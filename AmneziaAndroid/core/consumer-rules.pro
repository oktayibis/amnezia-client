# kotlinx.serialization — keep generated serializers for models in this module
-keepattributes *Annotation*, InnerClasses
-keepclassmembers class kotlinx.serialization.json.** { *** Companion; }
-keepclasseswithmembers class kotlinx.serialization.json.** { kotlinx.serialization.KSerializer serializer(...); }
-keep,includedescriptorclasses class org.amnezia.core.**$$serializer { *; }
-keepclassmembers class org.amnezia.core.** { *** Companion; }
-keepclasseswithmembers class org.amnezia.core.** { kotlinx.serialization.KSerializer serializer(...); }

# AmneziaWG NDK / JNI keep rules
-dontwarn javax.annotation.**
-keep class org.amnezia.awg.** { *; }
-keepclasseswithmembernames class * {
    native <methods>;
}
