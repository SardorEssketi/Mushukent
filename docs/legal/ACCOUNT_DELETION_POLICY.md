# Mushukistan Account Deletion Policy

Version: 2026-08-01

Users can delete their account from Settings.

Users can delete their Mushukistan account directly inside the app:
Settings -> About account -> Delete account

Users who cannot access the app can start account deletion from:
https://mushukistan.uz/delete-account

The public page asks for the account email address. The backend returns the same response whether or not the email address belongs to an account. If an active account exists, Mushukistan sends a time-limited confirmation link to that email address. The account is deleted only after the user opens the confirmation link and explicitly confirms deletion.

When account deletion is requested, the backend:
- Disables login for the account.
- Replaces the email address with a non-routable deleted-account address.
- Removes password hash, name, avatar URL, phone number, bio, legal acceptance timestamps, and last-login data.
- Removes Telegram username, resets preferred language, and removes moderator status from the deleted account tombstone.
- Turns off public activity visibility.
- Deletes the user's likes and updates affected post like counters.
- Deletes user block rows involving the deleted account.
- Deletes affected leaderboard cache entries.
- Hides and anonymizes the user's posts, comments, and lost-pet posts.
- Hides and anonymizes the user's adoption/rehoming posts.
- Removes copied lost-pet and adoption/rehoming contact details.
- Removes the user as creator/reporter/handler where possible.
- Attempts best-effort media cleanup for profile, post, lost-pet, and adoption/rehoming media URLs.

Backups are not configured in the verified repository. If backups are enabled later, backup deletion timing must be documented before production release.
Mushukistan may retain limited records when necessary for legal compliance, security, fraud prevention, abuse prevention, copyright enforcement, or moderation audit purposes.
The verified repository does not define a guaranteed automatic deletion period for all retained records.
