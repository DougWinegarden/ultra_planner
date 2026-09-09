# Firebase setup

The app is fully wired for Firebase Auth + Firestore, but it ships with
**placeholder credentials**. `flutterfire configure` has to be run by someone
signed in to the Google account that owns the Firebase project, which was not
possible on the machine where this code was written.

Until step 2 is done, the app builds and runs but opens on a
"Firebase is not configured yet" screen instead of the login page.

---

## 1. Enable Email/Password sign-in

Firebase console → **Authentication** → **Sign-in method** → enable
**Email/Password**.

If this is skipped, sign-up fails with
`operation-not-allowed` (the app shows: "Email/password sign-in is not enabled
for this Firebase project").

## 2. Generate real credentials

```bash
dart pub global activate flutterfire_cli
flutterfire configure
```

Select the existing project and the platforms you want (macos, ios, web).
This **overwrites `lib/firebase_options.dart`** with real values — that is
expected and is the whole point of this step.

Doing it by hand instead: copy each value from
**Project settings → General → Your apps → SDK setup and configuration** into
the matching field in `lib/firebase_options.dart`, replacing every
`TODO_REPLACE_ME`.

> These values are not secrets. A Firebase `apiKey` identifies the project; it
> does not grant access on its own. Access is controlled by Authentication plus
> the rules in step 3.

## 3. Deploy the security rules

**Do not skip this.** A Firestore database left in test mode is readable and
writable by anyone on the internet, and in locked mode the app will show
"Firestore denied access".

```bash
firebase deploy --only firestore:rules
```

`firestore.rules` grants each signed-in user access to their own documents and
nothing else. It is deny-by-default: any collection added later needs its own
rule.

## 4. macOS only — allow outbound network access

The macOS sandbox blocks network calls by default. Both entitlement files need
the client permission, or every Firebase and Gemini request fails silently:

`macos/Runner/DebugProfile.entitlements` and `macos/Runner/Release.entitlements`

```xml
<key>com.apple.security.network.client</key>
<true/>
```

## 5. Run it

```bash
flutter run -d macos
```

---

## Data model

Two top-level collections, each scoped by an `ownerId` field, plus a private
per-user settings document.

```
lists/{listId}
  ownerId    string    uid of the owner
  name       string
  order      number    display order
  createdAt  timestamp

tasks/{taskId}
  ownerId    string    uid of the owner
  listId     string    id of the parent lists/ document
  name       string
  dueDate    timestamp or null
  isDone     boolean
  createdAt  timestamp

users/{uid}/private/settings
  geminiApiKey  string
  updatedAt     timestamp
```

**If a `tasks` collection already exists in the project** with a different shape,
either clear it and let the app recreate documents, or add the missing
`ownerId` / `listId` fields to the existing documents. The app only ever reads
documents whose `ownerId` matches the signed-in user, so pre-existing documents
without that field are simply invisible rather than harmful.

No composite indexes are required. Sorting is done client-side in
`PlannerRepository._stitch` specifically so that no index has to be deployed by
hand.

Deleting a list cascades to its tasks in `PlannerRepository.deleteList` —
Firestore does not cascade on its own, and orphaned tasks would otherwise keep
appearing in the calendar views.

---

## Gemini API key

The key is entered once (account menu → **Add Gemini API key**, or the
assistant's setup panel) and saved to `users/{uid}/private/settings`. It is
loaded automatically on every later sign-in, on any device.

**What this does and does not protect.** The key is out of the app bundle and
out of other users' reach, and the rules stop any other signed-in account from
reading it. It is still stored in plaintext in Firestore, so anyone with owner
access to the Firebase console can read it, and it still reaches the device at
runtime. Preventing a client from ever holding the key means proxying Gemini
through a Cloud Function and never sending it down — worth doing if this app is
ever handed to people other than its owner.

The build-time `--dart-define=GEMINI_API_KEY=...` path still works and takes
effect when no key is saved to the account.
