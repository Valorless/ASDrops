-- Second icon row: items known to drop in the current zone that are not yet collected.
-- Fully separate from ASDropsBar; it only reads ASDropsLiveItems and loot chat.
local MAX_MISSING_ICONS = 30;
local lastAzerlootCount = -2;
local ICON_GAP = 4;
local DEFAULT_SIZE = 28;
local UNKNOWN_ICON = "Interface\\Icons\\INV_Misc_QuestionMark";
local NO_ITEMS_ICON = "Interface\\Icons\\INV_Stone_12";
local RARITY_ORDER = { Heirloom = 8, Artifact = 7, Legendary = 6, Epic = 5, Rare = 4, Uncommon = 3, Common = 2, Poor = 1 };

local bar;
local label;
local overflow;
local buttons = {};
local shown = {};
local currentZone;
local currentZoneName;
local lastCounts = {};
local pollElapsed = 0;
local needsRefresh = true;

local function Print(text)
	DEFAULT_CHAT_FRAME:AddMessage("ASDrops missing: " .. text, 0.7, 0.9, 1);
end

local function RarityFromColor(color)
	if ( not color ) then return nil; end
	color = string.lower(tostring(color));
	local _, _, hex = string.find(color, "(%x%x%x%x%x%x%x%x)$");
	if ( hex ) then color = string.sub(hex, 3); end
	local rarities = {
		["9d9d9d"] = "Poor", ["ffffff"] = "Common", ["1eff00"] = "Uncommon",
		["0070dd"] = "Rare", ["a335ee"] = "Epic", ["ff8000"] = "Legendary",
		["e6cc80"] = "Artifact", ["00ccff"] = "Heirloom",
	};
	return rarities[color];
end

local function RarityFromQuality(quality)
	local names = { [0] = "Poor", [1] = "Common", [2] = "Uncommon", [3] = "Rare",
		[4] = "Epic", [5] = "Legendary", [6] = "Artifact", [7] = "Heirloom" };
	return names[tonumber(quality)];
end

local function RarityColor(rarity)
	local colors = {
		Poor = { 0.62, 0.62, 0.62 }, Common = { 1, 1, 1 }, Uncommon = { 0.12, 1, 0 },
		Rare = { 0, 0.44, 0.87 }, Epic = { 0.64, 0.21, 0.93 },
		Legendary = { 1, 0.5, 0 }, Artifact = { 0.9, 0.8, 0.5 }, Heirloom = { 0, 0.8, 1 },
	};
	local color = colors[rarity] or colors.Common;
	return color[1], color[2], color[3];
end

local function EnsureDB()
	if ( type(ASDropsZoneDB) ~= "table" ) then ASDropsZoneDB = {}; end
	if ( type(ASDropsZoneDB.zones) ~= "table" ) then ASDropsZoneDB.zones = {}; end
	return ASDropsZoneDB;
end

local function ZoneTable(zone, create)
	local db = EnsureDB();
	if ( not zone ) then return nil; end
	if ( not db.zones[zone] and create ) then db.zones[zone] = {}; end
	return db.zones[zone];
end

local function KeyFromLink(link)
	if ( not link ) then return nil; end
	local _, _, id = string.find(link, "item:(%d+)");
	return id;
end

local function LinkFromText(text)
	if ( not text ) then return nil; end
	local _, _, link = string.find(text, "(|c%x%x%x%x%x%x%x%x|Hitem:[^|]+|h.-|h|r)");
	if ( not link ) then _, _, link = string.find(text, "(|Hitem:[^|]+|h.-|h)"); end
	return link;
end

local function NameFromLink(link)
	local _, _, name = string.find(link or "", "|h%[(.-)%]|h");
	return name;
end

local function ReadZone()
	local db = EnsureDB();
	if ( type(AZS_ZONE) == "table" and AZS_ZONE.zone and AZS_ZONE.zone ~= "" ) then
		db.lastZone = AZS_ZONE.zone;
		db.lastZoneName = AZS_ZONE.zname or AZS_ZONE.zone;
		return db.lastZone, db.lastZoneName;
	end
	-- AZS_ZONE is empty after a reload until the next run starts; reuse the last known zone.
	return db.lastZone, db.lastZoneName;
end

-- Fill in anything GetItemInfo can tell us; safe to call repeatedly as the cache fills.
local function ResolveEntry(entry)
	local lookup = entry.link or entry.name;
	if ( lookup and type(GetItemInfo) == "function" ) then
		local ok, itemName, itemLink, quality, _, _, _, _, _, texture = pcall(GetItemInfo, lookup);
		if ( ok and itemName and itemName ~= "" ) then
			entry.name = entry.name or itemName;
			entry.link = entry.link or itemLink;
			entry.rarity = RarityFromQuality(quality) or entry.rarity;
			if ( texture and not entry.icon ) then entry.icon = texture; end
		end
	end
	if ( not entry.icon and ASDROPS_LOOT_ICONS and entry.name ) then entry.icon = ASDROPS_LOOT_ICONS[entry.name]; end
end

local function RecordItem(zone, key, link, name, icon, rarity, collected)
	if ( not zone or not key ) then return; end
	local zoneItems = ZoneTable(zone, true);
	local entry = zoneItems[key];
	if ( not entry ) then
		entry = { seen = 0 };
		zoneItems[key] = entry;
	end
	entry.seen = (entry.seen or 0) + 1;
	entry.link = link or entry.link;
	entry.name = name or entry.name;
	entry.icon = icon or entry.icon;
	entry.rarity = rarity or entry.rarity;
	if ( collected ) then entry.collected = true; end
	ResolveEntry(entry);
	needsRefresh = true;
end

local function SortMissing(a, b)
	local orderA = RARITY_ORDER[a.rarity or "Common"] or 2;
	local orderB = RARITY_ORDER[b.rarity or "Common"] or 2;
	if ( orderA ~= orderB ) then return orderA > orderB; end
	return string.lower(a.name or "") < string.lower(b.name or "");
end

local function ReadClass()
	local db = EnsureDB();
	if ( type(AZS_ZONE) == "table" and AZS_ZONE.class and AZS_ZONE.class ~= "" ) then
		db.lastClass = string.lower(AZS_ZONE.class);
	end
	if ( db.lastClass ) then return db.lastClass; end
	if ( type(AzerlootDB) == "table" and AzerlootDB.lastClass ) then return AzerlootDB.lastClass; end
	if ( type(UnitClass) == "function" ) then
		local _, class = UnitClass("player");
		if ( class ) then return string.lower(class); end
	end
	return nil;
end

-- Azerloot (installed separately) holds the full boss drop list; it is only read here, never copied.
local function AzerlootMissing()
	local data = Azerloot_Loot;
	if ( type(data) ~= "table" or type(data.zones) ~= "table" or type(data.drops) ~= "table" or not currentZone ) then return nil; end
	local class = ReadClass();
	local classDrops = class and data.drops[class];
	if ( type(classDrops) ~= "table" ) then return nil; end
	local zoneIndex;
	for i = 1, table.getn(data.zones) do
		if ( data.zones[i].key == currentZone ) then zoneIndex = i; break; end
	end
	local zoneDrops = zoneIndex and classDrops[zoneIndex];
	if ( type(zoneDrops) ~= "table" ) then return nil; end
	local zoneData = data.zones[zoneIndex];
	local collected = type(AzerlootDB) == "table" and type(AzerlootDB.collected) == "table" and AzerlootDB.collected[class] or {};
	local db = EnsureDB();
	local marks = type(db.marks) == "table" and db.marks[class] or {};
	local list, seenNames = {}, {};
	for bossIndex = 1, table.getn(zoneDrops) do
		local boss = zoneData.bosses and zoneData.bosses[bossIndex];
		local bossItems = zoneDrops[bossIndex];
		for n = 1, table.getn(bossItems or {}) do
			local drop = bossItems[n];
			if ( drop.name and not seenNames[drop.name] ) then
				seenNames[drop.name] = true;
				if ( not collected[drop.name] and not marks[drop.name] ) then
					table.insert(list, { key = drop.name, name = drop.name, rarity = drop.rarity or zoneData.rarity,
						icon = drop.icon and ("Interface\\Icons\\" .. drop.icon) or nil, azl = true,
						slot = drop.slot, bonus = drop.bonus, boss = boss and boss.name, chance = zoneData.chance });
				end
			end
		end
	end
	table.sort(list, SortMissing);
	return list;
end

local function BuildMissingList()
	local fromAzerloot = AzerlootMissing();
	if ( fromAzerloot ) then return fromAzerloot; end
	local list = {};
	local zoneItems = ZoneTable(currentZone, false);
	if ( not zoneItems ) then return list; end
	for key, entry in pairs(zoneItems) do
		if ( not entry.collected ) then
			ResolveEntry(entry);
			table.insert(list, { key = key, name = entry.name or ("item:" .. key),
				rarity = entry.rarity, icon = entry.icon, link = entry.link, entry = entry });
		end
	end
	table.sort(list, SortMissing);
	return list;
end

local function SavePosition()
	if ( not bar ) then return; end
	local db = EnsureDB();
	local point, _, relativePoint, x, y = bar:GetPoint();
	db.point = point;
	db.relativePoint = relativePoint;
	db.x = x;
	db.y = y;
end

local function ApplyPosition()
	local db = EnsureDB();
	bar:ClearAllPoints();
	if ( db.point ) then
		bar:SetPoint(db.point, UIParent, db.relativePoint or db.point, db.x or 0, db.y or 0);
	elseif ( ASDropsBar ) then
		bar:SetPoint("TOPLEFT", ASDropsBar, "BOTTOMLEFT", 0, -18);
	else
		bar:SetPoint("CENTER", UIParent, "CENTER", 0, -170);
	end
end

local function CurrentIconSize()
	if ( ASDropsBar and ASDropsBar.GetHeight ) then
		local height = ASDropsBar:GetHeight();
		if ( type(height) == "number" and height >= 16 ) then return height; end
	end
	return DEFAULT_SIZE;
end

local function CreateButton(index)
	local button = CreateFrame("Button", nil, bar);
	button:SetID(index);
	button.rarityBorder = CreateFrame("Frame", nil, button);
	button.rarityBorder:SetAllPoints(button);
	button.rarityBorder:SetFrameLevel(button:GetFrameLevel() + 1);
	button.rarityBorder:EnableMouse(false);
	button.rarityBorder:SetBackdrop({
		edgeFile = "Interface\\Tooltips\\UI-Tooltip-Border",
		edgeSize = 15,
		insets = { left = 2, right = 2, top = 2, bottom = 2 },
	});
	button.texture = button:CreateTexture(nil, "ARTWORK");
	button.texture:SetPoint("TOPLEFT", button, "TOPLEFT", 2, -2);
	button.texture:SetPoint("BOTTOMRIGHT", button, "BOTTOMRIGHT", -2, 2);
	button:RegisterForDrag("LeftButton");
	button:RegisterForClicks("LeftButtonUp", "RightButtonUp");
	button:EnableMouse(true);
	button:SetScript("OnDragStart", function()
		if ( IsShiftKeyDown() and not EnsureDB().locked ) then bar:StartMoving(); end
	end);
	button:SetScript("OnDragStop", function()
		bar:StopMovingOrSizing();
		SavePosition();
	end);
	button:SetScript("OnClick", function()
		local item = shown[this:GetID()];
		if ( not item ) then return; end
		if ( arg1 == "RightButton" and not item.azl ) then
			local zoneItems = ZoneTable(currentZone, false);
			if ( zoneItems ) then zoneItems[item.key] = nil; end
			Print("Removed " .. item.name .. " from this zone's list.");
		elseif ( item.azl ) then
			local db = EnsureDB();
			local class = ReadClass();
			if ( type(db.marks) ~= "table" ) then db.marks = {}; end
			if ( type(db.marks[class]) ~= "table" ) then db.marks[class] = {}; end
			db.marks[class][item.name] = true;
			Print("Marked " .. item.name .. " as collected.");
		else
			item.entry.collected = true;
			Print("Marked " .. item.name .. " as collected.");
		end
		GameTooltip:Hide();
		needsRefresh = true;
	end);
	button:SetScript("OnEnter", function()
		local item = shown[this:GetID()];
		if ( not item ) then return; end
		GameTooltip:SetOwner(this, "ANCHOR_TOP");
		local red, green, blue = RarityColor(item.rarity);
		if ( item.azl ) then
			GameTooltip:SetText(item.name, red, green, blue);
			GameTooltip:AddLine((item.rarity or "") .. (item.slot and (" " .. item.slot) or ""), red, green, blue);
			if ( item.bonus ) then
				for i = 1, table.getn(item.bonus) do GameTooltip:AddLine(item.bonus[i], 0.4, 1, 0.4); end
			end
			if ( item.boss ) then GameTooltip:AddLine("Drops from: " .. item.boss, 1, 0.8, 0.2); end
			GameTooltip:AddLine("Not yet collected", 1, 0.5, 0.5);
			GameTooltip:AddLine("Click: mark collected | Shift-drag: move", 0.6, 0.6, 0.6);
			GameTooltip:Show();
			return;
		end
		if ( item.link ) then GameTooltip:SetHyperlink(item.link);
		else GameTooltip:SetText(item.name); end
		GameTooltip:AddLine((item.rarity or "Unknown rarity") .. " - not yet collected", red, green, blue);
		GameTooltip:AddLine("Seen in " .. (currentZoneName or "this zone") .. " x" .. (item.entry.seen or 1), 0.8, 0.8, 0.8);
		GameTooltip:AddLine("Click: mark collected | Right-click: forget | Shift-drag: move", 0.6, 0.6, 0.6);
		GameTooltip:Show();
	end);
	button:SetScript("OnLeave", function() GameTooltip:Hide(); end);
	return button;
end

local function RefreshRow()
	needsRefresh = false;
	if ( not bar ) then return; end
	local db = EnsureDB();
	local list = BuildMissingList();
	local total = table.getn(list);
	if ( db.hidden ) then
		shown = {};
		for i = 1, table.getn(buttons) do buttons[i]:Hide(); end
		bar:Hide();
		return;
	end
	local size = CurrentIconSize();
	local count = total;
	if ( count > MAX_MISSING_ICONS ) then count = MAX_MISSING_ICONS; end
	local slots = count;
	if ( slots < 1 ) then slots = 1; end
	shown = {};
	for i = 1, slots do
		local button = buttons[i];
		if ( not button ) then button = CreateButton(i); buttons[i] = button; end
		local item = list[i];
		shown[i] = item;
		button:SetWidth(size);
		button:SetHeight(size);
		button:ClearAllPoints();
		button:SetPoint("LEFT", bar, "LEFT", (i - 1) * (size + ICON_GAP), 0);
		if ( item ) then
			button.texture:SetTexture(item.icon or UNKNOWN_ICON);
			local red, green, blue = RarityColor(item.rarity or "Common");
			button.rarityBorder:SetBackdropBorderColor(red, green, blue, 1);
		else
			button.texture:SetTexture(NO_ITEMS_ICON);
			button.rarityBorder:SetBackdropBorderColor(0.62, 0.62, 0.62, 1);
		end
		button:Show();
	end
	for i = slots + 1, table.getn(buttons) do buttons[i]:Hide(); end
	bar:SetWidth(slots * size + (slots - 1) * ICON_GAP);
	bar:SetHeight(size);
	label:SetText("Missing in " .. (currentZoneName or "this zone") .. " (" .. total .. ")");
	if ( total > count ) then overflow:SetText("+" .. (total - count)); else overflow:SetText(""); end
	bar:Show();
end

local function CheckZone()
	local zone, zoneName = ReadZone();
	currentZoneName = zoneName;
	if ( zone ~= currentZone ) then
		currentZone = zone;
		lastCounts = {};
		needsRefresh = true;
	end
end

-- Items on the main bar were looted by the player, so they count as collected.
local function PollLiveItems()
	local live = ASDropsLiveItems;
	if ( type(live) ~= "table" ) then return; end
	local counts = {};
	for i = 1, table.getn(live) do
		local item = live[i];
		if ( type(item) == "table" and item.key and item.kind ~= "bossdown" ) then
			local key = tostring(item.key);
			local count = tonumber(item.count) or 1;
			counts[key] = count;
			local previous = lastCounts[key];
			if ( currentZone and (not previous or count > previous) and string.find(key, "^%d+$") ) then
				local zoneItems = ZoneTable(currentZone, false);
				local known = zoneItems and zoneItems[key];
				if ( previous or not known or not known.collected ) then
					RecordItem(currentZone, key, item.link, item.name, item.icon, item.rarity, true);
				end
			end
		end
	end
	lastCounts = counts;
end

local function OnLootMessage(message)
	if ( not currentZone or type(message) ~= "string" ) then return; end
	local link = LinkFromText(message);
	local key = KeyFromLink(link);
	if ( not key ) then return; end
	local _, _, color = string.find(link, "^|c(%x%x%x%x%x%x%x%x)");
	local name = NameFromLink(link);
	local collected = false;
	if ( string.find(message, "^You receive") ) then collected = true; end
	-- Own loot is also caught from the main bar; only record the rest here.
	if ( collected ) then return; end
	if ( string.find(message, "^You ") ) then return; end
	RecordItem(currentZone, key, link, name, nil, RarityFromColor(color), false);
end

-- Anything offered in a loot window is known to drop here; it stays missing until looted.
local function ScanLootWindow()
	if ( not currentZone or type(GetNumLootItems) ~= "function" or type(GetLootSlotLink) ~= "function" ) then return; end
	for slot = 1, GetNumLootItems() do
		local link = GetLootSlotLink(slot);
		local key = KeyFromLink(link);
		if ( key ) then
			local zoneItems = ZoneTable(currentZone, false);
			if ( not (zoneItems and zoneItems[key]) ) then
				local _, _, color = string.find(link, "^|c(%x%x%x%x%x%x%x%x)");
				local texture;
				if ( type(GetLootSlotInfo) == "function" ) then texture = GetLootSlotInfo(slot); end
				RecordItem(currentZone, key, link, NameFromLink(link), texture, RarityFromColor(color), false);
			end
		end
	end
end

local function FindEntry(text)
	local zoneItems = ZoneTable(currentZone, false);
	if ( not zoneItems or not text or text == "" ) then return nil, nil; end
	local link = LinkFromText(text);
	local key = KeyFromLink(link);
	if ( key and zoneItems[key] ) then return key, zoneItems[key]; end
	if ( string.find(text, "^%d+$") and zoneItems[text] ) then return text, zoneItems[text]; end
	local wanted = string.lower(NameFromLink(link) or text);
	for itemKey, entry in pairs(zoneItems) do
		if ( entry.name and string.lower(entry.name) == wanted ) then return itemKey, entry; end
	end
	return nil, nil;
end

local function PrintHelp()
	Print("/asmissing list | collected <item> | missing <item> | add <item link> | remove <item> | reset | lock | unlock | show | hide");
end

SLASH_ASDROPSMISSING1 = "/asmissing";
SlashCmdList["ASDROPSMISSING"] = function(message)
	message = message or "";
	local _, _, command, rest = string.find(message, "^%s*(%S*)%s*(.-)%s*$");
	command = string.lower(command or "");
	local db = EnsureDB();
	CheckZone();
	if ( command == "lock" ) then db.locked = true; Print("Row locked.");
	elseif ( command == "unlock" ) then db.locked = false; Print("Row unlocked (Shift-drag an icon to move it).");
	elseif ( command == "show" ) then db.hidden = false; needsRefresh = true; Print("Row shown.");
	elseif ( command == "hide" ) then db.hidden = true; needsRefresh = true; Print("Row hidden.");
	elseif ( command == "list" ) then
		if ( not currentZone ) then Print("No zone detected yet."); return; end
		local zoneItems = ZoneTable(currentZone, false) or {};
		local total, got = 0, 0;
		for key, entry in pairs(zoneItems) do
			total = total + 1;
			if ( entry.collected ) then got = got + 1; end
		end
		Print(currentZoneName .. ": " .. total .. " known, " .. got .. " collected, " .. (total - got) .. " missing.");
		local list = BuildMissingList();
		for i = 1, table.getn(list) do Print("  " .. (list[i].link or list[i].name)); end
	elseif ( command == "reset" ) then
		if ( currentZone ) then db.zones[currentZone] = nil; needsRefresh = true; Print("Cleared the list for " .. currentZoneName .. "."); end
	elseif ( command == "add" ) then
		local link = LinkFromText(rest);
		local key = KeyFromLink(link);
		if ( not currentZone ) then Print("No zone detected yet."); return; end
		if ( not key ) then Print("Shift-click an item link after /asmissing add."); return; end
		local _, _, color = string.find(link, "^|c(%x%x%x%x%x%x%x%x)");
		RecordItem(currentZone, key, link, NameFromLink(link), nil, RarityFromColor(color), false);
		Print("Added " .. link .. " as missing.");
	elseif ( command == "collected" or command == "missing" or command == "remove" ) then
		local key, entry = FindEntry(rest);
		if ( not entry ) then Print("Item not found in this zone's list."); return; end
		local name = entry.name or key;
		if ( command == "remove" ) then ZoneTable(currentZone, false)[key] = nil; Print("Removed " .. name .. ".");
		elseif ( command == "collected" ) then entry.collected = true; Print("Marked " .. name .. " as collected.");
		else entry.collected = nil; Print("Marked " .. name .. " as missing."); end
		needsRefresh = true;
	else
		PrintHelp();
	end
end;

bar = CreateFrame("Frame", "ASDropsMissingBar", UIParent);
bar:SetWidth(DEFAULT_SIZE);
bar:SetHeight(DEFAULT_SIZE);
bar:SetMovable(true);
bar:SetClampedToScreen(true);
bar:Hide();
label = bar:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall");
label:SetPoint("BOTTOMLEFT", bar, "TOPLEFT", 0, 2);
overflow = bar:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall");
overflow:SetPoint("LEFT", bar, "RIGHT", 4, 0);

local events = CreateFrame("Frame");
events:RegisterEvent("VARIABLES_LOADED");
events:RegisterEvent("PLAYER_ENTERING_WORLD");
events:RegisterEvent("CHAT_MSG_ADDON");
events:RegisterEvent("CHAT_MSG_LOOT");
events:RegisterEvent("LOOT_OPENED");
events:SetScript("OnEvent", function()
	if ( event == "LOOT_OPENED" ) then
		ScanLootWindow();
	elseif ( event == "CHAT_MSG_LOOT" ) then
		OnLootMessage(arg1);
	elseif ( event == "CHAT_MSG_ADDON" ) then
		if ( arg1 == "AZSZONE" ) then CheckZone(); end
	else
		EnsureDB();
		ApplyPosition();
		CheckZone();
		needsRefresh = true;
	end
end);
events:SetScript("OnUpdate", function()
	pollElapsed = pollElapsed + arg1;
	if ( pollElapsed < 0.5 ) then return; end
	pollElapsed = 0;
	CheckZone();
	PollLiveItems();
	local azlList = AzerlootMissing();
	local azlCount = azlList and table.getn(azlList) or -1;
	if ( azlCount ~= lastAzerlootCount ) then lastAzerlootCount = azlCount; needsRefresh = true; end
	if ( needsRefresh or (bar:IsShown() and math.abs(bar:GetHeight() - CurrentIconSize()) > 0.5) ) then RefreshRow(); end
end);
