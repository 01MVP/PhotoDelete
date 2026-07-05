# PhotoDelete Release Checklist

## Ready

- Core flow: request Photos permission, index library, open a category, swipe left/right/up, undo, finish, and confirm batch operations.
- UI direction: iPhone portrait and landscape are supported with separate layouts for the home and swipe screens.
- Privacy positioning: app copy says no account is required and photos are not uploaded.
- App icon: generated app icons have no alpha channel.
- Website: `photodelete.01mvp.com` is deployed through Cloudflare Pages.
- Automation: `scripts/release-testflight.sh` archives and uploads TestFlight builds.

## Before App Store Release

- Verify on a physical iPhone with a large real photo library, including iCloud optimized storage.
- Confirm App Store Connect privacy details match the app behavior: no account, no photo upload, no tracking.
- Prepare App Store screenshots for portrait and landscape if landscape support remains enabled.
- Confirm support/contact copy: website, WeChat `mvps01`, and feedback email.
- Run the final release script with a new build number, then wait for TestFlight processing and install the uploaded build.
- Do a fresh-install permission test: first launch, permission prompt, indexing state, home intro card, and swipe flow.

## Manual Real-Device Regression Checklist

- Continue organizing with no new photos: leave All Photos on a middle photo, force quit, reopen, and confirm review resumes at that photo or the next unreviewed photo.
- Continue organizing with new photos: add several new photos, reopen All Photos, confirm the new photos appear first, then confirm the flow returns to the previous saved position after they are reviewed.
- Review mode sync: organize to a middle photo, switch from card mode to the two-row browser, and confirm the selected/centered item is the same photo and the position label matches.
- Video review: open a video in the organizer, drag the progress bar, confirm playback seeks without triggering a photo swipe, then swipe the card after releasing the progress bar.
- Similar photos: check at least one burst/near-duplicate group and one mixed-time album area, confirming real bursts group together and unrelated adjacent photos are not grouped.
- Photos write paths: with a real Photos library, validate delete confirmation, favorite writes, album add, limited-library management, iCloud optimized media loading, background/foreground recovery, and undo before batch confirmation.
