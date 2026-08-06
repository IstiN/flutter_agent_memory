# MediaPipe / on-device LLM references optional classes that R8 cannot resolve.
# Keep the public API and suppress warnings for classes that are not bundled.
-dontwarn com.google.auto.value.extension.memoized.Memoized
-dontwarn com.google.mediapipe.proto.CalculatorProfileProto$CalculatorProfile
-dontwarn com.google.mediapipe.proto.GraphTemplateProto$CalculatorGraphTemplate
