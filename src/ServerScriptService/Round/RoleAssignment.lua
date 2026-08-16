--!strict
--[[
	Picks who plays what each round.

	Runner is the most-wanted seat and only one player gets it, so selection is
	weighted by how long someone has gone without it. Pure random feels unfair
	fast: with 8 players there is a real chance somebody plays six rounds
	straight as an Agent and leaves.

	Server-only. Never trust a client's opinion about its own role.
]]

local Players = game:GetService("Players")

local RoleAssignment = {}

export type Role = "Runner" | "Tracker" | "Agent"

export type Assignment = {
	runner: Player,
	tracker: Player?,
	agents: { Player },
}

-- userId -> rounds elapsed since that player was last the Runner.
-- Higher means they are more overdue. Cleared when a player leaves.
local roundsSinceRunner: { [number]: number } = {}

Players.PlayerRemoving:Connect(function(player)
	roundsSinceRunner[player.UserId] = nil
end)

--[[
	Weighted pick. Weight is (rounds waited + 1), so a player who has never
	been Runner in this session starts at 1 and climbs each round they miss.

	Weighted rather than strict "longest wait always wins" so the assignment
	is not fully predictable — but the bias is strong enough that everyone
	gets a turn in a normal session.
]]
local function pickWeightedRunner(candidates: { Player }): Player
	local totalWeight = 0
	local weights: { number } = {}

	for index, player in candidates do
		local waited = roundsSinceRunner[player.UserId] or 0
		local weight = waited + 1
		weights[index] = weight
		totalWeight += weight
	end

	local roll = math.random() * totalWeight
	local cursor = 0

	for index, weight in weights do
		cursor += weight
		if roll <= cursor then
			return candidates[index]
		end
	end

	-- Floating point can leave the roll a hair past the final boundary.
	return candidates[#candidates]
end

--[[
	Assigns roles for one round.

	Returns nil when there are not enough players, so the caller can stay in
	lobby rather than starting a broken round.
]]
function RoleAssignment.assign(players: { Player }, minPlayers: number): Assignment?
	if #players < minPlayers then
		return nil
	end

	local pool = table.clone(players)
	local runner = pickWeightedRunner(pool)

	-- Remove the runner from the pool by identity, not index — pickWeighted
	-- returns a Player, and the index it came from is not exposed.
	local runnerIndex = table.find(pool, runner)
	if runnerIndex then
		table.remove(pool, runnerIndex)
	end

	-- Tracker is a plain random pick from whoever is left. It is a strong
	-- role but not the scarce one, so it does not need rotation weighting yet.
	local tracker: Player? = nil
	if #pool > 0 then
		tracker = table.remove(pool, math.random(1, #pool))
	end

	-- Everyone still in the pool is an Agent.
	local agents = pool

	-- Book-keeping for next round's weighting.
	for _, player in players do
		if player == runner then
			roundsSinceRunner[player.UserId] = 0
		else
			roundsSinceRunner[player.UserId] = (roundsSinceRunner[player.UserId] or 0) + 1
		end
	end

	return {
		runner = runner,
		tracker = tracker,
		agents = agents,
	}
end

--[[
	How overdue a player is for the Runner seat. Exposed for debugging and for
	a future "you are next up" UI hint.
]]
function RoleAssignment.getRoundsWaited(player: Player): number
	return roundsSinceRunner[player.UserId] or 0
end

return RoleAssignment
