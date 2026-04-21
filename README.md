# CareShare 2026

Flutter + Firebase app for care coordination.

## Prerequisites

- Flutter SDK 3.41+
- Firebase CLI (`firebase-tools`)
- FlutterFire CLI (`flutterfire_cli`)
- A Firebase project (`careshare-2026`)

## Local Setup

1. Install dependencies:

```bash
flutter pub get
```

2. Generate Firebase config:

```bash
flutterfire configure --project=careshare-2026 --platforms=android,ios,web,windows,macos,linux --android-package-name=com.careshare.app --ios-bundle-id=com.careshare.app --macos-bundle-id=com.careshare.app
```

3. Deploy security rules:

```bash
firebase deploy --only firestore:rules,storage
```

## Run

Run on web:

```bash
flutter run -d chrome
```

Run on Windows desktop:

```bash
flutter run -d windows
```

## Firebase Files

- Firestore rules: `firebase/firestore.rules`
- Storage rules: `firebase/storage.rules`
- Firebase config: `lib/firebase_options.dart`

## Repository

GitHub: [chrisfoulkes1965/careshare_2026](https://github.com/chrisfoulkes1965/careshare_2026)
