# CuffTag

*The snap tag in your cuff that keeps the threads alive.*

CuffTag is a personal, unofficial iOS 27+ companion app for a Levi's Jacquard jacket, built with
SwiftUI and Google's archived [Jacquard iOS SDK](https://github.com/google/JacquardSDKiOS).
The jacket connection uses local Bluetooth; it does not require a Google account
or the retired Jacquard cloud.

**Status:** the app builds for iPhone and includes automated iOS simulator tests.
The service tests use a simulated SDK connection to check pairing state, gesture
delivery, profiles, Cover chords, camera error handling and Shortcut URLs.
UI tests cover navigation, named camera controls, minimum touch targets, profile
editing, demo replay and touch gestures, reset confirmation and scrolling at the
largest Dynamic Type size.
They are **not a physical jacket test**. Compatibility with your exact tag and firmware, locked-phone
behavior, camera capture and real playback still need the device checks below.

## What you need

- A Mac with full Xcode installed. This project has been built with Xcode 27.1.
- An Apple ID added in Xcode's Settings > Accounts. A free Personal Team can be
  used for your own iPhone; a paid developer membership is not required for this setup.
- An iPhone running iOS 27 or later, and a cable for the initial installation.
- A charged Jacquard tag and compatible jacket. The SDK lists Levi's Trucker
  jackets, but this is not a guarantee for every Jacquard generation or firmware.
- Apple's Shortcuts app if you want to run Shortcuts.
- Internet access for Xcode's initial package downloads, podcast search/streaming,
  Apple Music streaming and network automations.

Clone the repository. It already keeps these folders together, and the Xcode
project depends on that layout:

```sh
git clone https://github.com/jamierytlewski/cufftag.git
```

```text
cufftag/
  README.md
  CuffTag/
    CuffTag.xcodeproj
    project.yml
    CuffTag/
    CuffTagTests/
    sdk-offline-firmware.patch
  JacquardSDKiOS/
```

The app references the **local, patched SDK** in the sibling folder. Do not
replace it with an unpatched online package.

CuffTag is the name of the app, project and repository. Its Xcode project,
targets, source folders, bundle identifier and URL scheme all use CuffTag.

Google archived the SDK at v1.0.0, so there is no newer release to pull. The
local copy is kept building cleanly on current Xcode instead: its protobuf code
is regenerated with SwiftProtobuf 1.39 from the `.proto` files in
`JacquardSDKiOS/Protos/` (run `Protos/generate.sh` after editing them), and
deprecated API calls are replaced. The SDK is vendored in this repository: the
commit tagged `sdk-upstream-7db0fe2` is the untouched upstream copy, so
`git diff sdk-upstream-7db0fe2 HEAD -- JacquardSDKiOS` lists every local SDK
change.

## Install on your iPhone

1. Open `CuffTag/CuffTag.xcodeproj` in Xcode. Use the
   **CuffTag** scheme, not the SDK example project. Let package resolution finish.
2. Connect and unlock your iPhone. Accept **Trust This Computer** if prompted.
3. In Xcode, select the project, then the **CuffTag** app target.
   Under **Signing & Capabilities**, leave automatic signing on and choose
   your Apple ID's **Personal Team** or your paid team.
4. If Xcode says the bundle identifier is unavailable, choose your own unique
   identifier, such as `com.yourname.CuffTag`.
5. Select your actual iPhone as the run destination and press **Run** (Command-R).
   An unsigned command-line build or a simulator build cannot be installed on a phone.
6. If prompted, enable **Settings > Privacy & Security > Developer Mode** on
   the iPhone, restart it, and confirm. If iOS asks you to trust the developer,
   follow the entry under **Settings > General > VPN & Device Management**.
7. Open CuffTag and allow Bluetooth. Other permissions are requested when you
   use the corresponding features.

Xcode may need to download device support before its first run. Signing errors
must be resolved with your own Apple account; no credentials belong in this project.

### The seven-day reminder

With a free Apple ID, development signing typically lasts **seven days**.
When it expires, the installed app can no longer launch until it is signed again.
This is an Apple restriction, not a Google service, jacket subscription or
firmware expiration.

Before expiry, reconnect the iPhone and press **Run** in Xcode again, using the
same team and bundle identifier. Updating in place normally preserves app data;
deleting the app removes its local data.

The Jacket tab warns near the expiration date read from the embedded
provisioning profile. Settings shows the date when available. It is an in-app
reminder, not an automatic re-signing service or guaranteed background alert.
Other signing methods have different validity periods.

## Pair the jacket

1. Charge the tag. Close any other app that might be competing for it.
2. In CuffTag, choose **Begin**, then follow **Find your tag**.
   If you skipped onboarding, use **Jacket > Pair your tag**.
3. Take the tag out of the cuff. Hold its button for about **four seconds**
   until the light pulses, then select it from the nearby-tags list.
4. Wait for **Connected**, then snap the tag securely into the cuff.
   The app should show attached gear, not just a connected tag.
5. Try the four gestures during **Gesture school**.
6. Leave Practice mode off when you want gestures to perform actions.

Advertising can stop after about a minute. Hold the button again if needed.
Scanning now waits for Bluetooth to become ready and resumes after a Bluetooth
power cycle while the pairing screen remains open.

If pairing fails, check Bluetooth permission and charge first. If the tag has
forgotten the phone, forget its old entry in **iOS Settings > Bluetooth** and
pair again. Avoid factory resets or speculative firmware flashes.

The app saves the paired identifier and attempts reconnection. Do not routinely
force-quit it: that can prevent iOS from relaunching it for Bluetooth events.

## Everyday controls

These are the initial **Everyday** profile mappings. Change them under **Gestures**.

| Sleeve gesture | Action |
|---|---|
| Double Tap | Play/pause |
| Brush In | Skip forward 30 seconds in CuffTag podcasts; next Apple Music track |
| Brush Out | Back 15 seconds in CuffTag podcasts; restart/previous Apple Music track |
| Cover | Say what's playing, after the Cover-chord window |
| Cover, then Double Tap | Bookmark the current CuffTag podcast position |
| Cover, then Brush In | Volume up |
| Cover, then Brush Out | Volume down |

With Cover chords enabled, make the second gesture within about **1.4 seconds**.
Turn that option off if you prefer Cover to act immediately. Ride and Focus
profiles have their own mappings.

Brush Up and Brush Down are **experimental**, not additional gestures confirmed
for this jacket. Alerts are outgoing vibrations/lights, not an input gesture.
The tag must be in the cuff for sleeve haptics; the tag itself provides the LED.

On-screen practice tiles simulate gestures. Seeing one in the recent-gesture
list after tapping a tile does not prove that the jacket reported it.

### Replay the demo and see the threads respond

Use **Jacket > Settings > Replay introduction** to revisit the opening experience,
or **Jacket > Gesture school** to jump straight to practice. **Start over** resets
the demo to its opening screen; **Try again** clears the practice checkmarks and
thread feedback. The completion screen also offers **Try gestures again**.
None of these controls forgets your tag or resets profiles, Shortcuts or mappings.
You can choose **Try without a tag** on the pairing step.

The sleeve illustration responds to both recognized jacket gestures and phone
touches: swipe left for Brush In, right for Brush Out, double tap for ripples,
or touch and hold for about half a second to preview Cover lighting all the threads.
These interactions work in the introduction, Gesture school and the Jacket tab.
Vertical drags still scroll the page; VoiceOver offers named preview actions.

Feedback is labeled **Jacket** or **Preview** in the demo. This is an illustration
of a recognized gesture, not a live sensor map of individual conductive threads.
Image previews never run mapped actions or get added to jacket history. While
the demo is open, real jacket gestures also only confirm and animate; closing it
restores normal behavior and leaves your previous Practice mode setting intact.
Outside the demo, the existing gesture tiles still run their mapped actions
unless Practice mode is on; their history entries are labeled **On-screen**.

## Podcasts and Apple Music

- **Podcasts > + / Add a show:** search for a public podcast or enter its RSS feed.
  Start an episode in CuffTag, then use the sleeve. The player supports progress,
  playback speed, skipping and timestamp bookmarks.
- **Jacket > Settings > Media gestures control:** choose Podcasts or Apple Music.
  Start a track in Apple's Music app and grant media-library permission if requested.
  The selected source can also follow playback activity.

CuffTag does **not** remotely control the Apple Podcasts app, import its private
library or sync its listening position. It has its own podcast player because
iOS does not provide a general public API for controlling another podcast app.
The same limitation applies to Spotify. Public podcast feeds normally provide
the same episodes, but subscriptions and listening history are separate.

Background playback, Apple Music commands and system-volume changes need testing
on your iPhone and audio route. The presence of the Bluetooth/audio background
modes is not a guarantee of unrestricted background execution.

## Shortcuts, including Segway Mobility

You can assign a gesture to any installed, runnable Shortcut by its **exact name**.
The app cannot enumerate or silently install your personal Shortcuts.

### Open Segway before your ride

For the simplest version:

1. In Apple's Shortcuts app, create **Start my ride**.
2. Add **Open App**, select **Segway Mobility**, and run it once manually.
3. In CuffTag's **Gestures** tab, choose a profile and gesture, for example Brush In.
4. Select **Run a Shortcut** and enter `Start my ride`.
5. Leave **Return to CuffTag when finished** off.

Choosing a gesture replaces that gesture's existing mapping in the selected
profile. You can use a Cover chord instead if you want to keep its media action.

The shared [I'm riding my Segway shortcut](https://www.icloud.com/shortcuts/053b1b68c1d94e319022ef902942970c)
is also supported: add it in Shortcuts and use `I'm riding my Segway` as the name.
The action picker has a button to fill in that name and a link to review the shortcut.
It does not install or execute it automatically.

Inspection of the shared shortcut found these actions: open Segway Mobility,
start a workout, ask for a playback destination, get the current song, ask for a
listening mode, and set volume to approximately **85%**. Review the workout/audio
actions, prompts, device requirements and volume before using it. If you only
want to open Segway, the simple version above is enough.

**Important iOS limits:**

- With CuffTag on screen, a gesture can open Shortcuts and request the shortcut.
- With CuffTag in the background or the phone locked, the gesture requests a
  notification. **Tap it**, and unlock if asked, to run the shortcut.
- Allow CuffTag notifications. Focus, notification settings and iOS background
  scheduling can delay or suppress the visible alert.
- Opening Shortcuts successfully does not prove the named shortcut exists or
  that every action completed. Test it manually first.
- A Shortcut that opens an app cannot bypass the lock screen. Webhooks do not
  remove this restriction.
- Once Segway is foreground, CuffTag is background: another sleeve-triggered
  Shortcut uses the notification path.

Configure and use pre-ride actions while stopped. Opening Segway does not itself
unlock or operate the scooter.

### Shortcuts can signal the jacket, too

Under Shortcuts actions, look for **CuffTag**. Actions include **Signal My Jacket**,
**Get Jacket Battery**, **Set Gesture Profile**, podcast commands and opening
Sleeve Camera. The **Alerts** tab contains personal-automation recipes.

For example, a supported Message automation can invoke **Signal My Jacket**.
CuffTag cannot read other apps' notifications. These actions still need
Bluetooth permission, a reachable compatible tag and sufficient time granted by iOS.

## Sleeve Camera

Open **Sleeve Camera** from the Jacket tab, or map a gesture to **Open Sleeve Camera**.
Keep CuffTag's camera visible and the phone unlocked.

| Gesture while Sleeve Camera is open | Action |
|---|---|
| Double Tap | Take a photo |
| Brush In | Flip front/back camera |
| Brush Out | Start/stop video |
| Cover | Cycle timer: off, 3 seconds, 10 seconds |

Allow Camera and Photos access; allow Microphone for video sound.
Captures are saved to Photos. A failed save shows an error and offers **Retry save**
or an explicit **Discard** action. Resolve an unsaved capture before closing the
app: pending photos are held in memory and videos in temporary storage, not a
durable backup.

This controls the camera **inside CuffTag**, not Apple's Camera app, and cannot
take pictures while locked or silently start filming in the background.

## Firmware: no updates or flashing

The app uses the firmware already installed on the tag. **It does not update,
downgrade, replace or recover firmware.** Settings displays the connected tag's
reported version when the SDK provides it.

The upstream SDK forces a cloud update for versions on its known-bad-firmware
list, including 1.0.6 and 1.1.0. This local SDK copy skips that connection-time
update gate because the old Google firmware service is discontinued.

That change only allows a connection attempt. It **does not fix those firmware
versions**, guarantee compatibility, or make a never-updated retail tag usable.
A tag that genuinely needs different firmware may remain unsupported.

The change is in:

```text
JacquardSDKiOS/JacquardSDK/Classes/Internal/Connection/TagConnectionStateMachine.swift
```

`CuffTag/sdk-offline-firmware.patch` records the SDK modification.
Do not install random firmware or factory-reset a working tag hoping the app
can restore it. A future updater would require a verified image for the exact
hardware, a verified update procedure and a recovery plan.

## First real-device check

Before relying on the jacket:

1. Confirm Connected, attached gear and a battery reading.
2. Physically perform each of the four gestures, without tapping the practice tiles.
   Confirm they appear under Recently.
3. Play a podcast in CuffTag. Check play/pause and both skips, then repeat with the
   screen locked and headphones connected.
4. Test Apple Music separately, including background behavior.
5. Test the tag light and cuff vibration.
6. Run your chosen Shortcut manually, then from a sleeve gesture in foreground,
   then through the background notification.
7. Take a photo and a short video in Sleeve Camera. Confirm they actually appear
   in Photos and that video audio matches the granted permissions.
8. Move out of Bluetooth range and return. Confirm reconnection and gesture delivery.

If a check fails, note the iPhone/iOS version, tag firmware, connection status,
whether the tag was in the cuff, whether the phone was locked, and the exact error.

## Developer commands

Run these from `CuffTag/`.

The visual system is intentionally dark and portrait-only for iPhone: indigo
denim, copper controls and cyan sleeve feedback. Display text uses scalable
system serif styles; controls and body copy use system text styles. Accessibility
text sizes switch dense layouts to single columns or vertical stacks. Reduce
Motion keeps sleeve/status feedback static instead of continuously animating it,
and Reduce Transparency makes stitched cards opaque.

The checked-in/generated project is ready to open. If changing `project.yml` or
adding source files, regenerate it with [XcodeGen](https://github.com/yonaskolb/XcodeGen):

```sh
xcodegen generate
```

`project.yml` is the project source of truth. Persist bundle-ID/team changes there
if you intend to regenerate, or Xcode-only edits may be replaced.

Build for iPhone without signing (compile check, not an installable build):

```sh
xcodebuild -project CuffTag.xcodeproj -scheme CuffTag \
  -destination 'generic/platform=iOS' CODE_SIGNING_ALLOWED=NO build
```

Run tests with an installed simulator. Replace `YOUR_SIMULATOR_UDID` with an ID
from `xcrun simctl list devices available`:

```sh
xcodebuild test -project CuffTag.xcodeproj -scheme CuffTag \
  -destination 'platform=iOS Simulator,id=YOUR_SIMULATOR_UDID' \
  -parallel-testing-enabled NO CODE_SIGNING_ALLOWED=NO
```

For just the design regression suite, add
`-only-testing:CuffTagUITests`. Use a dedicated simulator: the UI tests
change the active profile icon and exercise onboarding. Screenshots are retained
in the test result bundle. Before release, also check VoiceOver traversal on a
real iPhone and camera controls over bright and dark scenes; simulator tests do
not certify complete accessibility conformance.

The app icon (light, dark and tinted) is generated by `AppIcon/make_icon.swift`.
To change it, edit the script, then regenerate the PNGs in the asset catalog
(needs [resvg](https://github.com/linebender/resvg): `brew install resvg`):

```sh
swift AppIcon/make_icon.swift
```

The SDK retains its upstream Apache 2.0 license in `JacquardSDKiOS/LICENSE`.
This is not an official Google, Levi's, Apple or Segway app.
