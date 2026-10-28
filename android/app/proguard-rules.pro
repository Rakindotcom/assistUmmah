# Firebase discovers these registrar classes through AndroidManifest metadata and
# invokes their public no-argument constructors reflectively. Keep the
# constructors when R8 optimizes the signed release build.
-keep class * implements com.google.firebase.components.ComponentRegistrar {
    public <init>();
}
