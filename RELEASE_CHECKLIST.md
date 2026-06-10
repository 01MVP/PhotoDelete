# PhotoDel Release Checklist

## Ready

- Core flow: request Photos permission, index library, open a category, swipe left/right/up, undo, finish, and confirm batch operations.
- UI direction: iPhone portrait and landscape are supported with separate layouts for the home and swipe screens.
- Privacy positioning: app copy says no account is required and photos are not uploaded.
- App icon: generated app icons have no alpha channel.
- Website: `photodel.01mvp.com` is deployed through Cloudflare Pages.
- Automation: `scripts/release-testflight.sh` archives and uploads TestFlight builds.

## Before App Store Release

- Verify on a physical iPhone with a large real photo library, including iCloud optimized storage.
- Confirm App Store Connect privacy details match the app behavior: no account, no photo upload, no tracking.
- Prepare App Store screenshots for portrait and landscape if landscape support remains enabled.
- Confirm support/contact copy: website, WeChat `mvps01`, and feedback email.
- Run the final release script with a new build number, then wait for TestFlight processing and install the uploaded build.
- Do a fresh-install permission test: first launch, permission prompt, indexing state, home intro card, and swipe flow.
