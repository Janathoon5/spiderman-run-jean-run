--!strict
--[[
	Server entry point. Requires and starts the game's services in order.

	Keep this thin — it should read as a table of contents for the server, not
	contain logic of its own.
]]

local RunService = game:GetService("RunService")

local Round = script.Parent:WaitForChild("Round")
local Crowd = script.Parent:WaitForChild("Crowd")

local RoundService = require(Round:WaitForChild("RoundService"))
local CrowdService = require(Crowd:WaitForChild("CrowdService"))

print(("[Bootstrap] starting on %s"):format(RunService:IsStudio() and "Studio" or "live server"))

-- Bind listeners BEFORE starting the round loop, or a fast first transition
-- can fire before anything is subscribed to it.
CrowdService.bindTo(RoundService)

RoundService.start()
