--!strict
--[[
	Minimal HUD: role reveal, round clock, objective count, and the prompts
	that tell you what your key does right now.

	Built in code rather than authored as instances so it lives in the repo as
	diffable text — per the source-of-truth split, anything created by hand in
	the Studio Explorer would never sync back.

	Layout is banded into fixed, non-overlapping regions down the screen. Every
	label wraps, and the banner clears its text once faded, so nothing can
	linger behind a later message.
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
local DIM = Color3.fromRGB(155, 165, 180)
local ALERT = Color3.fromRGB(255, 120, 90)
local GOOD = Color3.fromRGB(120, 220, 150)

-- Fixed vertical bands, as Y scale. Nothing may cross a neighbour's range —
-- overlapping text was the original bug here.
local BAND_CLOCK = 0.02
local BAND_STATUS = 0.095
local BAND_BANNER = 0.36
local BAND_BANNER_SUB = 0.45
local BAND_PROMPT = 0.87

-- ----------------------------------------------------------------- build ----

local screen = Instance.new("ScreenGui")
screen.Name = "HUD"
screen.ResetOnSpawn = false
screen.IgnoreGuiInset = true
screen.ZIndexBehavior = Enum.ZIndexBehavior.Sibling
screen.Parent = playerGui

local function label(
	name: string,
	heightScale: number,
	bandY: number,
	textSize: number,
	font: Enum.Font
): TextLabel
	local text = Instance.new("TextLabel")
	text.Name = name
	text.AnchorPoint = Vector2.new(0.5, 0)
	text.Size = UDim2.fromScale(0.8, heightScale)
	text.Position = UDim2.fromScale(0.5, bandY)
	text.BackgroundTransparency = 1
	text.Font = font
	text.TextSize = textSize
	text.TextColor3 = INK
	-- Stroke rather than a backdrop panel: readable over any map without
	-- boxing the screen in with chrome.
	text.TextStrokeTransparency = 0.4
	text.TextWrapped = true
	text.Text = ""
	text.Parent = screen
	return text
end

local clock = label("Clock", 0.07, BAND_CLOCK, 36, Enum.Font.GothamBold)
local status = label("Status", 0.04, BAND_STATUS, 18, Enum.Font.GothamMedium)
status.TextColor3 = DIM

local bannerTitle = label("BannerTitle", 0.08, BAND_BANNER, 46, Enum.Font.GothamBold)
local bannerSub = label("BannerSub", 0.05, BAND_BANNER_SUB, 22, Enum.Font.GothamMedium)

local prompt = label("Prompt", 0.05, BAND_PROMPT, 20, Enum.Font.GothamMedium)

bannerTitle.TextTransparency = 1
bannerSub.TextTransparency = 1

-- ---------------------------------------------------------------- helpers ----

-- Incremented per banner so a stale fade cannot wipe a newer message, and a
-- newer message cannot be left on screen by an older timer.
local bannerToken = 0

local function showBanner(title: string, subtitle: string, color: Color3, holdFor: number)
	bannerToken += 1
	local token = bannerToken

	bannerTitle.Text = title
	bannerTitle.TextColor3 = color
	bannerTitle.TextTransparency = 0

	bannerSub.Text = subtitle
	bannerSub.TextColor3 = color
	bannerSub.TextTransparency = if subtitle == "" then 1 else 0.15

	task.delay(holdFor, function()
		if token ~= bannerToken then
			return -- superseded
		end

		local fade = TweenInfo.new(0.5)
		TweenService:Create(bannerTitle, fade, { TextTransparency = 1 }):Play()
		TweenService:Create(bannerSub, fade, { TextTransparency = 1 }):Play()

		-- Clear the text too. Leaving it set is what let old messages show
		-- through behind later ones.
		task.delay(0.55, function()
			if token == bannerToken then
				bannerTitle.Text = ""
				bannerSub.Text = ""
			end
		end)
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

	prompt.TextColor3 = INK

	if role == "Runner" then
		prompt.Text = "[E] jump into a nearby civilian"
	elseif role == "Tracker" then
		prompt.Text = "[Hold E] chip   ·   [E] retrieve your chip   ·   [Q] sense"
	elseif role == "Agent" then
		prompt.Text = "[Hold E] chip a civilian   ·   [E] retrieve your chip"
	else
		prompt.Text = ""
	end
end

local function refreshStatus(claimed: number?, required: number?)
	if roundState ~= "Active" then
		status.Text = ""
		return
	end

	local parts = { string.upper(role) }
	if claimed and required then
		table.insert(parts, ("sites %d/%d"):format(claimed, required))
	end
	status.Text = table.concat(parts, "   ·   ")
end

-- ---------------------------------------------------------------- remotes ----

local lastClaimed, lastRequired = 0, Config.Objective.RequiredToWin

Remotes.event("RoleAssigned").OnClientEvent:Connect(function(assigned: string)
	role = assigned

	local subtitle = if assigned == "Runner"
		then "Blend in. Claim " .. Config.Objective.RequiredToWin .. " sites to escape."
		elseif assigned == "Tracker" then "Find her. You move faster than anyone else."
		else "One chip. Make it count."

	showBanner("YOU ARE THE " .. string.upper(assigned), subtitle, INK, 4)
	refreshPrompt()
	refreshStatus(lastClaimed, lastRequired)
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
		elseif state == "Lobby" then
			role = "None"
			lastClaimed = 0
			clock.Text = "waiting for players"
			clock.TextColor3 = DIM
		end

		refreshPrompt()
		refreshStatus(lastClaimed, lastRequired)
	end)

Remotes.event("ObjectiveProgress").OnClientEvent:Connect(function(claimed: number, required: number)
	lastClaimed, lastRequired = claimed, required
	refreshStatus(claimed, required)
end)

Remotes.event("ChipProgress").OnClientEvent:Connect(function(kind: string, value: number)
	if kind == "incoming" then
		-- The most important message in the game — she has three seconds.
		showBanner("A CHIP IS GOING ON YOU", "[F] break out — but they will see you", ALERT, 3)
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
		showBanner("chip recovered", "", GOOD, 1.5)
		refreshPrompt()
	elseif kind == "cap_reached" then
		prompt.Text = "you have used all your chips this round"
		prompt.TextColor3 = ALERT
	end
end)

Remotes.event("ChipResolved").OnClientEvent:Connect(function(kind: string)
	if kind == "breakout" then
		showBanner("SHE BROKE OUT", "that civilian was her a second ago", ALERT, 3)
	elseif kind == "wrong" then
		showBanner("wrong civilian", "your chip is stuck on them until you collect it", ALERT, 3)
	elseif kind == "caught" then
		showBanner("CONTAINED", "", GOOD, 4)
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

	showBanner(text, "", if won then GOOD else ALERT, Config.Round.EndScreenDuration - 1)
	prompt.Text = ""
	status.Text = ""
	clock.Text = ""
end)

clock.Text = "waiting for players"
clock.TextColor3 = DIM
