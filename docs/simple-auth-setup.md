# HomeEase local accounts

No backend setup is required. Supabase and its build configuration have been removed from the app.

## Use the app

1. Install the latest `build/app/outputs/flutter-apk/app-debug.apk` over the previous HomeEase APK.
2. Open **Create new account**. Enter your name, email, password (8?128 characters) and matching confirmation. The email is a local account identifier; no verification email is sent.
3. Save the recovery code shown once in a safe place outside the app. Check **I have saved my recovery code**, then **Continue to HomeEase**.
4. Log out at **Settings ? Profile & logout ? Log out**. Settings, routines, activity and history remain saved for this account.
5. Sign in using the same email and password. A saved session also restores when the app reopens.

## Forgot password

On Login, tap **Forgot your password?** Enter the email and your saved recovery code. Set a new password, save the replacement recovery code, then sign in. The previous recovery code no longer works after a successful reset. Codes tolerate spaces/hyphens and lowercase letters. Without the correct code or current password there is no password reset bypass.

Recovery authorization is kept in memory and is cancelled when the app restarts. Five incorrect password/code attempts on an account trigger a 30-second cooldown that survives a restart. Keep the recovery code private.

## Data and compatibility

Accounts exist only on this installation. Old Supabase accounts are not automatically imported. Create a new local account; the same email may be used because the stores are separate. Existing cloud resources were not modified or deleted. No account or history synchronizes across phones. Uninstalling, clearing app data or losing secure storage can remove local access and records. A recovery code cannot restore a deleted account or database.

The ESP32 service and demo/live separation remain independent. New accounts start with demo mode enabled; enter the board address in Settings and disable demo mode when hardware is ready. Guest demo has its own storage. Signing out removes protected routes and stops voice/alarm sessions, while retaining this account's local data.

## Build and run

```powershell
cd C:\Users\Ahron\appdev
flutter pub get
flutter run
flutter build apk --debug
```

No `--dart-define` configuration is needed. Android secure credentials use `flutter_secure_storage`; password and recovery-code plaintext are not saved in SharedPreferences.
