local _, ns = ...

SLASH_ITEMFINDER1 = "/itemfinder"
SLASH_ITEMFINDER2 = "/if"
SlashCmdList["ITEMFINDER"] = function(msg)
	msg = msg:trim()
	if msg == "minimap" then
		ns.ToggleMinimapButton()
	elseif msg == "rescan" then
		-- Walks all item IDs again; items already found are kept
		ns.StartScan(true)
		print("Item Finder: rescanning items.")
	elseif msg == "start" then
		ns.StartScan()
		print("Item Finder: scan started.")
	elseif msg == "stop" then
		ns.StopScan()
		print("Item Finder: scan stopped. Type /itemfinder start to go on.")
	elseif msg:match("^rate%s+%d+$") then
		-- Any rate works here, not just the window's steps
		local rate = math.max(1, tonumber(msg:match("%d+")))
		ns.SetScanRate(rate)
		print(("Item Finder: scanning %d items per second."):format(rate))
	elseif msg == "stats" then
		-- Every stat code the saved items have, to pick from for Stats.lua
		local counts = ns.GetStatCounts()
		local codes = {}
		for code in pairs(counts) do
			codes[#codes + 1] = code
		end
		table.sort(codes)
		print("Item Finder: stat codes of the saved items (code, name, items):")
		for _, code in ipairs(codes) do
			print(("  %s  %s  %d"):format(code, ns.GetStatName(code), counts[code]))
		end
	elseif msg ~= "" then
		-- /if <text> opens the window searching for the text
		ns.ShowSearch(msg)
	else
		ns.ToggleWindow()
	end
end
