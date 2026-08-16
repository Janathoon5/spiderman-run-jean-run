--!strict
--[[
	The Runner's jump between civilian bodies.

	Implemented by handing the player the civilian's actual Model as their
	Character, rather than re-skinning their own avatar. That way she does not
	merely look like a civilian — she IS one, built by the same factory, so
	there is no cosmetic seam for a hunter to spot.

	SERVER AUTHORITY: RequestJump is a request, never an instruction. Range,
	cooldown, role, and target validity are all re-checked here. A client
	saying "I jumped into civilian 12" proves nothing.
]]

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Config = require(ReplicatedStorage:WaitForChild("Config"))
local Remotes = require(ReplicatedStorage:WaitForChild("Remotes"))
local CrowdService =
	require(script.Parent.Parent:WaitForChild("Crowd"):WaitForChild("CrowdService"))

local PossessionService = {}

local runner: Player? = nil
local possessed: CrowdService.ActiveCivilian? = nil
local lastJumpAt = 0
local breakoutRequested = false

-- When each body was last vacated. Keyed by the civilian entry itself; cleared
-- wholesale at round start since the crowd is rebuilt each round anyway.
local vacatedAt: { [CrowdService.ActiveCivilian]: number } = {}

local function log(message: string, ...: any)
	if Config.Debug.VerboseRoundLogging then
		print(("[Possession] " .. message):format(...))
	end
end

-- ------------------------------------------------------------------ read ----

function PossessionService.getRunner(): Player?
	return runner
end

function PossessionService.getPossessed(): CrowdService.ActiveCivilian?
	return possessed
end

--[[
	Is this civilian the Runner right now? The chip system's whole question.
]]
function PossessionService.isRunnerBody(entry: CrowdService.ActiveCivilian): boolean
	return possessed ~= nil and possessed == entry
end

function PossessionService.getRunnerPosition(): Vector3?
	local body = possessed
	if not body then
		return nil
	end
	local root = body.model.PrimaryPart
	return root and root.Position or nil
end

-- ---------------------------------------------------------- jump handling ----

--[[
	Broadcasts the jump tell to hunters standing close enough to notice.

	Filtered server-side by distance on purpose: sending it to everyone and
	letting clients decide whether to render it would hand an exploiter the
	Runner's exact position on every jump.
]]
local function broadcastTell(position: Vector3)
	local radius = Config.Runner.JumpTellRadiusStuds

	for _, player in Players:GetPlayers() do
		if player == runner then
			continue
		end

		local character = player.Character
		local root = character and character:FindFirstChild("HumanoidRootPart")
		if not root or not root:IsA("BasePart") then
			continue
		end

		if (root.Position - position).Magnitude <= radius then
			-- Position only, no identity: they learn a jump happened near
			-- here, not which body it landed in. That gap is the game.
			Remotes.event("JumpTell"):FireClient(player, position)
		end
	end
end

--[[
	Moves the Runner into a civilian body. Handles releasing the previous one.
]]
local function occupy(player: Player, entry: CrowdService.ActiveCivilian)
	local previous = possessed

	if previous then
		CrowdService.releaseControl(previous, CrowdService.getRoutes())
		-- Starts this body's re-entry cooldown.
		vacatedAt[previous] = os.clock()
	end

	CrowdService.takeControl(entry)
	possessed = entry

	-- The old real character is disposable — a fresh one is loaded when the
	-- round ends. Destroying it avoids leaving an orphan standing in the map.
	local oldCharacter = player.Character
	player.Character = entry.model
	if oldCharacter and oldCharacter ~= entry.model then
		oldCharacter:Destroy()
	end

	entry.humanoid.WalkSpeed = 16

	if Config.Camera.FirstPersonWhilePossessing then
		player.CameraMode = Enum.CameraMode.LockFirstPerson
	else
		-- Third person, but capped: she needs to see her own body to know what
		-- disguise she is wearing, without getting a wide view of the block.
		player.CameraMode = Enum.CameraMode.Classic
		player.CameraMaxZoomDistance = Config.Camera.PossessedMaxZoomStuds
	end
end

--[[
	Handles a jump request. Returns a reason string on rejection so the client
	can show something useful ("too far", "on cooldown") rather than failing
	silently, which reads as the game being broken.
]]
local function handleJumpRequest(player: Player, targetModel: Instance?): (boolean, string)
	if player ~= runner then
		return false, "not the runner"
	end

	local current = possessed
	if not current then
		return false, "not currently possessing"
	end

	local now = os.clock()
	if now - lastJumpAt < Config.Runner.JumpCooldown then
		return false, "too fast"
	end

	local target = CrowdService.findByModel(targetModel)
	if not target then
		return false, "not a civilian"
	end

	if target == current then
		return false, "already in that body"
	end

	-- Per-body cooldown, so she cannot bounce straight back into the body she
	-- just left and shake a pursuer without actually going anywhere.
	local left = vacatedAt[target]
	if left and now - left < Config.Runner.BodyReentryCooldown then
		return false, "that body is still warm"
	end

	if target.playerControlled then
		return false, "occupied"
	end

	-- Chipped bodies are off limits. This is what makes a spent chip deny her
	-- space, and the reason hunters must weigh retrieving against leaving it.
	if target.marked and Config.Chip.MarkedNPCsBlockJump then
		return false, "that one is chipped"
	end

	local fromRoot = current.model.PrimaryPart
	local toRoot = target.model.PrimaryPart
	if not fromRoot or not toRoot then
		return false, "body has no root"
	end

	local distance = (toRoot.Position - fromRoot.Position).Magnitude
	if distance > Config.Runner.JumpRangeStuds then
		return false, "too far"
	end

	local jumpPosition = fromRoot.Position
	occupy(player, target)
	lastJumpAt = now

	broadcastTell(jumpPosition)
	log(
		"%s jumped %s -> %s (%.1f studs)",
		player.Name,
		current.model.Name,
		target.model.Name,
		distance
	)

	return true, "ok"
end

-- --------------------------------------------------------------- breakout ----

--[[
	The Runner escaping a chip hold. The chip system asks whether she tried.

	Escaping locks out her jump for a few seconds — it has to cost something
	or it is a free reset. She survives, but is stuck in the body everyone
	just watched do something no civilian can do.
]]
function PossessionService.consumeBreakout(): boolean
	local requested = breakoutRequested
	breakoutRequested = false

	if requested then
		-- Pushed into the future rather than set to now, since the ordinary
		-- jump gate is only a fraction of a second these days.
		lastJumpAt = os.clock() + Config.Runner.BreakoutJumpLockout - Config.Runner.JumpCooldown
	end

	return requested
end

function PossessionService.clearBreakout()
	breakoutRequested = false
end

-- --------------------------------------------------------------- lifecycle ----

--[[
	Puts the Runner into a random unchipped body at round start.
]]
function PossessionService.beginRound(newRunner: Player)
	runner = newRunner
	lastJumpAt = 0
	breakoutRequested = false
	table.clear(vacatedAt)

	local candidates = {}
	for _, entry in CrowdService.getCrowd() do
		if not entry.playerControlled and not entry.marked then
			table.insert(candidates, entry)
		end
	end

	if #candidates == 0 then
		warn("[Possession] no civilian available to place the Runner in")
		return
	end

	local chosen = candidates[math.random(1, #candidates)]
	occupy(newRunner, chosen)
	log("%s starts as %s", newRunner.Name, chosen.model.Name)
end

--[[
	Returns the Runner to a normal character and the body to AI control.
]]
function PossessionService.endRound()
	local body = possessed
	local player = runner

	if body then
		CrowdService.releaseControl(body, CrowdService.getRoutes())
	end

	if player and player.Parent then
		-- Hand the camera back, or the possession restrictions persist through
		-- the lobby and every round after.
		player.CameraMode = Enum.CameraMode.Classic
		player.CameraMaxZoomDistance = 128

		-- Detach first so LoadCharacter does not destroy the civilian body,
		-- which still belongs to the crowd.
		player.Character = nil
		task.spawn(function()
			pcall(function()
				player:LoadCharacter()
			end)
		end)
	end

	runner = nil
	possessed = nil
	breakoutRequested = false
end

function PossessionService.start()
	Remotes.event("RequestJump").OnServerEvent:Connect(function(player, targetModel)
		if typeof(targetModel) ~= "Instance" then
			return
		end

		local ok, reason = handleJumpRequest(player, targetModel)
		if not ok then
			log("rejected jump from %s: %s", player.Name, reason)
		end
	end)

	Remotes.event("RequestBreakout").OnServerEvent:Connect(function(player)
		if player == runner then
			breakoutRequested = true
		end
	end)

	Players.PlayerRemoving:Connect(function(player)
		if player == runner then
			PossessionService.endRound()
		end
	end)
end

return PossessionService
