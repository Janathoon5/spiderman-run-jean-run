--!strict
--[[
	Player input: jumping bodies, placing and retrieving chips, breaking out.

	Everything here is a REQUEST. The client picks a target and asks; the
	server decides. Nothing in this file is trusted, and the highlighting is
	only a hint about what the server would probably accept.

		E (tap)   Runner   jump into the highlighted civilian
		E (hold)  Hunter   attach the chip — hold the full 3s
		E (tap)   Hunter   retrieve your own chip from a marked civilian
		F         Runner   break out of a chip being attached to you
		Q         Tracker  coarse sense ping, twice a round
]]

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")
local UserInputService = game:GetService("UserInputService")
local Workspace = game:GetService("Workspace")

local Config = require(ReplicatedStorage:WaitForChild("Config"))
local Remotes = require(ReplicatedStorage:WaitForChild("Remotes"))
local RoleState = require(script.Parent:WaitForChild("RoleState"))

local player = Players.LocalPlayer

local currentTarget: Model? = nil
local highlight: Highlight? = nil
local chipping = false
local breakoutAvailable = false

-- --------------------------------------------------------------- targeting ----

local function rootOf(model: Instance?): BasePart?
	if not model or not model:IsA("Model") then
		return nil
	end
	local root = model.PrimaryPart or model:FindFirstChild("HumanoidRootPart")
	return (root and root:IsA("BasePart")) and root or nil
end

--[[
	Nearest civilian within reach, excluding the body we are currently in.

	Nearest rather than look-direction because civilians cluster: in a crowd
	of eight, "the one I am facing" is ambiguous and misfires constantly,
	whereas walking up to someone is unambiguous.
]]
local function findTarget(): Model?
	local character = player.Character
	local origin = rootOf(character)
	if not origin then
		return nil
	end

	local crowd = Workspace:FindFirstChild("Crowd")
	if not crowd then
		return nil
	end

	local best: Model? = nil
	local bestDistance = Config.Runner.JumpRangeStuds

	for _, model in crowd:GetChildren() do
		if model == character or not model:IsA("Model") then
			continue
		end

		local root = rootOf(model)
		if not root then
			continue
		end

		local distance = (root.Position - origin.Position).Magnitude
		if distance <= bestDistance then
			best = model
			bestDistance = distance
		end
	end

	return best
end

local function setHighlight(model: Model?)
	if currentTarget == model then
		return
	end
	currentTarget = model

	if highlight then
		highlight:Destroy()
		highlight = nil
	end

	if not model then
		return
	end

	local created = Instance.new("Highlight")
	created.Name = "TargetHint"
	-- Distinct from the orange chip mark so "already spent" and "in reach"
	-- never read as the same thing.
	created.FillColor = Color3.fromRGB(120, 200, 255)
	created.OutlineColor = Color3.fromRGB(220, 245, 255)
	created.FillTransparency = 0.8
	created.Parent = model
	highlight = created
end

-- ------------------------------------------------------------------ input ----

local function onInteractBegin()
	local target = currentTarget
	if not target or not RoleState.isActive() then
		return
	end

	if RoleState.role == "Runner" then
		Remotes.event("RequestJump"):FireServer(target)
		return
	end

	if RoleState.isHunter() then
		-- A marked civilian is either someone else's spent chip or our own.
		-- Asking to retrieve is harmless if it is not ours — the server just
		-- ignores it — so we can send both without knowing which.
		if target:FindFirstChild("ChipMark") then
			Remotes.event("RequestChipRetrieve"):FireServer(target)
			return
		end

		chipping = true
		Remotes.event("RequestChipStart"):FireServer(target)
	end
end

local function onInteractEnd()
	if chipping then
		chipping = false
		-- Releasing early aborts. The hold has to be held.
		Remotes.event("RequestChipCancel"):FireServer()
	end
end

UserInputService.InputBegan:Connect(function(input, processed)
	if processed then
		return
	end

	if input.KeyCode == Enum.KeyCode.E then
		onInteractBegin()
	elseif input.KeyCode == Enum.KeyCode.F then
		if breakoutAvailable and RoleState.role == "Runner" then
			Remotes.event("RequestBreakout"):FireServer()
			breakoutAvailable = false
		end
	elseif input.KeyCode == Enum.KeyCode.Q then
		if RoleState.role == "Tracker" and RoleState.isActive() then
			Remotes.event("RequestSense"):FireServer()
		end
	end
end)

UserInputService.InputEnded:Connect(function(input)
	if input.KeyCode == Enum.KeyCode.E then
		onInteractEnd()
	end
end)

-- ------------------------------------------------------------- server news ----

Remotes.event("ChipProgress").OnClientEvent:Connect(function(kind: string)
	-- A chip is going onto the body we are wearing. This is the moment the
	-- Runner has to decide: eat it and lose, or break out and be seen.
	if kind == "incoming" then
		breakoutAvailable = true
	elseif kind == "cancelled" then
		breakoutAvailable = false
		chipping = false
	end
end)

Remotes.event("ChipResolved").OnClientEvent:Connect(function()
	breakoutAvailable = false
	chipping = false
end)

--[[
	Drops a marker at the sensed region. Deliberately a wide, short-lived disc
	rather than an arrow: it says "somewhere around here", which is all the
	Tracker is entitled to know.
]]
Remotes.event("SenseResult").OnClientEvent:Connect(function(region: Vector3?)
	if not region then
		return
	end

	local marker = Instance.new("Part")
	marker.Name = "SenseRegion"
	marker.Shape = Enum.PartType.Cylinder
	marker.Size = Vector3.new(
		1,
		Config.Tracker.SenseRegionRadiusStuds * 2,
		Config.Tracker.SenseRegionRadiusStuds * 2
	)
	marker.CFrame = CFrame.new(region) * CFrame.Angles(0, 0, math.pi / 2)
	marker.Anchored = true
	marker.CanCollide = false
	marker.CanQuery = false
	marker.Material = Enum.Material.Neon
	marker.Color = Color3.fromRGB(255, 90, 90)
	marker.Transparency = 0.85
	-- Client-side only: it is this player's information, not a beacon that
	-- tells the whole server where she is.
	marker.Parent = Workspace

	task.delay(6, function()
		marker:Destroy()
	end)
end)

--[[
	Repoint the camera when we are moved into a new body.

	Setting player.Character from the server does fire CharacterAdded, but the
	camera does not reliably re-target on its own — without this a jump leaves
	you watching the body you just left.
]]
local function followCharacter(character: Model)
	local humanoid = character:WaitForChild("Humanoid", 5)
	if not humanoid or not humanoid:IsA("Humanoid") then
		return
	end

	local camera = Workspace.CurrentCamera
	if camera then
		camera.CameraSubject = humanoid
		camera.CameraType = Enum.CameraType.Custom
	end
end

player.CharacterAdded:Connect(followCharacter)
if player.Character then
	followCharacter(player.Character)
end

-- Clear stale targeting between rounds so a highlight cannot outlive the
-- crowd it was pointing at.
RoleState.onChanged(function()
	if not RoleState.isActive() then
		setHighlight(nil)
		breakoutAvailable = false
		chipping = false
	end
end)

RunService.Heartbeat:Connect(function()
	if not RoleState.isActive() or RoleState.role == "None" then
		setHighlight(nil)
		return
	end
	setHighlight(findTarget())
end)
