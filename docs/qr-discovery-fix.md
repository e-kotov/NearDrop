# Personal fork: QR discovery update fix

Android can advertise its Bonjour service before the QR scan and then change
that service's TXT record to include QR information. Upstream handles additions
and removals but ignores changes. This branch reprocesses the new record,
refreshes the device entry, and starts at most one automatic transfer per QR key.
The share extension updates existing rows and ignores callbacks after a device
has been selected or the QR sheet has closed.

This is a targeted fix for a plausible cause of intermittent waiting after a QR
scan. It does not establish that every Samsung connection failure has that cause.
It preserves upstream sandbox entitlements and the existing QR workflow.

## Build on a Mac

Xcode 27 requires a deployment target of macOS 12 or later. The build override
below leaves upstream project settings and locked package versions unchanged.
Keep build products and package checkouts outside the source checkout:

```sh
mkdir -p "$HOME/tmp/neardrop-build"
xcodebuild -project NearDrop.xcodeproj -scheme NearDrop \
  -configuration Release -destination 'platform=macOS,arch=arm64' \
  -derivedDataPath "$HOME/tmp/neardrop-build/DerivedData" \
  -clonedSourcePackagesDirPath "$HOME/tmp/neardrop-build/SourcePackages" \
  -onlyUsePackageVersionsFromResolvedFile \
  CODE_SIGNING_ALLOWED=NO MACOSX_DEPLOYMENT_TARGET=12.0 \
  ARCHS=arm64 ONLY_ACTIVE_ARCH=YES ENABLE_TESTABILITY=YES build
scripts/check-discovery-updates.sh \
  "$HOME/tmp/neardrop-build/DerivedData/Build/Products/Release"
```

The integration check uses real local Bonjour TXT updates and the production
discovery handler. An internal service-filter dependency lets the fixture accept
only its own local announcement; the app retains its default loopback filter.
The check sends no files and connects to no phone. It covers initial discovery,
updated public names, QR matching after a TXT update, repeated update suppression,
a fresh QR session on the same endpoint, private-name decryption, and removal.
It also verifies that actual metadata-change events occurred. This check requires
local Bonjour operation; an environmental discovery failure is a failed check.

The unsigned build needs code signing before distribution or use. Sign the nested
library copies first, then the share extension with its original entitlements,
then the main app with its original entitlements. Ad-hoc signing is sufficient
for a local test build; it does not provide Apple Developer ID verification or
notarization. This branch introduces no automatic updater.

## Phone trial

Use the built app as the sole installed NearDrop copy, so Finder uses the intended
share extension. Quit the old app before replacing it. This branch does not
automatically install or replace an existing copy.

Try several transfers in both situations: open NearDrop sharing before opening
receiving on the phone, and open it while the phone is already advertising.
Scan each fresh QR code once. Check that the phone appears once, that sharing
starts without reopening the window, and that cancelling/reopening for the next
file still works. Also try private visibility, whose name is encrypted in the
QR advertisement. A passing local regression does not replace these phone trials.

This personal fork is maintained separately from upstream; upstream does not
accept AI-assisted contributions.
