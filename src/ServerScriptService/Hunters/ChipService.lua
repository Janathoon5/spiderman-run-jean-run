--!strict
--[[
	The inhibitor chip.

	One per hunter, and it is a physical object rather than a cooldown: a wrong
	guess leaves it stuck on that civilian, and you have to walk back and
	collect it before you can accuse again. That cost is ACTIVE — it scales
	with how recklessly the chip was spent — which is what stops hunters
	brute-forcing the crowd.

	See Config.Chip for the budget math. If the Runner never wins, that ratio
	is the first thing to check.
]]

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Config = require(ReplicatedStorage:WaitForChild("Config"))
local Remotes = require(ReplicatedStorage:WaitForChild("Remotes"))
local CrowdService =
	require(script.Parent.Parent:WaitForChild("Crowd"):WaitForChild("CrowdService"))
local PossessionService =
	require(script.Parent.Parent:WaitForChild("Runner"):WaitForChild("PossessionService"))

local ChipService = {}

type ChipState = {
	player: Player,
	holding: boolean,
	plantedOn: CrowdService.ActiveCivilian?,
	plantedAt: number,
	usesThisRound: number,
}

local states: { [Player]: ChipState } = {}
local active = false
local onRunnerChipped: (() -> ())? = nil

local function log(message: string, ...: any)
	if Config.Debug.VerboseRoundLogging then
		print(("[Chip] " .. message):format(...))
	end
end

local function stateFor(player: Player): ChipState
	local existing = states[player]
	if existing then
		return existing
	end

	local created: ChipState = {
		player = player,
		holding = false,
		plantedOn = nil,
		plantedAt = 0,
		usesThisRound = 0,
	}
	states[player] = created
	return created
end

-- ---------------------------------------------------------------- marking ----

--[[
	Visual mark on a chipped civilian. Hunters need to see at a glance which
	bodies are already spent, and it has to be findable later — retrieval
	should feel like "grab it as I pass", not "search for my own chip".
]]
local function applyMark(entry: CrowdService.ActiveCivilian)
	entry.marked = true

	local highlight = Instance.new("Highlight")
	highlight.Name = "ChipMark"
	highlight.FillColor = Color3.fromRGB(255, 170, 60)
	highlight.OutlineColor = Color3.fromRGB(255, 220, 150)
	highlight.FillTransparency = 0.65
	highlight.Parent = entry.model
end

local function clearMark(entry: CrowdService.ActiveCivilian)
	entry.marked = false

	local highlight = entry.model:FindFirstChild("ChipMark")
	if highlight then
		highlight:Destroy()
	end
end

local function rootPosition(entry: CrowdService.ActiveCivilian): Vector3?
	local root = entry.model.PrimaryPart
	return root and root.Position or nil
end

-- ------------------------------------------------------------- the hold ----

--[[
	Runs the hold-to-attach window.

	This is the best moment in the game: if it IS her, she can break out — but
	breaking out is something no real civilian could do, so escaping reveals
	her to everyone watching. Either way the attempt pays out, which is why
	nobody hangs back waiting for someone else to take the risk.
]]
local function runHold(state: ChipState, entry: CrowdService.ActiveCivilian)
	local player = state.player
	local isRunnerBody = PossessionService.isRunnerBody(entry)
	local runner = PossessionService.getRunner()

	PossessionService.clearBreakout()

	-- She must be told a chip is going on, or "she can break out" is a lie.
	if isRunnerBody and runner then
		Remotes.event("ChipProgress"):FireClient(runner, "incoming", Config.Chip.HoldDuration)
	end

	local elapsed = 0
	local step = 0.1

	while elapsed < Config.Chip.HoldDuration do
		if not state.holding or not active then
			Remotes.event("ChipProgress"):FireClient(player, "cancelled", 0)
			if isRunnerBody and runner then
				Remotes.event("ChipProgress"):FireClient(runner, "cancelled", 0)
			end
			return
		end

		-- Walking away cancels it. Holding someone at arm's length for three
		-- seconds should require actually standing there.
		local character = player.Character
		local root = character and character:FindFirstChild("HumanoidRootPart")
		local targetAt = rootPosition(entry)
		if not root or not root:IsA("BasePart") or not targetAt then
			state.holding = false
			return
		end

		if (root.Position - targetAt).Magnitude > Config.Runner.JumpRangeStuds then
			state.holding = false
			Remotes.event("ChipProgress"):FireClient(player, "cancelled", 0)
			return
		end

		if isRunnerBody and PossessionService.consumeBreakout() then
			-- She got out. The chip is spent on empty air and the hunters now
			-- know exactly which body she was in a second ago.
			state.holding = false
			log(
				"%s BROKE OUT of a chip on %s",
				runner and runner.Name or "runner",
				entry.model.Name
			)

			Remotes.event("ChipResolved"):FireAllClients("breakout", targetAt)
			state.usesThisRound += 1
			applyMark(entry)
			state.plantedOn = entry
			state.plantedAt = os.clock()
			return
		end

		task.wait(step)
		elapsed += step
		Remotes.event("ChipProgress")
			:FireClient(player, "holding", elapsed / Config.Chip.HoldDuration)
	end

	state.holding = false
	state.usesThisRound += 1

	if isRunnerBody then
		log("%s CHIPPED the runner in %s", player.Name, entry.model.Name)
		Remotes.event("ChipResolved"):FireAllClients("caught", rootPosition(entry))
		if onRunnerChipped then
			onRunnerChipped()
		end
		return
	end

	-- Wrong body. The chip stays on it and has to be collected.
	applyMark(entry)
	state.plantedOn = entry
	state.plantedAt = os.clock()

	log("%s chipped %s — wrong, chip is stuck there", player.Name, entry.model.Name)
	Remotes.event("ChipResolved"):FireClient(player, "wrong", entry.model.Name)
end

-- ---------------------------------------------------------------- public ----

function ChipService.setRunnerChippedCallback(callback: () -> ())
	onRunnerChipped = callback
end

function ChipService.beginRound(hunters: { Player })
	table.clear(states)
	active = true

	for _, player in hunters do
		stateFor(player)
	end

	log("armed %d hunters", #hunters)
end

function ChipService.endRound()
	active = false

	for _, state in states do
		if state.plantedOn then
			clearMark(state.plantedOn)
		end
	end

	table.clear(states)
end

--[[
	True when this hunter is carrying their chip and may accuse.
]]
function ChipService.hasChip(player: Player): boolean
	local state = states[player]
	return state ~= nil and state.plantedOn == nil
end

function ChipService.start()
	Remotes.event("RequestChipStart").OnServerEvent:Connect(function(player, targetModel)
		if not active or typeof(targetModel) ~= "Instance" then
			return
		end

		local state = states[player]
		if not state or state.holding then
			return
		end

		if state.plantedOn then
			Remotes.event("ChipProgress"):FireClient(player, "no_chip", 0)
			return
		end

		if state.usesThisRound >= Config.Chip.HardCapPerRoundPerHunter then
			Remotes.event("ChipProgress"):FireClient(player, "cap_reached", 0)
			return
		end

		local entry = CrowdService.findByModel(targetModel)
		if not entry or entry.marked then
			return
		end

		state.holding = true
		task.spawn(runHold, state, entry)
	end)

	Remotes.event("RequestChipCancel").OnServerEvent:Connect(function(player)
		local state = states[player]
		if state then
			state.holding = false
		end
	end)

	Remotes.event("RequestChipRetrieve").OnServerEvent:Connect(function(player, targetModel)
		if not active or typeof(targetModel) ~= "Instance" then
			return
		end

		local state = states[player]
		local planted = state and state.plantedOn
		if not state or not planted then
			return
		end

		if planted.model ~= targetModel then
			return
		end

		-- LOAD-BEARING: without the lockout a hunter just picks the chip back
		-- up off the civilian they are standing next to, and the whole
		-- limiter does nothing.
		local held = os.clock() - state.plantedAt
		if held < Config.Chip.RetrievalLockout then
			Remotes.event("ChipProgress")
				:FireClient(player, "locked", Config.Chip.RetrievalLockout - held)
			return
		end

		local character = player.Character
		local root = character and character:FindFirstChild("HumanoidRootPart")
		local targetPart = planted.model.PrimaryPart
		if not root or not root:IsA("BasePart") or not targetPart then
			return
		end

		if (root.Position - targetPart.Position).Magnitude > Config.Runner.JumpRangeStuds then
			return
		end

		clearMark(planted)
		state.plantedOn = nil
		state.plantedAt = 0

		log("%s retrieved their chip from %s", player.Name, planted.model.Name)
		Remotes.event("ChipProgress"):FireClient(player, "retrieved", 0)
	end)

	Players.PlayerRemoving:Connect(function(player)
		local state = states[player]
		if state and state.plantedOn then
			clearMark(state.plantedOn)
		end
		states[player] = nil
	end)
end

return ChipService
