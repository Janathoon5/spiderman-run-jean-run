# Roadmap

Solo dev, coding background but new to Roblox/Luau, aiming to actually ship.
Plan targets a minimal playable prototype first, then expands only once the
core loop is proven fun.

## The game

A round-based hunter/runner game. One player is the **Runner**, hiding among
a crowd of NPCs and able to jump between them. Everyone else hunts her.

**Roles**

| Role | Count | Abilities |
|---|---|---|
| Runner (Jean) | 1 | Jump into a nearby NPC; act as that NPC; claim objectives |
| Tracker (Spider-Man) | 1 | Everything an Agent has, plus traversal mobility and 2 area-sense pings per round |
| Agent (Damage Control) | rest | One inhibitor chip, recovered from the field after a wrong guess |

Nobody is eliminated. A wrong chip costs a retrieval trip, not the round.
The Tracker's mobility means he completes that trip far faster than an agent
can — which is where the "elite hunter" role comes from, rather than any
special rule.

**Win conditions**

- Runner wins: claims 3 objective sites before the timer expires.
- Hunters win: the chip fully attaches to the Runner, **or** the timer
  expires with objectives unclaimed.

The timer pressures the Runner, not the hunters — she has to leave cover and
take risks, and hunters have sites worth watching.

**The loop:** hunters can't tell the Runner from ~35 civilians, so they read
behavior — who broke their route, who stopped where nobody stops. Chipping is
both accusation and probe: guess wrong and you lose tempo, guess right and
she may escape the hold, but now everyone knows where she was.

## IP consideration — decide now, not later

The current framing (Spider-Man: Brand New Day, Damage Control, Jean Grey)
uses characters from two active Marvel franchises and is pitched as a movie
tie-in. Roblox actively moderates this, and a tie-in to a current release is
*more* likely to be flagged than a generic borrowed name — there's also no
realistic path to licensing as a solo dev, so this is rename-or-don't-ship.

None of the design depends on it. Build under original names from day one
and keep the Marvel framing as a private playtest skin only:

| Marvel framing | Original |
|---|---|
| Jean Grey | psychic fugitive who body-hops |
| Damage Control | containment agency |
| Spider-Man | enhanced tracker with a sixth sense |
| Inhibitor chip | suppressor / dampener |

Renaming now costs nothing. Renaming at Phase 3 means churn across the repo
name, place name, UI strings, and every asset.

## Design spec — starting numbers

First-pass guesses so playtests have a baseline to tune from. All of these
should live in one config module so they can be changed without hunting
through scripts.

| Knob | Start at |
|---|---|
| Round length | 5:00 |
| Lobby size | min 4, target 8–12 |
| NPC count | ~35 |
| Objective sites on map | 7–8 |
| Objectives needed to win | 3 |
| Objective claim time | 8–10s, standing at the site |
| Runner jump cooldown | 15s |
| Runner jump range | ~20 studs |
| Jump tell radius | visible/audible within ~40 studs |
| Chips per hunter | 1 |
| Chip hold-to-attach | 3s, Runner can break out |
| Chip retrieval lockout | 45s before it can be collected |
| Chip retrieval | instant on touch |
| Hard cap on chip uses per round | 8 (safety net, see below) |
| Tracker area-sense | 2 uses per round, coarse region |

### The chip is a physical object, not a cooldown

A hunter carries **one** chip. Attaching it to the wrong civilian leaves it
stuck to that NPC — to accuse again, they have to walk back and collect it.
There is no cooldown system; the inventory is the limiter.

This is an *active* cost rather than a passive timer, and it scales with how
recklessly the chip was spent — a wrong guess across the map hurts more than
one nearby. The NPC also keeps walking its route during the lockout, so it
has wandered by the time it can be collected. The cost generates itself.

**Two requirements or this breaks:**

- **The 45s lockout is load-bearing.** Without it a hunter simply picks the
  chip back up off the civilian they're standing next to, and the limiter
  does nothing.
- **Chipped NPCs must be findable** — glow plus a HUD marker, and retrieval
  instant on touch. The intent is "grab it as I pass on patrol," not "stop
  and search for my own chip." Tedium is the main risk in this mechanic.

### Chip budget

Total accusations across the round must stay **under** the NPC count, or
hunters brute-force the crowd and the Runner cannot win:

```
3s hold + 45s lockout + travel to find it  ≈  60s+ per attempt
300s round ÷ 60s × ~6 agents  ≈  ~30 attempts vs 35 NPCs
```

That lands in the right zone on its own, but the ratio is coupled to lobby
size, NPC count, map size, and round length — recheck it whenever any of
those move. **This is the first thing to look at if the Runner never wins.**
The per-round hard cap exists as a backstop if the math drifts in playtests.

### Marking, and the tradeoff it creates

A chipped civilian is visibly marked for as long as the chip is on it, and
the Runner **cannot jump into a marked NPC**. Since collecting a chip also
un-marks that NPC, hunters face a real choice: pull chips back to keep
accusing, or leave them in the field to shrink the Runner's hiding space.
No dominant answer, and it costs nothing to build — it's just the
consequence of the two rules above.

## Design decisions — settled

- **Runner objectives.** Claim any 3 of 7–8 scattered sites to win. More
  sites than needed so hunters can't camp them all. Claiming happens *while
  possessing* — stand at the site ~8–10s — which reads as an NPC parked off
  its route, and hooks the win condition straight into the behavior-reading
  loop.
- **No elimination.** Nobody sits in spectator. A wrong chip costs a
  retrieval trip instead of the round, and that trip routes the agent back
  through the crowd — downtime becomes observation rather than a timer.
- **Hold-to-attach.** Chipping takes a 3s hold. The Runner can break out
  mid-hold — but breaking out reveals she was there. This makes every chip a
  probe that yields information whether or not it lands, which is why there's
  no separate scanner ability.
- **Tracker differentiation.** Traversal mobility (grapple/swing, rooftops,
  fast repositioning) plus 2 coarse area pings per round. Mobility, not
  information, is what makes the role distinct — he's the one who can
  actually respond when someone flushes her across the map.
- **NPC behavior.** Each civilian has a distinct look and a fixed, robotic
  route — walks a set path, pauses at set points. Readable enough that
  deviation is noticeable. The Runner chooses per moment: mimic the route
  (safe, slow, no progress) or move freely (fast, suspicious). Waypoint loops
  are also far cheaper than live pathfinding, so this is the performance-safe
  choice too.
- **Role rotation.** Track who has played Runner and weight assignment
  against it. Runner is the most-wanted seat and only one player gets it.

## Open design decisions

- [ ] **Sense counterplay.** Does jumping scramble or delay the Tracker's
      next ping? Less urgent now that it's only 2 uses, but worth a look if
      the Tracker feels oppressive in playtests.
- [ ] **Minimum viable lobby.** What happens at 2–3 players? Fill hunter
      slots with bots, or refuse to start? A round-based game with no players
      can't start rounds, and that kills more Roblox games than bad mechanics.
- [ ] **Chip-break penalty.** When the Runner breaks out of a hold, does she
      pay anything (jump cooldown burned, brief slow) or is escaping free?
- [ ] **Runner steals chips.** Let her spend a few seconds pulling a chip off
      a civilian, denying its owner. Fits well — it punishes over-chipping
      and turns scattered chips into a resource she can farm — but it's scope.
      Park until Phase 2 and only add it if the loop asks for it.

## Phase 0 — Foundations (1–2 weeks)

- [x] Install Roblox Studio.
- [x] Install Rojo + the Rojo Studio plugin; confirm `rojo serve` syncs
      this repo's `src/` into a test place.
- [x] Pin the toolchain with Rokit so versions are reproducible
      (`rokit.toml` pins Rojo 7.7.0 — commit it).
- [x] Editor setup: Luau LSP, StyLua (formatting), selene (linting) — all
      pinned in `rokit.toml`, configured in `stylua.toml` / `selene.toml`,
      with VSCode wired up in `.vscode/settings.json` (format on save,
      sourcemap autogenerated from the Rojo project).
- [ ] Learn just enough Luau/Roblox API: Services (Players, Workspace,
      ReplicatedStorage, ServerScriptService), RemoteEvent/RemoteFunction,
      Humanoid/character basics, DataStoreService.
- [x] **Source-of-truth split — decided.** All code lives in `src/` and is
      Rojo-synced; the map lives in a committed `place/*.rbxl`. Sync is
      one-directional (disk → Studio), so the place file is the only record
      of anything built by hand in the Explorer. Never author scripts in
      Studio. Full convention in [place/README.md](place/README.md).
- [x] Prove the pipeline with a trivial script edited in VSCode, synced via
      Rojo, running in Studio play-test. *(Confirmed — `Bootstrap.server.lua`
      printed from the server on play-test.)*

## Phase 1 — Minimal Playable Prototype (4–6 weeks)

One ugly test map, core loop only, no art polish.

**Architecture rule:** server-authoritative from the first line. The client
never asserts "I possessed NPC #7" or "I chipped NPC #12" — the server
validates range, cooldown, and target validity on every action. This can't
be bolted on later without rewriting the mechanics.

- [x] Config module holding every number from the spec above.
      *(`ReplicatedStorage/Config.lua`)*
- [x] Round state machine (server-authoritative): lobby → assign roles →
      timer → win/lose → reset. *(`Round/RoundService.lua`)*
- [x] Role assignment with rotation weighting so the same player doesn't get
      Agent eight rounds running. *(`Round/RoleAssignment.lua`)*
- [x] NPC crowd: ~35 dummies on fixed waypoint routes with set pause points.
      **Visually distinct from each other** — identical NPCs make deduction
      impossible and reduce hunters to coin-flipping. Routes must be readable
      enough that a player can notice one broken. *(`Crowd/CrowdService.lua`,
      `Crowd/Civilian.lua` — reads `Workspace.CivilianRoutes` when authored,
      otherwise generates procedural loops.)*
- [x] Runner jump: proximity interact (E) on a nearby NPC, server-validated,
      on cooldown. Real character hidden while possessing. Marked NPCs are
      not valid jump targets. *(`Runner/PossessionService.lua` — she is handed
      the civilian's Model as her Character, so there is no cosmetic seam.)*
- [x] Jump tell: the sound/visual cue that leaks the jump to nearby hunters.
      This is the central balance lever — build it in Phase 1, not as polish.
      *(Filtered server-side by distance; carries position, never identity.)*
- [x] Inhibitor chip: one per hunter, 3s hold-to-attach, breakable by the
      Runner mid-hold. A wrong chip stays stuck to that civilian, marks it,
      and is collectable after a 45s lockout — with a glow + HUD marker so
      the owner can find it while it walks its route.
      *(`Hunters/ChipService.lua`)*
- [x] Tracker: traversal mobility + 2 coarse area pings per round.
      *(`Hunters/TrackerService.lua` — the ping is offset within the radius so
      repeated uses can't triangulate her.)*
- [x] Objective sites: 7–8 placed, claim any 3, ~8–10s claim while possessing,
      with claim progress visible to hunters at the site.
      *(`Runner/ObjectiveService.lua`)*
- [x] Win conditions: Runner claims 3, or chip lands, or timer expires.
      *(`RoundService.reportOutcome`, wired in `Bootstrap.server.lua`.)*
- [x] Minimal UI: role reveal, countdown, cooldown indicators, win screen.
      *(`StarterGui/HUD.client.lua`, `StarterPlayerScripts/`.)*
- [ ] **Untested.** Everything above passes selene, StyLua, and `rojo build`,
      but none of it has been run with real players yet. Next step is a
      Studio multi-client test, then friends in an unlisted place.

**Expect the time sinks to be NPC behavior and character/model swapping on
possession** — both are fiddlier in Roblox than they look.

### Fun gate

Do not start Phase 2 until: **three sessions with 5+ friends where people
ask for another round unprompted.** If that isn't happening after tuning the
numbers, the loop needs a change, not more content.

## Phase 2 — Expand & Polish

Only after the loop clears the fun gate.

- [ ] 2–3 real maps, more NPC variety/animation so blending in feels legit.
- [ ] **NPC performance budget.** Dozens of Humanoids with live
      PathfindingService will tank the server. Cap NPC count, prefer
      waypoint loops over per-frame pathfinding, disable unused Humanoid
      states, and profile with the server perf stats before adding more.
- [ ] Exploit hardening pass — this genre gets targeted, and fly/speed hacks
      break hide-and-seek instantly.
- [ ] Lobby polish: minimum player count handling, end-of-round flow.
- [ ] Sound/VFX for the jump, the chip hold, and a broken-out chip (the
      game's signature moments — the failed catch is the loud one).
- [ ] DataStore-backed stats (wins as Runner / Tracker / Agent).

## Phase 3 — Release Prep

- [ ] Confirm the rename is fully applied (repo, place, UI, assets).
- [ ] Icon, thumbnail, game page copy, short trailer clip.
- [ ] Beta group to tune the chip budget (cooldown vs NPC count), round
      length, tell radius, and objective count.
- [ ] Wire up Roblox Analytics funnel events (round start / complete / quit)
      — discovery runs on retention metrics, so server logs alone won't tell
      you what's wrong.
- [ ] Decide whether monetization exists at all in v1 (cosmetics? nothing?).
- [ ] Publish, watch metrics, iterate on balance.
