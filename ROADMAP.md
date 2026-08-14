# Roadmap

Solo dev, coding background but new to Roblox/Luau, aiming to actually ship.
Plan targets a minimal playable prototype first, then expands only once the
core loop is proven fun.

## IP consideration (decide before publishing)

The working title and pitch reference Spider-Man and Jean Grey, both
licensed Marvel characters. Roblox actively moderates/takes down games
built around unlicensed third-party IP. Before Phase 3 (release), either:
- Reskin to an original character (e.g. a psychic/telepathic fugitive with
  a "mind-jump" power) — same mechanics, no IP risk, or
- Resolve the licensing question some other way.

This doesn't block prototyping — the core loop is genre mechanics, not IP.

## Phase 0 — Foundations (1-2 weeks)

- [ ] Install Roblox Studio.
- [ ] Install Rojo + the Rojo Studio plugin; confirm `rojo serve` syncs
      this repo's `src/` into a test place.
- [ ] Learn just enough Luau/Roblox API: Services (Players, Workspace,
      ReplicatedStorage, ServerScriptService), RemoteEvent/RemoteFunction,
      Humanoid/character basics, DataStoreService.
- [ ] Prove the pipeline with a trivial script edited in VSCode, synced via
      Rojo, running in Studio play-test.

## Phase 1 — Minimal Playable Prototype (3-5 weeks)

One ugly test map, core loop only, no art polish.

- [ ] Round state machine (server-authoritative): lobby -> assign one
      player as the hunted role -> timer -> win/lose -> reset.
- [ ] NPC decoys: simple humanoid dummies with basic wander/patrol scripts.
- [ ] Possession/"jump" mechanic: proximity interact (E key) on a nearby
      NPC + cooldown -> server swaps which NPC the hunted player is
      puppeting; real character hidden while possessing.
- [ ] Seeker mechanic: tag/interact ability with a cooldown to "check" a
      suspected NPC.
- [ ] Win conditions: seekers correctly tag the hunted player, or she
      survives the timer.
- [ ] Minimal UI: role reveal, countdown, win screen.
- [ ] Playtest solo (Studio multi-client test), then with friends in an
      unlisted place.

## Phase 2 — Expand & Polish

Only after the loop is proven fun.

- [ ] 2-3 real maps, better NPC variety/animations so blending in feels
      legit.
- [ ] Server-side exploit hardening (this genre gets targeted by cheaters —
      fly/speed hacks defeat hide-and-seek games fast).
- [ ] Lobby polish: minimum player count, spectator mode for eliminated
      seekers.
- [ ] Sound/VFX for the possession jump (the game's signature moment).
- [ ] DataStore-backed stats (wins as hunted vs. seeker).

## Phase 3 — Release Prep

- [ ] Icon, thumbnail, game page copy, short trailer clip.
- [ ] Resolve the IP/naming question (see above).
- [ ] Small beta group to tune timer length, cooldowns, NPC count.
- [ ] Publish, watch server logs, iterate on balance.
