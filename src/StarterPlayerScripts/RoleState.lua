--!strict
--[[
	The client's view of what it is allowed to do.

	Shared by the input and UI scripts so they cannot disagree about the
	current role or round state. Purely advisory — it gates which prompts get
	shown, never what the server accepts.
]]

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Remotes = require(ReplicatedStorage:WaitForChild("Remotes"))

local RoleState = {}

export type Role = "Runner" | "Tracker" | "Agent" | "None"

RoleState.role = "None" :: Role
RoleState.roundState = "Lobby"
RoleState.timeRemaining = 0

type Listener = () -> ()
local listeners: { Listener } = {}

local function notify()
	for _, listener in listeners do
		task.spawn(listener)
	end
end

function RoleState.onChanged(listener: Listener): () -> ()
	table.insert(listeners, listener)
	return function()
		local index = table.find(listeners, listener)
		if index then
			table.remove(listeners, index)
		end
	end
end

function RoleState.isHunter(): boolean
	return RoleState.role == "Agent" or RoleState.role == "Tracker"
end

function RoleState.isActive(): boolean
	return RoleState.roundState == "Active"
end

Remotes.event("RoleAssigned").OnClientEvent:Connect(function(role: Role)
	RoleState.role = role
	notify()
end)

Remotes.event("RoundStateChanged").OnClientEvent
	:Connect(function(state: string, timeRemaining: number)
		RoleState.roundState = state
		RoleState.timeRemaining = timeRemaining or 0

		-- Roles are handed out per round; clear on the way back to lobby so a
		-- stale role cannot leave prompts on screen between rounds.
		if state == "Lobby" then
			RoleState.role = "None"
		end

		notify()
	end)

return RoleState
