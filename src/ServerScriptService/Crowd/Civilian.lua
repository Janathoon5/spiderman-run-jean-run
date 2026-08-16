--!strict
--[[
	Builds one civilian.

	Deliberately a plain R6 rig assembled from parts rather than a loaded
	avatar: no asset downloads, no async, and it spawns instantly, which
	matters when 35 of them appear at once at round start.

	The important property is that every civilian looks DIFFERENT. With 35
	identical bodies "which one is Jean" is unanswerable and hunters are just
	coin-flipping — being able to think "the one in the red shirt was across
	the plaza a second ago" is what makes the whole deduction layer work.
]]

local Config = require(game:GetService("ReplicatedStorage"):WaitForChild("Config"))

local Civilian = {}

-- Picked to stay distinguishable at a distance and under Roblox's default
-- lighting. Avoid near-identical neighbours — that defeats the point.
local SHIRT_COLORS: { Color3 } = {
	Color3.fromRGB(196, 40, 28), -- red
	Color3.fromRGB(13, 105, 172), -- blue
	Color3.fromRGB(75, 151, 75), -- green
	Color3.fromRGB(245, 205, 48), -- yellow
	Color3.fromRGB(180, 128, 255), -- lilac
	Color3.fromRGB(255, 176, 0), -- orange
	Color3.fromRGB(17, 17, 17), -- black
	Color3.fromRGB(248, 248, 248), -- white
	Color3.fromRGB(124, 92, 70), -- brown
	Color3.fromRGB(0, 143, 156), -- teal
}

local PANTS_COLORS: { Color3 } = {
	Color3.fromRGB(35, 35, 40),
	Color3.fromRGB(70, 70, 80),
	Color3.fromRGB(105, 90, 70),
	Color3.fromRGB(45, 60, 90),
}

local SKIN_COLORS: { Color3 } = {
	Color3.fromRGB(234, 184, 146),
	Color3.fromRGB(204, 142, 105),
	Color3.fromRGB(163, 106, 74),
	Color3.fromRGB(120, 80, 58),
	Color3.fromRGB(88, 58, 42),
}

export type Appearance = {
	shirt: Color3,
	pants: Color3,
	skin: Color3,
	heightScale: number,
}

local function makePart(name: string, size: Vector3, color: Color3): Part
	local part = Instance.new("Part")
	part.Name = name
	part.Size = size
	part.Color = color
	part.Material = Enum.Material.SmoothPlastic
	part.TopSurface = Enum.SurfaceType.Smooth
	part.BottomSurface = Enum.SurfaceType.Smooth
	part.Anchored = false
	return part
end

local function joint(name: string, part0: BasePart, part1: BasePart, c0: CFrame, c1: CFrame)
	local motor = Instance.new("Motor6D")
	motor.Name = name
	motor.Part0 = part0
	motor.Part1 = part1
	motor.C0 = c0
	motor.C1 = c1
	motor.Parent = part0
end

--[[
	Rolls a random look. Exposed separately so the possession system can later
	copy a civilian's exact appearance onto the Runner's character — she has to
	look like the body she is wearing, or the disguise is meaningless.
]]
function Civilian.rollAppearance(): Appearance
	return {
		shirt = SHIRT_COLORS[math.random(1, #SHIRT_COLORS)],
		pants = PANTS_COLORS[math.random(1, #PANTS_COLORS)],
		skin = SKIN_COLORS[math.random(1, #SKIN_COLORS)],
		-- Slight height variation adds silhouette difference at range without
		-- affecting collision or movement noticeably.
		heightScale = 0.95 + math.random() * 0.1,
	}
end

--[[
	Builds a civilian rig. Not parented — the caller decides where it goes.

	R6 layout, because it is the simplest structure Roblox reliably accepts as
	a character: a Humanoid plus a part named HumanoidRootPart, a Torso, and a
	Head, joined with Motor6Ds.
]]
function Civilian.build(appearance: Appearance): Model
	local model = Instance.new("Model")
	model.Name = "Civilian"

	-- The invisible part the Humanoid actually steers. Everything else hangs
	-- off it.
	local root = makePart("HumanoidRootPart", Vector3.new(2, 2, 1), appearance.skin)
	root.Transparency = 1
	root.CanCollide = false
	root.Parent = model

	local torso = makePart("Torso", Vector3.new(2, 2, 1), appearance.shirt)
	torso.Parent = model

	local head = makePart("Head", Vector3.new(2, 1, 1), appearance.skin)
	head.Parent = model

	local leftArm = makePart("Left Arm", Vector3.new(1, 2, 1), appearance.skin)
	leftArm.CanCollide = false
	leftArm.Parent = model

	local rightArm = makePart("Right Arm", Vector3.new(1, 2, 1), appearance.skin)
	rightArm.CanCollide = false
	rightArm.Parent = model

	local leftLeg = makePart("Left Leg", Vector3.new(1, 2, 1), appearance.pants)
	leftLeg.CanCollide = false
	leftLeg.Parent = model

	local rightLeg = makePart("Right Leg", Vector3.new(1, 2, 1), appearance.pants)
	rightLeg.CanCollide = false
	rightLeg.Parent = model

	-- R6 joint layout. These offsets are the standard ones Roblox characters
	-- use; changing them will visibly dislocate the rig.
	joint("RootJoint", root, torso, CFrame.new(0, 0, 0), CFrame.new(0, 0, 0))
	joint("Neck", torso, head, CFrame.new(0, 1, 0), CFrame.new(0, -0.5, 0))
	joint("Left Shoulder", torso, leftArm, CFrame.new(-1.5, 0.5, 0), CFrame.new(0, 0.5, 0))
	joint("Right Shoulder", torso, rightArm, CFrame.new(1.5, 0.5, 0), CFrame.new(0, 0.5, 0))
	joint("Left Hip", torso, leftLeg, CFrame.new(-0.5, -2, 0), CFrame.new(0, 0, 0))
	joint("Right Hip", torso, rightLeg, CFrame.new(0.5, -2, 0), CFrame.new(0, 0, 0))

	local humanoid = Instance.new("Humanoid")
	humanoid.RigType = Enum.HumanoidRigType.R6
	humanoid.WalkSpeed = Config.NPC.WalkSpeed
	humanoid.DisplayDistanceType = Enum.HumanoidDisplayDistanceType.None
	humanoid.HealthDisplayType = Enum.HumanoidHealthDisplayType.AlwaysOff

	-- Performance: 35 Humanoids is the single heaviest thing in this game.
	-- Civilians never jump, climb, swim, or ragdoll, so turning those states
	-- off stops the engine evaluating them every frame.
	humanoid:SetStateEnabled(Enum.HumanoidStateType.Climbing, false)
	humanoid:SetStateEnabled(Enum.HumanoidStateType.Swimming, false)
	humanoid:SetStateEnabled(Enum.HumanoidStateType.Jumping, false)
	humanoid:SetStateEnabled(Enum.HumanoidStateType.FallingDown, false)
	humanoid:SetStateEnabled(Enum.HumanoidStateType.Ragdoll, false)
	humanoid.Parent = model

	model.PrimaryPart = root

	return model
end

return Civilian
