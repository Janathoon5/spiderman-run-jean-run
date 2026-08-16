--!strict
--[[
	Minimal HUD: role reveal, round clock, objective count, and the prompts
	that tell you what your key does right now.

	Built in code rather than authored as instances so it lives in the repo as
	diffable text - per the source-of-truth split, anything created by hand in
	the Studio Explorer would never sync back.

	Layout uses a UIListLayout with auto-sized labels rather than hand-placed
	offsets. Hand-computed positions assume every string fits on one line, and
	they silently overlap the moment one wraps.

	Text is ASCII only. Fancy punctuation survives poorly through tooling that
	rewrites the file, and a mojibake HUD is worse than a plain one.
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

-- ----------------------------------------------------------------- build ----

local screen = Instance.new("ScreenGui")
screen.Name = "HUD"
screen.ResetOnSpawn = false
screen.IgnoreGuiInset = true
screen.ZIndexBehavior = Enum.ZIndexBehavior.Sibling
screen.Parent = playerGui

--[[
	A vertical stack. Children are auto-height, so the layout reflows instead
	of letting a wrapped line spill into whatever sits below it.
]]
local function stack(name: string, anchorY: number, positionY: number): Frame
	local frame = Instance.new("Frame")
	frame.Name = name
	frame.AnchorPoint = Vector2.new(0.5, anchorY)
	frame.Position = UDim2.fromScale(0.5, positionY)
	frame.Size = UDim2.fromScale(0.8, 0)
	frame.AutomaticSize = Enum.AutomaticSize.Y
	frame.BackgroundTransparency = 1
	frame.Parent = screen

	local layout = Instance.new("UIListLayout")
	layout.FillDirection = Enum.FillDirection.Vertical
	layout.HorizontalAlignment = Enum.HorizontalAlignment.Center
	layout.SortOrder = Enum.SortOrder.LayoutOrder
	layout.Padding = UDim.new(0, 6)
	layout.Parent = frame

	return frame
end

local function label(
	parent: Frame,
	name: string,
	order: number,
	textSize: number,
	font: Enum.Font
): TextLabel
	local text = Instance.new("TextLabel")
	text.Name = name
	text.LayoutOrder = order
	-- Full width, height driven by content - the bit that prevents overlap.
	text.Size = UDim2.fromScale(1, 0)
	text.AutomaticSize = Enum.AutomaticSize.Y
	text.BackgroundTransparency = 1
	text.Font = font
	text.TextSize = textSize
	text.TextColor3 = INK
	-- Stroke rather than a backdrop panel: readable over any map without
	-- boxing the screen in with chrome.
	text.TextStrokeTransparency = 0.4
	text.TextWrapped = true
	text.Text = ""
	text.Visible = false
	text.Parent = parent
	return text
end

local topStack = stack("Top", 0, 0.03)
local clock = label(topStack, "Clock", 1, 38, Enum.Font.GothamBold)
local status = label(topStack, "Status", 2, 18, Enum.Font.GothamMedium)
status.TextColor3 = DIM

local centerStack = stack("Center", 0.5, 0.42)
local bannerTitle = label(centerStack, "BannerTitle", 1, 46, Enum.Font.GothamBold)
local bannerSub = label(centerStack, "BannerSub", 2, 22, Enum.Font.GothamMedium)

local bottomStack = stack("Bottom", 1, 0.93)
local prompt = label(bottomStack, "Prompt", 1, 20, Enum.Font.GothamMedium)

-- ---------------------------------------------------------------- helpers ----

--[[
	Sets text and hides the label when there is nothing to say.

	An empty auto-sized label still occupies a slot and its layout padding, so
	blank strings leave gaps and stale spacing on screen. Tying Visible to
	content means the HUD only ever shows what is currently relevant.
]]
local function setText(target: TextLabel, text: string)
	target.Text = text
	target.Visible = text ~= ""
end

-- Incremented per banner so a stale fade cannot wipe a newer message, and a
-- newer message cannot be left on screen by an older timer.
local bannerToken = 0

local function showBanner(title: string, subtitle: string, color: Color3, holdFor: number)
	bannerToken += 1
	local token = bannerToken

	setText(bannerTitle, title)
	bannerTitle.TextColor3 = color
	bannerTitle.TextTransparency = 0

	setText(bannerSub, subtitle)
	bannerSub.TextColor3 = color
	bannerSub.TextTransparency = 0.15

	task.delay(holdFor, function()
		if token ~= bannerToken then
			return -- superseded
		end

		local fade = TweenInfo.new(0.5)
		TweenService:Create(bannerTitle, fade, { TextTransparency = 1 }):Play()
		TweenService:Create(bannerSub, fade, { TextTransparency = 1 }):Play()

		-- Hide outright once faded. Leaving the text set is what let old
		-- messages ghost through behind later ones.
		task.delay(0.55, function()
			if token == bannerToken then
				setText(bannerTitle, "")
				setText(bannerSub, "")
			end
		end)
	end)
end

local function formatClock(seconds: number): string
	local whole = math.max(0, math.floor(seconds + 0.5))
	return ("%d:%02d"):format(whole // 60, whole % 60)
end

--[[
	The prompt is the whole tutorial. Nobody reads instructions, so the bottom
	line always says what E does for you right now.
]]
local function refreshPrompt()
	if roundState ~= "Active" then
		setText(prompt, "")
		return
	end

	prompt.TextColor3 = INK

	if role == "Runner" then
		setText(prompt, "[E] jump into a nearby civilian")
	elseif role == "Tracker" then
		setText(prompt, "[Hold E] chip     [E] retrieve your chip     [Q] sense")
	elseif role == "Agent" then
		setText(prompt, "[Hold E] chip a civilian     [E] retrieve your chip")
	else
		setText(prompt, "")
	end
end

local lastClaimed, lastRequired = 0, Config.Objective.RequiredToWin

local function refreshStatus()
	if roundState ~= "Active" or role == "None" then
		setText(status, "")
		return
	end
	setText(status, ("%s     sites %d/%d"):format(string.upper(role), lastClaimed, lastRequired))
	status.TextColor3 = if lastClaimed >= lastRequired then GOOD else DIM
end

-- ----------------------------------------------------------------- clock ----

--[[
	Ticked locally and re-seeded whenever the server sends an update.

	The server only broadcasts every ten seconds; counting down client-side
	between syncs gives a clock that moves every second without putting a
	remote call per player per second on the wire.
]]
local deadline = 0

local function updateClock()
	if roundState ~= "Active" then
		return
	end

	local remaining = math.max(0, deadline - os.clock())
	setText(clock, formatClock(remaining))
	clock.TextColor3 = if remaining <= 30 then ALERT else INK
end

task.spawn(function()
	while true do
		task.wait(0.25)
		updateClock()
	end
end)

-- ---------------------------------------------------------------- remotes ----

Remotes.event("RoleAssigned").OnClientEvent:Connect(function(assigned: string)
	role = assigned

	local subtitle = if assigned == "Runner"
		then "Blend in. Claim " .. Config.Objective.RequiredToWin .. " sites to escape."
		elseif assigned == "Tracker" then "Find her. You move faster than anyone else."
		else "One chip. Make it count."

	showBanner("YOU ARE THE " .. string.upper(assigned), subtitle, INK, 4)
	refreshPrompt()
	refreshStatus()
end)

Remotes.event("RoundStateChanged").OnClientEvent
	:Connect(function(state: string, timeRemaining: number)
		roundState = state

		if state == "Active" then
			deadline = os.clock() + (timeRemaining or 0)
			updateClock()
		elseif state == "Starting" then
			setText(clock, "get ready")
			clock.TextColor3 = DIM
		elseif state == "Lobby" then
			role = "None"
			lastClaimed = 0
			setText(clock, "waiting for players")
			clock.TextColor3 = DIM
		end

		refreshPrompt()
		refreshStatus()
	end)

Remotes.event("ObjectiveProgress").OnClientEvent:Connect(function(claimed: number, required: number)
	lastClaimed, lastRequired = claimed, required
	refreshStatus()
end)

Remotes.event("ChipProgress").OnClientEvent:Connect(function(kind: string, value: number)
	if kind == "incoming" then
		-- The most important message in the game - she has three seconds.
		showBanner("A CHIP IS GOING ON YOU", "[F] break out, but they will see you", ALERT, 3)
	elseif kind == "holding" then
		setText(prompt, ("attaching...  %d%%"):format(math.floor((value or 0) * 100)))
		prompt.TextColor3 = ALERT
	elseif kind == "cancelled" then
		refreshPrompt()
	elseif kind == "no_chip" then
		setText(prompt, "your chip is still on a civilian - go collect it")
		prompt.TextColor3 = ALERT
	elseif kind == "locked" then
		setText(prompt, ("chip not ready to collect - %ds"):format(math.ceil(value or 0)))
		prompt.TextColor3 = ALERT
	elseif kind == "out_cold" then
		setText(prompt, "that one is out cold - it cannot be her")
		prompt.TextColor3 = ALERT
	elseif kind == "retrieved" then
		showBanner("chip recovered", "", GOOD, 1.5)
		refreshPrompt()
	elseif kind == "cap_reached" then
		setText(prompt, "you have used all your chips this round")
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
		elseif outcome == "Timeout" then "TIME - CONTAINMENT HOLDS"
		else "ROUND ABORTED"

	local won = if role == "Runner"
		then outcome == "RunnerEscaped"
		else outcome == "RunnerChipped" or outcome == "Timeout"

	showBanner(text, "", if won then GOOD else ALERT, Config.Round.EndScreenDuration - 1)
	setText(prompt, "")
	setText(status, "")
	setText(clock, "")
end)

setText(clock, "waiting for players")
clock.TextColor3 = DIM
