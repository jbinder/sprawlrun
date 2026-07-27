# Google Play Services is deliberately excluded from the build — see the
# `com.google.android.gms` exclusion in build.gradle.kts.
#
# geolocator_android is still *compiled* against it, so its bytecode carries
# references to classes that are no longer on the runtime classpath. R8 treats
# missing classes as errors, so it has to be told these absences are intended.
#
# Nothing here weakens shrinking of code that actually ships: the referencing
# code paths (FusedLocationClient and the availability probe) are unreachable
# because forceLocationManager is set.
-dontwarn com.google.android.gms.**
-dontwarn com.google.android.play.core.**
