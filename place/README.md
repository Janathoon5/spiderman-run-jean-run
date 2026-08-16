# place/

The map lives here, and it is the **only** binary file the repo tracks.

## The split

| What | Lives in | Edited with |
|---|---|---|
| All code | `src/` | VSCode, synced by Rojo |
| Map, terrain, hand-placed instances, Studio-built UI | `place/*.rbxl` | Roblox Studio directly |

Rojo sync is **one-directional: disk → Studio.** Anything built by hand in the
Studio Explorer never travels back to `src/`. That is why the place file is
tracked — it is the only record of the map.

## Working session

1. `rojo serve` from the repo root.
2. Open `place/SpidermanRunJeanRun.rbxl` in Studio.
3. Connect via the Rojo plugin. Code appears under `ServerScriptService` etc.
4. Edit code in VSCode — it hot-syncs. Edit the map in Studio.
5. **Save the place file in Studio** before committing map changes. Code
   changes are already on disk; map changes are not until you hit save.

## Rules that keep this from getting messy

- **Never author scripts in the Studio Explorer.** They will be overwritten by
  sync, or worse, silently shadow the real file. All code goes in `src/`.
- Commit the place file when the map changes. It is binary, so git cannot
  merge it — solo that is fine, but two people editing the map at once will
  lose work.
- If the place file gets large or map history becomes worth diffing, the
  upgrade path is exporting map sections as `.rbxmx` into `src/` so Rojo owns
  them too. Not worth it yet.
