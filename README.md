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

**→ Follow [SETUP.md](SETUP.md).** It covers enabling
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

22 Dart tests covering the Firestore repository (against `fake_cloud_firestore`),
the login form (against `firebase_auth_mocks`), and the unconfigured-Firebase
startup path. None of them need a live Firebase project.

The function has its own tests (`cd functions && npm test`, 8 cases covering the
rate limit window logic) which need no emulator.

## Layout

```
lib/
  main.dart                        app bootstrap + planner UI
  firebase_options.dart            PLACEHOLDERS -- see SETUP.md
  gemini_quackers_service.dart     Gemini API client
  auth/
    auth_gate.dart                 setup notice / login / planner routing
    auth_service.dart              FirebaseAuth wrapper + error messages
    login_page.dart                combined login + signup screen
  data/
    models.dart                    TaskItem, TaskListData, DatedTask
    planner_repository.dart        lists + tasks CRUD and streams
  widgets/
    ocean_background.dart          animated background, capybara, painters
functions/
  index.js                         askQuackers -- the Gemini proxy
  rateLimit.js                     per-user throttle (pure, unit tested)
firestore.rules                    security rules -- must be deployed
```

## The Gemini key

There isn't one in the app. Quackers calls the `askQuackers` Cloud Function
(`functions/index.js`), which holds the key in Secret Manager and never sends it
to the client. The function requires a signed-in caller and rate limits per
account, since one key serves every user.

Deploying it needs the Blaze plan - see Part 5 of [SETUP.md](SETUP.md).
