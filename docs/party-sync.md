# Party Sync — Bidirectional Multi-Account Sync

**Goal**: Allow a user with multiple WoW accounts in a party to sync all character rating data bidirectionally with one button press in the Settings tab (or `/nxr sync`), using WoW's addon messaging API, so all accounts end up with a merged union of character data.

---

## Story 1 — Party Sync

### Acceptance Criteria

**New module**
- [ ] New file `Sync.lua` added to the project and loaded in `NelxRated.toc` after `Core.lua` and after `ImportExportUI.lua` (depends on merge logic)
- [ ] `Sync.lua` registers the addon message prefix `"NXR_SYNC"` via `C_ChatInfo.RegisterAddonMessagePrefix("NXR_SYNC")` on `PLAYER_LOGIN`
- [ ] All sync state is local to `Sync.lua`; public surface is `NXR.InitiateSync()` and `NXR.GetSyncStatus()` only

**Slash command**
- [ ] `/nxr sync` triggers `NXR.InitiateSync()`; added alongside existing slash handling in `Core.lua` or wherever slash commands are dispatched

**Chunking / reassembly**
- [ ] Outbound payload is character data serialized using the existing v2 character serialization format (same shape as `ImportExportUI.lua` `SerializeCharacters` output)
- [ ] Payload split into chunks of 200 bytes or fewer (leaving headroom under the 255-byte `C_ChatInfo.SendAddonMessage` limit for prefix and chunk header)
- [ ] Each chunk sent as a single `C_ChatInfo.SendAddonMessage("NXR_SYNC", chunkStr, "PARTY")` call
- [ ] Chunk format: `"CHUNK:<sessionID>:<chunkIndex>/<totalChunks>:<data>"` where `sessionID` is a unique string per sync initiation (e.g. `tostring(time()) .. "-" .. tostring(math.random(10000,99999))`)
- [ ] Receiver accumulates chunks keyed by `sessionID` + sender name; reassembles when `chunkIndex == totalChunks`
- [ ] Incomplete chunk sets older than 30 seconds are discarded from the reassembly buffer

**Sync protocol**
- [ ] Initiator sends its full character chunk sequence to `"PARTY"` channel
- [ ] Any NXR instance in the party that receives a complete chunk set from sender X:
  1. Merges received character data via `MergeCharacters` (reusing existing logic from `ImportExportUI.lua`)
  2. Sends its own full character chunk sequence back to `"PARTY"` channel
- [ ] Initiator listens for responses and merges each complete incoming chunk set via `MergeCharacters`
- [ ] Addon ignores its own messages (compare sender against current character key `Name-Realm`)
- [ ] If initiator is not in a party when sync is triggered, show status `"Not in a party. Join a party with your other accounts first."` and do not transmit

**Merge behavior**
- [ ] Received character data merged using existing `MergeCharacterData` per-character, per-bracket logic — `updatedAt` on each bracket entry determines winner (higher timestamp kept)
- [ ] Merge never replaces a full character entry wholesale — always calls `MergeCharacterData` for existing keys (same guarantee as import merge, lint rule D2)
- [ ] After each successful merge, refresh overlay and any open UI panels

**syncPartners storage**
- [ ] `NelxRatedDB.syncPartners` initialized as `{}` in `InitDB()` if not present
- [ ] After successful merge from sender X, upsert sender's character name into `NelxRatedDB.syncPartners`: `syncPartners[senderName] = time()`
- [ ] `syncPartners` not used for any automatic behavior — storage only, for future whisper sync feature

**Settings tab UI**
- [ ] A "Party Sync" section added to `SettingsUI.lua` scroll content, below existing settings sections, with section header styled `GameFontNormal`, `TEXT_TITLE` color
- [ ] A button labeled `"Sync"` (`BTN_H` height, 80px wide) calls `NXR.InitiateSync()` on click
- [ ] A FontString below the button shows sync status, updated by `NXR.UpdateSyncStatusUI()`:
  - Before any sync this session: `""` (empty)
  - While waiting for responses (up to 5 seconds after sending): `"Syncing…"`
  - After sync completes: `"Synced with N partner(s)"` where N = count of unique senders that responded this session
  - If not in party: `"Not in a party."` (shown immediately, no transmission)
- [ ] Informational states use `TEXT_BODY` color; not-in-party error uses `CRIMSON_BRIGHT` color
- [ ] Status text does not persist across reloads (session-only, no storage)

---

## Out of Scope

- Auto-sync on login or any event-driven automatic sync
- Whisper-based sync or online partner detection
- Delta sync — always full character data
- Cross-guild or cross-realm messaging channels
- Syncing challenges, settings, or any data other than `NelxRatedDB.characters`
- Any UI outside the Settings tab
