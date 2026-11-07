# CuffTag — App Store & TestFlight submission draft

This kit reflects the Apple Podcasts-only library decision. Review all copy,
privacy answers and media before submission. Simulator screenshots do not prove
physical jacket compatibility, real capture or locked-phone playback.

## 1. Build and media commands

Run from `CuffTag/`:

```bash
./scripts/generate-appstore-media.sh --shots-only
./scripts/generate-appstore-media.sh --video-only
./scripts/release-testflight.sh --archive-only
```

The screenshot test captures eight native screens, including the Apple Podcasts
Shortcut setup instead of a duplicated podcast library or CuffTag Now Playing.
`-appStoreDemo YES` is a launch argument for simulator media capture, not an
end-user hardware simulator. Camera media in this mode uses a synthetic backdrop.
Do not present it as an actual photograph or live camera feed.

The media script exports resized display variants. Check current App Store
Connect requirements and review the files; resize output is not evidence that a
different device was tested. Preview recording requires `ffmpeg` and manual review
of timing, content, sound and submission requirements.

The release script archives, signs and optionally exports/uploads using your
Apple Developer account. No archive or upload has been performed by this polish
pass.

## 2. Listing copy

| Field | Draft |
|---|---|
| Name | CuffTag |
| Subtitle | Jacquard Jacket & Cuff Control |
| Category | Utilities |
| Bundle ID | com.jamierytlewski.cufftag |
| Keywords | jacquard,levi,trucker,jacket,wearable,cuff,bluetooth,gesture,haptic,podcast,shortcuts |

### Promotional text

Connect your compatible Jacquard tag locally over Bluetooth. Customize sleeve
gestures, configure Apple Podcasts Shortcuts, and explore Gesture school.

### Description

Your jacket remembers.

CuffTag is an unofficial companion for compatible Levi's Jacquard jackets.
Pair your tag locally over Bluetooth without a Google account or the retired
Jacquard cloud service. Compatibility depends on the tag and its installed firmware;
CuffTag does not update or recover firmware.

Map Double Tap, Brush In, Brush Out and Cover, with optional Cover chords, to
media requests, volume changes, spoken information, camera actions or your own
Shortcuts. Use Everyday, Ride and Focus profiles or create your own.

ONE PODCAST LIBRARY

Keep subscriptions and listening history in Apple Podcasts. Configure your own
tested Play / Pause, Skip 30s and Back 15s Shortcuts in CuffTag. Playback gestures
open Shortcuts while CuffTag is foreground. In the background or while locked,
tap the notification and unlock if asked. CuffTag cannot directly control or read
Apple Podcasts playback, and opening Shortcuts does not prove an action completed.
Apple Music is also supported through its system music player.

SLEEVE CAMERA

With CuffTag's camera visible and your phone unlocked, use your cuff to take
photos, flip cameras, start/stop video or take a countdown photo. Camera,
Microphone and Photos permissions are required as appropriate. Failed saves offer
retry or explicit discard.

GESTURE SCHOOL AND JACKET SIGNALS

Practice gestures on the interactive sleeve illustration. Image previews do not
run mapped actions or prove that hardware reported a gesture. Use Shortcuts
automations to request jacket vibration and tag-light signals. CuffTag cannot
read other apps' notifications.

No sign-up, analytics SDK or CuffTag cloud backend is required. Apple Podcasts,
Shortcuts and network actions have their own connectivity and privacy requirements.
Bluetooth delivery, background execution and device compatibility need testing on
your own iPhone and jacket. Configure pre-ride actions while stopped.

### What's new

Initial release: local Bluetooth pairing, configurable sleeve gestures and
profiles, Apple Podcasts Shortcut setup, Gesture school, jacket signals and
Sleeve Camera.

## 3. App Review and TestFlight notes

CuffTag requires a compatible physical Jacquard tag/jacket for Bluetooth,
recognized jacket gestures, vibration and tag LED verification.

Without hardware, reviewers can open the introduction, choose **Try without a
tag**, practice all four image gestures, edit mappings/profiles, configure playback
Shortcut names and inspect automation recipes. These previews are not a test of
100% of the app. Camera capture requires a physical iPhone with appropriate
permissions. Playback requires Apple Podcasts and installed, tested Shortcuts.

The `bluetooth-central` background mode supports communication with the jacket.
The `audio` mode supports spoken announcements and the phone-finder sound.
Neither guarantees unrestricted background execution. Background Shortcut requests
require tapping a notification and may require unlocking.

This is not an official Google or Levi's app. No firmware updates are offered.

## 4. Privacy policy draft and App Privacy review

CuffTag has no analytics or advertising SDK and no developer-operated backend.
Pairing identifiers, profiles and Shortcut names remain on the device. Legacy
local podcast data is preserved but no longer exposed as a second library.
Camera captures are saved locally to Photos and are not uploaded by CuffTag.

Apple Podcasts and Shortcuts are separate apps with their own privacy practices.
User-configured webhooks send network requests to the configured destination;
review those destinations and the Shortcut actions you choose. Do not claim the
app is entirely offline or never transmits data.

Before answering App Store Connect privacy questions, review the current bundled
privacy manifest, SDK behavior and optional network features against Apple's
definitions. A draft "no developer collection" answer is not a compliance
certification. Set the policy's effective date when publishing.

Contact: https://github.com/jamierytlewski/cufftag/issues
