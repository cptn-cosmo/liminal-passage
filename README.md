# Liminal Passage

A WoW Forever addon (Interface 16001). It finds other Liminal Passage users who are resting at your destination. It then groups you with one of them automatically and uses a **Scroll of Liminal Passage** on them.

## Install
Copy the `LiminalPassage/` folder into `World of Warcraft/_forever_/Interface/AddOns/`. Use the Forever client's AddOns folder if its name differs.

## Using it (traveler, needs the scroll: mage only)
1. `/lp` opens the window. You can also open it from the addon compartment or a keybind.
2. Search for a destination:
   - **Window:** type a zone, city or inn subzone (e.g. `Goldshire`) and press **Search**. **Anywhere** lists everyone who is resting.
   - **World map:** **Liminal: search here** searches the map you're looking at. **Alt+Click** a spot to search there, with results sorted by distance from that spot. Results also appear as pins, and clicking a pin requests a teleport.
3. Click **Teleport** (or **Ask** for busy players). The addon handles the request, the invite and accepting the invite.
4. Once you're grouped, a glowing scroll button appears. Click it once (or press the "Use scroll on destination player" keybind). It runs `/target <name>` and then `/use` on the scroll.
   WoW only lets an addon target a player or use an item when you click or press a key, so this one click can't be automated.
5. After the scroll is used, you leave the group automatically if the addon created it (you can turn this off).

## Status (host side)
| Status | Behaviour |
|---|---|
| **Online** (default) | You show up in searches. Requests are accepted and invites auto-accepted. |
| **Busy** | You show up in searches. Each request shows an Accept/Decline popup. |
| **Offline** | You leave the hidden channel and ignore every message, as if the addon wasn't installed. You can still search as a traveler. |

Only players who are **resting** (inn or capital city) answer searches. The scroll requires both players to be resting.

## Commands
`/lp` · `/lp online|busy|offline` · `/lp search <text>` · `/lp cancel` · `/lp item <itemID>` · `/lp resetpos`

## How it works
- Searches go out on a hidden custom channel (`LiminalPassage`) using addon messages (prefix `LIMPASS`). Hosts reply by whisper, and only when they match the search.
- Map matching: a host matches when the searched map is its current map or any parent of it. Text matching compares against the zone, subzone and parent map names.
- Grouping: if the host is solo, the traveler invites the host. If the host leads a group, the host invites the traveler. Each side auto-accepts only the invite it is expecting.
- The scroll is found by item ID (default 213548, from Season of Discovery) or by name in your bags. If it isn't detected, use `/lp item <id>`.

## Notes / limitations
- Not tested in the live Forever client yet; the code has only passed syntax checks.
- Combat: the scroll button can't appear, change or hide during combat. Changes are applied when combat ends.
- Cross-faction grouping isn't possible, so you'll only find players of your own faction.
- Trial accounts can't send addon messages in Forever.

## Releasing
Push a tag like `v1.0.1`. The **Release** workflow checks the syntax, stamps the version into the `.toc`, zips `LiminalPassage/` and publishes a GitHub release with the zip attached.
