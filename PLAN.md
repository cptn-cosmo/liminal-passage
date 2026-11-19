# Liminal Passage — build plan / resume state

Status (2026-11-19): **v1.0.0 code written** in LiminalPassage/ (syntax-checked with luac/xmllint). Not yet tested in-game.
See README.md for usage. This file is the design reference.

## Research facts
- WoW Forever = Midnight retail client, TOC `## Interface: 16001` (patch 1.60.1). Retail `C_*` APIs from 12.1.5.
  Midnight addon restrictions (secret values) apply → guard with `issecretvalue`. Trial accounts can't send addon msgs.
- Scroll of Liminal Passage: item ID 213548 (SoD ID; may differ in Forever → also find by name in bags),
  mage-only, "Teleport to a party member. Both you and the target must be resting at an inn or city."
- Targeting + using items are protected → final step needs ONE hardware click (secure button / keybind).
  Invite (`C_PartyInfo.InviteUnit`) and `AcceptGroup()` can be automated.

## Files to create (LiminalPassage/)
LiminalPassage.toc, Core.lua, Comm.lua, Party.lua, UI.lua, Map.lua, MapPin.xml, Bindings.xml, README.md (repo root)

## Design
- Namespace global `LiminalPassage`; SavedVariables `LiminalPassageDB` {status="online", leaveAfter=true, itemID, positions}.
- Statuses: online (auto-accept everything), busy (StaticPopup approve each request), offline (leave channel,
  ignore all messages = as if not installed; can still search as traveler).
- Transport: hidden custom channel "LiminalPassage" (JoinTemporaryChannel, poll GetChannelName, remove from chat frames),
  prefix "LIMPASS", fields joined with "~" (strip ~ | \n).
- Messages:
  - Q~qid~mapID~text   (channel) traveler search. Host replies only if status≠offline, IsResting(), and matches
    (mapID in its map ancestry via C_Map.GetMapInfo parentMapID chain, or text substring in zone/subzone/ancestry names; empty = any).
  - P~qid~status~mapID~x~y~class~level~zone~subzone  (whisper, random 0–1.5s jitter)
  - R~rid request → host: offline ignore; D if combat/notresting/grouped(non-leader)/full; busy → W~rid + popup; online → accept.
  - A~rid~hostState (solo|lead|same): solo → traveler invites; lead → traveler sends I~rid, host invites; same → arm.
  - D~rid~reason, W~rid (waiting approval), I~rid, C~rid (cancel), T~rid (done).
- Host stores hostPending[sender] (90–120s) → PARTY_INVITE_REQUEST auto AcceptGroup + StaticPopup_Hide("PARTY_INVITE").
  Traveler auto-accepts only from target when state=="awaitinvite". 5s per-sender request cooldown.
- GROUP_ROSTER_UPDATE: when target in group → ArmButton: standalone secure button `LiminalPassageUseButton`
  (SecureActionButtonTemplate, parent UIParent, type=macro, macrotext "/target Name\n/use item:ID",
  RegisterForClicks("AnyUp","AnyDown"), shift-type* disabled for shift-drag moving). Defer arm/disarm to PLAYER_REGEN_ENABLED.
- UNIT_SPELLCAST_SUCCEEDED with spell from C_Item.GetItemSpell(itemID) → done, send T, after 5s LeaveParty if we created the group and leaveAfter.
- Search point/distance: C_Map.GetWorldPosFromMapPos / GetMapPosFromWorldPos, sort results by yards.
- UI: BasicFrameTemplateWithInset window: status buttons (Online/Busy/Offline + description), search editbox + Search/Anywhere/Map,
  scrolling result rows (class-colored name, level, zone–subzone, distance, status, Teleport/Ask button),
  travel status + Cancel, "Leave group after teleport" checkbox, scroll count. ESC closes (UISpecialFrames).
- Map: button on WorldMapFrame.ScrollContainer "Liminal: search here" (current map); Alt+Click (capture on OnMouseDown before nav)
  = point search; MapCanvasDataProviderMixin provider + pin template (mixin defined in Map.lua before MapPin.xml) showing results,
  click pin = request. Setup after Blizzard_WorldMap loaded.
- Bindings.xml: toggle window + "CLICK LiminalPassageUseButton:LeftButton". Addon compartment func. Slash /lp, /liminal
  (online|busy|offline|search <text>|item <id>|cancel|help).
