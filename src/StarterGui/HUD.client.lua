--!strict
--[[
	Minimal HUD: role reveal, round clock, objective count, and the prompts
	that tell you what your key does right now.

	Built in code rather than authored as instances so it lives in the repo as
	diffable text — per the source-of-truth split, anything created by hand in
	the Studio Explorer would never sync back.

	Listens to remotes directly instead of sharing RoleState with the input
	script: this is a different container, and reaching across for one string
	is not worth the coupling.
]]

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local TweenService = game:GetService("TweenService")

local Config = require(ReplicatedStorage:WaitForChild("Config"))
local Remotes = require(ReplicatedStorage:WaitForChild("Remotes"))

local player = Players.LocalPlayer
local playerGui = player:WaitForChild("PlayerGui")

local role = "None"
local roundState = "Lobby"

local INK = Color3.fromRGB(240, 244, 250)
local DIM = Color3.fromRGB(150, 160, 175)
local ALERT = Color3.fromRGB(255, 120, 90)
local GOOD = Color3.fromRGB(120, 220, 150)

-- ----------------------------------------------------------------- build ----

local screen = Instance.new("ScreenGui")
screen.Name = "HUD"
screen.ResetOnSpawn = false
screen.IgnoreGuiInset = true
screen.ZIndexBehavior = Enum.ZIndexBehavior.Sibling
screen.Parent = playerGui

local function label(name: string, size: UDim2, position: UDim2, textSize: number): TextLabel
	local text = Instance.new("TextLabel")
	text.Name = name
	text.Size = size
	text.Position = position
	text.BackgroundTransparency = 1
	text.Font = Enum.Font.GothamMedium
	text.TextSize = textSize
	text.TextColor3 = INK
	text.TextStrokeTransparency = 0.6
	text.Text = ""
	text.Parent = screen
	return text
end

local clock = label("Clock", UDim2.fromScale(0.3, 0.08), UDim2.fromScale(0.35, 0.02), 34)
local objectives = label("Objectives", UDim2.fromScale(0.3, 0.05), UDim2.fromScale(0.35, 0.10), 20)
objectives.TextColor3 = DIM

local prompt = label("Prompt", UDim2.fromScale(0.6, 0.06), UDim2.fromScale(0.2, 0.82), 22)
local banner = label("Banner", UDim2.fromScale(0.8, 0.14), UDim2.fromScale(0.1, 0.40), 52)
banner.Font = Enum.Font.GothamBold
banner.TextTransparency = 1

-- ---------------------------------------------------------------- helpers ----

local function showBanner(text: string, color: Color3, holdFor: number)
	banner.Text = text
	banner.TextColor3 = color
	banner.TextTransparency = 0

	task.delay(holdFor, function()
		if banner.Text ~= text then
			return -- something newer already replaced it
		end
		TweenService:Create(banner, TweenInfo.new(0.6), { TextTransparency = 1 }):Play()
	end)
end

local function formatClock(seconds: number): string
	local whole = math.max(0, math.floor(seconds))
	return ("%d:%02d"):format(whole // 60, whole % 60)
end

--[[
	The prompt is the whole tutorial. Nobody reads instructions, so the bottom
	line always says what E does for you right now.
]]
local function refreshPrompt()
	if roundState ~= "Active" then
		prompt.Text = ""
		return
	end

	if role == "Runner" then
		prompt.Text = "[E] jump into a nearby civilian   ·   claim "
			.. Config.Objective.RequiredToWin
			.. " sites to escape"
		prompt.TextColor3 = INK
	elseif role == "Agent" or role == "Tracker" then
		prompt.Text =
			"[Hold E] attach the chip   ·   [E] retrieve your chip from a marked civilian"
		prompt.TextColor3 = INK
	else
		prompt.Text = ""
	end
end

-- ---------------------------------------------------------------- remotes ----

Remotes.event("RoleAssigned").OnClientEvent:Connect(function(assigned: string)
	role = assigned

	local blurb = if assigned == "Runner"
		then "Blend in. Claim " .. Config.Objective.RequiredToWin .. " sites."
		elseif assigned == "Tracker" then "Find her. You move faster than anyone."
		else "One chip. Make it count."

	showBanner("YOU ARE THE " .. string.upper(assigned) .. "\n" .. blurb, INK, 4)
	refreshPrompt()
end)

Remotes.event("RoundStateChanged").OnClientEvent
	:Connect(function(state: string, timeRemaining: number)
		roundState = state

		if state == "Active" then
			clock.Text = formatClock(timeRemaining)
			clock.TextColor3 = if timeRemaining <= 30 then ALERT else INK
		elseif state == "Starting" then
			clock.Text = "get ready"
			clock.TextColor3 = DIM
			objectives.Text = ""
		elseif state == "Lobby" then
			role = "None"
			clock.Text = "waiting for players"
			clock.TextColor3 = DIM
			objectives.Text = ""
		end

		refreshPrompt()
	end)

Remotes.event("ObjectiveProgress").OnClientEvent:Connect(function(claimed: number, required: number)
	objectives.Text = ("sites claimed  %d / %d"):format(claimed, required)
	objectives.TextColor3 = if claimed >= required then GOOD else DIM
end)

Remotes.event("ChipProgress").OnClientEvent:Connect(function(kind: string, value: number)
	if kind == "incoming" then
		-- The most important message in the game — she has three seconds.
		showBanner("A CHIP IS GOING ON YOU\n[F] break out — they will see you", ALERT, 3)
	elseif kind == "holding" then
		prompt.Text = ("attaching…  %d%%"):format(math.floor((value or 0) * 100))
		prompt.TextColor3 = ALERT
	elseif kind == "cancelled" then
		refreshPrompt()
	elseif kind == "no_chip" then
		prompt.Text = "your chip is still on a civilian — go collect it"
		prompt.TextColor3 = ALERT
	elseif kind == "locked" then
		prompt.Text = ("chip not ready to collect — %ds"):format(math.ceil(value or 0))
		prompt.TextColor3 = ALERT
	elseif kind == "retrieved" then
		showBanner("chip recovered", GOOD, 1.5)
		refreshPrompt()
	elseif kind == "cap_reached" then
		prompt.Text = "you have used all your chips this round"
		prompt.TextColor3 = ALERT
	end
end)

Remotes.event("ChipResolved").OnClientEvent:Connect(function(kind: string)
	if kind == "breakout" then
		showBanner("SHE BROKE OUT", ALERT, 3)
	elseif kind == "wrong" then
		showBanner("wrong civilian — your chip is stuck on them", ALERT, 3)
	elseif kind == "caught" then
		showBanner("CONTAINED", GOOD, 4)
	end
	refreshPrompt()
end)

Remotes.event("RoundEnded").OnClientEvent:Connect(function(outcome: string)
	local text = if outcome == "RunnerEscaped"
		then "SHE ESCAPED"
		elseif outcome == "RunnerChipped" then "CONTAINED"
		elseif outcome == "Timeout" then "TIME — CONTAINMENT HOLDS"
		else "ROUND ABORTED"

	local won = if role == "Runner"
		then outcome == "RunnerEscaped"
		else outcome == "RunnerChipped" or outcome == "Timeout"

	showBanner(text, if won then GOOD else ALERT, Config.Round.EndScreenDuration - 1)
	prompt.Text = ""
	clock.Text = ""
end)

clock.Text = "waiting for players"
clock.TextColor3 = DIM
