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

## 4.2 The assistant

Quackers needs the Cloud Functions from **Part 5**, plus your own Gemini API key
entered in the app once Part 5 is deployed.

Everything else -- lists, tasks, the calendar -- works without it.

---

# Verify it worked

- [ ] Login screen appears instead of the setup notice
- [ ] You can create an account and land on the planner
- [ ] Adding a task makes it appear in the Firebase console under
      **Firestore Database → tasks**
- [ ] Logging out and back in shows your tasks again
- [ ] Quackers replies once you add your Gemini key (needs Part 5)
- [ ] `users/{uid}/private/settings` in the console shows ciphertext, not a key
- [ ] `flutter test` passes (22 tests)
- [ ] `cd functions && npm test` passes (20 tests)

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

# Part 5 - Deploy the Quackers Cloud Functions

Quackers reaches Gemini through Cloud Functions. **Each user brings their own
Gemini key.** The key is encrypted before it is stored, so it is never sitting
in plaintext in Firestore and is never sent back to the app.

> **This part requires the Blaze plan.** Cloud Functions cannot be deployed on
> the free Spark plan. Everything in Parts 1-4 works on Spark; only the
> assistant needs this.
>
> Costs for a class-sized project land inside Blaze's free tier (2M function
> invocations/month). Gemini usage is billed to each user's own key, not to
> this project. Setting a budget alert is still worth doing:
> **console -> gear icon -> Usage and billing -> Details & settings.**

## 5.1 Create the encryption key

This is the master key that encrypts every user's Gemini key. It is *not* a
Gemini key -- it is 32 random bytes you generate yourself:

```bash
openssl rand -base64 32
```

Store it as a secret:

```bash
firebase functions:secrets:set GEMINI_KEY_ENCRYPTION_KEY
```

Paste the generated value when prompted.

> Keep a copy somewhere safe. **Rotating or losing this invalidates every stored
> key** and each user has to enter theirs again. Nothing else breaks.

## 5.2 Deploy

```bash
cd functions && npm install && cd ..
firebase deploy --only functions
```

First deploy takes a few minutes, asks to enable some Google Cloud APIs, and
asks to grant the functions access to the secret. Say yes to all.

Verify:

```bash
firebase functions:list
```

You want four functions in `us-central1`: `askQuackers`, `saveGeminiKey`,
`quackersStatus`, `deleteGeminiKey`.

## 5.3 Deploy the updated rules

```bash
firebase deploy --only firestore:rules
```

## 5.4 Each user adds their own key

In the app: **avatar menu -> Add Gemini API key**, or open Quackers and use the
setup panel. Free keys come from <https://aistudio.google.com/apikey>.

Entered once per account, not per device -- it is stored server-side and
follows the login.

Watch it work:

```bash
firebase functions:log --only askQuackers
```

---

# How the key is protected

```
App --(key, once, over TLS)--> saveGeminiKey --encrypt--> Firestore (ciphertext)

App --(question)--> askQuackers --decrypt--> Gemini
                         |
                  master key (Secret Manager)
```

The key is encrypted with **AES-256-GCM** using a master key held in Secret
Manager, with a fresh random IV per key so no two records share one.

**What this protects against**

- Browsing Firestore in the console shows ciphertext, not keys
- A database export or leaked backup is useless on its own
- Other signed-in users: security rules deny *all* client access to the stored
  record
- The app itself: the key is never sent back. The client can ask whether a key
  exists and see its last four characters, nothing more
- Tampering: GCM authenticates, so a modified record fails to decrypt instead of
  silently producing garbage

**What it does not protect against**

Anyone who can read the master secret in Secret Manager can decrypt every stored
key. A proxy has to recover the plaintext to call Gemini, so this is
unavoidable. The honest summary: keys are no longer *lying around* in plaintext,
but a determined project owner can still get at them.

The only design where the operator genuinely cannot read the key is one where
the key never reaches the server -- which means no proxy, and the key living on
each device instead.

## What each function does

| Function | Purpose |
| --- | --- |
| `saveGeminiKey` | Encrypts and stores the caller's key. Returns only a `...abcd` hint. |
| `quackersStatus` | Whether a key is saved, plus that hint. Never the key. |
| `deleteGeminiKey` | Forgets the caller's key. |
| `askQuackers` | Decrypts the caller's key, calls Gemini, returns the reply. |

All four reject unauthenticated callers. `askQuackers` also validates input
(2000-char question, 8000-char context, last 20 turns) and rate limits to 30
requests per 10 minutes per account, counted in `rateLimits/{uid}` inside a
transaction so simultaneous calls cannot both slip past. Tune the constants in
`functions/rateLimit.js`.

Gemini errors are logged in full server-side; the app gets a safe message. A
`400` or `403` from Gemini is reported as a rejected key, which is the one cause
the user can actually fix.

## Changing the model

Set `GEMINI_MODEL` in `functions/.env` and redeploy:

```
GEMINI_MODEL=gemini-2.5-flash-lite
```

If Quackers reports the configured model was not found, check
<https://ai.google.dev/gemini-api/docs/models>.

## Cleaning up old plaintext keys

Keys saved before this change are still in Firestore in the clear, under
`users/{uid}/private/settings` as a `geminiApiKey` field. Delete that field for
every user in the console, and have each user re-enter their key so it is stored
encrypted. Any key that sat in plaintext should be revoked at
<https://aistudio.google.com/apikey> and replaced rather than reused.

## Running the function tests

Pure logic, no emulator needed:

```bash
cd functions && npm test
```

20 tests: encryption round-trip, tamper detection, IV uniqueness, wrong master
key, and the rate limit window boundaries.
