--!strict
--[[
	Spawns the civilian crowd and walks it around.

	Routes are fixed loops with pause points — robotic on purpose. A readable
	pattern is the whole reason a BROKEN pattern is noticeable, which is what
	hunters are actually reading. It is also the performance-safe choice:
	waypoint loops cost almost nothing, whereas 35 NPCs each running
	PathfindingService would flatten the server.

	Civilians can be handed over to a player (that is what possession is) via
	takeControl/releaseControl. A controlled civilian stops being driven here
	so the AI does not fight the player's own input.
]]

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Workspace = game:GetService("Workspace")

local Config = require(ReplicatedStorage:WaitForChild("Config"))
local Civilian = require(script.Parent:WaitForChild("Civilian"))

local CrowdService = {}

export type Route = { Vector3 }

export type ActiveCivilian = {
	model: Model,
	humanoid: Humanoid,
	route: Route,
	waypointIndex: number,
	appearance: Civilian.Appearance,

	-- True while a player is puppeting this body. The drive loop idles.
	playerControlled: boolean,

	-- A chip is stuck on this civilian. Marked bodies are not valid jump
	-- targets, which is what makes spent chips deny the Runner space.
	marked: boolean,

	-- Collapsed after the Runner left this body. Doubles as the re-entry
	-- cooldown and as a visible clue that she was standing right here.
	passedOut: boolean,
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
	folder of numbered parts) those win. Otherwise we generate loops so the
	crowd is testable before any map exists.
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

	Runs as its own task per civilian. Fine at this scale — they spend nearly
	all their time yielded on MoveToFinished or a pause, not burning CPU.
]]
local function driveCivilian(entry: ActiveCivilian)
	while running and entry.model.Parent do
		-- Idle while a player is puppeting this body, or while it is collapsed
		-- after being vacated. Resume the route from wherever it ends up.
		if entry.playerControlled or entry.passedOut then
			task.wait(0.5)
			continue
		end

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

		if entry.playerControlled then
			continue
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

function CrowdService.findByModel(model: Instance?): ActiveCivilian?
	if not model then
		return nil
	end
	for _, entry in crowd do
		if entry.model == model then
			return entry
		end
	end
	return nil
end

--[[
	Nearest civilian to a point, skipping any the caller rejects.

	Used by possession (nearest valid jump target) and by the chip (what am I
	standing in front of).
]]
function CrowdService.findNearest(
	position: Vector3,
	maxDistance: number,
	filter: ((ActiveCivilian) -> boolean)?
): (ActiveCivilian?, number)
	local best: ActiveCivilian? = nil
	local bestDistance = maxDistance

	for _, entry in crowd do
		if filter and not filter(entry) then
			continue
		end

		local root = entry.model.PrimaryPart
		if not root then
			continue
		end

		local distance = (root.Position - position).Magnitude
		if distance <= bestDistance then
			best = entry
			bestDistance = distance
		end
	end

	return best, bestDistance
end

--[[
	Hands a civilian over to player control. The drive loop idles until
	released, so the AI does not fight the player's input.
]]
function CrowdService.takeControl(entry: ActiveCivilian)
	entry.playerControlled = true
end

--[[
	Collapses a body for a while, then stands it back up.

	This is what the Runner leaves behind when she jumps out. It does three
	jobs at once: it enforces the re-entry cooldown, it makes that cooldown
	legible instead of an invisible rule, and it hands hunters a real clue —
	someone was standing exactly here a moment ago. It does not say where she
	went, which is the part that keeps it a clue rather than an arrow.
]]
function CrowdService.knockOut(entry: ActiveCivilian, duration: number)
	if entry.passedOut then
		return
	end

	entry.passedOut = true
	-- PlatformStand drops them without needing the ragdoll states, which are
	-- deliberately disabled on civilians for performance.
	entry.humanoid.PlatformStand = true

	task.delay(duration, function()
		if not entry.model.Parent then
			return
		end

		entry.passedOut = false
		entry.humanoid.PlatformStand = false

		-- Rejoin the nearest loop rather than walking back across the map to
		-- wherever the old route started. Called through the table so it
		-- resolves at call time — activeRoutes is declared further down.
		CrowdService.releaseControl(entry, CrowdService.getRoutes())
	end)
end

function CrowdService.isAvailable(entry: ActiveCivilian): boolean
	return not entry.playerControlled and not entry.marked and not entry.passedOut
end

--[[
	Returns a civilian to AI control. It resumes its route from wherever it
	now stands — reassigned to the nearest route so a vacated body does not
	walk conspicuously across the map back to its old loop.
]]
function CrowdService.releaseControl(entry: ActiveCivilian, routes: { Route }?)
	entry.playerControlled = false

	local root = entry.model.PrimaryPart
	if not root or not routes or #routes == 0 then
		return
	end

	local bestRoute = routes[1]
	local bestDistance = math.huge
	for _, route in routes do
		local distance = (route[1] - root.Position).Magnitude
		if distance < bestDistance then
			bestDistance = distance
			bestRoute = route
		end
	end

	entry.route = bestRoute
	entry.waypointIndex = 1
end

local activeRoutes: { Route } = {}

function CrowdService.getRoutes(): { Route }
	return activeRoutes
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
	activeRoutes = routes
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
			playerControlled = false,
			marked = false,
			passedOut = false,
		}

		table.insert(crowd, entry)
		task.spawn(driveCivilian, entry)
	end

	log("spawned %d civilians across %d route(s)", #crowd, #routes)
end

function CrowdService.despawn()
	running = false
	table.clear(crowd)
	table.clear(activeRoutes)

	if crowdFolder then
		crowdFolder:Destroy()
		crowdFolder = nil
	end
end

return CrowdService
