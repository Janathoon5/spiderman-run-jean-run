--!strict
--[[
	Server entry point. Requires the game's services and wires them to the
	round lifecycle.

	Deliberately the only place that knows about all of them: RoundService does
	not depend on gameplay systems, and gameplay systems do not depend on each
	other, so the whole graph is assembled here rather than tangled across
	modules.
]]

local RunService = game:GetService("RunService")

local Round = script.Parent:WaitForChild("Round")
local Crowd = script.Parent:WaitForChild("Crowd")
local Runner = script.Parent:WaitForChild("Runner")
local Hunters = script.Parent:WaitForChild("Hunters")

local RoundService = require(Round:WaitForChild("RoundService"))
local CrowdService = require(Crowd:WaitForChild("CrowdService"))
local PossessionService = require(Runner:WaitForChild("PossessionService"))
local ObjectiveService = require(Runner:WaitForChild("ObjectiveService"))
local ChipService = require(Hunters:WaitForChild("ChipService"))
local TrackerService = require(Hunters:WaitForChild("TrackerService"))

print(("[Bootstrap] starting on %s"):format(RunService:IsStudio() and "Studio" or "live server"))

-- Remote listeners, running for the lifetime of the server.
PossessionService.start()
ChipService.start()
ObjectiveService.start()
TrackerService.start()

-- Win conditions report back into the round loop.
ChipService.setRunnerChippedCallback(function()
	RoundService.reportOutcome("RunnerChipped")
end)

ObjectiveService.setCompletedCallback(function()
	RoundService.reportOutcome("RunnerEscaped")
end)

--[[
	Per-round setup and teardown.

	Order matters on Active: the crowd must already exist before the Runner can
	be placed into one of its bodies.
]]
RoundService.onStateChanged(function(newState)
	if newState == "Starting" then
		CrowdService.spawn()
		return
	end

	if newState == "Active" then
		local assignment = RoundService.getAssignment()
		if not assignment then
			return
		end

		local hunters = table.clone(assignment.agents)
		if assignment.tracker then
			table.insert(hunters, assignment.tracker)
		end

		PossessionService.beginRound(assignment.runner)
		ChipService.beginRound(hunters)
		ObjectiveService.beginRound()
		TrackerService.beginRound(assignment.tracker)
		return
	end

	if newState == "Ending" then
		PossessionService.endRound()
		ChipService.endRound()
		ObjectiveService.endRound()
		TrackerService.endRound()
		return
	end

	if newState == "Lobby" then
		CrowdService.despawn()
	end
end)

-- Listeners are bound before the loop starts, so a fast first transition
-- cannot fire before anything is subscribed to it.
RoundService.start()
