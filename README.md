# Ocean Lists (ultra_planner)

A Flutter task planner with lists, a year/month/day calendar, and **Quackers** —
a Gemini-powered assistant in a duck suit that can also change your planner:
"move everything after 5 PM to tomorrow", "give me two hours Saturday for my
game project", "what's overdue?". Its changes show up as a card you can apply,
trim or undo.

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

132 Dart tests covering the Firestore repository (against
`fake_cloud_firestore`), applying and undoing Quackers' changes, the chat sheet
end to end with a fake Quackers, the login form (against `firebase_auth_mocks`),
the calendar and holidays, and the unconfigured-Firebase startup path. None of
them need a live Firebase project.

The functions have their own tests (`cd functions && npm test`, 58 cases
covering encryption, rate limits, every planner tool, and the function-calling
loop against a scripted fake model) which need no emulator or Gemini key.

## Layout

```
lib/
  main.dart                        app bootstrap + planner UI
  firebase_options.dart            PLACEHOLDERS -- see SETUP.md
  gemini_quackers_service.dart     askQuackers client + reply parsing
  auth/
    auth_gate.dart                 setup notice / login / planner routing
    auth_service.dart              FirebaseAuth wrapper + error messages
    login_page.dart                combined login + signup screen
  data/
    models.dart                    TaskItem, TaskListData, DatedTask
    planner_repository.dart        lists + tasks CRUD, streams, apply/undo
    task_changes.dart              Quackers' proposed changes + snapshot
    task_time.dart                 date/time wire and display formats
  widgets/
    ocean_background.dart          animated background, capybara, painters
    change_proposal_card.dart      apply / cancel / undo card in the chat
functions/
  index.js                         save/status/delete key + askQuackers
  plannerTools.js                  Quackers' planner tools (pure, unit tested)
  toolLoop.js                      Gemini function-calling loop
  crypto.js                        AES-256-GCM envelope encryption
  rateLimit.js                     per-user throttle (pure, unit tested)
firestore.rules                    security rules -- must be deployed
```

## The Gemini key

Each user brings their own. It is sent once to the `saveGeminiKey` Cloud
Function, encrypted with AES-256-GCM under a master key in Secret Manager, and
stored as ciphertext -- so it is not readable in the Firestore console and is
never sent back to the app. `askQuackers` decrypts it server-side for the
duration of one Gemini call.

A project owner who can read the master secret can still decrypt stored keys;
that is unavoidable for a proxy. See "How the key is protected" in
[SETUP.md](SETUP.md).

Deploying the functions needs the Blaze plan.
