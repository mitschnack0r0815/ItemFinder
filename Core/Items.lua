local _, ns = ...

-- Classic has no API that lists every item, so we build the list ourselves: walk the item
-- IDs, skip the ones the client doesn't know (GetItemInfoInstant is local and instant), and
-- ask the server for the name of the rest. Names arrive later via GET_ITEM_INFO_RECEIVED.
--
-- ItemFinderDB (account-wide):
--   items   = { [itemID] = { n = name, q = quality, l = required level, i = item level, s = stats } }
--             stats only on items that have any: { STAMINA = 12, STRENGTH = 5, ... }, keys are
--             the game's ITEM_MOD_<code>_SHORT stat names without the prefix and suffix
--   version = layout of items; when it changes the scan runs again to fill in what's missing
--   scan    = { nextID = <next ID to check>, done = <bool>, paused = <bool>,
--               build = <client build it ran on> }
--   settings = { rate = <items looked up per second>, compare = <false to hide the comparison> }
--   minimap = { angle, hide }

local GetItemInfo = C_Item and C_Item.GetItemInfo or GetItemInfo
local GetItemInfoInstant = C_Item and C_Item.GetItemInfoInstant or GetItemInfoInstant
local GetItemStats = C_Item and C_Item.GetItemStats or GetItemStats

local DATA_VERSION = 4 -- 2: stats added, 3: levels added, 4: unpause to fill in levels

local lowerNames = {} -- [itemID] = lowercase name, for searching
local numItems = 0
local numMissingLevel = 0 -- saved by an older version, the scan still has to look them up
local statCounts = {} -- [stat code] = number of items with that stat, for /itemfinder stats
local pending = {} -- [itemID] = { sent = <GetTime()>, tries = n }
local numPending = 0

function ns.GetDB()
	ItemFinderDB = ItemFinderDB or {}
	ItemFinderDB.items = ItemFinderDB.items or {}
	ItemFinderDB.scan = ItemFinderDB.scan or { nextID = 1 }
	ItemFinderDB.settings = ItemFinderDB.settings or {}
	return ItemFinderDB
end

function ns.GetItem(itemID)
	return ns.GetDB().items[itemID]
end

function ns.GetNumItems()
	return numItems
end

function ns.GetNumMissingLevel()
	return numMissingLevel
end

-- "ITEM_MOD_STAMINA_SHORT" -> "STAMINA"; keys without the prefix (like armor) stay as they are
local function ToStatCode(key)
	return (key:gsub("^ITEM_MOD_", ""):gsub("_SHORT$", ""))
end

local statLabels = {} -- [stat code] = label from ns.STATS
for _, stat in ipairs(ns.STATS) do
	statLabels[stat.code] = stat.label
end

-- Name for a stat code: the label from Stats.lua, or the game's own name ("Stamina")
function ns.GetStatName(code)
	return statLabels[code] or _G["ITEM_MOD_" .. code .. "_SHORT"] or _G["ITEM_MOD_" .. code] or _G[code] or code
end

-- Only works while the client has the item loaded, which it does when its name arrives
local function ReadStats(itemID)
	local stats = GetItemStats and GetItemStats("item:" .. itemID)
	if not stats or not next(stats) then
		return nil
	end
	local codes = {}
	for key, value in pairs(stats) do
		codes[ToStatCode(key)] = value
	end
	return codes
end

local function CountStats(item, delta)
	for code in pairs(item.s or {}) do
		statCounts[code] = (statCounts[code] or 0) + delta
		if statCounts[code] <= 0 then
			statCounts[code] = nil
		end
	end
end

-- Leftover and placeholder items: "OLDRecruit's Belt", "[PH] ...". Not "Old Greatsword".
local function IsUnwanted(name)
	return name:find("^OLD") or name:find("^%[")
end

local function StoreItem(itemID, name, quality, itemLevel, reqLevel)
	if IsUnwanted(name) then
		return
	end
	local items = ns.GetDB().items
	local old = items[itemID]
	if old then
		CountStats(old, -1)
		if old.l == nil then
			numMissingLevel = numMissingLevel - 1
		end
	else
		numItems = numItems + 1
	end
	local item = { n = name, q = quality, l = reqLevel or 0, i = itemLevel, s = ReadStats(itemID) }
	items[itemID] = item
	CountStats(item, 1)
	lowerNames[itemID] = name:lower()
end

-- { [stat code] = number of known items with it }
function ns.GetStatCounts()
	return statCounts
end

-- Stores the item if the client already has its info, otherwise asks the server for it
local function Request(itemID)
	local name, _, quality, itemLevel, reqLevel = GetItemInfo(itemID)
	if name then
		StoreItem(itemID, name, quality, itemLevel, reqLevel)
		return
	end
	local request = pending[itemID]
	if not request then
		request = { tries = 0 }
		pending[itemID] = request
		numPending = numPending + 1
	end
	request.sent = GetTime()
	request.tries = request.tries + 1
end

local function Resolve(itemID)
	if pending[itemID] then
		pending[itemID] = nil
		numPending = numPending - 1
	end
end

---------------------------------------------------------------------------
-- Scanning
---------------------------------------------------------------------------

local scanner = CreateFrame("Frame")
local lastSweep = 0
local budget = 0 -- lookups the scan may do right now, refilled at the scan rate

-- Items looked up per second. Skipping IDs the client doesn't know doesn't count, it
-- costs nothing; only real lookups (which may ask the server) do.
function ns.GetScanRate()
	return ns.GetDB().settings.rate or ns.DEFAULT_SCAN_RATE
end

function ns.SetScanRate(rate)
	ns.GetDB().settings.rate = rate
end

-- Goes to the next faster (delta 1) or slower (delta -1) rate in ns.SCAN_RATES; a rate set
-- by command between two steps goes to the nearest step in that direction
function ns.StepScanRate(delta)
	local rate = ns.GetScanRate()
	local rates = ns.SCAN_RATES
	local first, last, step = 1, #rates, 1
	if delta < 0 then
		first, last, step = #rates, 1, -1
	end
	for i = first, last, step do
		if (delta > 0 and rates[i] > rate) or (delta < 0 and rates[i] < rate) then
			ns.SetScanRate(rates[i])
			return
		end
	end
end

-- Retries requests the server never answered, gives up after the second try
local function SweepPending(now)
	for itemID, request in pairs(pending) do
		if now - request.sent > ns.REQUEST_TIMEOUT then
			if request.tries >= 2 then
				Resolve(itemID)
			else
				Request(itemID)
			end
		end
	end
end

local function ScanStep(self, elapsed)
	local now = GetTime()
	if now - lastSweep > 1 then
		lastSweep = now
		SweepPending(now)
	end

	-- Refill the budget; keep at most a quarter second's worth so it never bursts
	local rate = ns.GetScanRate()
	budget = math.min(budget + elapsed * rate, math.max(1, rate / 4))
	-- Faster rates need more requests in flight while the server answers
	local maxPending = math.max(ns.MAX_PENDING, rate)

	local scan = ns.GetDB().scan
	local checks = 0
	while checks < ns.CHECKS_PER_FRAME and budget >= 1 and numPending < maxPending
		and scan.nextID <= ns.MAX_ITEM_ID do
		local itemID = scan.nextID
		scan.nextID = itemID + 1
		checks = checks + 1
		local item = ns.GetItem(itemID)
		-- Items saved by an older version have no level yet: look them up again
		if GetItemInfoInstant(itemID) and (not item or item.l == nil) then
			budget = budget - 1
			Request(itemID)
		end
	end

	if scan.nextID > ns.MAX_ITEM_ID and numPending == 0 then
		scan.done = true
		scanner:SetScript("OnUpdate", nil)
		print(("Item Finder: scan finished, %d items known."):format(numItems))
	end
	if ns.OnItemsChanged then
		ns.OnItemsChanged(scan.done) -- right away when finished, so the window shows it
	end
end

function ns.IsScanning()
	return scanner:GetScript("OnUpdate") ~= nil
end

function ns.IsScanDone()
	return ns.GetDB().scan.done and true or false
end

-- 0..1, how far through the item IDs the scan is
function ns.GetScanProgress()
	local scan = ns.GetDB().scan
	return scan.done and 1 or math.min(1, (scan.nextID - 1) / ns.MAX_ITEM_ID)
end

local function NotifyChanged()
	if ns.OnItemsChanged then
		ns.OnItemsChanged(true)
	end
end

-- Starts or resumes the scan where it stopped; fromScratch walks all IDs again,
-- keeping the items already found
function ns.StartScan(fromScratch)
	local scan = ns.GetDB().scan
	if fromScratch then
		scan.nextID = 1
		scan.done = false
	end
	scan.paused = nil
	if not scan.done then
		budget = 0
		scanner:SetScript("OnUpdate", ScanStep)
	end
	NotifyChanged()
end

-- Stops the scan until started again, also across logins. Requests already sent still
-- get stored when their answer arrives.
function ns.StopScan()
	ns.GetDB().scan.paused = true
	scanner:SetScript("OnUpdate", nil)
	NotifyChanged()
end

scanner:RegisterEvent("PLAYER_LOGIN")
scanner:RegisterEvent("GET_ITEM_INFO_RECEIVED")
scanner:SetScript("OnEvent", function(self, event, itemID, success)
	if event == "PLAYER_LOGIN" then
		local db = ns.GetDB()
		if db.version ~= DATA_VERSION then
			if (db.version or 0) < 2 then
				-- Too old to fill in: build the list again
				db.items = {}
			end
			-- Walk the IDs again; the scan looks up the items that lack the new fields.
			-- Runs even if the scan was stopped, or the new filters wouldn't work.
			db.version = DATA_VERSION
			db.scan.nextID = 1
			db.scan.done = false
			db.scan.paused = nil
		end
		-- Saved before these were skipped
		for id, item in pairs(db.items) do
			if IsUnwanted(item.n) then
				db.items[id] = nil
			end
		end
		for id, item in pairs(db.items) do
			lowerNames[id] = item.n:lower()
			numItems = numItems + 1
			CountStats(item, 1)
			if item.l == nil then
				numMissingLevel = numMissingLevel + 1
			end
		end
		-- Some items still lack their level (say the server didn't answer): look again
		if numMissingLevel > 0 and db.scan.done then
			db.scan.nextID = 1
			db.scan.done = false
		end
		-- A new client build can add items: walk the IDs again, keeping what we have
		local _, build = GetBuildInfo()
		if db.scan.build ~= build then
			db.scan.build = build
			db.scan.nextID = 1
			db.scan.done = false
		end
		if not db.scan.paused then
			ns.StartScan()
		end
		return
	end

	-- Fires for items anyone asked about, so items seen elsewhere get picked up too
	local wasPending = pending[itemID] ~= nil
	Resolve(itemID)
	if success and (wasPending or not ns.GetItem(itemID)) then
		local name, _, quality, itemLevel, reqLevel = GetItemInfo(itemID)
		if name then
			StoreItem(itemID, name, quality, itemLevel, reqLevel)
		end
	end
end)

---------------------------------------------------------------------------
-- Searching
---------------------------------------------------------------------------

-- The slot filter's equip locations, as a set: { INVTYPE_HAND = true }
local slotSets = {}
for _, slot in ipairs(ns.SLOTS) do
	slotSets[slot.key] = {}
	for _, equipLoc in ipairs(slot.equipLocs) do
		slotSets[slot.key][equipLoc] = true
	end
end

-- Label of a slot filter key: the first equip location's game name ("Hands"), unless set
function ns.GetSlotName(key)
	for _, slot in ipairs(ns.SLOTS) do
		if slot.key == key then
			return slot.label or _G[slot.equipLocs[1]] or key
		end
	end
	return key
end

-- filters = { text, slot, stats, quality, minLevel, maxLevel }, each optional:
--   text      part of the name, case-insensitive
--   slot      key from ns.SLOTS
--   stats     list of codes from ns.STATS; items need all of them
--   quality   lowest quality wanted (2 = uncommon or better)
--   minLevel, maxLevel   required level range, inclusive

local function HasFilter(filters)
	return (filters.slot or (filters.stats and #filters.stats > 0) or filters.quality
		or filters.minLevel or filters.maxLevel) and true or false
end

-- Total of the given stats on the item, or nil when it lacks one of them
local function SumStats(item, stats)
	local sum = 0
	for _, code in ipairs(stats) do
		local value = item.s and item.s[code]
		if not value then
			return nil
		end
		sum = sum + value
	end
	return sum
end

-- A search is worth running with enough text, or with any filter and any text at all
function ns.CanSearch(filters)
	return #(filters.text or ""):trim() >= ns.MIN_SEARCH_LENGTH or HasFilter(filters)
end

-- Item IDs matching all the filters. With stat filters the highest total of those stats
-- comes first; otherwise names that start with the text, then the rest alphabetically.
-- Returns the list and whether it was cut off.
function ns.Search(filters)
	local results = {}
	if not ns.CanSearch(filters) then
		return results, false
	end
	local text = (filters.text or ""):trim():lower()
	local equipLocs = filters.slot and slotSets[filters.slot]
	local stats = filters.stats and #filters.stats > 0 and filters.stats
	local quality = filters.quality
	local minLevel, maxLevel = filters.minLevel, filters.maxLevel
	local items = ns.GetDB().items

	local isPrefix = {}
	local statSums = {}
	for itemID, lowerName in pairs(lowerNames) do
		local item = items[itemID]
		local start = text == "" and 1 or lowerName:find(text, 1, true)
		local sum = stats and SumStats(item, stats)
		if start
			and (not quality or (item.q or 0) >= quality)
			and (not minLevel or (item.l or 0) >= minLevel)
			and (not maxLevel or (item.l or 0) <= maxLevel)
			and (not stats or sum)
			and (not equipLocs or equipLocs[select(4, GetItemInfoInstant(itemID))]) then
			results[#results + 1] = itemID
			isPrefix[itemID] = start == 1
			statSums[itemID] = sum
		end
	end

	table.sort(results, function(a, b)
		if stats and statSums[a] ~= statSums[b] then
			return statSums[a] > statSums[b]
		end
		if isPrefix[a] ~= isPrefix[b] then
			return isPrefix[a]
		end
		if lowerNames[a] ~= lowerNames[b] then
			return lowerNames[a] < lowerNames[b]
		end
		return a < b
	end)

	-- Cut after sorting, so a stat search keeps the best items
	local truncated = #results > ns.MAX_RESULTS
	for i = #results, ns.MAX_RESULTS + 1, -1 do
		results[i] = nil
	end
	return results, truncated
end
