--!strict
--[[
	Spawns the civilian crowd and walks it around.

	Routes are fixed loops with pause points — robotic on purpose. A readable
	pattern is the whole reason a BROKEN pattern is noticeable, which is what
	hunters are actually reading. It is also the performance-safe choice:
	waypoint loops cost almost nothing, whereas 35 NPCs each running
	PathfindingService would flatten the server.

	Hooks into RoundService state rather than polling, so the crowd appears at
	Starting and is cleaned up at Ending.
]]

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Workspace = game:GetService("Workspace")

local Config = require(ReplicatedStorage:WaitForChild("Config"))
local Civilian = require(script.Parent:WaitForChild("Civilian"))

local CrowdService = {}

export type Route = { Vector3 }

type ActiveCivilian = {
	model: Model,
	humanoid: Humanoid,
	route: Route,
	waypointIndex: number,
	appearance: Civilian.Appearance,
}

local crowd: { ActiveCivilian } = {}
local crowdFolder: Folder? = nil
local running = false

local function log(message: string, ...: any)
	if Config.Debug.VerboseRoundLogging then
		print(("[Crowd] " .. message):format(...))
	end
end

-- --------------------------------------------------------------- routes ----

--[[
	Where civilians walk.

	If the map defines routes (a Workspace.CivilianRoutes folder, each child a
	folder of numbered parts) those win. Otherwise we generate loops on the
	baseplate so the crowd is testable before any map exists — which is where
	the project is right now.
]]
local function buildRoutes(count: number): { Route }
	local routes: { Route } = {}

	local authored = Workspace:FindFirstChild("CivilianRoutes")
	if authored then
		for _, routeFolder in authored:GetChildren() do
			local points: Route = {}
			-- Sorted by name so "1, 2, 3" is walked in order rather than in
			-- whatever order GetChildren happens to return.
			local parts = routeFolder:GetChildren()
			table.sort(parts, function(a, b)
				return a.Name < b.Name
			end)
			for _, part in parts do
				if part:IsA("BasePart") then
					table.insert(points, part.Position)
				end
			end
			if #points >= 2 then
				table.insert(routes, points)
			end
		end

		if #routes > 0 then
			log("using %d authored route(s) from Workspace.CivilianRoutes", #routes)
			return routes
		end
	end

	-- Fallback: scatter loops across a flat area. Each civilian gets its own
	-- small circuit so the crowd spreads out instead of conga-lining.
	log("no authored routes found, generating %d procedural loops", count)

	local areaRadius = 140
	for _ = 1, count do
		local centerAngle = math.random() * math.pi * 2
		local centerDistance = math.random() * areaRadius
		local center = Vector3.new(
			math.cos(centerAngle) * centerDistance,
			3,
			math.sin(centerAngle) * centerDistance
		)

		local loopRadius = 12 + math.random() * 25
		local pointCount = math.random(3, 5)
		local points: Route = {}

		for i = 1, pointCount do
			local angle = (i / pointCount) * math.pi * 2
			table.insert(
				points,
				center + Vector3.new(math.cos(angle) * loopRadius, 0, math.sin(angle) * loopRadius)
			)
		end

		table.insert(routes, points)
	end

	return routes
end

-- ------------------------------------------------------------- movement ----

--[[
	Walks one civilian around its loop forever.

	Runs as its own task per civilian. That is fine at this scale — they spend
	nearly all their time yielded on MoveToFinished or a pause, not burning
	CPU. Revisit if the crowd ever grows past a few hundred.
]]
local function driveCivilian(entry: ActiveCivilian)
	while running and entry.model.Parent do
		local target = entry.route[entry.waypointIndex]
		entry.humanoid:MoveTo(target)

		-- MoveToFinished fires on arrival OR after an 8s internal timeout, so
		-- a civilian wedged on geometry recovers on its own rather than
		-- freezing forever — which would read as a very obvious "that one is
		-- Jean" tell.
		entry.humanoid.MoveToFinished:Wait()

		if not (running and entry.model.Parent) then
			break
		end

		-- The pause is part of the readable pattern: civilians stop at fixed
		-- points, so someone standing still somewhere they shouldn't stands out.
		task.wait(Config.NPC.PauseDuration)

		entry.waypointIndex += 1
		if entry.waypointIndex > #entry.route then
			entry.waypointIndex = 1
		end
	end
end

-- ---------------------------------------------------------------- public ----

function CrowdService.getCrowd(): { ActiveCivilian }
	return crowd
end

function CrowdService.getCount(): number
	return #crowd
end

--[[
	Spawns the crowd. Safe to call when one already exists — it clears first.
]]
function CrowdService.spawn()
	CrowdService.despawn()

	local folder = Instance.new("Folder")
	folder.Name = "Crowd"
	folder.Parent = Workspace
	crowdFolder = folder

	local count = Config.NPC.Count
	local routes = buildRoutes(count)
	running = true

	for i = 1, count do
		local appearance = Civilian.rollAppearance()
		local model = Civilian.build(appearance)
		local route = routes[((i - 1) % #routes) + 1]

		model.Name = ("Civilian_%02d"):format(i)
		model:PivotTo(CFrame.new(route[1]))
		model.Parent = folder

		local humanoid = model:FindFirstChildOfClass("Humanoid")
		if not humanoid then
			warn(("[Crowd] %s built without a Humanoid — skipping"):format(model.Name))
			continue
		end

		local entry: ActiveCivilian = {
			model = model,
			humanoid = humanoid,
			route = route,
			-- Start partway along the loop so they are not all synchronised,
			-- which would look obviously mechanical.
			waypointIndex = math.random(1, #route),
			appearance = appearance,
		}

		table.insert(crowd, entry)
		task.spawn(driveCivilian, entry)
	end

	log("spawned %d civilians across %d route(s)", #crowd, #routes)
end

function CrowdService.despawn()
	running = false
	table.clear(crowd)

	if crowdFolder then
		crowdFolder:Destroy()
		crowdFolder = nil
	end
end

--[[
	Wires the crowd to the round lifecycle. Call once at startup.
]]
function CrowdService.bindTo(roundService: {
	onStateChanged: ((string, string) -> ()) -> () -> (),
})
	roundService.onStateChanged(function(newState: string)
		if newState == "Starting" then
			CrowdService.spawn()
		elseif newState == "Ending" or newState == "Lobby" then
			CrowdService.despawn()
		end
	end)
end

return CrowdService
