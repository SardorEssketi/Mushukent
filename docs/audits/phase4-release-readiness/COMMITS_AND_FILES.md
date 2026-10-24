# Commits and files (Phase 4)

Base: `47ebff4`. New commits on `fix/release-readiness`:
- `9bc3fc4` hide owner contact details from guests, lists and feeds (adoption_posts and lost_pets schemas and services, feed service, test_contact_privacy, test_feed_map)
- `ab499f1` restrict cat edits to creator or moderator, platform cover URLs (cats service, storage service `owns_url`, test_cat_editing_policy)
- `6b39386` client uses `contact_available` (mushukistan_api.dart, detail screens, publication_detail_parts, contact_privacy_test)
- `4bcc45f` persist chosen language locally (app.dart, language_controller.dart, auth_widget_test)
- `2b24800` ci: pythonpath fix and research extra (ci.yml, pyproject.toml)
- `a31ae47` docs (API.md, CONTACT_PRIVACY.md, CAT_EDITING.md)

This audit folder is uncommitted, like the earlier audit folders, for your review. Pre-existing uncommitted changes (.gitignore, DEPLOYMENT.md, adr-public-homepage.md, pubspec.yaml, nginx configs, website/*, .claude/) were not touched or staged.
