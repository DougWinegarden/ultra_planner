# Ocean Lists — Setup Guide

Start to finish, assuming **nothing is installed yet**. Expect 30–60 minutes,
most of it downloads.

The app will not work until you finish **Part 3**. Until then it opens on a
"Firebase is not configured yet" screen. That is expected, not a bug.

**You need to be signed in to the Google account that owns the Firebase
project** — the same one where Firebase was originally set up.

---

## Which platform can you run on?

This project contains `ios/`, `macos/`, and `web/` folders only.

| Your computer | What you can run |
| --- | --- |
| **Mac** | macOS app, iOS simulator, and web |
| **Windows / Linux** | **Web only** (`-d chrome`) |

There is no `android/` or `windows/` folder. To add Android later:
`flutter create --platforms=android .`

---

# Part 1 — Install the tools

## 1.1 Check what you already have

```bash
flutter --version
```

If that prints a version, skip to 1.3.

## 1.2 Install Flutter

Follow the official installer for your OS:
<https://docs.flutter.dev/get-started/install>

Then confirm:

```bash
flutter doctor
```

Green checkmarks matter for the platform you plan to use. On Windows, a red X
next to Android toolchain is fine — you are running web.

**Mac users targeting macOS/iOS** also need Xcode:

```bash
# Install Xcode from the App Store first, then:
sudo xcode-select --switch /Applications/Xcode.app/Contents/Developer
sudo xcodebuild -license accept
sudo gem install cocoapods
```

## 1.3 Get the project dependencies

```bash
cd ultra_planner
flutter pub get
```

## 1.4 Install the Firebase CLI

Pick **one**:

**Mac / Linux (easiest — no Node.js needed):**
```bash
curl -sL https://firebase.tools | bash
```

**Mac with Homebrew:**
```bash
brew install firebase-cli
```

**Windows:** download `firebase-tools-instant-win.exe` from
<https://firebase.tools/> and run it.

**Any OS, if you already have Node.js 20+:**
```bash
npm install -g firebase-tools
```

Confirm it worked:
```bash
firebase --version
```

## 1.5 Sign in to Firebase

```bash
firebase login
```

A browser opens. **Sign in with the Google account that owns the Firebase
project.** If you sign in with the wrong account, the project will not appear in
the next step — run `firebase logout` and try again.

## 1.6 Install the FlutterFire CLI

```bash
dart pub global activate flutterfire_cli
```

This almost always prints a **PATH warning**. You must fix it or the
`flutterfire` command will not be found.

**Mac (zsh):**
```bash
echo 'export PATH="$PATH":"$HOME/.pub-cache/bin"' >> ~/.zshrc
source ~/.zshrc
```

**Linux (bash):**
```bash
echo 'export PATH="$PATH":"$HOME/.pub-cache/bin"' >> ~/.bashrc
source ~/.bashrc
```

**Windows:** add `%LOCALAPPDATA%\Pub\Cache\bin` to your PATH environment
variable, then open a new terminal.

Confirm:
```bash
flutterfire --version
```

---

# Part 2 — Set up Firebase in the console

Go to <https://console.firebase.google.com/> and open the project.

## 2.1 Turn on Email/Password sign-in

**Build → Authentication → Get started → Sign-in method →
Email/Password → Enable → Save.**

Skip this and sign-up fails with: *"Email/password sign-in is not enabled for
this Firebase project."*

## 2.2 Create the Firestore database

**Build → Firestore Database → Create database.**

- Pick a location close to you (this **cannot be changed later**).
- Choose **Production mode**. You will deploy the real rules in step 3.3.

> Test mode leaves your database readable and writable by anyone on the internet
> for 30 days. Don't use it.

---

# Part 3 — Connect the app to Firebase

## 3.1 Generate the config file

From the project folder:

```bash
flutterfire configure
```

- Select the existing project from the list.
- When asked which platforms: select **macos, ios, web** (or just **web** on
  Windows). Do **not** select android — there is no `android/` folder.

This **overwrites `lib/firebase_options.dart`**. That is the entire point of the
step — the file currently holds `TODO_REPLACE_ME` placeholders.

> These values are not secrets. A Firebase `apiKey` identifies the project; it
> does not grant access by itself. Access is controlled by Authentication plus
> the rules in the next step.

## 3.2 Tell the CLI which project to deploy to

The repo has no `.firebaserc`, so this is required or the next command fails
with *"No currently active project"*:

```bash
firebase use --add
```

Select the project and accept the default alias.

## 3.3 Deploy the security rules

**Do not skip this.**

```bash
firebase deploy --only firestore:rules
```

`firestore.rules` is deny-by-default: each signed-in user can reach only their
own documents, and nobody can read anyone else's Gemini API key.

Without deploying, production mode blocks everything and the app shows
*"Firestore denied access."*

## 3.4 Mac only — allow network access

Already committed to the repo, but worth knowing why it's there. The macOS
sandbox blocks all outbound connections by default, so
`macos/Runner/DebugProfile.entitlements` and `Release.entitlements` both contain:

```xml
<key>com.apple.security.network.client</key>
<true/>
```

Remove it and every Firebase and Gemini request fails silently.

---

# Part 4 — Run it

```bash
flutter run -d macos     # Mac
flutter run -d chrome    # Windows, Linux, or Mac
```

First macOS run downloads CocoaPods dependencies and takes several minutes.

You should land on the **login screen**, not the setup notice. If you still see
"Firebase is not configured yet", step 3.1 did not write the file — re-run it.

## 4.1 Create your account

Tap **Sign up**, enter an email and a password of at least 6 characters.

The email does not need to be real for testing, but use something you'll
remember — password reset emails only work for real addresses.

You'll get two starter lists ("School" and "Shopping") on first sign-in.

## 4.2 Add your Gemini API key

Get a free key at <https://aistudio.google.com/apikey>.

In the app: **avatar menu (top right) → Add Gemini API key → paste → Save.**

The key is saved to your account, so you only do this once — it loads
automatically on every later sign-in, on any device.

---

# Verify it worked

- [ ] Login screen appears instead of the setup notice
- [ ] You can create an account and land on the planner
- [ ] Adding a task makes it appear in the Firebase console under
      **Firestore Database → tasks**
- [ ] Logging out and back in shows your tasks again
- [ ] Quackers replies when you ask it something
- [ ] `flutter test` passes (24 tests)

---

# Troubleshooting

| Symptom | Cause and fix |
| --- | --- |
| `flutterfire: command not found` | PATH not set — redo step 1.6 and open a **new** terminal |
| `firebase: command not found` | Firebase CLI not installed — step 1.4 |
| Project missing from `flutterfire configure` | Signed in as the wrong Google account: `firebase logout`, then `firebase login` |
| "No currently active project" | Run `firebase use --add` (step 3.2) |
| "Firebase is not configured yet" | `flutterfire configure` did not write the file — re-run step 3.1 |
| "Firestore denied access" | Rules not deployed — step 3.3 |
| "Email/password sign-in is not enabled" | Step 2.1 |
| "Cannot reach Firebase" on Mac | Network entitlement missing — step 3.4 |
| Assistant returns a 404 | The model name in `lib/gemini_quackers_service.dart` may need updating — see note below |
| `flutter pub get` version conflicts | Try `flutter pub upgrade`. The SDK constraint is `^3.9.0`, which works on Flutter 3.35 and newer. |
| Pod install fails on Mac | `cd macos && pod repo update && cd ..` then rebuild |

---

# How the data is stored

```
lists/{listId}
  ownerId    uid of the owner
  name       list name
  order      display order
  createdAt  timestamp

tasks/{taskId}
  ownerId    uid of the owner
  listId     id of the parent lists/ document
  name       task text
  dueDate    timestamp or null
  isDone     boolean
  createdAt  timestamp

users/{uid}/private/settings
  geminiApiKey  string
  updatedAt     timestamp
```

Two top-level collections scoped by `ownerId`, which is what the rules match
against `request.auth.uid`. The app only reads documents whose `ownerId` is the
signed-in user, so any pre-existing documents without that field are invisible
rather than harmful.

No composite indexes are needed — sorting happens client-side in
`PlannerRepository._stitch` specifically to avoid that.

Deleting a list also deletes its tasks (`PlannerRepository.deleteList`).
Firestore does not cascade on its own, and orphaned tasks would keep showing up
in the calendar.

---

# A note on the Gemini key

The key is stored in `users/{uid}/private/settings` and the rules stop any other
signed-in user from reading it.

**What that does not protect:** it is stored in plaintext, so anyone with owner
access to the Firebase console can read it, and it still reaches the device at
runtime. That is fine for a personal project. If this app is ever given to other
people, move the Gemini call into a Cloud Function so the key never reaches the
client at all.

The build-time fallback still works when no key is saved to the account:

```bash
flutter run -d macos --dart-define=GEMINI_API_KEY=your_key
```

**Model name:** `lib/gemini_quackers_service.dart` targets
`gemini-3.5-flash-lite`. If the assistant returns a 404, check the current model
list at <https://ai.google.dev/gemini-api/docs/models> and update the `_endpoint`
constant.
