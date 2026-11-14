# Working in this repository

Several Claude sessions work here at once, usually one per mod. To keep out of each other's way:

- **Stay in your mod's folder** (`mods/<mod>/`, plus `listings/<mod>/`). Changes to another mod's files, to
  `shared/`, `tools/` or `.github/` are made by the session that owns them, or after the user agrees.
- **Commit only your own paths** (`git add mods/<mod> listings/<mod>`, never `git add -A` at the root), and
  only when the user asks.
- **`shared/settingspanel/` belongs to the Frame Mage session.** Other mods use it as it is and send requests
  through a handoff document.
- **Text:** American English in prose and code; the game's own names stay as they are.
- **Releases:** a tag `<mod>-v<version>` releases one mod. Frame Mage's distribution builds turn off its
  on-screen banners and developer hotkeys (see `mods/framemage/docs/HANDOFF.md`).
- **Line endings:** files are stored with LF (`.gitattributes`).
