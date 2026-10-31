local BAR_NAME = "ASDropsBar";
local iconSize = 36;
local ICON_GAP = 4;
local PREVIEW_ICONS = 3;
local MAX_LOOT_ITEMS = 20;
local BOSS_LOOT_WINDOW = 12;
local NO_LOOT_ICON = "Interface\\Icons\\INV_Stone_12";
local items = {};
local icons = {};
local pendingBossDowns = {};
local restoredBossKills = false;
local restoreComplete = false;
local lastItemLootAt;
local seenLootNotices = {};
local recentLootSources = {};
local recentLootSounds = {};
local lastRecordedLootItem;
local lastBossDown;
local haveRunSnapshot = false;
local runSeen;
local resizeHandle;
local resizing = false;
local resizeStartX = 0;
local resizeStartY = 0;
local resizeStartSize = 36;
local locked = false;
local ToggleLock;
local ResolveItemMetadata;

local function GetItemKey(link)
	if ( not link ) then return nil; end
	local _, _, id = string.find(link, "item:(%d+)");
	if ( id ) then return id; end
	return link;
end

local function PlayLootPickupSound()
	if ( type(PlaySoundFile) == "function" ) then
		pcall(PlaySoundFile, "Sound\\Interface\\UiLootPickUpItem.wav");
	end
end

local function LocalizedLootText(text)
	if ( DFRL and DFRL.locale and type(DFRL.locale.Native) == "function" ) then
		local ok, result = pcall(DFRL.locale.Native, text);
		if ( ok and type(result) == "string" and result ~= "" ) then return result; end
	end
	return text;
end

local function CollectionStatusFromMessage(message)
	if ( type(message) ~= "string" ) then return nil; end
	local text = string.lower(message);
	local newText = string.lower(LocalizedLootText("New in your collection!"));
	if ( string.find(text, newText, 1, true) or string.find(text, "new in your collection", 1, true) ) then return "new"; end
	local collectedText = string.lower(LocalizedLootText("already collected"));
	if ( string.find(text, collectedText, 1, true) or string.find(text, "already collected", 1, true) ) then return "collected"; end
	return nil;
end

local function IsSelfLootMessage(message)
	if ( type(message) ~= "string" ) then return false; end
	local lootFormat = LOOT_ITEM_SELF;
	if ( type(lootFormat) == "string" ) then
		local marker = string.find(lootFormat, "%s", 1, true);
		if ( marker and marker > 1 and string.find(message, string.sub(lootFormat, 1, marker - 1), 1, true) ) then return true; end
	end
	local prefix = LocalizedLootText("You receive loot:");
	return string.find(message, prefix, 1, true) ~= nil
		or string.find(message, "You receive loot:", 1, true) ~= nil;
end

local function ParsePlainLootLabel(message)
	local _, _, color, name = string.find(message, "|c(%x%x%x%x%x%x%x%x)%[([^%]]+)%]");
	if ( not name ) then _, _, name = string.find(message, "%[([^%]]+)%]"); end
	if ( name ) then
		name = string.gsub(name, "^%s+", "");
		name = string.gsub(name, "%s+$", "");
	end
	return name, color;
end

local function RarityFromColor(color)
	if ( not color ) then return nil; end
	color = string.lower(tostring(color));
	color = string.gsub(color, "^|c", "");
	local _, _, hex = string.find(color, "(%x%x%x%x%x%x%x%x)$");
	if ( hex ) then color = string.sub(hex, 3); end
	local rarities = {
		["9d9d9d"] = "Poor", ["ffffff"] = "Common", ["1eff00"] = "Uncommon",
		["0070dd"] = "Rare", ["a335ee"] = "Epic", ["ff8000"] = "Legendary",
		["e6cc80"] = "Artifact", ["00ccff"] = "Heirloom",
	};
	return rarities[color];
end

local function ColorFromItemLink(link)
	local _, _, color = string.find(link or "", "^|c(%x%x%x%x%x%x%x%x)");
	return color;
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

local function TypeFromEquipLoc(equipLoc)
	if ( not equipLoc ) then return nil; end
	local types = {
		INVTYPE_HEAD = "Helmet", INVTYPE_SHOULDER = "Shoulders", INVTYPE_CHEST = "Chest",
		INVTYPE_ROBE = "Chest", INVTYPE_CLOAK = "Cloak", INVTYPE_WRIST = "Wrist",
		INVTYPE_HAND = "Hands", INVTYPE_WAIST = "Waist", INVTYPE_LEGS = "Legs",
		INVTYPE_FEET = "Feet", INVTYPE_FINGER = "Finger", INVTYPE_NECK = "Neck",
		INVTYPE_TRINKET = "Trinket", INVTYPE_SHIELD = "Off Hand", INVTYPE_2HWEAPON = "Weapon",
		INVTYPE_WEAPON = "Weapon", INVTYPE_WEAPONMAINHAND = "Weapon", INVTYPE_WEAPONOFFHAND = "Weapon",
		INVTYPE_RANGED = "Ranged", INVTYPE_THROWN = "Ranged", INVTYPE_RELIC = "Relic",
	};
	return types[equipLoc];
end

local function TypeFromIcon(icon)
	if ( type(icon) ~= "string" ) then return nil; end
	local types = {
		{ "INV_Helmet", "Helmet" }, { "INV_Shoulder", "Shoulders" },
		{ "INV_Chest", "Chest" }, { "INV_Robe", "Chest" }, { "INV_Cloak", "Cloak" },
		{ "INV_Boot", "Feet" }, { "INV_Pant", "Legs" }, { "INV_Belt", "Waist" },
		{ "INV_Glove", "Hands" }, { "INV_Gauntlet", "Hands" }, { "INV_Bracer", "Wrist" },
		{ "INV_Shield", "Off Hand" }, { "INV_Ring", "Finger" }, { "INV_Neck", "Neck" },
		{ "INV_Trinket", "Trinket" }, { "INV_Sword", "Weapon" }, { "INV_Axe", "Weapon" },
		{ "INV_Mace", "Weapon" }, { "INV_Staff", "Weapon" }, { "INV_Bow", "Ranged" },
	};
	for i = 1, table.getn(types) do
		if ( string.find(icon, types[i][1], 1, true) ) then return types[i][2]; end
	end
	return nil;
end

local function ItemIconByName(name)
	if ( not name ) then return nil; end
	local className = type(AZS_ZONE) == "table" and AZS_ZONE.class or nil;
	if ( (not className or className == "") and type(ASDropsZoneDB) == "table" ) then className = ASDropsZoneDB.lastClass; end
		local catalogs = DFRL.LootIconCatalog;
		local code = DFRL.locale and DFRL.locale.code;
		local classes = catalogs.classes and (catalogs.classes[code] or catalogs.classes.en);
		local classCatalog = classes and className and classes[className];
		local classIcon = classCatalog and classCatalog[name];
		if ( type(classIcon) == "string" ) then return classIcon; end
		local catalog = catalogs[code] or catalogs.en;
		local icon = catalog and catalog[name];
		if ( type(icon) == "string" ) then return icon; end
	end
	local classCatalog = ASDROPS_LOOT_ICON_CLASSES and className and ASDROPS_LOOT_ICON_CLASSES[className];
	local classIcon = classCatalog and classCatalog[name];
	if ( type(classIcon) == "string" ) then return classIcon; end
	if ( ASDROPS_LOOT_ICONS and type(ASDROPS_LOOT_ICONS[name]) == "string" ) then
		return ASDROPS_LOOT_ICONS[name];
	end
	-- Class still unknown (for example right after a reload): any class's art beats a blank icon.
	if ( type(ASDROPS_LOOT_ICON_CLASSES) == "table" ) then
		for _, classTable in pairs(ASDROPS_LOOT_ICON_CLASSES) do
			if ( type(classTable) == "table" and type(classTable[name]) == "string" ) then return classTable[name]; end
		end
	end
	return nil;
end

local function SavePosition()
	if ( not ASDropsDB or not ASDropsBar ) then return; end
	local point, _, relativePoint, x, y = ASDropsBar:GetPoint();
	ASDropsDB.point = point;
	ASDropsDB.relativePoint = relativePoint;
	ASDropsDB.x = x;
	ASDropsDB.y = y;
	ASDropsDB.iconSize = iconSize;
end

-- Keep the entire bar inside the screen. Store its position from the lower-left
-- corner after clamping so wide rows remain recoverable on the next login.
local function KeepBarOnScreen()
	if ( not ASDropsBar or not UIParent ) then return; end
	local left = ASDropsBar:GetLeft();
	local bottom = ASDropsBar:GetBottom();
	local screenWidth = UIParent:GetWidth();
	local screenHeight = UIParent:GetHeight();
	if ( not left or not bottom or not screenWidth or not screenHeight ) then return; end
	local width = ASDropsBar:GetWidth();
	local height = ASDropsBar:GetHeight();
	local maxLeft = screenWidth - width;
	-- Leave extra headroom at the top: the game's visible UI area can be
	-- shorter than the physical screen, and this bar should still reach higher.
	local maxBottom = screenHeight - height + 85;
	if ( maxLeft < 0 ) then maxLeft = 0; end
	if ( maxBottom < 0 ) then maxBottom = 0; end
	local clampedLeft = left;
	local clampedBottom = bottom;
	if ( clampedLeft < 0 ) then clampedLeft = 0; end
	if ( clampedLeft > maxLeft ) then clampedLeft = maxLeft; end
	if ( clampedBottom < 0 ) then clampedBottom = 0; end
	if ( clampedBottom > maxBottom ) then clampedBottom = maxBottom; end
	if ( clampedLeft ~= left or clampedBottom ~= bottom ) then
		ASDropsBar:ClearAllPoints();
		ASDropsBar:SetPoint("BOTTOMLEFT", UIParent, "BOTTOMLEFT", clampedLeft, clampedBottom);
		SavePosition();
	end
end

local function SaveItems()
	if ( not ASDropsDB or not restoreComplete ) then return; end
	local saved = {};
	for i = 1, table.getn(items) do
		local item = items[i];
		saved[i] = {
			key = item.key,
			link = item.link,
			itemReference = item.itemReference,
			name = item.name,
			icon = item.icon,
			count = item.count,
			kind = item.kind,
			history = item.history,
			at = item.at,
			text = item.text,
			lootMessage = item.lootMessage,
			bossName = item.bossName,
			bossText = item.bossText,
			rarity = item.rarity,
			itemType = item.itemType,
			nameColor = item.nameColor,
			collection = item.collection,
		};
	end
	ASDropsDB.items = saved;
	local runTime;
	if ( type(AZS_GetRunTime) == "function" ) then runTime = AZS_GetRunTime(); end
	if ( type(runTime) ~= "number" and type(AZS_RUN) == "table" ) then runTime = tonumber(AZS_RUN.t); end
	if ( type(runTime) == "number" ) then ASDropsDB.runTime = runTime; end
end

ToggleLock = function()
	locked = not locked;
	if ( ASDropsDB ) then ASDropsDB.locked = locked; end
	if ( ASDropsBar and ASDropsBar.SetMovable ) then
		ASDropsBar:SetMovable(not locked);
	end
	if ( resizeHandle and resizeHandle.gripTextures ) then
		for i = 1, table.getn(resizeHandle.gripTextures) do
			if ( locked ) then resizeHandle.gripTextures[i]:Hide();
			else resizeHandle.gripTextures[i]:Show(); end
		end
	end
end

local function CreateIcon(index)
	local button = CreateFrame("Button", nil, ASDropsBar);
	button:SetWidth(iconSize);
	button:SetHeight(iconSize);
	button:SetID(index);
	button:SetPoint("LEFT", ASDropsBar, "LEFT", (index - 1) * (iconSize + ICON_GAP), 0);
	button.rarityBorder = CreateFrame("Frame", nil, button);
	button.rarityBorder:SetAllPoints(button);
	button.rarityBorder:SetFrameLevel(button:GetFrameLevel() + 1);
	button.rarityBorder:EnableMouse(false);
	button.rarityBorder:SetBackdrop({
		edgeFile = "Interface\\Tooltips\\UI-Tooltip-Border",
		edgeSize = 15,
		insets = { left = 2, right = 2, top = 2, bottom = 2 },
	});
	button:RegisterForDrag("LeftButton");
	button:RegisterForClicks("LeftButtonUp", "RightButtonUp");
	button:SetScript("OnClick", function()
		if ( arg1 == "RightButton" ) then ToggleLock(); end
	end);
	button:SetScript("OnDragStart", function()
		if ( not locked ) then ASDropsBar:StartMoving(); end
	end);
	button:SetScript("OnDragStop", function()
		if ( not locked ) then
			ASDropsBar:StopMovingOrSizing();
			SavePosition();
		end
	end);
	button.texture = button:CreateTexture(nil, "ARTWORK");
	button.texture:SetPoint("TOPLEFT", button, "TOPLEFT", 2, -2);
	button.texture:SetPoint("BOTTOMRIGHT", button, "BOTTOMRIGHT", -2, 2);
	button.count = button:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall");
	button.count:SetPoint("BOTTOMRIGHT", button, "BOTTOMRIGHT", -1, 1);
	button.count:SetTextColor(1, 1, 1, 1);
	button.count:SetShadowColor(0, 0, 0, 1);
	button.count:SetShadowOffset(1, -1);
	button.newLabel = button:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall");
	button.newLabel:SetFont("Fonts\\FRIZQT__.TTF", 10, "THICKOUTLINE");
	button.newLabel:SetPoint("BOTTOM", button, "BOTTOM", 0, 2);
	button.newLabel:SetTextColor(1, 1, 1);
	button.newLabel:SetShadowColor(0, 0, 0, 1);
	button.newLabel:SetShadowOffset(1, -1);
	button:EnableMouse(true);
	button:SetScript("OnEnter", function()
		local item = items[this:GetID()];
		if ( item ) then
			GameTooltip:SetOwner(this, "ANCHOR_TOP");
			if ( item.kind == "bossdown" ) then
				GameTooltip:SetText("A Pretty Rock", 1, 0.8, 0.2);
				GameTooltip:AddLine("Nothing of value was dropped, but you found a pretty rock.", 0.9, 0.9, 0.9, 1);
				if ( item.history ) then
					GameTooltip:AddLine("Restored from recent game history", 0.7, 0.9, 1);
				--elseif ( item.lootMessage and item.lootMessage ~= "" ) then
				--	GameTooltip:AddLine("Debug: item link was not recognized", 1, 0.5, 0.5);
				--else
				--	GameTooltip:AddLine("Debug: boss-down banner received", 0.7, 0.9, 1);
				end
				if ( item.name and item.name ~= "" ) then GameTooltip:AddLine("Boss: " .. item.name); end
				--if ( item.text and item.text ~= "" ) then GameTooltip:AddLine("Banner: " .. item.text, 0.8, 0.8, 0.8, 1); end
				if ( item.text and item.text ~= "" ) then GameTooltip:AddLine(item.text, 0.8, 0.8, 0.8, 1); end
				--if ( item.lootMessage and item.lootMessage ~= "" ) then
				--	GameTooltip:AddLine("Loot chat: " .. item.lootMessage, 1, 1, 1, 1);
				--else
				--	GameTooltip:AddLine("Loot chat: no loot event captured", 1, 0.5, 0.5);
				--end
			else
				ResolveItemMetadata(item);
				local tooltipReference = item.link or item.itemReference;
				if ( tooltipReference ) then GameTooltip:SetHyperlink(tooltipReference);
				else GameTooltip:SetText(item.name or "Loot received"); end
				local detail = item.rarity;
				if ( item.itemType and item.itemType ~= "" ) then
					if ( detail ) then detail = detail .. " "; else detail = ""; end
					detail = detail .. item.itemType;
				end
				if ( detail and detail ~= "" ) then
					local red, green, blue = RarityColor(item.rarity);
					GameTooltip:AddLine(detail, red, green, blue);
				end
				if ( item.bossName and item.bossName ~= "" ) then GameTooltip:AddLine("Boss: " .. item.bossName, 1, 0.8, 0.2); end
				if ( item.bossText and item.bossText ~= "" ) then GameTooltip:AddLine(item.bossText, 0.8, 0.8, 0.8, 1); end
			end
			GameTooltip:Show();
		elseif ( this:IsShown() ) then
			GameTooltip:SetOwner(this, "ANCHOR_TOP");
			GameTooltip:SetText("ASDrops", 1, 0.8, 0.2);
			GameTooltip:AddLine("Preview: drops appear here during a run.", 0.9, 0.9, 0.9, 1);
			GameTooltip:AddLine("Drag: move | Drag corner: resize | Right-click: lock/unlock", 0.6, 0.6, 0.6, 1);
			GameTooltip:Show();
		end
	end);
	button:SetScript("OnLeave", function() GameTooltip:Hide(); end);
	return button;
end

ResolveItemMetadata = function(item)
	item.rarity = RarityFromColor(item.nameColor) or item.rarity;
	local catalogIcon = ItemIconByName(item.name);
	if ( catalogIcon and (not item.icon or item.icon == "Interface\\Icons\\INV_Misc_QuestionMark") ) then
		item.icon = catalogIcon;
	end
	item.itemType = item.itemType or TypeFromIcon(item.icon);
	if ( type(GetItemInfo) ~= "function" ) then item.rarity = item.rarity or "Common"; return nil; end
	local lookup = item.link or item.itemReference or item.name or item.key;
	if ( not lookup ) then item.rarity = item.rarity or "Common"; return nil; end
	local ok, itemName, itemLink, quality, _, itemType, _, _, equipLoc, texture = pcall(GetItemInfo, lookup);
	if ( not ok or not itemName or itemName == "" ) then item.rarity = item.rarity or "Common"; return nil; end
	-- Name lookups are cache-based; reject a result that disagrees with SDUI's
	-- name so an ambiguous lookup cannot silently turn into a different item.
	if ( item.name and string.lower(itemName) ~= string.lower(item.name) ) then item.rarity = item.rarity or "Common"; return nil; end
	item.name = item.name or itemName;
	if ( itemLink and itemLink ~= "" ) then item.link = item.link or itemLink; end
	item.rarity = RarityFromQuality(quality) or RarityFromColor(item.nameColor) or item.rarity or "Common";
	item.itemType = item.itemType or TypeFromEquipLoc(equipLoc)
		or TypeFromIcon(texture or item.icon) or itemType;
	if ( texture and texture ~= "Interface\\Icons\\INV_Misc_QuestionMark" ) then
		item.icon = texture;
		return texture;
	end
	return nil;
end

local function ResolveItemTexture(item)
	local nativeTexture = ResolveItemMetadata(item);
	if ( nativeTexture ) then return nativeTexture; end
	if ( item.itemReference and DFRL and DFRL.loot and type(DFRL.loot.Resolve) == "function" ) then
		local ok, resolved = pcall(DFRL.loot.Resolve, { name = item.name, itemReference = item.itemReference });
		if ( ok and type(resolved) == "table" and resolved.icon
				and resolved.icon ~= "Interface\\Icons\\INV_Misc_QuestionMark" ) then
			item.icon = resolved.icon;
			return resolved.icon;
		end
	end
	if ( item.icon == "Interface\\Icons\\INV_Misc_QuestionMark" ) then return nil; end
	return item.icon;
end

-- Before the run clock passes one second (or exists at all) the bar shows placeholders.
local function PreviewActive()
	local runTime;
	if ( type(AZS_GetRunTime) == "function" ) then runTime = AZS_GetRunTime(); end
	if ( type(runTime) ~= "number" and type(AZS_RUN) == "table" ) then runTime = tonumber(AZS_RUN.t); end
	return (type(runTime) ~= "number" or runTime < 1);
end

local previewShown = nil;

local function RefreshBar()
	-- Share the live row with companion modules even before SavedVariables are ready.
	ASDropsLiveItems = items;
	local preview = PreviewActive();
	previewShown = preview;
	local iconCount = table.getn(items);
	local previewCount = 0;
	if ( preview ) then previewCount = PREVIEW_ICONS; end
	if ( table.getn(icons) > iconCount ) then iconCount = table.getn(icons); end
	if ( previewCount > iconCount ) then iconCount = previewCount; end
	for i = 1, iconCount do
		local button = icons[i];
		if ( not button ) then button = CreateIcon(i); icons[i] = button; end
		button:SetWidth(iconSize);
		button:SetHeight(iconSize);
		button:ClearAllPoints();
		button:SetPoint("LEFT", ASDropsBar, "LEFT", (i - 1) * (iconSize + ICON_GAP), 0);
		local item = items[i];
		if ( preview ) then item = nil; end
		if ( item ) then
			local texture = ResolveItemTexture(item);
			button.texture:SetTexture(texture or "Interface\\Icons\\INV_Misc_QuestionMark");
			local red, green, blue = RarityColor(item.rarity or "Common");
			button.rarityBorder:SetBackdropBorderColor(red, green, blue, 1);
			if ( item.count > 1 ) then button.count:SetText(item.count); else button.count:SetText(""); end
			if ( item.collection == "new" ) then button.newLabel:SetText("New"); else button.newLabel:SetText(""); end
			button:Show();
		elseif ( i <= previewCount ) then
			-- Placeholder icons let players position the bar before a run starts.
			button.texture:SetTexture("Interface\\Icons\\INV_Misc_QuestionMark");
			button.rarityBorder:SetBackdropBorderColor(0.62, 0.62, 0.62, 1);
			button.count:SetText("");
			button.newLabel:SetText("");
			button:Show();
		else
			button:Hide();
		end
	end
	local count = table.getn(items);
	if ( preview ) then count = PREVIEW_ICONS; end
	if ( count < 1 ) then count = 1; end
	ASDropsBar:SetWidth(count * iconSize + (count - 1) * ICON_GAP);
	ASDropsBar:SetHeight(iconSize);
	if ( resizeHandle ) then resizeHandle:Raise(); end
	SaveItems();
end

local function ResetItems()
	restoreComplete = true;
	items = {};
	pendingBossDowns = {};
	lastItemLootAt = nil;
	lastRecordedLootItem = nil;
	lastBossDown = nil;
	seenLootNotices = {};
	recentLootSources = {};
	recentLootSounds = {};
	RefreshBar();
end

local function OnBossDown(banner)
	if ( type(banner) ~= "table" or banner.kind ~= "bossdown" ) then return; end
	lastBossDown = { at = GetTime(), name = banner.name, text = banner.text };
	-- Some boss rewards are reported to CHAT_MSG_LOOT just before the banner.
	if ( lastItemLootAt and GetTime() - lastItemLootAt <= BOSS_LOOT_WINDOW ) then
		if ( lastRecordedLootItem ) then
			lastRecordedLootItem.bossName = banner.name;
			lastRecordedLootItem.bossText = banner.text;
			RefreshBar();
		end
		return;
	end
	table.insert(pendingBossDowns, {
		at = GetTime(),
		name = banner.name,
		text = banner.text,
		lootMessage = nil,
	});
end

local function RestoreSavedDrops()
	if ( not ASDropsDB ) then return false; end
	if ( not haveRunSnapshot ) then return false; end
	if ( type(AZS_RUN) ~= "table" or tonumber(AZS_RUN.bk) == nil ) then return false; end
	local phase = type(AZS_GetPhase) == "function" and AZS_GetPhase() or nil;
	if ( not phase or phase == "ready" ) then return false; end
	local liveItems = items;
	items = {};
	if ( type(ASDropsDB.items) == "table" ) then
		for i = 1, table.getn(ASDropsDB.items) do
			local saved = ASDropsDB.items[i];
			if ( type(saved) == "table" ) then
			local savedIcon = saved.kind == "bossdown" and NO_LOOT_ICON or saved.icon;
			local savedNameColor = saved.nameColor or ColorFromItemLink(saved.link);
				table.insert(items, {
					key = saved.key,
					link = saved.link,
					itemReference = saved.itemReference,
					name = saved.name,
				icon = savedIcon,
					count = tonumber(saved.count) or 1,
					kind = saved.kind,
					history = saved.history,
					at = saved.at,
					text = saved.text,
					lootMessage = saved.lootMessage,
					bossName = saved.bossName,
					bossText = saved.bossText,
				rarity = saved.rarity or RarityFromColor(savedNameColor),
				itemType = saved.itemType or TypeFromIcon(savedIcon),
				nameColor = savedNameColor,
					collection = saved.collection,
				});
			end
		end
	else
		local killed = tonumber(AZS_RUN.bk) or 0;
		for i = 1, killed do
			table.insert(items, {
				kind = "bossdown",
				history = true,
				name = "Boss " .. i,
				icon = NO_LOOT_ICON,
				count = 1,
			});
		end
	end
	local killed = tonumber(AZS_RUN.bk) or 0;
	local represented = 0;
	for i = 1, table.getn(items) do
		if ( items[i].kind == "bossdown" or items[i].bossName ) then represented = represented + 1; end
	end
	local missing = killed - represented;
	if ( missing > 0 and type(AZS_SCHEDULE) == "table" ) then
		for i = 1, table.getn(AZS_SCHEDULE) do
			local boss = AZS_SCHEDULE[i];
			if ( missing > 0 and boss.state == "dead" ) then
				table.insert(items, {
					kind = "bossdown",
					history = true,
					name = boss.name,
					icon = NO_LOOT_ICON,
					count = 1,
				});
				missing = missing - 1;
			end
		end
	end
	while ( missing > 0 ) do
		table.insert(items, {
			kind = "bossdown",
			history = true,
			name = "Boss defeated",
			icon = NO_LOOT_ICON,
			count = 1,
		});
		missing = missing - 1;
	end
	for i = 1, table.getn(liveItems) do
		local live = liveItems[i];
		local merged = false;
		if ( live.key and live.kind ~= "bossdown" ) then
			for j = 1, table.getn(items) do
				if ( items[j].key == live.key and items[j].kind ~= "bossdown" ) then
					items[j].count = (tonumber(items[j].count) or 1) + (tonumber(live.count) or 1);
					if ( not items[j].icon or items[j].icon == "Interface\\Icons\\INV_Misc_QuestionMark" ) then
						items[j].icon = live.icon;
					end
					merged = true;
					break;
				end
			end
		end
		if ( not merged ) then table.insert(items, live); end
	end
	restoreComplete = true;
	RefreshBar();
	return true;
end

local function CurrentRunTime()
	if ( type(AZS_GetRunTime) == "function" ) then
		local runTime = AZS_GetRunTime();
		if ( type(runTime) == "number" ) then return runTime; end
	end
	if ( type(AZS_RUN) == "table" ) then return tonumber(AZS_RUN.t); end
	return nil;
end

local function CheckForNewRun()
	if ( not haveRunSnapshot ) then return; end
	local runTime = CurrentRunTime();
	if ( not runTime ) then return; end
	local savedTime = tonumber(ASDropsDB and ASDropsDB.runTime);
	-- Match AZSSpellMeter's live clock-rewind check. Keep a session high-water
	-- mark so a new run is detected even if SavedVariables or phase updates race.
	local phase = type(AZS_GetPhase) == "function" and AZS_GetPhase() or nil;
	local clockRewound = runSeen and runTime + 1 < runSeen;
	local savedRunRewound = savedTime and runTime + 3 < savedTime and phase ~= "ready";
	if ( clockRewound or savedRunRewound ) then
		ResetItems();
		restoredBossKills = true;
	end
	if ( not runSeen or runTime > runSeen or clockRewound or savedRunRewound ) then runSeen = runTime; end
end

local function SaveCurrentRunTime()
	if ( not ASDropsDB or not haveRunSnapshot ) then return; end
	local runTime = CurrentRunTime();
	local savedTime = tonumber(ASDropsDB.runTime);
	if ( runTime and (not savedTime or runTime > savedTime) ) then
		ASDropsDB.runTime = runTime;
	end
end

local function CheckPendingBossDowns()
	local now = GetTime();
	for i = table.getn(pendingBossDowns), 1, -1 do
		local pending = pendingBossDowns[i];
		if ( now - pending.at >= 5 ) then
			table.insert(items, {
				kind = "bossdown",
				at = pending.at,
				name = pending.name,
				text = pending.text,
				lootMessage = pending.lootMessage,
				icon = NO_LOOT_ICON,
				count = 1,
			});
			table.remove(pendingBossDowns, i);
			RefreshBar();
		end
	end
end

local function RecordLoot(key, link, name, texture, source, lootAt, itemReference, nameColor, itemType, quality, equipLoc, collection)
	if ( not key ) then return; end
	lootAt = lootAt or GetTime();
	-- The Dragon UI toast and CHAT_MSG_LOOT describe the same delivery. Suppress
	-- only cross-source duplicates; repeated notices from one source still count.
	local recent = recentLootSources[key];
	if ( recent and recent.source ~= source and lootAt - recent.at <= 1.5 ) then
		recentLootSources[key] = nil;
		return;
	end
	recentLootSources[key] = { source = source, at = lootAt };
	local soundKey = string.lower(tostring(name or key));
	local recentSound = recentLootSounds[soundKey];
	if ( not recentSound or recentSound.source == source or lootAt - recentSound.at > 1.5 ) then
		PlayLootPickupSound();
	end
	recentLootSounds[soundKey] = { source = source, at = lootAt };
	lastItemLootAt = lootAt;
	-- A link-bearing loot notice replaces a matching boss placeholder whether it
	-- arrived just before the banner or after it.
	local boss;
	if ( table.getn(pendingBossDowns) > 0 ) then
		local newest = pendingBossDowns[table.getn(pendingBossDowns)];
		if ( lootAt - newest.at <= BOSS_LOOT_WINDOW ) then
			boss = newest;
			table.remove(pendingBossDowns, table.getn(pendingBossDowns));
		end
	end
	if ( not boss and lastBossDown and math.abs(lootAt - lastBossDown.at) <= BOSS_LOOT_WINDOW ) then boss = lastBossDown; end
	for i = 1, table.getn(items) do
		if ( items[i].key == key ) then
			local existing = items[i];
			existing.count = existing.count + 1;
			existing.link = existing.link or link;
			existing.itemReference = existing.itemReference or itemReference;
			existing.name = existing.name or name;
			existing.nameColor = existing.nameColor or nameColor;
			existing.rarity = RarityFromQuality(quality) or RarityFromColor(nameColor) or existing.rarity;
			existing.itemType = existing.itemType or itemType or TypeFromEquipLoc(equipLoc) or TypeFromIcon(texture);
			if ( collection == "new" ) then existing.collection = "new";
			elseif ( not existing.collection ) then existing.collection = collection; end
			if ( not existing.icon or existing.icon == "Interface\\Icons\\INV_Misc_QuestionMark" ) then existing.icon = texture; end
			if ( boss ) then existing.bossName = boss.name; existing.bossText = boss.text; end
			lastRecordedLootItem = existing;
			RefreshBar();
			return;
		end
	end
	if ( table.getn(items) >= MAX_LOOT_ITEMS ) then return; end
	local item = {
		key = key, link = link, itemReference = itemReference, name = name, icon = texture, count = 1,
		nameColor = nameColor, rarity = RarityFromQuality(quality) or RarityFromColor(nameColor),
		itemType = itemType or TypeFromEquipLoc(equipLoc) or TypeFromIcon(texture),
		collection = collection,
	};
	if ( boss ) then item.bossName = boss.name; item.bossText = boss.text; end
	table.insert(items, item);
	lastRecordedLootItem = item;
	RefreshBar();
end

local function AddLoot(message, eventName)
	if ( not message ) then return; end
	local lootAt = GetTime();
	local collection = CollectionStatusFromMessage(message);
	-- SurvivorsDragonUi exposes the same localized loot parser and icon resolver
	-- it uses for its own toast. Use them when present, but keep native fallback.
	local parsed;
	if ( DFRL and DFRL.CleanerChat and type(DFRL.CleanerChat.ParseLootMessage) == "function" ) then
		local ok, result = pcall(DFRL.CleanerChat.ParseLootMessage, message);
		if ( ok and type(result) == "table" ) then parsed = result; end
	end
	if ( parsed ) then
		local resolved = parsed;
		if ( DFRL.loot and type(DFRL.loot.Resolve) == "function" ) then
			local ok, result = pcall(DFRL.loot.Resolve, parsed);
			if ( ok and type(result) == "table" ) then resolved = result; end
		end
		local link = parsed.label;
		if ( link and not string.find(link, "|Hitem:", 1, true) ) then link = nil; end
		local key = GetItemKey(parsed.itemReference) or (link and GetItemKey(link))
			or string.lower(tostring(parsed.name or "loot"));
		RecordLoot(key, link, parsed.name, resolved.icon, eventName or "chat", lootAt, parsed.itemReference,
			parsed.color, resolved.equipText or parsed.equipText, resolved.quality or parsed.quality,
			resolved.equipLoc or parsed.equipLoc, resolved.collection or parsed.collection or collection);
		return;
	end
	local _, _, link = string.find(message,
		"(|c%x%x%x%x%x%x%x%x|Hitem:[^|]+|h.-|h|r)");
	if ( not link ) then
		_, _, link = string.find(message, "(|Hitem:[^|]+|h.-|h)");
	end
	if ( not link ) then
		if ( IsSelfLootMessage(message) ) then
			local name, nameColor = ParsePlainLootLabel(message);
			if ( name and name ~= "" ) then
				local ok, itemName, itemLink, quality, itemLevel, minLevel, itemClass, itemSubClass, stackCount, equipLoc, texture;
				if ( type(GetItemInfo) == "function" ) then
					ok, itemName, itemLink, quality, itemLevel, minLevel, itemClass, itemSubClass, stackCount, equipLoc, texture = pcall(GetItemInfo, name);
					if ( not ok ) then itemName, itemLink, quality, equipLoc, texture = nil, nil, nil, nil, nil; end
				end
				local resolvedName = itemName or name;
				local itemReference;
				if ( itemLink ) then _, _, itemReference = string.find(itemLink, "|H(item:[^|]+)|h"); end
				local key = GetItemKey(itemReference) or string.lower(resolvedName);
				RecordLoot(key, itemLink, resolvedName, texture, eventName or "chat", lootAt, itemReference,
					nameColor, nil, quality, equipLoc, collection);
				return;
			end
		end
		-- Keep the raw event available on the corresponding marker for diagnosis.
		if ( table.getn(pendingBossDowns) > 0 ) then
			local newest = pendingBossDowns[table.getn(pendingBossDowns)];
			if ( lootAt - newest.at <= BOSS_LOOT_WINDOW ) then newest.lootMessage = message; end
		end
		return;
	end
	local key = GetItemKey(link);
	local name, _, quality, _, _, _, _, _, equipLoc, texture = GetItemInfo(link);
	local _, _, itemReference = string.find(link, "|H(item:[^|]+)|h");
	if ( not texture and itemReference and DFRL and DFRL.loot and type(DFRL.loot.Resolve) == "function" ) then
		local ok, resolved = pcall(DFRL.loot.Resolve, { name = name, itemReference = itemReference });
		if ( ok and type(resolved) == "table" ) then texture = resolved.icon; end
	end
	local _, _, nameColor = string.find(link, "^|c(%x%x%x%x%x%x%x%x)");
	RecordLoot(key, link, name, texture, eventName or "chat", lootAt, itemReference, nameColor, nil, quality, equipLoc, collection);
end

local hookedDragonUIObserver = false;
local function HookDragonUIObserver()
	if ( hookedDragonUIObserver or not DFRL or not DFRL.loot
			or type(DFRL.loot.Observe) ~= "function" ) then return; end
	local loot = DFRL.loot;
	local originalObserve = loot.Observe;
	loot.Observe = function(message, eventName)
		if ( eventName == "CHAT_MSG_LOOT" or eventName == "CHAT_MSG_SYSTEM" ) then
			local chat = DFRL.CleanerChat;
			if ( chat and type(chat.ParseLootMessage) == "function" ) then
				local ok, entry = pcall(chat.ParseLootMessage, message);
				if ( ok and type(entry) == "table" ) then
					local resolved = entry;
					if ( type(loot.Resolve) == "function" ) then
						local resolvedOK, result = pcall(loot.Resolve, entry);
						if ( resolvedOK and type(result) == "table" ) then resolved = result; end
					end
					local link = entry.label;
					if ( link and not string.find(link, "|Hitem:", 1, true) ) then link = nil; end
					local key = GetItemKey(entry.itemReference) or (link and GetItemKey(link))
						or string.lower(tostring(entry.name or "loot"));
					RecordLoot(key, link, entry.name, resolved.icon, "sdui-observer", GetTime(), entry.itemReference,
						entry.color, resolved.equipText or entry.equipText, resolved.quality or entry.quality,
						resolved.equipLoc or entry.equipLoc, resolved.collection or entry.collection);
				end
			end
		end
		return originalObserve(message, eventName);
	end;
	hookedDragonUIObserver = true;
end

local function ScanDragonUILoot()
	local frame = _G and _G.DFRL_LootNotifications;
	if ( not frame or not frame.IsShown or not frame:IsShown() or not frame.GetChildren ) then return; end
	local children = { frame:GetChildren() };
	for i = 1, table.getn(children) do
		local card = children[i];
		local entry = card and card.entry;
		if ( entry and card.IsShown and card:IsShown() ) then
			local noticeKey = entry.sequence or entry.receivedAt;
			if ( noticeKey ) then noticeKey = tostring(noticeKey); end
			if ( not noticeKey ) then
				noticeKey = tostring(entry.name or "") .. "|" .. tostring(entry.itemReference or "");
			end
			local texture = entry.icon;
			if ( not texture and card.icon and card.icon.GetTexture ) then texture = card.icon:GetTexture(); end
			local key = GetItemKey(entry.itemReference)
				or (string.lower(tostring(entry.name or "loot")) .. "|" .. tostring(texture or ""));
			if ( not seenLootNotices[noticeKey] ) then
				seenLootNotices[noticeKey] = true;
				RecordLoot(key, nil, entry.name, texture, "dragonui", entry.receivedAt, entry.itemReference,
					entry.color, entry.equipText, entry.quality, entry.equipLoc, entry.collection);
			else
				-- SDUI may resolve native item metadata a few frames after showing
				-- its toast. Keep our copy in sync with that resolved icon.
				for itemIndex = 1, table.getn(items) do
					local item = items[itemIndex];
					if ( item.key == key and texture
							and (not item.icon or item.icon == "Interface\\Icons\\INV_Misc_QuestionMark") ) then
						item.icon = texture;
						item.name = item.name or entry.name;
						item.nameColor = item.nameColor or entry.color;
						item.rarity = RarityFromColor(entry.color) or item.rarity;
						item.itemType = item.itemType or entry.equipText or TypeFromEquipLoc(entry.equipLoc) or TypeFromIcon(texture);
						RefreshBar();
						break;
					end
				end
			end
		end
	end
end

local function RetryItemIcons()
	local changed = false;
	for i = 1, table.getn(items) do
		local item = items[i];
		local needsIcon = not item.icon or item.icon == "Interface\\Icons\\INV_Misc_QuestionMark";
		if ( item.kind ~= "bossdown" and (item.link or item.itemReference or item.name or item.key)
				and (needsIcon or not item.link) ) then
			local oldLink = item.link;
			local texture = ResolveItemTexture(item);
			if ( item.link ~= oldLink or (needsIcon and texture) ) then changed = true; end
		end
	end
	if ( changed ) then RefreshBar(); end
end

local root = CreateFrame("Frame", "ASDropsRoot", UIParent);
root:RegisterEvent("VARIABLES_LOADED");
root:RegisterEvent("PLAYER_ENTERING_WORLD");
root:RegisterEvent("CHAT_MSG_LOOT");
root:RegisterEvent("CHAT_MSG_SYSTEM");
root:RegisterEvent("CHAT_MSG_ADDON");
root:SetScript("OnEvent", function()
	if ( event == "VARIABLES_LOADED" ) then
		if ( not ASDropsDB ) then ASDropsDB = ASDropReminderDB or {}; end
		locked = (ASDropsDB.locked and true or false);
		iconSize = tonumber(ASDropsDB.iconSize) or 36;
		if ( iconSize < 24 ) then iconSize = 24; end
		if ( iconSize > 80 ) then iconSize = 80; end
		local bar = CreateFrame("Frame", BAR_NAME, UIParent);
		bar:SetWidth(iconSize);
		bar:SetHeight(iconSize);
		bar:SetFrameStrata("HIGH");
		bar:EnableMouse(true);
		bar:SetMovable(not locked);
		bar:RegisterForDrag("LeftButton");
		bar:SetScript("OnMouseUp", function()
			if ( arg1 == "RightButton" ) then ToggleLock(); end
		end);
		bar:SetScript("OnDragStart", function() if ( not locked ) then this:StartMoving(); end end);
		bar:SetScript("OnDragStop", function() this:StopMovingOrSizing(); KeepBarOnScreen(); SavePosition(); end);
		bar:SetPoint(ASDropsDB.point or "CENTER", UIParent,
			ASDropsDB.relativePoint or "CENTER", ASDropsDB.x or 0, ASDropsDB.y or -120);
		KeepBarOnScreen();
		bar:SetScript("OnUpdate", function() KeepBarOnScreen(); end);
		resizeHandle = CreateFrame("Button", nil, bar);
		resizeHandle:SetWidth(20);
		resizeHandle:SetHeight(20);
		resizeHandle:SetPoint("BOTTOMRIGHT", bar, "BOTTOMRIGHT", 0, 0);
		resizeHandle:SetFrameLevel(bar:GetFrameLevel() + 5);
		resizeHandle:SetFrameStrata("DIALOG");
		resizeHandle:EnableMouse(true);
		-- Draw the opposing resize arrows from basic UI textures so this works even
		-- when a client build omits the stock chat-frame grip art.
		local arrowPoints = {
			{ -5, 5 }, { -4, 4 }, { -3, 3 }, { -2, 2 }, { -1, 1 }, { 0, 0 },
			{ 1, -1 }, { 2, -2 }, { 3, -3 }, { 4, -4 }, { 5, -5 },
			{ -3, 5 }, { -5, 3 }, { 3, -5 }, { 5, -3 },
		};
		resizeHandle.gripTextures = {};
		for i = 1, table.getn(arrowPoints) do
			local point = arrowPoints[i];
			local shadow = resizeHandle:CreateTexture(nil, "OVERLAY");
			shadow:SetWidth(3);
			shadow:SetHeight(3);
			shadow:SetPoint("CENTER", resizeHandle, "CENTER", point[1] + 1, point[2] - 1);
			shadow:SetTexture("Interface\\Buttons\\WHITE8X8");
			shadow:SetVertexColor(0, 0, 0);
			table.insert(resizeHandle.gripTextures, shadow);
			local mark = resizeHandle:CreateTexture(nil, "OVERLAY");
			mark:SetWidth(2);
			mark:SetHeight(2);
			mark:SetPoint("CENTER", resizeHandle, "CENTER", point[1], point[2]);
			mark:SetTexture("Interface\\Buttons\\WHITE8X8");
			mark:SetVertexColor(1, 1, 1);
			table.insert(resizeHandle.gripTextures, mark);
			if ( locked ) then shadow:Hide(); mark:Hide(); end
		end
		resizeHandle:Show();
		resizeHandle:RegisterForDrag("LeftButton");
		resizeHandle:SetScript("OnDragStart", function()
			if ( locked ) then return; end
			resizing = true;
			resizeStartX, resizeStartY = GetCursorPosition();
			resizeStartSize = iconSize;
		end);
		resizeHandle:SetScript("OnDragStop", function()
			resizing = false;
			SavePosition();
		end);
		resizeHandle:SetScript("OnEnter", function()
			GameTooltip:SetOwner(this, "ANCHOR_TOPLEFT");
			if ( locked ) then
				GameTooltip:SetText("Right-click to unlock", 1, 1, 1);
			else
				GameTooltip:SetText("Drag to resize; right-click to lock", 1, 1, 1);
			end
			GameTooltip:Show();
		end);
		resizeHandle:RegisterForClicks("RightButtonUp");
		resizeHandle:SetScript("OnClick", function()
			if ( arg1 == "RightButton" ) then ToggleLock(); end
		end);
		resizeHandle:SetScript("OnLeave", function() GameTooltip:Hide(); end);
		RefreshBar();
		if ( type(AZS_RegisterBannerHandler) == "function" ) then
			AZS_RegisterBannerHandler(OnBossDown);
		end
		return;
	end
	if ( event == "CHAT_MSG_LOOT" or event == "CHAT_MSG_SYSTEM" ) then
		AddLoot(arg1, event);
		return;
	end
	if ( event == "CHAT_MSG_ADDON" ) then
		if ( arg1 == "AZSRUN" ) then
			haveRunSnapshot = true;
			CheckForNewRun();
		end
	end
end);

local updater = CreateFrame("Frame");
local iconRetryAge = 0;
updater:SetScript("OnUpdate", function()
	CheckPendingBossDowns();
	HookDragonUIObserver();
	ScanDragonUILoot();
	CheckForNewRun();
	if ( previewShown ~= PreviewActive() ) then RefreshBar(); end
	iconRetryAge = iconRetryAge + (arg1 or 0);
	if ( iconRetryAge >= 0.5 ) then
		iconRetryAge = 0;
		SaveCurrentRunTime();
		RetryItemIcons();
	end
	if ( resizing ) then
		local cursorX, cursorY = GetCursorPosition();
		local scale = UIParent:GetScale();
		if ( not scale or scale == 0 ) then scale = 1; end
		local delta = ((cursorX - resizeStartX) - (cursorY - resizeStartY)) / (2 * scale);
		local newSize = math.floor(resizeStartSize + delta + 0.5);
		if ( newSize < 24 ) then newSize = 24; end
		if ( newSize > 80 ) then newSize = 80; end
		if ( newSize ~= iconSize ) then
			iconSize = newSize;
			RefreshBar();
		end
	end
	if ( not restoredBossKills and RestoreSavedDrops() ) then restoredBossKills = true; end
end);

SLASH_ASDROPS1 = "/asdrops";
SlashCmdList["ASDROPS"] = function(message)
	local command = string.lower(message or "");
	if ( command ~= "debug" ) then
		DEFAULT_CHAT_FRAME:AddMessage("ASDrops: use /asdrops debug to inspect recorded drops.", 1, 0.8, 0.2);
		return;
	end
	local count = table.getn(items);
	DEFAULT_CHAT_FRAME:AddMessage("ASDrops: " .. count .. " recorded entr" .. (count == 1 and "y" or "ies") .. ".", 0.7, 0.9, 1);
	for i = 1, count do
		local item = items[i];
		DEFAULT_CHAT_FRAME:AddMessage(string.format("%d. %s | name=%s | rarity=%s | type=%s | new=%s | key=%s | ref=%s | color=%s | icon=%s",
			i, tostring(item.kind or "loot"), tostring(item.name or "?"), tostring(item.rarity or "?"),
			tostring(item.itemType or "?"), tostring(item.collection or "?"), tostring(item.key or "?"), tostring(item.itemReference or "?"),
			tostring(item.nameColor or "?"), tostring(item.icon or "?")), 1, 1, 1);
		if ( item.link ) then DEFAULT_CHAT_FRAME:AddMessage("   link=" .. tostring(item.link), 0.8, 0.8, 0.8); end
		if ( item.bossName ) then DEFAULT_CHAT_FRAME:AddMessage("   boss=" .. tostring(item.bossName), 1, 0.8, 0.2); end
		if ( item.lootMessage ) then DEFAULT_CHAT_FRAME:AddMessage("   loot chat=" .. tostring(item.lootMessage), 1, 0.6, 0.6); end
	end
	local runTime;
	if ( type(AZS_GetRunTime) == "function" ) then runTime = AZS_GetRunTime(); end
	local snapshotTime = type(AZS_RUN) == "table" and AZS_RUN.t or nil;
	DEFAULT_CHAT_FRAME:AddMessage("ASDrops preview: active=" .. tostring(PreviewActive()) .. " shownState=" .. tostring(previewShown)
		.. " runTime=" .. tostring(runTime) .. " AZS_RUN.t=" .. tostring(snapshotTime)
		.. " phase=" .. tostring(type(AZS_GetPhase) == "function" and AZS_GetPhase() or nil), 0.7, 0.9, 1);
	local screenWidth, screenHeight = UIParent:GetWidth(), UIParent:GetHeight();
	local barLeft, barBottom = ASDropsBar:GetLeft(), ASDropsBar:GetBottom();
	DEFAULT_CHAT_FRAME:AddMessage(string.format("   bar: shown=%s w=%s h=%s left=%s bottom=%s alpha=%s scale=%s screen=%dx%d",
		tostring(ASDropsBar:IsShown()), tostring(ASDropsBar:GetWidth()), tostring(ASDropsBar:GetHeight()),
		tostring(barLeft), tostring(barBottom), tostring(ASDropsBar:GetAlpha()), tostring(ASDropsBar:GetEffectiveScale()),
		screenWidth, screenHeight), 1, 1, 1);
	for i = 1, table.getn(icons) do
		local button = icons[i];
		local left, bottom = button:GetLeft(), button:GetBottom();
		local onScreen = (left and bottom and left >= 0 and bottom >= 0
			and left + button:GetWidth() <= screenWidth and bottom + button:GetHeight() <= screenHeight);
		DEFAULT_CHAT_FRAME:AddMessage(string.format("   icon %d: shown=%s visible=%s size=%s left=%s bottom=%s onScreen=%s texture=%s",
			i, tostring(button:IsShown()), tostring(button:IsVisible()), tostring(button:GetWidth()), tostring(left), tostring(bottom),
			tostring(onScreen and true or false), tostring(button.texture:GetTexture())), 1, 1, 1);
	end
end;

