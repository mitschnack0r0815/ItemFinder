local _, ns = ...

ns.ICON = "Interface\\Icons\\INV_Misc_Spyglass_02" -- spyglass

-- Item IDs to scan. Classic items stop around 25000, but later Classic versions add
-- items far above that; IDs the client doesn't know are skipped almost for free.
ns.MAX_ITEM_ID = 260000

-- Scan speed: items looked up per second (the window's [-] [+] steps through SCAN_RATES).
-- Unknown IDs are skipped for free, at most CHECKS_PER_FRAME IDs per frame. At least
-- MAX_PENDING server requests may wait for an answer at once, more at faster rates.
ns.DEFAULT_SCAN_RATE = 50
ns.SCAN_RATES = { 5, 10, 25, 50, 100, 200, 500 }
ns.CHECKS_PER_FRAME = 400
ns.MAX_PENDING = 40
ns.REQUEST_TIMEOUT = 15 -- seconds before an unanswered request is retried

-- Searches stop collecting after this many matches
ns.MAX_RESULTS = 500
ns.MIN_SEARCH_LENGTH = 2

-- How many stat filters the form can show at once
ns.MAX_STAT_FILTERS = 3

-- Choices of the slot filter. Each matches the items whose equip location is in equipLocs;
-- the label is the game's name for the first one unless given.
ns.SLOTS = {
	{ key = "HEAD", equipLocs = { "INVTYPE_HEAD" } },
	{ key = "NECK", equipLocs = { "INVTYPE_NECK" } },
	{ key = "SHOULDER", equipLocs = { "INVTYPE_SHOULDER" } },
	{ key = "BACK", equipLocs = { "INVTYPE_CLOAK" } },
	{ key = "CHEST", equipLocs = { "INVTYPE_CHEST", "INVTYPE_ROBE" } },
	{ key = "SHIRT", equipLocs = { "INVTYPE_BODY" } },
	{ key = "TABARD", equipLocs = { "INVTYPE_TABARD" } },
	{ key = "WRIST", equipLocs = { "INVTYPE_WRIST" } },
	{ key = "HANDS", equipLocs = { "INVTYPE_HAND" } },
	{ key = "WAIST", equipLocs = { "INVTYPE_WAIST" } },
	{ key = "LEGS", equipLocs = { "INVTYPE_LEGS" } },
	{ key = "FEET", equipLocs = { "INVTYPE_FEET" } },
	{ key = "FINGER", equipLocs = { "INVTYPE_FINGER" } },
	{ key = "TRINKET", equipLocs = { "INVTYPE_TRINKET" } },
	{ key = "ONEHAND", equipLocs = { "INVTYPE_WEAPON" } },
	{ key = "MAINHAND", equipLocs = { "INVTYPE_WEAPONMAINHAND" } },
	{ key = "OFFHAND", equipLocs = { "INVTYPE_WEAPONOFFHAND", "INVTYPE_HOLDABLE" } },
	{ key = "SHIELD", equipLocs = { "INVTYPE_SHIELD" } },
	{ key = "TWOHAND", equipLocs = { "INVTYPE_2HWEAPON" } },
	{ key = "RANGED", label = "Ranged", equipLocs = { "INVTYPE_RANGED", "INVTYPE_RANGEDRIGHT", "INVTYPE_THROWN" } },
	{ key = "RELIC", equipLocs = { "INVTYPE_RELIC" } },
	{ key = "AMMO", equipLocs = { "INVTYPE_AMMO" } },
	{ key = "BAG", equipLocs = { "INVTYPE_BAG", "INVTYPE_QUIVER" } },
}
