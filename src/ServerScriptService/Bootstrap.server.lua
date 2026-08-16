--!strict
--[[
	Server entry point. Requires and starts the game's services in order.

	Keep this thin — it should read as a table of contents for the server, not
	contain logic of its own.
]]

local RunService = game:GetService("RunService")

local Round = script.Parent:WaitForChild("Round")
local RoundService = require(Round:WaitForChild("RoundService"))

print(("[Bootstrap] starting on %s"):format(RunService:IsStudio() and "Studio" or "live server"))

RoundService.start()
