# Card identification and missing-card checks

Development branch: `kyler/dev`.

## Implemented scope

Screen keeps cards in saved discovery order and enriches their names from the
Mac's existing Wallet cache. Card identity, selection and skin file paths are
stored by the full card ID, separately for each connected iPhone. Repeated
scan events update the same item; identical display names do not merge cards.

Payment-card confirmation uses the activated secure-element application ID
from the NFC log and maps it to the exact pass ID in the matched Mac cache.
Wallet's batch resource paths can also verify existence because they are
observed in the current iPhone log, although their order does not represent
either user selection or Wallet display order. After one live payment ID
matches exactly one remote-device cache, the remaining payment IDs in that
same cache are included because iOS does not log every card consistently.

The grid contains IDs matched during the current scan. Saved records stay
hidden and are excluded from flashing until current iPhone activity identifies
the device's payment cache again:

- **Matched in this scan** means the ID was observed in a pass/cache path or
  exact activation event, or belongs to the one payment cache matched by such
  a live ID.
- **Saved IDs to confirm** includes migrated legacy IDs and manually added IDs
  that have not been scanned on this iPhone in the new version.
- **Payment entries to confirm** come from one matching remote-device cache.
  Matching requires the device model and an exact scan-confirmed card ID.
  Multiple matching devices are reported as ambiguous, rather than guessed.
- **Mac passes to confirm** are membership/ticket metadata from the Mac's local
  Wallet library. Their presence on the connected iPhone is not assumed.

Neither the scanned count nor cache count is presented as the phone's total.
Cache contents can be stale or incomplete. The app does not synchronize the
phone's actual Wallet display order; that original requirement remains deferred
under the subsequently approved, smaller scope.

## Checking a missing card

1. Connect, unlock and trust the iPhone, then choose **Scan Cards**.
2. Open each missing card in the iPhone Wallet app. Payment cards can also be
   opened through the side-button Apple Pay interface after authentication.
   Membership cards may need opening directly inside Wallet.
3. Expand **Check missing cards** to see named cache entries that still need
   scan confirmation. Short ID suffixes distinguish cards with the same name.
4. If scanning stops unexpectedly, inspect **Log**, use **Reconnect**, then
   start scanning again. The app distinguishes connection failure, scanner
   startup failure, unexpected exit and a scan with no detected IDs.
5. **Read Cache** rereads local metadata. It does not force an iCloud refresh.
   Missing or unreadable metadata leaves scanning available and displays a
   diagnostic instead of declaring that the phone has zero cards.

## Persistence and migration

Version-two records use per-device UserDefaults keys. Existing legacy stores
remain untouched and are imported as unconfirmed IDs on first use. An empty
version-two list is authoritative, so clearing cards does not reimport legacy
entries on restart. Saved images retain their file paths; if an original image
file is moved or deleted, choose it again using the unavailable-image notice.

Saved IDs may remain after a card is removed from the phone, but they are not
shown or eligible to flash unless a new scan matches their device cache again.
Screen does not use a cache based only on the phone model; it requires an exact
live card-ID overlap first.

## Validation

`python3 -m unittest discover -s tests -v` covers native log decoding, cache
parsing, malformed/cyclic archives, ambiguous devices, missing metadata, exact
ID matching, duplicate names, pending counts, repeat scanning, legacy migration,
per-device persistence, skin identity across reordering, and clear/relaunch.
All committed fixtures use synthetic identifiers.

`./script/build_and_run.sh --verify` builds the universal macOS app and DMG and
launches the local build. This feature reads local metadata and device logs;
verification does not flash card artwork or modify the phone's Wallet database.
