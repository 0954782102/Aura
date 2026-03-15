# 🎵 AURA Music Player — Flutter

**Засновник: Артем Процьків | Мова: Dart / Flutter**

Один проект → APK (Android) + IPA (iOS)

## Запуск

```bash
flutter pub get
flutter run
```

## Збірка

```bash
# Android APK
flutter build apk --release
# Файл: build/app/outputs/flutter-apk/app-release.apk

# Android App Bundle (Google Play)
flutter build appbundle --release

# iOS (тільки на Mac з Xcode)
flutter build ipa --release
```

## Файли в assets/

Скопіюй з Android проекту (`app/src/main/res/raw/`):
- `no_art_video.mp4`
- `scanning.gif`
- `loading_animation.gif`

## Мінімальні вимоги
- Android: 6.0+ (API 23)
- iOS: 12.0+
