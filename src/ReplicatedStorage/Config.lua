--!strict
--[[
	Every tunable number in the game.

	Shared between client and server on purpose: the client needs cooldowns and
	durations to draw honest UI, and the server needs them to enforce the rules.
	The server is still the authority — the client knowing a cooldown does not
	let it skip one.

	Rule of thumb: if you would ever want to change it during a playtest, it
	belongs in this file, not buried in a script.
]]

local Config = {}

-- ---------------------------------------------------------------- round ----

Config.Round = {
	-- Seconds of actual play. The Runner must finish her objectives inside it;
	-- the timer running out is a HUNTER win, not a stalemate.
	Duration = 300,

	-- Countdown between roles being revealed and the round going live, so
	-- people can orient before anyone can act.
	StartCountdown = 10,

	-- How long the result screen holds before returning to lobby.
	EndScreenDuration = 8,

	-- Below this, the round cannot start. See the open question in ROADMAP
	-- about whether small lobbies get filled with bots instead.
	MinPlayers = 4,

	-- Above this the crowd stops being readable and hunters trip over
	-- each other. Soft target, not enforced.
	TargetPlayers = 12,
}

-- ------------------------------------------------------------------ npcs ----

Config.NPC = {
	-- Coupled to Config.Chip.RetrievalLockout — see the chip budget note
	-- below. Changing one without rechecking the other breaks balance.
	Count = 35,

	-- Civilians walk a fixed loop and pause at fixed points. Robotic on
	-- purpose: a readable pattern is what makes a broken pattern noticeable,
	-- and waypoint loops are far cheaper than live pathfinding.
	WalkSpeed = 8,
	PauseDuration = 2.5,

	-- Deviation beyond this from the expected waypoint is what a future
	-- "this one is acting odd" tell would key on.
	RouteToleranceStuds = 6,
}

-- ---------------------------------------------------------------- runner ----

Config.Runner = {
	JumpCooldown = 15,
	JumpRangeStuds = 20,

	-- How far away the jump is seen or heard. THE core balance lever: too
	-- small and hunters are coin-flipping, too large and she can never move.
	JumpTellRadiusStuds = 40,

	-- Time to break out of a chip hold. Must be under Config.Chip.HoldDuration
	-- or escaping is impossible.
	BreakoutWindow = 3,
}

-- ------------------------------------------------------------ objectives ----

Config.Objective = {
	-- More sites than needed, so hunters cannot camp them all at once.
	SitesOnMap = 8,
	RequiredToWin = 3,

	-- Claimed while possessing an NPC — which reads as a civilian standing
	-- somewhere off its route. That is the intended tell.
	ClaimDuration = 9,

	-- Leaving the site resets progress rather than banking it.
	ClaimResetsOnLeave = true,
	ClaimRadiusStuds = 12,
}

-- ------------------------------------------------------------------ chip ----

Config.Chip = {
	-- One each. The chip is a physical object, not a cooldown: a wrong guess
	-- leaves it stuck on that civilian and you have to walk back for it.
	PerHunter = 1,

	HoldDuration = 3,

	-- Cannot be collected until this elapses. LOAD-BEARING: without it a
	-- hunter just picks the chip back up off the civilian they are standing
	-- next to, and the limiter does nothing at all.
	RetrievalLockout = 45,

	-- Instant on touch. Retrieval should feel like "grab it as I pass", not
	-- "stop and search for my own chip".
	RetrievalInstant = true,

	-- A chipped civilian is visibly marked, and the Runner cannot hide in one.
	-- Collecting the chip un-marks it, which is the pull-back-vs-deny-space
	-- tradeoff.
	MarkedNPCsBlockJump = true,

	--[[
		CHIP BUDGET — the first thing to check if the Runner never wins.

		Total accusations across a round must stay UNDER Config.NPC.Count, or
		hunters brute-force the whole crowd:

			3s hold + 45s lockout + travel  ~= 60s per attempt
			300s / 60s * 6 agents           ~= 30 attempts vs 35 NPCs

		That lands right, but it is coupled to round length, agent count, NPC
		count, and map size. Recheck whenever any of those move.
	]]
	HardCapPerRoundPerHunter = 8,
}

-- --------------------------------------------------------------- tracker ----

Config.Tracker = {
	-- Coarse region, never a pinpoint. Twice a round, so using one is a real
	-- decision about when.
	SenseUsesPerRound = 2,
	SenseRegionRadiusStuds = 120,

	-- Mobility is what makes the Tracker elite — he completes the retrieval
	-- trip far faster than an agent can. That advantage is deliberate and is
	-- the whole role, so keep it clearly above a walking agent.
	TraversalSpeedMultiplier = 1.6,
}

-- ---------------------------------------------------------------- camera ----

Config.Camera = {
	--[[
		Tried first person for the Runner; it made the game unreadable.

		In a disguise game she has to SEE her disguise — which civilian she
		currently is, and therefore what everyone else sees. First person hides
		exactly that, so she loses track of which body she is driving and where
		the rest of the crowd is.

		Third person with a capped zoom keeps the disguise visible while still
		denying the wide tactical overview that makes standing still safe.
	]]
	FirstPersonWhilePossessing = false,

	-- How far she may pull the camera back while possessing. Enough to see
	-- her own body and immediate neighbours, not enough to survey the block.
	PossessedMaxZoomStuds = 14,

	FirstPersonForHunters = false,
}

-- ------------------------------------------------------------------ misc ----

Config.Debug = {
	-- Lets a round start with a single player in Studio. NEVER ship true.
	AllowSoloRound = true,
	VerboseRoundLogging = true,
}

return table.freeze(Config)
