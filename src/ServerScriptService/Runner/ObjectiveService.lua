--!strict
--[[
	The Runner's escape objectives.

	Without these the optimal play is to possess one civilian in the densest
	crowd and stand perfectly still for five minutes — safe, boring, and it
	never uses the possession mechanic at all. Objectives force her into the
	open and give hunters somewhere worth watching.

	Claiming happens WHILE POSSESSING: she stands at the site and waits. To a
	hunter that reads as a civilian parked somewhere off its route, which is
	exactly the tell the crowd's robotic routes exist to make visible.

	More sites than she needs, so hunters cannot camp them all at once.
]]

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Workspace = game:GetService("Workspace")

local Config = require(ReplicatedStorage:WaitForChild("Config"))
local Remotes = require(ReplicatedStorage:WaitForChild("Remotes"))
local PossessionService = require(script.Parent:WaitForChild("PossessionService"))

local ObjectiveService = {}

type Site = {
	part: BasePart,
	claimed: boolean,
	progress: number,
}

local sites: { Site } = {}
local folder: Folder? = nil
local active = false
local claimedCount = 0
local onAllClaimed: (() -> ())? = nil

local UNCLAIMED = Color3.fromRGB(80, 140, 200)
local CLAIMED = Color3.fromRGB(90, 200, 120)

local function log(message: string, ...: any)
	if Config.Debug.VerboseRoundLogging then
		print(("[Objective] " .. message):format(...))
	end
end

--[[
	Site positions. Authored parts under Workspace.ObjectiveSites win if they
	exist; otherwise they are scattered so the system is testable before a map
	exists.
]]
local function buildSitePositions(count: number): { Vector3 }
	local positions: { Vector3 } = {}

	local authored = Workspace:FindFirstChild("ObjectiveSites")
	if authored then
		for _, child in authored:GetChildren() do
			if child:IsA("BasePart") then
				table.insert(positions, child.Position)
			end
		end
		if #positions > 0 then
			log("using %d authored site(s)", #positions)
			return positions
		end
	end

	-- Spread evenly around a ring so no two are trivially close together —
	-- clustered sites would let one hunter cover several at once.
	local radius = 110
	for i = 1, count do
		local angle = (i / count) * math.pi * 2
		table.insert(positions, Vector3.new(math.cos(angle) * radius, 3, math.sin(angle) * radius))
	end
	return positions
end

local function buildSite(position: Vector3, index: number): Site
	local part = Instance.new("Part")
	part.Name = ("ObjectiveSite_%d"):format(index)
	part.Size =
		Vector3.new(Config.Objective.ClaimRadiusStuds * 2, 1, Config.Objective.ClaimRadiusStuds * 2)
	part.Shape = Enum.PartType.Cylinder
	part.Anchored = true
	part.CanCollide = false
	part.Color = UNCLAIMED
	part.Transparency = 0.6
	part.Material = Enum.Material.Neon
	-- Cylinder parts extend along X, so lie it flat as a floor disc.
	part.CFrame = CFrame.new(position) * CFrame.Angles(0, 0, math.pi / 2)

	return {
		part = part,
		claimed = false,
		progress = 0,
	}
end

-- ----------------------------------------------------------------- claim ----

--[[
	Advances or resets claim progress each tick.

	Progress resets when she leaves rather than banking, so a claim is a
	commitment: eight seconds standing still in the open, where a hunter who
	is paying attention can see a civilian doing something civilians do not do.
]]
local function tick(deltaTime: number)
	local runnerAt = PossessionService.getRunnerPosition()

	for _, site in sites do
		if site.claimed then
			continue
		end

		local inRange = runnerAt ~= nil
			and (site.part.Position - runnerAt).Magnitude <= Config.Objective.ClaimRadiusStuds

		if inRange then
			site.progress += deltaTime
		elseif Config.Objective.ClaimResetsOnLeave then
			site.progress = 0
		end

		local fraction = math.clamp(site.progress / Config.Objective.ClaimDuration, 0, 1)

		-- Progress is visible to everyone standing there. Hunters should be
		-- able to watch a site fill up and come running.
		site.part.Color = UNCLAIMED:Lerp(CLAIMED, fraction)

		if site.progress >= Config.Objective.ClaimDuration then
			site.claimed = true
			site.progress = Config.Objective.ClaimDuration
			site.part.Color = CLAIMED
			site.part.Transparency = 0.3
			claimedCount += 1

			log("site claimed (%d/%d)", claimedCount, Config.Objective.RequiredToWin)
			Remotes.event("ObjectiveProgress")
				:FireAllClients(claimedCount, Config.Objective.RequiredToWin)

			if claimedCount >= Config.Objective.RequiredToWin and onAllClaimed then
				onAllClaimed()
			end
		end
	end
end

-- ---------------------------------------------------------------- public ----

function ObjectiveService.setCompletedCallback(callback: () -> ())
	onAllClaimed = callback
end

function ObjectiveService.getClaimedCount(): number
	return claimedCount
end

function ObjectiveService.beginRound()
	ObjectiveService.endRound()

	local container = Instance.new("Folder")
	container.Name = "Objectives"
	container.Parent = Workspace
	folder = container

	local positions = buildSitePositions(Config.Objective.SitesOnMap)
	for index, position in positions do
		local site = buildSite(position, index)
		site.part.Parent = container
		table.insert(sites, site)
	end

	claimedCount = 0
	active = true

	log("placed %d sites, %d needed to win", #sites, Config.Objective.RequiredToWin)
	Remotes.event("ObjectiveProgress"):FireAllClients(0, Config.Objective.RequiredToWin)
end

function ObjectiveService.endRound()
	active = false
	claimedCount = 0
	table.clear(sites)

	if folder then
		folder:Destroy()
		folder = nil
	end
end

function ObjectiveService.start()
	task.spawn(function()
		local last = os.clock()
		while true do
			task.wait(0.25)
			local now = os.clock()
			local delta = now - last
			last = now

			if active then
				tick(delta)
			end
		end
	end)
end

return ObjectiveService
