--!strict
--[[
	The Tracker's two advantages.

	MOBILITY is the real one. He carries the same single chip as everyone else,
	so what makes the role elite is that he completes the retrieval trip far
	faster than an agent can — he is the one who can actually respond when
	somebody flushes her across the map. That falls out of one stat rather
	than a special-case rule.

	THE SENSE is deliberately weak: a coarse region, twice a round. Enough to
	narrow a search, never enough to solve it — and rationed hard enough that
	using one is a real decision about when.
]]

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Config = require(ReplicatedStorage:WaitForChild("Config"))
local Remotes = require(ReplicatedStorage:WaitForChild("Remotes"))
local PossessionService =
	require(script.Parent.Parent:WaitForChild("Runner"):WaitForChild("PossessionService"))

local TrackerService = {}

local tracker: Player? = nil
local sensesRemaining = 0
local active = false

local function log(message: string, ...: any)
	if Config.Debug.VerboseRoundLogging then
		print(("[Tracker] " .. message):format(...))
	end
end

--[[
	Applies the movement advantage to whatever character he currently has.
	Re-applied on respawn, since a fresh character resets WalkSpeed.
]]
local function applyMobility(player: Player)
	local character = player.Character
	local humanoid = character and character:FindFirstChildOfClass("Humanoid")
	if humanoid then
		humanoid.WalkSpeed = 16 * Config.Tracker.TraversalSpeedMultiplier
	end
end

--[[
	A coarse fix on the Runner.

	Returns a point offset randomly within the sense radius rather than her
	actual position, so the answer is honestly "somewhere around here" — a
	pinpoint would end the round on the spot and make the crowd pointless.
]]
local function computeSenseRegion(): Vector3?
	local runnerAt = PossessionService.getRunnerPosition()
	if not runnerAt then
		return nil
	end

	local radius = Config.Tracker.SenseRegionRadiusStuds
	local angle = math.random() * math.pi * 2
	-- Square root keeps the offset uniform across the disc instead of
	-- clustering near the true position, which would make repeated pings
	-- triangulate her exactly.
	local distance = math.sqrt(math.random()) * (radius * 0.5)

	return runnerAt + Vector3.new(math.cos(angle) * distance, 0, math.sin(angle) * distance)
end

function TrackerService.beginRound(newTracker: Player?)
	tracker = newTracker
	sensesRemaining = Config.Tracker.SenseUsesPerRound
	active = true

	if newTracker then
		applyMobility(newTracker)
		log("%s is the Tracker (%d senses)", newTracker.Name, sensesRemaining)
	end
end

function TrackerService.endRound()
	active = false

	-- Hand the speed back, or he keeps it into the lobby and every round after.
	local player = tracker
	if player and player.Parent then
		local character = player.Character
		local humanoid = character and character:FindFirstChildOfClass("Humanoid")
		if humanoid then
			humanoid.WalkSpeed = 16
		end
	end

	tracker = nil
	sensesRemaining = 0
end

function TrackerService.start()
	Remotes.event("RequestSense").OnServerEvent:Connect(function(player)
		if not active or player ~= tracker then
			return
		end

		if sensesRemaining <= 0 then
			Remotes.event("SenseResult"):FireClient(player, nil, 0)
			return
		end

		local region = computeSenseRegion()
		if not region then
			return
		end

		sensesRemaining -= 1
		log("%s used a sense (%d left)", player.Name, sensesRemaining)
		Remotes.event("SenseResult"):FireClient(player, region, sensesRemaining)
	end)

	-- A respawn wipes WalkSpeed, so reapply if he is mid-round.
	Players.PlayerAdded:Connect(function(player)
		player.CharacterAdded:Connect(function()
			if active and player == tracker then
				task.wait(0.2)
				applyMobility(player)
			end
		end)
	end)
end

return TrackerService
