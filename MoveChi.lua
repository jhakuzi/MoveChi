local ADDON_NAME = ...

local MIN_WIDTH, MIN_HEIGHT = 160, 54
local SCALE_MIN, SCALE_MAX, SCALE_STEP = 0.5, 2.5, 0.05

local db
local applying
local hooked
local unlocked
local dragging
local pendingUnlock
local pendingReset
local defaultParent
local hinted

local overlay

local function Print(msg)
	DEFAULT_CHAT_FRAME:AddMessage("|cff4ec3ffMoveChi|r: " .. msg)
end

local function GetContainer()
	if GetPlayerBottomManagedFrameContainer then
		local container = GetPlayerBottomManagedFrameContainer()
		if container then
			return container
		end
	end
	return _G.PlayerBottomManagedFrameContainer or _G.PlayerFrameBottomManagedFramesContainer
end

local function HasCustomPosition()
	return db and db.point ~= nil
end

local function ClampScale(scale)
	scale = tonumber(scale)
	if not scale then
		return nil
	end
	return math.max(SCALE_MIN, math.min(SCALE_MAX, scale))
end

local function ApplyPosition()
	if applying then
		return
	end
	local container = GetContainer()
	if not container or not db then
		return
	end

	applying = true
	if db.scale then
		container:SetScale(db.scale)
	end
	if HasCustomPosition() then
		if container:GetParent() ~= UIParent then
			container:SetParent(UIParent)
		end
		container:ClearAllPoints()
		container:SetPoint(db.point, UIParent, db.relativePoint or db.point, db.x or 0, db.y or 0)
	end
	applying = false
end

local function SavePosition()
	local container = GetContainer()
	if not container then
		return
	end
	local x, y = container:GetCenter()
	if not x then
		return
	end
	local scale = container:GetEffectiveScale()
	local uiScale = UIParent:GetEffectiveScale()
	x = x * scale / uiScale
	y = y * scale / uiScale
	db.point = "CENTER"
	db.relativePoint = "CENTER"
	db.x = x - (UIParent:GetWidth() / 2)
	db.y = y - (UIParent:GetHeight() / 2)
	db.scale = container:GetScale()
end

local function DetachForMove(container)
	local x, y = container:GetCenter()
	local effective = container:GetEffectiveScale()
	local uiScale = UIParent:GetEffectiveScale()
	applying = true
	if container:GetParent() ~= UIParent then
		container:SetParent(UIParent)
	end
	container:SetScale(effective / uiScale)
	if x then
		x = x * effective / uiScale
		y = y * effective / uiScale
		container:ClearAllPoints()
		container:SetPoint("CENTER", UIParent, "BOTTOMLEFT", x, y)
	end
	container:SetMovable(true)
	container:SetClampedToScreen(true)
	applying = false
end

local function RestoreDefault()
	local container = GetContainer()
	if not container then
		return
	end

	applying = true
	db.point = nil
	db.relativePoint = nil
	db.x = nil
	db.y = nil
	db.scale = nil
	container:SetScale(1)
	container:SetParent(defaultParent or PlayerFrame or UIParent)
	container:ClearAllPoints()
	container:SetPoint("TOP", PlayerFrame, "BOTTOM", 30, 25)
	if container.Layout then
		container:Layout()
	end
	applying = false
end

local function UpdateOverlay()
	if not overlay or not unlocked then
		return
	end
	local container = GetContainer()
	if not container then
		return
	end
	overlay:SetParent(container)
	overlay:SetFrameStrata("DIALOG")
	overlay:ClearAllPoints()
	overlay:SetPoint("CENTER", container, "CENTER")
	overlay:SetSize(math.max(container:GetWidth() or 0, MIN_WIDTH), math.max(container:GetHeight() or 0, MIN_HEIGHT))
end

local function SetUnlocked(state)
	if InCombatLockdown() then
		pendingUnlock = state
		Print("waiting until combat ends.")
		return
	end

	local container = GetContainer()
	if not container then
		Print("class resource bar not found.")
		return
	end

	unlocked = state and true or false
	if unlocked then
		container:SetMovable(true)
		container:SetClampedToScreen(true)
		UpdateOverlay()
		overlay:Show()
		if not hinted then
			hinted = true
			Print("drag to move, mousewheel to scale, click Lock when done.")
		end
	else
		if dragging then
			dragging = false
			container:StopMovingOrSizing()
			SavePosition()
			ApplyPosition()
		end
		overlay:Hide()
		overlay:SetParent(UIParent)
	end
end

local function Reset()
	if InCombatLockdown() then
		pendingReset = true
		Print("reset queued until combat ends.")
		return
	end
	SetUnlocked(false)
	RestoreDefault()
	Print("position restored to the player frame.")
end

local function SetScale(scale)
	scale = ClampScale(scale)
	if not scale then
		Print("usage: /movechi scale 1.2")
		return
	end
	local container = GetContainer()
	if not container then
		return
	end
	db.scale = scale
	container:SetScale(scale)
	if HasCustomPosition() then
		ApplyPosition()
	end
	Print(string.format("scale set to %.2f.", scale))
end

local function Setup()
	local container = GetContainer()
	if not container then
		return false
	end
	if not defaultParent then
		defaultParent = container:GetParent()
	end
	if hooked then
		return true
	end
	hooked = true
	hooksecurefunc(container, "SetPoint", function()
		if applying then
			return
		end
		if HasCustomPosition() then
			ApplyPosition()
		end
	end)
	hooksecurefunc(container, "SetParent", function(_, parent)
		if applying then
			return
		end
		if HasCustomPosition() and parent ~= UIParent then
			ApplyPosition()
		end
	end)
	if container.Layout then
		hooksecurefunc(container, "Layout", UpdateOverlay)
	end
	return true
end

overlay = CreateFrame("Frame", "MoveChiMover", UIParent, "BackdropTemplate")
overlay:SetFrameStrata("DIALOG")
overlay:SetClampedToScreen(true)
overlay:EnableMouse(true)
overlay:EnableMouseWheel(true)
overlay:RegisterForDrag("LeftButton")
overlay:Hide()
overlay:SetBackdrop({
	bgFile = "Interface\\Buttons\\WHITE8X8",
	edgeFile = "Interface\\Buttons\\WHITE8X8",
	edgeSize = 1,
})
overlay:SetBackdropColor(0.05, 0.55, 0.9, 0.28)
overlay:SetBackdropBorderColor(0.4, 0.85, 1, 0.95)

local label = overlay:CreateFontString(nil, "OVERLAY", "GameFontNormal")
label:SetPoint("TOP", 0, -6)
label:SetText("MoveChi")

local lockButton = CreateFrame("Button", "MoveChiLockButton", overlay, "UIPanelButtonTemplate")
lockButton:SetSize(56, 20)
lockButton:SetPoint("BOTTOM", 0, 6)
lockButton:SetText("Lock")
lockButton:SetScript("OnClick", function()
	SetUnlocked(false)
end)

overlay:SetScript("OnDragStart", function()
	if InCombatLockdown() then
		return
	end
	local container = GetContainer()
	if not container then
		return
	end
	DetachForMove(container)
	container:StartMoving()
	dragging = true
end)

overlay:SetScript("OnDragStop", function()
	if not dragging then
		return
	end
	dragging = false
	local container = GetContainer()
	if not container then
		return
	end
	container:StopMovingOrSizing()
	SavePosition()
	ApplyPosition()
	UpdateOverlay()
end)

overlay:SetScript("OnMouseWheel", function(_, delta)
	local container = GetContainer()
	if not container then
		return
	end
	local scale = ClampScale((db.scale or container:GetScale() or 1) + (delta * SCALE_STEP))
	db.scale = scale
	container:SetScale(scale)
end)

local function PrintHelp()
	Print("/movechi — unlock or lock the resource bar")
	Print("/movechi reset — restore default position")
	Print("/movechi scale 1.2 — set scale")
end

SLASH_MOVECHI1 = "/movechi"
SLASH_MOVECHI2 = "/mchi"
SLASH_MOVECHI3 = "/movebar"
SlashCmdList.MOVECHI = function(msg)
	msg = string.lower((msg or ""):gsub("^%s+", ""):gsub("%s+$", ""))
	if msg == "" then
		SetUnlocked(not unlocked)
	elseif msg == "unlock" then
		SetUnlocked(true)
	elseif msg == "lock" then
		SetUnlocked(false)
	elseif msg == "reset" then
		Reset()
	elseif msg:match("^scale") then
		SetScale(msg:match("^scale%s+([%d%.]+)"))
	elseif msg == "help" then
		PrintHelp()
	else
		PrintHelp()
	end
end

local events = CreateFrame("Frame")
events:RegisterEvent("ADDON_LOADED")
events:SetScript("OnEvent", function(self, event, arg1)
	if event == "ADDON_LOADED" then
		if arg1 ~= ADDON_NAME then
			return
		end
		MoveChiDB = MoveChiDB or {}
		db = MoveChiDB
		self:UnregisterEvent("ADDON_LOADED")
		self:RegisterEvent("PLAYER_LOGIN")
		self:RegisterEvent("PLAYER_ENTERING_WORLD")
		self:RegisterEvent("PLAYER_REGEN_ENABLED")
		self:RegisterEvent("PLAYER_SPECIALIZATION_CHANGED")
	elseif event == "PLAYER_LOGIN" or event == "PLAYER_ENTERING_WORLD" then
		if Setup() then
			ApplyPosition()
			C_Timer.After(0, ApplyPosition)
		else
			C_Timer.After(1, function()
				if Setup() then
					ApplyPosition()
				end
			end)
		end
	elseif event == "PLAYER_SPECIALIZATION_CHANGED" then
		if arg1 == "player" or arg1 == nil then
			ApplyPosition()
			UpdateOverlay()
		end
	elseif event == "PLAYER_REGEN_ENABLED" then
		if pendingReset then
			pendingReset = nil
			pendingUnlock = nil
			Reset()
			return
		end
		if pendingUnlock ~= nil then
			local state = pendingUnlock
			pendingUnlock = nil
			SetUnlocked(state)
		end
	end
end)
