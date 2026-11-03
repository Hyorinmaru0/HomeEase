# Local signup troubleshooting

Install the newest APK from `build/app/outputs/flutter-apk/app-debug.apk`. This version uses local accounts and does not contact Supabase or send email.

- Fill all fields and use matching passwords of 8?128 characters. Validation appears beside the affected field.
- An existing email on this phone must use Sign in or Forgot password with its saved recovery code.
- Save the code after signup, check the confirmation box, and tap Continue to HomeEase.
- A failed save displays feedback beside the submit button. Restart the app if local credential storage cannot be opened; do not clear app data if you need your local records.
- After five wrong password/code attempts, wait 30 seconds before trying again.
- Old cloud accounts are separate. Create a local account for this version.

See [local account setup](simple-auth-setup.md) for recovery and data retention limits.
