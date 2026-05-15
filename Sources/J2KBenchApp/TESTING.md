# Helping us benchmark J2K Bench on your iPhone

Thank you for running this! 🪔

We're measuring how fast our JPEG-2000 codec runs across the
different Apple chips (M2 Mac, M4 Mac, A17 Pro iPhone, A18 Pro iPhone,
…). It takes ~3–7 minutes on a recent iPhone. We'd love a reading
from your phone before/during Diwali so we can plot the
cross-silicon comparison.

## What you'll need

* Your iPhone (any model running iOS 18 or later)
* A Mac with Xcode 26+ installed
* The same Apple ID signed in to **iCloud on the iPhone** and
  **Xcode → Settings → Accounts on the Mac** (any Apple ID works,
  no paid developer membership needed — free Apple IDs get a
  "Personal Team" that's good for 7-day app installs)
* A USB-C / Lightning cable

## Step-by-step

### 1. Get the code

```bash
git clone --branch v10.5-research https://github.com/Raster-Lab/J2KSwift.git
cd J2KSwift
```

If you don't have command-line access, ask whoever sent you this for
a zip of the repo.

### 2. Open the bench app

Open this file in Finder:

```
Sources/J2KBenchApp/J2KBenchApp.xcodeproj
```

Double-click it. Xcode will open the project. Wait for the
"Resolving Package Graph" spinner at the top to finish.

### 3. Pick your signing team

In the leftmost pane (Project Navigator), at the very top, click the
blue Xcode-document icon labelled **`J2KBenchApp`**.

The middle pane now shows two sections: **PROJECT** and **TARGETS**.
Click **`J2KBenchApp`** under **TARGETS** (the second occurrence).

The right pane shows tabs across the top. Click
**Signing & Capabilities**.

* Tick **Automatically manage signing** if not already ticked.
* In the **Team** dropdown, pick your Apple ID's team (it'll show as
  your name with "(Personal Team)" suffix for free Apple IDs).
* If Xcode complains the bundle ID is already taken, edit the
  **Bundle Identifier** field to anything unique, e.g. add your
  initials to the end:
  `in.raster.j2k.bench.<yourinitials>`.

When the red error indicator next to the tab clears, you're ready.

### 4. Plug in your iPhone + Run

1. Unlock your iPhone and plug it into the Mac with a cable.
2. If iOS asks "Trust This Computer?" on the iPhone, tap **Trust**
   and enter your passcode.
3. At the top of the Xcode window, click the device picker (the box
   that says "iPhone 17 Pro" or similar) and pick your iPhone from
   the list.
4. Press **⌘ R** (or click the ▶ button at the top-left). Xcode
   builds + installs the app. Takes ~2 minutes the first time.
5. The first time you launch, iOS will refuse to run it with
   "Untrusted Developer". On the iPhone, go to
   **Settings → General → VPN & Device Management** → tap your
   Apple ID under "Developer App" → **Trust**.
6. Re-launch the app by tapping its icon on the home screen
   (looks like the J2K logo with a wavelet underneath).

### 5. Run the benchmark

* Inside the app, tap **▶ Run Benchmark**.
* Leave the app in the foreground. The screen will dim eventually
  but the bench keeps running.
* The progress bar fills as each fixture completes. Total time is
  about 3–7 minutes depending on your model. For best results,
  plug the iPhone into a charger first so it doesn't throttle.
* When the progress bar reaches the end, you'll see "Done — N
  fixtures".

### 6. Share the JSON back

* Tap **↑ Share JSON**.
* Pick **AirDrop** (if your Mac is nearby), **Mail**, or **Messages**.
* Send it to the person who asked you to run this. The file name is
  something like `benchmark-results-iPhone17,1-10.1.0-warm-inproc-20261108.json`.

That's it! Thank you for helping. 🙏

## Troubleshooting

**"Could not launch — The executable is not codesigned"**
You skipped picking a Team in step 3. Go back to Signing &
Capabilities and pick one.

**"No profiles for ... were found"**
Same issue — bundle ID is taken on Apple's portal. Edit the Bundle
Identifier in the Signing tab to something unique.

**Bench hangs at one fixture for >2 minutes**
Some older phones / hot phones slow down on the largest fixtures
(the mammography-class ones at the end). Wait it out — the bench is
running, just slowly.

**App crashes or shows red errors**
Take a screenshot of the error and send it to the project team
along with your iPhone model + iOS version. We'll dig into it.

**I want to run it again later**
Apps installed via a free Personal Team expire after 7 days. Just
plug in the iPhone, open the xcodeproj, and hit Run again. Paid
developer team installs last a year.

## What gets measured

* 7 small/mid medical-image-shaped synthetic fixtures (256² up to
  1024×1280)
* 3 large mammography-class fixtures (DX 2544×3056, MG 3520×4784)
* For each: encode + 3 decode modes (CPU, GPU, GPU-HT), 7 timed runs
  after 2 warmups, median reported

The bench is purely in-process (no network calls, no telemetry).
The JSON contains only timings, your device model identifier
(e.g. "iPhone17,1"), iOS version, and the J2K library version.
Nothing else.
