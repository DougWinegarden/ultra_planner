# Ocean Lists (ultra_planner)

A Flutter task planner with lists, a year/month/day calendar, and **Quackers** —
a Gemini-powered assistant in a duck suit that can also change your planner:
"move everything after 5 PM to tomorrow", "give me two hours Saturday for my
game project", "what's overdue?". Its changes show up as a card you can apply,
trim or undo.

Finishing tasks earns XP, which fills an ocean-themed XP bar, levels you up to
100, grows a tree on your profile, and ranks you on a leaderboard. Level 100
takes about three months of daily tasks; after that you can prestige for a
badge. Usernames are picked from vetted word lists, never typed. See "XP,
levels and the leaderboard" in [SETUP.md](SETUP.md).

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

169 Dart tests covering the Firestore repository (against
`fake_cloud_firestore`), applying and undoing Quackers' changes, the chat sheet
end to end with a fake Quackers, levels and XP (checked against the server's
table at every level), the username lists, the tree at all 100 stages, the
profile and leaderboard pages, the login form (against `firebase_auth_mocks`),
the calendar and holidays, and the unconfigured-Firebase startup path. None of
them need a live Firebase project.

The functions have their own tests (`cd functions && npm test`, 84 cases
covering encryption, rate limits, every planner tool, the function-calling
loop against a scripted fake model, and the XP, cap, prestige and username
rules) which need no emulator or Gemini key.

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
  progress/
    leveling.dart                  level curve, task XP, badges (mirrors server)
    username_words.dart            the username word lists (mirrors server)
    player_profile.dart            PlayerProfile
    progress_repository.dart       profile + leaderboard reads, callables
    profile_page.dart              level, XP bar, tree, prestige, name
    leaderboard_page.dart          top players by lifetime XP
    username_picker.dart           pick-don't-type name dialog
  widgets/
    ocean_background.dart          animated background, capybara, painters
    change_proposal_card.dart      apply / cancel / undo card in the chat
    ocean_xp_bar.dart              water-filled XP bar + life-ring badge
    level_tree.dart                the tree that grows with your level
    player_badges.dart             initials avatar, prestige badges
functions/
  index.js                         save/status/delete key + askQuackers
  plannerTools.js                  Quackers' planner tools (pure, unit tested)
  toolLoop.js                      Gemini function-calling loop
  progress.js                      XP, levels, prestige, usernames (pure)
  usernameWords.json               the only words a username can use
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
