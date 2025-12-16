ChatBanglaPlus - Source-only Flutter project
===========================================

What you got:
- lib/main.dart  (full Flutter source, single-file app)
- pubspec.yaml
- assets/ (fonts, icons, splash placeholders)

Next steps to run on your Windows machine (VS Code):

1. Install Flutter SDK (latest stable) and set PATH.
   https://docs.flutter.dev/get-started/install/windows

2. Open a terminal in this project folder.

3. Run (this creates android/ios folders if missing):
   flutter create .

4. Get packages:
   flutter pub get

5. Run on connected device or emulator:
   flutter run

6. To build a universal release APK:
   flutter build apk --release --target-platform android-arm,android-arm64,android-x64

Notes:
- Replace the placeholder font in assets/fonts/NotoSansBengali-Regular.ttf with the real Noto Sans Bengali TTF for correct Bengali rendering.
- Replace placeholder icons in assets/icons/ and assets/splash/ with real PNGs if you want better visuals.
- The app stores the Gemini API key locally via Settings. Enter your key in Settings > API Key before using chat or PDF features.
- For iOS build you need macOS & Xcode. The `flutter create .` step will add necessary iOS files.
- Permissions (microphone, storage) will be requested at runtime.

Security:
- Do not commit your API key to public repos. Use server-side proxy for production use instead of embedding keys client-side.