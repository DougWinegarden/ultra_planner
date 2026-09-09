# Ocean Lists (ultra_planner)

A Flutter task planner with lists, a year/month/day calendar, and **Quackers** —
a Gemini-powered assistant in a duck suit.

Tasks are stored per-account in Cloud Firestore behind Firebase Authentication,
so they follow the user across devices.

## Before it will run

The app opens on a **"Firebase is not configured yet"** screen until real
credentials are filled in. `lib/firebase_options.dart` ships with placeholders
because `flutterfire configure` has to be run by the owner of the Firebase
project.

**→ Follow [FIREBASE_SETUP.md](FIREBASE_SETUP.md).** It covers enabling
email/password sign-in, generating credentials, deploying the security rules,
and the macOS network entitlement.

## Running

```bash
flutter pub get
flutter run -d macos
```

Other targets: `-d chrome`, `-d ios`. There is no `android/` folder yet; run
`flutter create --platforms=android .` to add one.

## Tests

```bash
flutter test
```

24 tests covering the Firestore repositories (against `fake_cloud_firestore`),
the login form (against `firebase_auth_mocks`), and the unconfigured-Firebase
startup path. None of them need a live Firebase project.

## Layout

```
lib/
  main.dart                        app bootstrap + planner UI
  firebase_options.dart            PLACEHOLDERS -- see FIREBASE_SETUP.md
  gemini_quackers_service.dart     Gemini API client
  auth/
    auth_gate.dart                 setup notice / login / planner routing
    auth_service.dart              FirebaseAuth wrapper + error messages
    login_page.dart                combined login + signup screen
  data/
    models.dart                    TaskItem, TaskListData, DatedTask
    planner_repository.dart        lists + tasks CRUD and streams
    user_settings_repository.dart  per-user Gemini API key
  widgets/
    ocean_background.dart          animated background, capybara, painters
firestore.rules                    security rules -- must be deployed
```

## The Gemini key

Entered once by the signed-in user (account menu → **Add Gemini API key**) and
saved to their Firestore settings document, so it is not re-entered on the next
launch or on another device. See the security note at the end of
FIREBASE_SETUP.md for what that does and does not protect.

The build-time `--dart-define=GEMINI_API_KEY=...` path still works as a fallback
when no key is saved to the account.
