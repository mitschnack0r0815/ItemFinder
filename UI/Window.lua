local _, ns = ...

-- Styled after the new spellbook, like WoW Notes: an open book with the search form and
-- scan controls on the left page and the results on the right page. Uses the spellbook's
-- own atlases; on a client without them the art falls back to plain colors.

local ROW_HEIGHT = 50
local PAGE_MARGIN = 56 -- space between a page's edges and its content
local BLIZZARD_BOOK_HEIGHT = 832 -- height of the spellbook pages, to scale the ribbon
local REFRESH_INTERVAL = 1 -- seconds between list refreshes while the scan finds items

local GetItemInfo = C_Item and C_Item.GetItemInfo or GetItemInfo
local GetItemInfoInstant = C_Item and C_Item.GetItemInfoInstant or GetItemInfoInstant

local FONT_COLOR = SPELLBOOK_FONT_COLOR or CreateColor(0.25, 0.16, 0.08)

local function Font(name, fallback)
	return _G[name] and name or fallback
end
local HEADER_FONT = Font("SystemFont_Huge2", "GameFontNormalHuge")
local NAME_FONT = Font("SystemFont_Large", "GameFontNormalLarge")
local SMALL_FONT = Font("SystemFont_Med1", "GameFontNormal")

local function GetAtlas(atlas)
	return C_Texture and C_Texture.GetAtlasInfo and C_Texture.GetAtlasInfo(atlas)
end

local function HasTemplate(template)
	return C_XMLUtil and C_XMLUtil.GetTemplateInfo and C_XMLUtil.GetTemplateInfo(template)
end

-- Sets a spellbook atlas, or a plain color when this client doesn't have it
local function SetArt(texture, atlas, r, g, b, a)
	if GetAtlas(atlas) then
		texture:SetAtlas(atlas)
	else
		texture:SetColorTexture(r or 0, g or 0, b or 0, a or 0)
	end
end

local function CreateText(parent, font)
	local text = parent:CreateFontString(nil, "ARTWORK", font)
	text:SetTextColor(FONT_COLOR:GetRGB())
	text:SetJustifyH("LEFT")
	return text
end

-- Quality colors are made for dark tooltips; darken them so they read on the parchment.
-- Poor and common items use the page's ink color.
local function SetQualityColor(text, quality)
	local color = quality and quality >= 2 and ITEM_QUALITY_COLORS and ITEM_QUALITY_COLORS[quality]
	if color then
		text:SetTextColor(color.r * 0.6, color.g * 0.6, color.b * 0.6)
	else
		text:SetTextColor(FONT_COLOR:GetRGB())
	end
end

-- "Cloth Chest", "Consumable Potion", ...
local function GetItemDescription(itemID)
	local _, itemType, subType, equipLoc = GetItemInfoInstant(itemID)
	local slot = equipLoc and equipLoc ~= "" and _G[equipLoc]
	if slot then
		return subType and subType ~= itemType and (subType .. " " .. slot) or slot
	end
	if subType and subType ~= itemType then
		return (itemType or "") .. " - " .. subType
	end
	return itemType or ""
end

---------------------------------------------------------------------------
-- Window and book
---------------------------------------------------------------------------

local window = CreateFrame("Frame", "ItemFinderMainFrame", UIParent,
	HasTemplate("PortraitFrameTemplate") and "PortraitFrameTemplate" or "BasicFrameTemplate")
window:SetSize(900, 600)
window:SetPoint("CENTER")
window:SetFrameStrata("HIGH")
window:SetToplevel(true)
window:SetClampedToScreen(true)
window:EnableMouse(true)
window:SetMovable(true)
window:RegisterForDrag("LeftButton")
window:SetScript("OnDragStart", window.StartMoving)
window:SetScript("OnDragStop", window.StopMovingOrSizing)
window:Hide()
tinsert(UISpecialFrames, "ItemFinderMainFrame") -- close with Escape

if window.SetTitle then
	window:SetTitle("Item Finder")
elseif window.TitleText then
	window.TitleText:SetText("Item Finder")
end
if window.SetPortraitToAsset then
	window:SetPortraitToAsset(ns.ICON)
end

local book = CreateFrame("Frame", nil, window)
book:SetPoint("TOPLEFT", 2, -21)
book:SetPoint("BOTTOMRIGHT", -2, 2)

local topBar = book:CreateTexture(nil, "BACKGROUND", nil, 1)
topBar:SetPoint("TOPLEFT")
topBar:SetPoint("TOPRIGHT")
topBar:SetHeight(54)
SetArt(topBar, "spellbook-background-evergreen-header", 0.12, 0.09, 0.06, 1)

local leftBG = book:CreateTexture(nil, "BACKGROUND", nil, 1)
leftBG:SetPoint("TOPLEFT", 0, -51)
leftBG:SetPoint("BOTTOMRIGHT", book, "BOTTOM")
SetArt(leftBG, "spellbook-background-evergreen-left", 0.82, 0.72, 0.54, 1)

local rightBG = book:CreateTexture(nil, "BACKGROUND", nil, 1)
rightBG:SetPoint("TOPLEFT", book, "TOP", 0, -51)
rightBG:SetPoint("BOTTOMRIGHT")
SetArt(rightBG, "spellbook-background-evergreen-right", 0.82, 0.72, 0.54, 1)

-- Bookmark ribbon hanging over the spine, scaled down with the book
local ribbonInfo = GetAtlas("spellbook-background-evergreen-ribbon")
if ribbonInfo then
	local ribbon = book:CreateTexture(nil, "BACKGROUND", nil, 2)
	ribbon:SetAtlas("spellbook-background-evergreen-ribbon")
	book:SetScript("OnSizeChanged", function(self, width, height)
		local scale = (height - 51) / BLIZZARD_BOOK_HEIGHT
		ribbon:SetSize(ribbonInfo.width * scale, ribbonInfo.height * scale)
		ribbon:ClearAllPoints()
		ribbon:SetPoint("TOPRIGHT", leftBG, "TOPRIGHT", 62 * scale, 0)
	end)
end

local leftPage = CreateFrame("Frame", nil, book)
leftPage:SetAllPoints(leftBG)

local rightPage = CreateFrame("Frame", nil, book)
rightPage:SetAllPoints(rightBG)

-- Page title with the ornate divider underneath, like the spellbook's "General"
local function CreateHeader(page)
	local header = CreateFrame("Frame", nil, page)
	header:SetPoint("TOPLEFT", PAGE_MARGIN + 12, -34)
	header:SetPoint("RIGHT", -PAGE_MARGIN, 0)
	header:SetHeight(51)

	if GetAtlas("spellbook-list-backplate") then
		local backplate = header:CreateTexture(nil, "BACKGROUND")
		backplate:SetAtlas("spellbook-list-backplate")
		backplate:SetAlpha(0.65)
		backplate:SetSize(416, 106)
		backplate:SetPoint("LEFT", -85, 10)
	end

	header.Text = CreateText(header, HEADER_FONT)
	header.Text:SetPoint("TOPLEFT", -8, 0)
	header.Text:SetPoint("BOTTOMRIGHT", 0, 11)
	header.Text:SetWordWrap(false)

	local divider = header:CreateTexture(nil, "ARTWORK")
	divider:SetHeight(11)
	divider:SetPoint("BOTTOMLEFT", -32, 0)
	divider:SetPoint("BOTTOMRIGHT")
	SetArt(divider, "spellbook-divider", FONT_COLOR.r, FONT_COLOR.g, FONT_COLOR.b, 0.4)
	return header
end

local FORM_LABEL_WIDTH = 74
local FORM_ROW_HEIGHT = 30
local CONTROL_WIDTH = 190

local filters = {} -- see ns.Search: text, slot, stats, quality, minLevel, maxLevel
local statPicks = {} -- [stat row] = stat code chosen there, or nil for "Any stat"
local numStatRows = 1
local results = {} -- item IDs matching the filters
local truncated = false
local page = 1 -- page of the result list

local RunSearch -- defined with the result list

local function GetQualityName(quality)
	local name = _G["ITEM_QUALITY" .. quality .. "_DESC"] or tostring(quality)
	local color = ITEM_QUALITY_COLORS and ITEM_QUALITY_COLORS[quality]
	return color and color.hex and (color.hex .. name .. "|r") or name
end

---------------------------------------------------------------------------
-- Filter menus
---------------------------------------------------------------------------

-- choices = { { text = "Hands", value = "HANDS" }, ... }; the first is "Any ..." with no value
local ShowMenu
if MenuUtil and MenuUtil.CreateContextMenu then
	-- Newer clients
	ShowMenu = function(owner, choices, current, onSelect)
		MenuUtil.CreateContextMenu(owner, function(_, root)
			for _, choice in ipairs(choices) do
				root:CreateRadio(choice.text,
					function() return choice.value == current end,
					function() onSelect(choice.value) end)
			end
		end)
	end
else
	-- Older clients: classic dropdown menu under the button
	local dropdown = CreateFrame("Frame", "ItemFinderFilterMenu", UIParent, "UIDropDownMenuTemplate")
	local menuChoices, menuCurrent, menuOnSelect
	UIDropDownMenu_Initialize(dropdown, function(_, level)
		for _, choice in ipairs(menuChoices or {}) do
			local info = UIDropDownMenu_CreateInfo()
			info.text = choice.text
			info.checked = choice.value == menuCurrent
			info.func = function() menuOnSelect(choice.value) end
			UIDropDownMenu_AddButton(info, level)
		end
	end, "MENU")
	ShowMenu = function(owner, choices, current, onSelect)
		menuChoices, menuCurrent, menuOnSelect = choices, current, onSelect
		ToggleDropDownMenu(1, nil, dropdown, owner, 0, 0)
	end
end

---------------------------------------------------------------------------
-- Left page: the search form
---------------------------------------------------------------------------

local formHeader = CreateHeader(leftPage)
formHeader.Text:SetText("Search")

-- One labeled row of the form: "Slot    [control]"
local formRows = 0
local function CreateFormRow(label)
	formRows = formRows + 1
	local row = CreateFrame("Frame", nil, leftPage)
	row:SetHeight(FORM_ROW_HEIGHT)
	row:SetPoint("TOPLEFT", formHeader, "BOTTOMLEFT", 0, -14 - (formRows - 1) * FORM_ROW_HEIGHT)
	row:SetPoint("RIGHT", -PAGE_MARGIN, 0)

	local text = CreateText(row, SMALL_FONT)
	text:SetPoint("LEFT")
	text:SetWidth(FORM_LABEL_WIDTH)
	text:SetText(label)
	return row
end

local function CreateMenuButton(row)
	local button = CreateFrame("Button", nil, row, "UIPanelButtonTemplate")
	button:SetSize(CONTROL_WIDTH, 24)
	button:SetPoint("LEFT", FORM_LABEL_WIDTH, 0)
	return button
end

-- Name
local nameRow = CreateFormRow("Name")
local searchBox = CreateFrame("EditBox", "ItemFinderSearchBox", nameRow,
	HasTemplate("SearchBoxTemplate") and "SearchBoxTemplate" or "InputBoxTemplate")
searchBox:SetSize(CONTROL_WIDTH - 6, 22)
searchBox:SetPoint("LEFT", FORM_LABEL_WIDTH + 6, 0)
searchBox:SetAutoFocus(false)
if searchBox.Instructions then
	searchBox.Instructions:SetText("Any name")
end

-- Slot and quality open a menu of choices
local slotButton = CreateMenuButton(CreateFormRow("Slot"))
local qualityButton = CreateMenuButton(CreateFormRow("Quality"))

-- Level: "[ 20 ] to [ 30 ]  [My level]", empty boxes mean no limit
local levelRow = CreateFormRow("Level")

local function CreateLevelBox()
	local box = CreateFrame("EditBox", nil, levelRow, "InputBoxTemplate")
	box:SetSize(36, 22)
	box:SetAutoFocus(false)
	box:SetNumeric(true)
	box:SetMaxLetters(2)
	box:SetJustifyH("CENTER")
	box.placeholder = box:CreateFontString(nil, "ARTWORK", "GameFontDisable")
	box.placeholder:SetPoint("CENTER")
	box.placeholder:SetText("any")
	box:SetScript("OnEscapePressed", box.ClearFocus)
	box:SetScript("OnEnterPressed", box.ClearFocus)
	return box
end

local minLevelBox = CreateLevelBox()
minLevelBox:SetPoint("LEFT", FORM_LABEL_WIDTH + 6, 0)

local toText = CreateText(levelRow, SMALL_FONT)
toText:SetPoint("LEFT", minLevelBox, "RIGHT", 8, 0)
toText:SetText("to")

local maxLevelBox = CreateLevelBox()
maxLevelBox:SetPoint("LEFT", toText, "RIGHT", 12, 0)

minLevelBox:SetScript("OnTabPressed", function() maxLevelBox:SetFocus() end)
maxLevelBox:SetScript("OnTabPressed", function() minLevelBox:SetFocus() end)

local myLevelButton = CreateFrame("Button", nil, levelRow, "UIPanelButtonTemplate")
myLevelButton:SetSize(80, 22)
myLevelButton:SetPoint("LEFT", maxLevelBox, "RIGHT", 8, 0)
myLevelButton:SetText("My level")

-- Stats: up to ns.MAX_STAT_FILTERS rows, items need all chosen stats.
-- "[Any stat] [+]" on the first row adds a row, "[-]" on the others removes it.
local statRows = {}
for i = 1, ns.MAX_STAT_FILTERS do
	local row = CreateFormRow(i == 1 and "Stats" or "and")
	row.button = CreateMenuButton(row)
	row.change = CreateFrame("Button", nil, row, "UIPanelButtonTemplate")
	row.change:SetSize(24, 22)
	row.change:SetPoint("LEFT", row.button, "RIGHT", 4, 0)
	row.change:SetText(i == 1 and "+" or "-")
	statRows[i] = row
end

local resetButton = CreateFrame("Button", nil, leftPage, "UIPanelButtonTemplate")
resetButton:SetSize(120, 24)
resetButton:SetText("Reset filters")

-- Scan section below the form, under a small divider:
-- "Item list"   [Stop scan]  [-] 50 [+] items/s   and the progress underneath
local scanTitle = CreateText(leftPage, NAME_FONT)
scanTitle:SetPoint("TOPLEFT", resetButton, "BOTTOMLEFT", -FORM_LABEL_WIDTH, -24)
scanTitle:SetText("Item list")

local scanDivider = leftPage:CreateTexture(nil, "ARTWORK")
scanDivider:SetHeight(11)
scanDivider:SetPoint("TOPLEFT", scanTitle, "BOTTOMLEFT", -24, -2)
scanDivider:SetPoint("RIGHT", -PAGE_MARGIN, 0)
SetArt(scanDivider, "spellbook-divider", FONT_COLOR.r, FONT_COLOR.g, FONT_COLOR.b, 0.4)

local scanButton = CreateFrame("Button", nil, leftPage, "UIPanelButtonTemplate")
scanButton:SetSize(96, 22)
scanButton:SetPoint("TOPLEFT", scanTitle, "BOTTOMLEFT", -4, -20)

local rateMinus = CreateFrame("Button", nil, leftPage, "UIPanelButtonTemplate")
rateMinus:SetSize(24, 22)
rateMinus:SetPoint("LEFT", scanButton, "RIGHT", 12, 0)
rateMinus:SetText("-")

local rateText = CreateText(leftPage, SMALL_FONT)
rateText:SetWidth(36)
rateText:SetJustifyH("CENTER")
rateText:SetPoint("LEFT", rateMinus, "RIGHT", 2, 0)

local ratePlus = CreateFrame("Button", nil, leftPage, "UIPanelButtonTemplate")
ratePlus:SetSize(24, 22)
ratePlus:SetPoint("LEFT", rateText, "RIGHT", 2, 0)
ratePlus:SetText("+")

local rateUnit = CreateText(leftPage, SMALL_FONT)
rateUnit:SetPoint("LEFT", ratePlus, "RIGHT", 6, 0)
rateUnit:SetText("items/s")

local scanText = CreateText(leftPage, SMALL_FONT)
scanText:SetPoint("TOPLEFT", scanButton, "BOTTOMLEFT", 4, -8)
scanText:SetPoint("RIGHT", -PAGE_MARGIN, 0)
scanText:SetAlpha(0.8)

local hintText = CreateText(leftPage, SMALL_FONT)
hintText:SetPoint("BOTTOMLEFT", PAGE_MARGIN + 12, 44)
hintText:SetPoint("RIGHT", -PAGE_MARGIN, 0)
hintText:SetAlpha(0.7)
hintText:SetText("Hover a result for details. Shift-click links it in chat, ctrl-click previews it.")

local function UpdateForm()
	slotButton:SetText(filters.slot and ns.GetSlotName(filters.slot) or "Any slot")
	qualityButton:SetText(filters.quality and (GetQualityName(filters.quality) .. " or better") or "Any quality")
	minLevelBox.placeholder:SetShown(minLevelBox:GetText() == "")
	maxLevelBox.placeholder:SetShown(maxLevelBox:GetText() == "")

	for i, row in ipairs(statRows) do
		row:SetShown(i <= numStatRows)
		row.button:SetText(statPicks[i] and ns.GetStatName(statPicks[i]) or "Any stat")
	end
	statRows[1].change:SetEnabled(numStatRows < ns.MAX_STAT_FILTERS)
	-- The reset button and scan section follow the last stat row
	resetButton:ClearAllPoints()
	resetButton:SetPoint("TOPLEFT", statRows[numStatRows], "BOTTOMLEFT", FORM_LABEL_WIDTH, -8)
end

local function UpdateScanControls()
	local rate = ns.GetScanRate()
	rateText:SetText(rate)
	rateMinus:SetEnabled(rate > ns.SCAN_RATES[1])
	ratePlus:SetEnabled(rate < ns.SCAN_RATES[#ns.SCAN_RATES])

	local progress = ("%d%%, %d items"):format(floor(ns.GetScanProgress() * 100), ns.GetNumItems())
	local text
	if ns.IsScanning() then
		scanButton:SetText("Stop scan")
		text = "Scanning: " .. progress
	elseif ns.IsScanDone() then
		scanButton:SetText("Rescan")
		text = ns.GetNumItems() .. " items known"
	else
		scanButton:SetText("Start scan")
		text = "Stopped at " .. progress
	end
	local missing = ns.GetNumMissingLevel()
	if missing > 0 then
		text = text .. ("\n%d items still need their level"):format(missing)
	end
	scanText:SetText(text)
end

local function ApplyFilters()
	page = 1
	-- The chosen stats, without the rows left at "Any stat"
	filters.stats = {}
	for i = 1, numStatRows do
		if statPicks[i] then
			tinsert(filters.stats, statPicks[i])
		end
	end
	UpdateForm()
	RunSearch()
end

slotButton:SetScript("OnClick", function(self)
	local choices = { { text = "Any slot" } }
	for _, slot in ipairs(ns.SLOTS) do
		choices[#choices + 1] = { text = ns.GetSlotName(slot.key), value = slot.key }
	end
	ShowMenu(self, choices, filters.slot, function(value)
		filters.slot = value
		ApplyFilters()
	end)
end)

-- The stats listed in Stats.lua, in that order, minus the ones other rows already have
local function IsPickedElsewhere(code, index)
	for i = 1, numStatRows do
		if i ~= index and statPicks[i] == code then
			return true
		end
	end
	return false
end

for index, row in ipairs(statRows) do
	row.button:SetScript("OnClick", function(self)
		local choices = { { text = "Any stat" } }
		for _, stat in ipairs(ns.STATS) do
			if not IsPickedElsewhere(stat.code, index) then
				choices[#choices + 1] = { text = ns.GetStatName(stat.code), value = stat.code }
			end
		end
		ShowMenu(self, choices, statPicks[index], function(value)
			statPicks[index] = value
			ApplyFilters()
		end)
	end)

	row.change:SetScript("OnClick", function()
		if index == 1 then
			numStatRows = math.min(numStatRows + 1, ns.MAX_STAT_FILTERS)
		else
			-- Close the gap: the rows below move up
			for i = index, ns.MAX_STAT_FILTERS do
				statPicks[i] = statPicks[i + 1]
			end
			numStatRows = numStatRows - 1
		end
		ApplyFilters()
	end)
end

-- Lowest quality wanted; poor or better would be every item, so it starts at common
qualityButton:SetScript("OnClick", function(self)
	local choices = { { text = "Any quality" } }
	for quality = 1, 5 do
		choices[#choices + 1] = { text = GetQualityName(quality) .. " or better", value = quality }
	end
	ShowMenu(self, choices, filters.quality, function(value)
		filters.quality = value
		ApplyFilters()
	end)
end)

searchBox:HookScript("OnTextChanged", function(self)
	filters.text = self:GetText()
	ApplyFilters()
end)
searchBox:HookScript("OnEscapePressed", function(self)
	self:ClearFocus()
end)
searchBox:HookScript("OnEnterPressed", function(self)
	self:ClearFocus()
end)

local function OnLevelChanged()
	filters.minLevel = tonumber(minLevelBox:GetText())
	filters.maxLevel = tonumber(maxLevelBox:GetText())
	ApplyFilters()
end
minLevelBox:SetScript("OnTextChanged", OnLevelChanged)
maxLevelBox:SetScript("OnTextChanged", OnLevelChanged)

-- Items for your level: from five levels below up to your level
myLevelButton:SetScript("OnClick", function()
	local level = UnitLevel("player")
	minLevelBox:SetText(math.max(1, level - 5))
	maxLevelBox:SetText(level)
end)
myLevelButton:SetScript("OnEnter", function(self)
	GameTooltip:SetOwner(self, "ANCHOR_RIGHT")
	GameTooltip:AddLine("Items for your level")
	GameTooltip:AddLine("Required level from five below your level up to yours.", 1, 1, 1, true)
	GameTooltip:Show()
end)
myLevelButton:SetScript("OnLeave", GameTooltip_Hide)

resetButton:SetScript("OnClick", function()
	wipe(filters)
	wipe(statPicks)
	numStatRows = 1
	-- Clearing the boxes fires their OnTextChanged, which searches again
	searchBox:SetText("")
	minLevelBox:SetText("")
	maxLevelBox:SetText("")
	searchBox:ClearFocus()
	ApplyFilters()
end)

scanButton:SetScript("OnClick", function()
	if ns.IsScanning() then
		ns.StopScan()
	else
		ns.StartScan(ns.IsScanDone()) -- after a finished scan, walk all IDs again
	end
end)

local function StepRate(delta)
	ns.StepScanRate(delta)
	UpdateScanControls()
end
rateMinus:SetScript("OnClick", function() StepRate(-1) end)
ratePlus:SetScript("OnClick", function() StepRate(1) end)

---------------------------------------------------------------------------
-- Right page: results
---------------------------------------------------------------------------

local listHeader = CreateHeader(rightPage)
listHeader.Text:SetText("Results")
listHeader.Text:SetPoint("BOTTOMRIGHT", -110, 11) -- leave room for the count

local countText = CreateText(listHeader, SMALL_FONT)
countText:SetPoint("BOTTOMRIGHT", 0, 16)
countText:SetJustifyH("RIGHT")
countText:SetAlpha(0.8)

local listArea = CreateFrame("Frame", nil, rightPage)
listArea:SetPoint("TOPLEFT", listHeader, "BOTTOMLEFT", 0, -18)
listArea:SetPoint("BOTTOMRIGHT", -PAGE_MARGIN, 74)

local listEmpty = CreateText(listArea, SMALL_FONT)
listEmpty:SetPoint("TOPLEFT", 4, -4)
listEmpty:SetPoint("RIGHT")
listEmpty:SetAlpha(0.7)

-- Paging controls in the bottom corner, as in the spellbook
local nextButton = CreateFrame("Button", nil, rightPage)
nextButton:SetSize(32, 32)
nextButton:SetPoint("BOTTOMRIGHT", -PAGE_MARGIN, 34)
nextButton:SetNormalTexture("Interface\\Buttons\\UI-SpellbookIcon-NextPage-Up")
nextButton:SetPushedTexture("Interface\\Buttons\\UI-SpellbookIcon-NextPage-Down")
nextButton:SetDisabledTexture("Interface\\Buttons\\UI-SpellbookIcon-NextPage-Disabled")
nextButton:SetHighlightTexture("Interface\\Buttons\\UI-Common-MouseHilight", "ADD")

local prevButton = CreateFrame("Button", nil, rightPage)
prevButton:SetSize(32, 32)
prevButton:SetPoint("RIGHT", nextButton, "LEFT", -4, 0)
prevButton:SetNormalTexture("Interface\\Buttons\\UI-SpellbookIcon-PrevPage-Up")
prevButton:SetPushedTexture("Interface\\Buttons\\UI-SpellbookIcon-PrevPage-Down")
prevButton:SetDisabledTexture("Interface\\Buttons\\UI-SpellbookIcon-PrevPage-Disabled")
prevButton:SetHighlightTexture("Interface\\Buttons\\UI-Common-MouseHilight", "ADD")

local pageText = CreateText(rightPage, SMALL_FONT)
pageText:SetPoint("RIGHT", prevButton, "LEFT", -8, 0)

-- "[x] Compare with equipped" in the bottom left corner, saved in ItemFinderDB.settings
local compareCheck = CreateFrame("CheckButton", nil, rightPage, "UICheckButtonTemplate")
compareCheck:SetSize(24, 24)
compareCheck:SetPoint("BOTTOMLEFT", PAGE_MARGIN + 8, 38)

local compareLabel = CreateText(rightPage, SMALL_FONT)
compareLabel:SetPoint("LEFT", compareCheck, "RIGHT", 2, 0)
compareLabel:SetText("Compare with equipped")

local function IsCompareOn()
	return ns.GetDB().settings.compare ~= false
end

-- Rows look like spellbook entries: framed icon, name and the item type underneath
local rows = {}
local hoveredRow

local function UpdateRowHighlight(row)
	local lit = row:IsMouseOver()
	row.backplate:SetAlpha(lit and 1 or 0.25)
	row.iconHighlight:SetAlpha(lit and 0.35 or 0)
end

-- With compare on, results use GameTooltip, which shows the equipped item next to it.
-- With compare off they use a tooltip of our own: it has no comparison tooltips to show.
local plainTooltip = CreateFrame("GameTooltip", "ItemFinderTooltip", UIParent, "GameTooltipTemplate")
plainTooltip.shoppingTooltips = nil

local GetCVar = C_CVar and C_CVar.GetCVar or GetCVar
local SetCVar = C_CVar and C_CVar.SetCVar or SetCVar

-- GameTooltip only compares while Shift is held, unless "Always compare items" is set.
-- Set it while a result is hovered, and put the player's own value back afterwards.
local savedAlwaysCompare
local function ForceAlwaysCompare()
	local current = GetCVar("alwaysCompareItems")
	if current and savedAlwaysCompare == nil then
		savedAlwaysCompare = current
		SetCVar("alwaysCompareItems", "1")
	end
end

local function RestoreAlwaysCompare()
	if savedAlwaysCompare ~= nil then
		SetCVar("alwaysCompareItems", savedAlwaysCompare)
		savedAlwaysCompare = nil
	end
end

local function HideRowTooltip()
	GameTooltip:Hide()
	plainTooltip:Hide()
	RestoreAlwaysCompare()
end

-- The item tooltip, just outside the book next to the row
local function ShowRowTooltip(row)
	local tooltip = plainTooltip
	if IsCompareOn() then
		tooltip = GameTooltip
		plainTooltip:Hide()
		ForceAlwaysCompare()
	else
		GameTooltip:Hide()
		RestoreAlwaysCompare()
	end
	tooltip:SetOwner(row, "ANCHOR_NONE")
	tooltip:SetPoint("TOPLEFT", row, "TOPRIGHT", PAGE_MARGIN + 8, 0)
	tooltip:SetItemByID(row.itemID)
	tooltip:Show()
end

compareCheck:SetScript("OnClick", function(self)
	ns.GetDB().settings.compare = self:GetChecked() and true or false
end)

-- Never leave the player's setting changed, even when logging out mid-hover
local cvarGuard = CreateFrame("Frame")
cvarGuard:RegisterEvent("PLAYER_LOGOUT")
cvarGuard:SetScript("OnEvent", RestoreAlwaysCompare)

local function GetRow(i)
	local row = rows[i]
	if row then
		return row
	end
	row = CreateFrame("Button", nil, listArea)
	row:SetHeight(ROW_HEIGHT)
	row:SetPoint("TOPLEFT", 0, -(i - 1) * ROW_HEIGHT)
	row:SetPoint("RIGHT")

	row.backplate = row:CreateTexture(nil, "BACKGROUND")
	row.backplate:SetPoint("TOPLEFT", -14, 4)
	row.backplate:SetPoint("BOTTOMRIGHT", 10, -8)
	SetArt(row.backplate, "spellbook-item-backplate", FONT_COLOR.r, FONT_COLOR.g, FONT_COLOR.b, 0.12)

	local iconFrame = CreateFrame("Frame", nil, row)
	iconFrame:SetSize(36, 36)
	iconFrame:SetPoint("LEFT", 4, 0)

	row.icon = iconFrame:CreateTexture(nil, "ARTWORK")
	row.icon:SetSize(32, 32)
	row.icon:SetPoint("CENTER")
	if GetAtlas("spellbook-item-spellicon-mask") then
		local mask = iconFrame:CreateMaskTexture()
		mask:SetAtlas("spellbook-item-spellicon-mask")
		mask:SetAllPoints(row.icon)
		row.icon:AddMaskTexture(mask)
	end

	if GetAtlas("spellbook-item-iconframe") then
		local border = iconFrame:CreateTexture(nil, "OVERLAY", nil, 1)
		border:SetAtlas("spellbook-item-iconframe")
		border:SetPoint("TOPLEFT", -10, 1)
		border:SetPoint("BOTTOMRIGHT", 1, -6)
	end

	row.iconHighlight = iconFrame:CreateTexture(nil, "OVERLAY", nil, 2)
	row.iconHighlight:SetAllPoints()
	row.iconHighlight:SetBlendMode("ADD")
	SetArt(row.iconHighlight, "spellbook-item-iconframe-hover", 1, 1, 1, 0.3)

	row.name = CreateText(row, NAME_FONT)
	row.name:SetPoint("BOTTOMLEFT", iconFrame, "RIGHT", 10, 1)
	row.name:SetPoint("RIGHT")
	row.name:SetWordWrap(false)

	row.sub = CreateText(row, SMALL_FONT)
	row.sub:SetPoint("TOPLEFT", row.name, "BOTTOMLEFT", 0, -2)
	row.sub:SetPoint("RIGHT")
	row.sub:SetWordWrap(false)

	row:SetScript("OnEnter", function(self)
		hoveredRow = self
		UpdateRowHighlight(self)
		ShowRowTooltip(self)
	end)
	row:SetScript("OnLeave", function(self)
		hoveredRow = nil
		UpdateRowHighlight(self)
		HideRowTooltip()
	end)
	row:SetScript("OnClick", function(self)
		-- Shift-click links the item in chat, ctrl-click previews it, as on any item button
		local _, link = GetItemInfo(self.itemID)
		if link then
			HandleModifiedItemClick(link)
		end
	end)
	rows[i] = row
	return row
end

local function GetRowsPerPage()
	return math.max(1, floor(listArea:GetHeight() / ROW_HEIGHT))
end

local function GetNumPages()
	return math.max(1, ceil(#results / GetRowsPerPage()))
end

-- "Level 24  +12 Stamina  Leather Hands"
local function GetRowDescription(itemID, item)
	local parts = {}
	if item.l and item.l > 0 then
		parts[#parts + 1] = "Level " .. item.l
	end
	for _, code in ipairs(filters.stats or {}) do
		local value = item.s and item.s[code]
		if value then
			parts[#parts + 1] = ("+%s %s"):format(value, ns.GetStatName(code))
		end
	end
	parts[#parts + 1] = GetItemDescription(itemID)
	return table.concat(parts, "  ")
end

local function RefreshList()
	local perPage = GetRowsPerPage()
	local numPages = GetNumPages()
	page = math.min(math.max(page, 1), numPages)

	local first = (page - 1) * perPage
	for i = 1, perPage do
		local itemID = results[first + i]
		local row = GetRow(i)
		if itemID then
			local item = ns.GetItem(itemID)
			row.itemID = itemID
			row.icon:SetTexture(select(5, GetItemInfoInstant(itemID)))
			row.name:SetText(item.n)
			SetQualityColor(row.name, item.q)
			row.sub:SetText(GetRowDescription(itemID, item))
			UpdateRowHighlight(row)
			row:Show()
		else
			row:Hide()
		end
	end
	for i = perPage + 1, #rows do
		rows[i]:Hide()
	end

	-- The rows under the cursor changed: show the tooltip of the new item
	if hoveredRow and hoveredRow:IsShown() then
		ShowRowTooltip(hoveredRow)
	end

	if #results > 0 then
		listEmpty:Hide()
	elseif not ns.CanSearch(filters) then
		listEmpty:SetText("Type at least " .. ns.MIN_SEARCH_LENGTH
			.. " letters of a name, or set a filter, to find items.")
		listEmpty:Show()
	else
		local text = ns.IsScanning() and "No matches yet. The item list is still being built."
			or "No items match this search."
		if (filters.minLevel or filters.maxLevel) and ns.GetNumMissingLevel() > 0 then
			text = text .. ("\n\n%d items don't have their level yet, so the level filter skips them."
				.. " The scan fills them in."):format(ns.GetNumMissingLevel())
		end
		listEmpty:SetText(text)
		listEmpty:Show()
	end

	if #results == 0 then
		countText:SetText("")
	else
		countText:SetText(truncated and ("First %d"):format(#results) or ("%d found"):format(#results))
	end
	pageText:SetText(("Page %d/%d"):format(page, numPages))
	prevButton:SetEnabled(page > 1)
	nextButton:SetEnabled(page < numPages)
	UpdateScanControls()
end

function RunSearch()
	results, truncated = ns.Search(filters)
	RefreshList()
end

local function TurnPage(delta)
	page = page + delta
	RefreshList()
	PlaySound(SOUNDKIT.IG_ABILITY_PAGE_TURN)
end
prevButton:SetScript("OnClick", function() TurnPage(-1) end)
nextButton:SetScript("OnClick", function() TurnPage(1) end)
listArea:EnableMouseWheel(true)
listArea:SetScript("OnMouseWheel", function(self, delta)
	if (delta > 0 and page > 1) or (delta < 0 and page < GetNumPages()) then
		TurnPage(-delta)
	end
end)

---------------------------------------------------------------------------
-- Live updates
---------------------------------------------------------------------------

-- The tooltip needs the full item info, which can arrive after hovering
local updater = CreateFrame("Frame")
updater:RegisterEvent("GET_ITEM_INFO_RECEIVED")
updater:SetScript("OnEvent", function(self, event, itemID)
	if hoveredRow and hoveredRow:IsShown() and hoveredRow.itemID == itemID then
		ShowRowTooltip(hoveredRow)
	end
end)

-- While the scan runs, refresh the results now and then so new items show up.
-- force skips the throttle, for changes the player made (start, stop) and the scan's end.
local lastRefresh = 0
function ns.OnItemsChanged(force)
	if not window:IsShown() or (not force and GetTime() - lastRefresh < REFRESH_INTERVAL) then
		return
	end
	lastRefresh = GetTime()
	if ns.CanSearch(filters) then
		RunSearch()
	else
		UpdateScanControls()
	end
end

window:SetScript("OnShow", function()
	compareCheck:SetChecked(IsCompareOn())
	UpdateForm()
	RunSearch()
	searchBox:SetFocus()
	PlaySound(SOUNDKIT.IG_SPELLBOOK_OPEN)
end)
window:SetScript("OnHide", function()
	PlaySound(SOUNDKIT.IG_SPELLBOOK_CLOSE)
end)

function ns.ToggleWindow()
	window:SetShown(not window:IsShown())
end

-- Opens the window searching for the text
function ns.ShowSearch(text)
	window:Show()
	searchBox:SetText(text)
	searchBox:ClearFocus()
end
