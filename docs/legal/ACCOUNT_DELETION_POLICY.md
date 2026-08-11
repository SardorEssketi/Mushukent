# Mushukistan Account Deletion Policy

Version: 2026-08-01

Users can delete their account from Settings.

Users can delete their Mushukistan account directly inside the app:
Settings -> About account -> Delete account

Users can also submit a deletion request by email:
support@mushukistan.uz

When account deletion is requested, the backend:
- Disables login for the account.
- Replaces the email address with a non-routable deleted-account address.
- Removes password hash, name, avatar URL, phone number, bio, legal acceptance timestamps, and last-login data.
- Turns off public activity visibility.
- Deletes the user's likes.
- Hides and anonymizes the user's posts, comments, and lost-pet posts.
- Removes copied lost-pet phone numbers.
- Removes the user as creator/reporter/handler where possible.
- Attempts best-effort media cleanup for profile, post, and lost-pet media URLs.

Backups are not configured in the verified repository. If backups are enabled later, backup deletion timing must be documented before production release.
Users may also request account deletion support by contacting: support@mushukistan.uz.
Mushukistan may retain limited records when necessary for legal compliance, security, fraud prevention, abuse prevention, copyright enforcement, or moderation audit purposes.
