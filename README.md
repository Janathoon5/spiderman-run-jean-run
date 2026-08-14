# Spiderman Run Jean Run (working title)

A Roblox hide-and-seek game: one player is the hunted character, able to "jump"
between NPCs to blend in and evade capture, while the rest of the players
(seekers) try to find and tag her before time runs out.

> **Naming note:** "Spiderman Run Jean Run" is a working title using
> licensed Marvel characters (Spider-Man, Jean Grey). Roblox moderates
> games built around unlicensed third-party IP, so before publishing this
> should either be renamed to an original character/concept, or the
> licensing question should be resolved. See ROADMAP.md.

## Project structure

This is a [Rojo](https://rojo.space) project, so the game is written as
plain files here and synced into Roblox Studio, with git for version
control (same workflow as the dental_office project).

```
src/
  ReplicatedStorage/     shared modules/events (client + server)
  ServerScriptService/   server-only game logic
  StarterPlayerScripts/  client-only scripts
  StarterGui/            UI
default.project.json     Rojo project/tree mapping
```

## Setup (not done yet)

1. Install [Roblox Studio](https://www.roblox.com/create).
2. Install Rojo, either via Aftman (`aftman add rojo-rbx/rojo`) or the
   standalone installer from rojo.space.
3. Install the matching **Rojo Studio plugin** (from the Roblox plugin
   marketplace) so Studio can connect to `rojo serve`.
4. From this folder: `rojo serve` — then connect from the Studio plugin.

See ROADMAP.md for the phased build plan.
