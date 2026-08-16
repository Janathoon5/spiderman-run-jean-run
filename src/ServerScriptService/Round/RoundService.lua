--!strict
--[[
	The round state machine. Server-authoritative and the spine everything
	else hangs off.

		Lobby -> Starting -> Active -> Ending -> Lobby

	Deliberately knows nothing about civilians, chips, or objectives. Gameplay
	systems subscribe via onStateChanged and report back through
	reportOutcome, so this file never has to grow a dependency on them.
]]

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Config = require(ReplicatedStorage:WaitForChild("Config"))
local Remotes = require(ReplicatedStorage:WaitForChild("Remotes"))
local RoleAssignment = require(script.Parent:WaitForChild("RoleAssignment"))

local RoundService = {}

export type RoundState = "Lobby" | "Starting" | "Active" | "Ending"

-- Timeout is a HUNTER win: the Runner has to finish her objectives inside the
-- clock, so running it out is her failure, not a stalemate.
export type RoundOutcome = "RunnerEscaped" | "RunnerChipped" | "Timeout" | "Aborted"

local state: RoundState = "Lobby"
local timeRemaining = 0
local currentAssignment: RoleAssignment.Assignment? = nil
local pendingOutcome: RoundOutcome? = nil
local started = false

type StateListener = (newState: RoundState, oldState: RoundState) -> ()
local stateListeners: { StateListener } = {}

local function log(message: string, ...: any)
	if Config.Debug.VerboseRoundLogging then
		print(("[Round] " .. message):format(...))
	end
end

local function setState(newState: RoundState)
	local oldState = state
	if oldState == newState then
		return
	end

	state = newState
	log("%s -> %s", oldState, newState)

	Remotes.event("RoundStateChanged"):FireAllClients(newState, timeRemaining)

	for _, listener in stateListeners do
		-- One misbehaving listener must not stall the round loop.
		local ok, err = pcall(listener, newState, oldState)
		if not ok then
			warn(("[Round] state listener errored: %s"):format(tostring(err)))
		end
	end
end

--[[
	Players eligible to be given a role. A player still loading in has no
	character yet and would be assigned a role they cannot play.
]]
local function getEligiblePlayers(): { Player }
	local eligible: { Player } = {}
	for _, player in Players:GetPlayers() do
		if player.Character then
			table.insert(eligible, player)
		end
	end
	return eligible
end

local function requiredPlayerCount(): number
	if Config.Debug.AllowSoloRound then
		return 1
	end
	return Config.Round.MinPlayers
end

-- ------------------------------------------------------------ public api ----

function RoundService.getState(): RoundState
	return state
end

function RoundService.getTimeRemaining(): number
	return timeRemaining
end

function RoundService.getAssignment(): RoleAssignment.Assignment?
	return currentAssignment
end

--[[
	How a gameplay system ends the round early — the chip landing, or the
	Runner finishing her objectives. Ignored outside an active round so a late
	callback cannot cut the next one short.
]]
function RoundService.reportOutcome(outcome: RoundOutcome)
	if state ~= "Active" then
		return
	end
	if pendingOutcome then
		return
	end
	pendingOutcome = outcome
	log("outcome reported: %s", outcome)
end

--[[
	Subscribe to state transitions. Returns a disconnect function.
]]
function RoundService.onStateChanged(listener: StateListener): () -> ()
	table.insert(stateListeners, listener)

	return function()
		local index = table.find(stateListeners, listener)
		if index then
			table.remove(stateListeners, index)
		end
	end
end

-- ------------------------------------------------------------- the loop ----

local function waitForEnoughPlayers()
	setState("Lobby")
	currentAssignment = nil

	while #getEligiblePlayers() < requiredPlayerCount() do
		task.wait(1)
	end
end

--[[
	Returns false if the lobby emptied out during the countdown.
]]
local function runStartCountdown(): boolean
	setState("Starting")

	for remaining = Config.Round.StartCountdown, 1, -1 do
		if #getEligiblePlayers() < requiredPlayerCount() then
			log("lost players during countdown, returning to lobby")
			return false
		end

		if remaining <= 3 or remaining % 5 == 0 then
			log("starting in %d", remaining)
		end

		task.wait(1)
	end

	return true
end

local function announceRoles(assignment: RoleAssignment.Assignment)
	Remotes.event("RoleAssigned"):FireClient(assignment.runner, "Runner")

	if assignment.tracker then
		Remotes.event("RoleAssigned"):FireClient(assignment.tracker, "Tracker")
	end

	for _, agent in assignment.agents do
		Remotes.event("RoleAssigned"):FireClient(agent, "Agent")
	end
end

local function runActiveRound(): RoundOutcome
	pendingOutcome = nil
	setState("Active")
	timeRemaining = Config.Round.Duration

	while timeRemaining > 0 do
		-- A gameplay system ended it: chip landed, or objectives finished.
		if pendingOutcome then
			return pendingOutcome
		end

		if #getEligiblePlayers() == 0 then
			return "Aborted"
		end

		task.wait(1)
		timeRemaining -= 1

		if timeRemaining % 10 == 0 or timeRemaining <= 10 then
			Remotes.event("RoundStateChanged"):FireAllClients("Active", timeRemaining)
		end

		if timeRemaining % 60 == 0 and timeRemaining > 0 then
			log("%d seconds remaining", timeRemaining)
		end
	end

	return pendingOutcome or "Timeout"
end

local function runEndScreen(outcome: RoundOutcome)
	setState("Ending")
	log("round over: %s", outcome)
	Remotes.event("RoundEnded"):FireAllClients(outcome)
	task.wait(Config.Round.EndScreenDuration)
end

--[[
	Starts the perpetual round loop. Safe to call once; further calls are
	ignored so a double-require cannot spawn two competing loops.
]]
function RoundService.start()
	if started then
		warn("[Round] start() called twice — ignoring")
		return
	end
	started = true

	log("service started (solo rounds %s)", Config.Debug.AllowSoloRound and "ENABLED" or "disabled")

	task.spawn(function()
		while true do
			waitForEnoughPlayers()

			if runStartCountdown() then
				local players = getEligiblePlayers()
				local assignment = RoleAssignment.assign(players, requiredPlayerCount())

				if assignment then
					currentAssignment = assignment
					announceRoles(assignment)
					log(
						"roles — Runner: %s | Tracker: %s | Agents: %d",
						assignment.runner.Name,
						assignment.tracker and assignment.tracker.Name or "(none)",
						#assignment.agents
					)

					local outcome = runActiveRound()
					runEndScreen(outcome)
				else
					log("could not assign roles, returning to lobby")
				end
			end

			currentAssignment = nil
			timeRemaining = 0
			pendingOutcome = nil
		end
	end)
end

return RoundService
