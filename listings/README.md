# Listings

What each mod's pages on Nexus Mods and CurseForge show, kept with the code so it changes with it. One folder per
mod, named like its folder under `mods/`. Nothing here is built into a mod's zip.

```
listings/<mod>/
  summary.txt     the one-line summary both sites ask for (plain text)
  description.md  the full description, in Markdown (CurseForge takes Markdown; Nexus Mods takes BBCode,
                  converted from this file when pasting)
  changelog.md    what changed in each release, newest first
  images/         the logo, the header or cover image, and promotional art (generated or drawn)
  screenshots/    in-game screenshots showing what the mod does, named for what they show
                  (inventory-elven-theme.png, editor-moving-the-compass.png)
```

Each site's image sizes change from time to time: check its upload page when making images for it, and note
the sizes used in the image's file name (logo-400x400.png, header-1920x1080.png).

Media that's only a draft or a source (layered files, unused generations) stays out of the repository: keep the
finished images only.
