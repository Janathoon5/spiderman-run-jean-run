--!strict
--[[
	The client/server boundary, in one place.

	Created at runtime by the server and awaited by the client, rather than
	authored as instances — one list, no chance of a name in code drifting
	from a name in the tree.

	Naming convention: Request* is client -> server and is always treated as
	untrusted; everything else is server -> client and is authoritative.
]]

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")

-- Must NOT be "Remotes": this ModuleScript is itself ReplicatedStorage.Remotes,
-- so a folder by the same name collides with it — FindFirstChild returns this
-- script, the server silently skips building the folder, and every client
-- lookup then fails with "no RemoteEvent named ...".
local FOLDER_NAME = "RemoteEvents"

local EVENT_NAMES = {
	-- Client -> server. Untrusted: the server re-checks range, cooldown, role,
	-- and target validity on every one of these.
	"RequestJump",
	"RequestChipStart",
	"RequestChipCancel",
	"RequestChipRetrieve",
	"RequestBreakout",
	"RequestSense",

	-- Server -> client.
	"RoleAssigned",
	"RoundStateChanged",
	"JumpTell",
	"ChipProgress",
	"ChipResolved",
	"ObjectiveProgress",
	"SenseResult",
	"RoundEnded",
}

local FUNCTION_NAMES = {
	-- Client asks once on spawn for whatever it missed.
	"GetRoundSnapshot",
}

local Remotes = {}

local function buildOnServer(): Folder
	local existing = ReplicatedStorage:FindFirstChild(FOLDER_NAME)
	if existing then
		-- Guard rather than blind-cast: if something that is not a Folder ever
		-- occupies this name again, fail here with a clear message instead of
		-- handing back a broken object that errors much further away.
		assert(
			existing:IsA("Folder"),
			("[Remotes] %s exists but is not a Folder"):format(FOLDER_NAME)
		)
		return existing
	end

	local folder = Instance.new("Folder")
	folder.Name = FOLDER_NAME

	for _, name in EVENT_NAMES do
		local event = Instance.new("RemoteEvent")
		event.Name = name
		event.Parent = folder
	end

	for _, name in FUNCTION_NAMES do
		local fn = Instance.new("RemoteFunction")
		fn.Name = name
		fn.Parent = folder
	end

	folder.Parent = ReplicatedStorage
	return folder
end

local folder: Folder
if RunService:IsServer() then
	folder = buildOnServer()
else
	-- No timeout: client scripts routinely start before the server's Bootstrap
	-- has run, so waiting indefinitely is correct here.
	folder = ReplicatedStorage:WaitForChild(FOLDER_NAME) :: Folder
end

--[[
	Fetches a RemoteEvent by name. Errors loudly on a typo rather than
	returning nil and failing somewhere far away later.
]]
function Remotes.event(name: string): RemoteEvent
	local remote = folder:WaitForChild(name, 10)
	if not remote or not remote:IsA("RemoteEvent") then
		error(("[Remotes] no RemoteEvent named %q"):format(name), 2)
	end
	return remote
end

function Remotes.fn(name: string): RemoteFunction
	local remote = folder:WaitForChild(name, 10)
	if not remote or not remote:IsA("RemoteFunction") then
		error(("[Remotes] no RemoteFunction named %q"):format(name), 2)
	end
	return remote
end

return Remotes
