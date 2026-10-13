# Application screenshot publication review

The four captures were supplied by the owner in the original repository's
`website/` directory as `map.jpg`, `feed.jpg`, `leaderboard.jpg`, and
`profile.jpg`, rather than the ZIP/PNG names in the brief. They are real Android
captures at 1080 × 2436, with the application interface in Uzbek. The private
inputs are copied only into ignored `.data/private-screenshots/` in the isolated
worktree. They must never be committed or copied into a release archive.

## Review — 2026-10-12

- Crop `(0, 104, 1080, 2316)` removes the Android status and system navigation
  bars. The full Mushukistan bottom navigation is preserved.
- Profile: opaque redaction of the name, email, and avatar initials.
- Leaderboard: opaque redaction of all three displayed names and avatars;
  the actual ranks, activity counts, tabs, and filters remain unchanged.
- Feed: both author names and avatars are concealed. The owner explicitly
  confirmed ownership or publication permission for the large first kitten
  photograph. It contains no visible person, address, or precise location.
  The visible portion of the second post photograph is covered because its
  publication rights were not established.
- Map: city-level Tashkent map with public pet-service icons/clusters. No
  visible private animal pin, current-position dot, contact, or coordinates.
  The caption links to https://www.openstreetmap.org/copyright for attribution.
- No fictional users, translated screenshot UI, changed counters, replacement
  photographs, or invented application controls are added. Opaque neutral
  covers indicate redaction; the section explains that personal details are
  concealed. Its Uzbek interface is disclosed in all three page languages.

## Repeatable processing

```powershell
python -m pip install -r website/tool/requirements-assets.txt
python website/tool/prepare_screenshots.py --input .data/private-screenshots
python website/build.py
```

The recipe verifies exact source SHA-256 values and dimensions before writing
any derivative, then applies fixed crop/redaction coordinates, Lanczos resizing,
and fixed encoder options. If an input changes, processing fails and requires a
fresh visual/privacy review. Pillow 11.2.1 is pinned for the asset workflow.
No image dependency is needed for the static site build itself.

Only publication-safe 270px/540px WebP and progressive JPEG derivatives, plus a
review manifest, live under `website/src/screenshots/`. Image metadata is
discarded. The builder copies an explicit allowlist of these sixteen images
into hashed `/landing-assets/` filenames; it never copies private inputs or the
review manifest. Native screenshot proportions and image dimensions reserve
layout space. WebP is preferred, JPEG is the fallback, and below-fold images
are lazy-loaded. No runtime image service or external asset origin is added.

## Refinement integration decision

This branch starts at the deployed `27adc4c` revision. Changes stay in the static
website and its documentation/tests. Nginx, Compose, Flutter, API, notification
services, and database remain unchanged. For deployment, copy the complete
validated production Flutter directory byte-for-byte into the new versioned
release, validate its file hashes, and replace only the website artifacts and
reviewed website source. Recreate only Nginx after automated gates pass. Retain
the current release as the rollback target; never modify active artifacts.
