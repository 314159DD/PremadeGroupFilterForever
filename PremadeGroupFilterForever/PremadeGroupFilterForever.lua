local defaults = {
	enabled = true,
	hideSoloDps = false,
	needTank = false,
	needHealer = false,
	minDpsFree = 0,
}

local db
local button
local hiddenCount = 0

local function IsSoloTankOrHealer(resultID)
	local leader = C_LFGList.GetSearchResultLeaderInfo(resultID)
	if not leader then
		return false
	end
	local roles = leader.lfgRoles
	if roles then
		return roles.tank == true or roles.healer == true
	end
	return leader.assignedRole == "TANK" or leader.assignedRole == "HEALER"
end

local function Passes(resultID)
	local info = C_LFGList.GetSearchResultInfo(resultID)
	if not info or info.hasSelf then
		return true
	end

	if (info.numMembers or 0) <= 1 then
		if db.hideSoloDps and not IsSoloTankOrHealer(resultID) then
			return false
		end
		return true
	end

	if db.needTank or db.needHealer or db.minDpsFree > 0 then
		local counts = C_LFGList.GetSearchResultMemberCounts(resultID)
		if counts then
			if db.needTank and (counts.TANK or 0) < 1 then
				return false
			end
			if db.needHealer and (counts.HEALER or 0) < 1 then
				return false
			end
			if (counts.DAMAGER_REMAINING or 0) < db.minDpsFree then
				return false
			end
		end
	end
	return true
end

local function UpdateButton()
	if not button then return end
	if not db.enabled then
		button:SetText("Filter: off")
	elseif hiddenCount > 0 then
		button:SetText("Filter: " .. hiddenCount .. " hidden")
	else
		button:SetText("Filter")
	end
end

local function ApplyFilter(frame)
	hiddenCount = 0
	local results = frame.results
	if db.enabled and type(results) == "table" then
		local kept = {}
		for i = 1, #results do
			local id = results[i]

			local ok, pass = pcall(Passes, id)
			if not ok or pass then
				kept[#kept + 1] = id
			else
				hiddenCount = hiddenCount + 1
			end
		end
		if hiddenCount > 0 then
			wipe(results)
			for i = 1, #kept do
				results[i] = kept[i]
			end
			frame:UpdateResults()
		end
	end
	UpdateButton()
end

local function Refresh()
	local frame = LFGBrowseFrame
	if frame and frame:IsShown() and frame.UpdateResultList then
		frame:UpdateResultList()
	else
		UpdateButton()
	end
end

local function Toggle(key)
	return function()
		db[key] = not db[key]
		Refresh()
	end
end

local function Checked(key)
	return function() return db[key] end
end

local function OpenMenu(owner)
	MenuUtil.CreateContextMenu(owner, function(_, root)
		root:CreateTitle("Premade Group Filter")
		root:CreateCheckbox("Filter on", Checked("enabled"), Toggle("enabled"))

		root:CreateDivider()
		root:CreateTitle("Solo players")
		root:CreateCheckbox("Solo players: tanks and healers only", Checked("hideSoloDps"), Toggle("hideSoloDps"))

		root:CreateDivider()
		root:CreateTitle("Groups")
		root:CreateCheckbox("Has a tank", Checked("needTank"), Toggle("needTank"))
		root:CreateCheckbox("Has a healer", Checked("needHealer"), Toggle("needHealer"))
		local slots = root:CreateButton("Free DPS slots")
		for n = 0, 3 do
			slots:CreateRadio(n == 0 and "Any" or (n .. " or more"),
				function() return db.minDpsFree == n end,
				function() db.minDpsFree = n; Refresh() end)
		end
	end)
end

local function Setup()
	local frame = LFGBrowseFrame
	if button or not frame or not frame.UpdateResultList or not frame.UpdateResults then
		return
	end
	hooksecurefunc(frame, "UpdateResultList", ApplyFilter)

	button = CreateFrame("Button", "PremadeGroupFilterForeverButton", frame, "UIPanelButtonTemplate")
	button:SetHeight(22)
	local left, right = frame.SendMessageButton, frame.GroupInviteButton
	if left and right then
		button:SetPoint("LEFT", left, "RIGHT", 6, 0)
		button:SetPoint("RIGHT", right, "LEFT", -6, 0)
	else
		button:SetWidth(140)
		button:SetPoint("BOTTOM", frame, "BOTTOM", 0, 6)
	end
	button:SetScript("OnClick", function(self)
		if MenuUtil and MenuUtil.CreateContextMenu then
			OpenMenu(self)
		else
			print("|cff66ccffPremade Group Filter:|r type /pgf for the options.")
		end
	end)
	UpdateButton()
end

local function PrintState()
	local function onoff(v) return v and "|cff40ff40on|r" or "|cff999999off|r" end
	print("|cff66ccffPremade Group Filter Forever|r " .. onoff(db.enabled))
	print("  /pgf solodps: solo players, tanks and healers only " .. onoff(db.hideSoloDps))
	print("  /pgf tank: groups with a tank " .. onoff(db.needTank))
	print("  /pgf healer: groups with a healer " .. onoff(db.needHealer))
	print("  /pgf dps 0-3: free DPS slots, now " .. db.minDpsFree)
	print("  /pgf on | off")
end

SLASH_PREMADEGROUPFILTERFOREVER1 = "/pgf"
SLASH_PREMADEGROUPFILTERFOREVER2 = "/groupfilter"
SlashCmdList.PREMADEGROUPFILTERFOREVER = function(msg)
	local cmd, arg = strsplit(" ", strlower(strtrim(msg or "")), 2)
	local keys = { solodps = "hideSoloDps", tank = "needTank", healer = "needHealer" }
	if cmd == "on" or cmd == "off" then
		db.enabled = cmd == "on"
	elseif keys[cmd] then
		db[keys[cmd]] = not db[keys[cmd]]
	elseif cmd == "dps" and tonumber(arg) then
		db.minDpsFree = math.max(0, math.min(3, math.floor(tonumber(arg))))
	end
	Refresh()
	PrintState()
end

local events = CreateFrame("Frame")
events:RegisterEvent("ADDON_LOADED")
events:RegisterEvent("PLAYER_LOGIN")
events:SetScript("OnEvent", function(_, event, name)
	if event == "ADDON_LOADED" and name == "PremadeGroupFilterForever" then
		PremadeGroupFilterForeverDB = PremadeGroupFilterForeverDB or {}
		db = PremadeGroupFilterForeverDB
		for key, value in pairs(defaults) do
			if db[key] == nil then db[key] = value end
		end
	end

	if db then Setup() end
end)
