# Working in this repository

Several Claude sessions work here at once, usually one per mod. To keep out of each other's way:

- **Stay in your mod's folder** (`mods/<mod>/`, plus `listings/<mod>/`). Changes to another mod's files, to
  `shared/`, `tools/` or `.github/` are made by the session that owns them, or after the user agrees.
- **Commit only your own paths** (`git add mods/<mod> listings/<mod>`, never `git add -A` at the root), and
  only when the user asks.
- **`shared/settingspanel/` belongs to the Frame Mage session.** Other mods use it as it is and send requests
  through a handoff document.
- **Text:** American English in prose and code; the game's own names stay as they are.
- **Releases:** a tag `<mod>-v<version>` releases one mod. Players get no developer tools: dumps, probes,
  developer hotkeys and the banner outside Frame Mage's editor live in each mod's `dev/` folder, which releases
  never contain. Shipping code never `require`s anything in `dev/` (each mod's tests check this); a helper both
  need belongs in the mod's own code. `shared/` is built into every release, so it's no place for developer code.
- **Line endings:** files are stored with LF (`.gitattributes`).
