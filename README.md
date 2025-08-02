## **Bear's Shit List**
_(This was previously called 'Player Notes', and has now been renamed to Shit List. All legacy commands still work)_

A Windower4 addon for Final Fantasy XI that lets you track and categorize other players based on your experiences with them. 
Whether someone helped you out or made your life harder, leave yourself a note so you remember next time you run into them.

## Features

- Add personal notes to any player with timestamps and keyword-based categorization
- Categories: **Positive** (green), **Negative** (red), **Neutral** (white)
- Auto-highlighting of player names in chat based on category
- On-screen overlays:
  - Party members with notes
  - Targeted players with notes
  - Shared database across multiple characters via a common file
- Wildcard search and filtering
- Sync updates automatically or manually
- Save overlay positions

## Commands

Prefix: `//sl`, `//shit`, `//pn`, or `//playernotes`

--add "name" "note" - Add note to player
--search "name" - Find player (wildcards supported: , name, *name)
--list <good|bad> - List players in a category
--remove "name" - Delete all notes for a player
--stats - Show summary stats
--sync - Manually sync the database
--on/off - Enable/disable addon overlays
--party on/off - Toggle party member overlay
--target on/off - Toggle target lookup
--highlight on/off - Toggle name highlighting in chat
--savepos - Save overlay positions
--help - Show command list


## Usage Examples
//sl add "Dramalord" "Aggressive and rude in party chat"
→ Adds a negative note for Dramalord

//sl search "Dramalord"
→ Shows all notes you've made for that player

//sl list good
→ Shows a list of players you've flagged positively

//sl party off
→ Turns off the party overlay temporarily

## Data Storage
Notes are saved in `Windower4/shitlist_shared.lua`, which is shared across all characters and sessions. Settings are saved per user.

## Inspired by
- Balloon’s highlight addon for name highlighting
- Windower’s built-in text overlays and party APIs

## Author
**Orangebear** (a.k.a. Bear)

---

Feel free to open an issue if you find a bug or want to suggest a feature.
