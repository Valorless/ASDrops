-- Visual-only copies of tracked loot in the backpack's display slots.
-- This does not create or change real inventory items.
local mirrorByButton = {};
local mirrorCount = 0;
local updateElapsed = 0;
local mirroredItems = 0;
local foundSlots = 0;
local visibleCopies = 0;

local function RarityColor(rarity)
	local colors = {
		Poor = { 0.62, 0.62, 0.62 }, Common = { 1, 1, 1 }, Uncommon = { 0.12, 1, 0 },
		Rare = { 0, 0.44, 0.87 }, Epic = { 0.64, 0.21, 0.93 },
		Legendary = { 1, 0.5, 0 }, Artifact = { 0.9, 0.8, 0.5 }, Heirloom = { 0, 0.8, 1 },
	};
	local color = colors[rarity] or colors.Common;
	return color[1], color[2], color[3];
end

local function GetGlobal(name)
	if ( type(getglobal) == "function" ) then return getglobal(name); end
	if ( _G ) then return _G[name]; end
	return nil;
end

local function GetMirror(button)
	local mirror = mirrorByButton[button];
	if ( mirror ) then return mirror; end
	-- Add the image on the slot button's overlay draw layer so the bag art can't
	-- render over a separate child frame.
	mirror = {};
	mirror.icon = button:CreateTexture(nil, "OVERLAY");
	mirror.icon:SetPoint("TOPLEFT", button, "TOPLEFT", 2, -2);
	mirror.icon:SetPoint("BOTTOMRIGHT", button, "BOTTOMRIGHT", -2, 2);
	mirrorCount = mirrorCount + 1;
	mirror.border = CreateFrame("Frame", "ASDropsMirrorBorder" .. mirrorCount, button);
	ASDropsKeepOnTop(mirror.border);
	mirror.border:SetAllPoints(button);
	mirror.border:SetFrameLevel(button:GetFrameLevel() + 6);
	mirror.border:EnableMouse(false);
	mirror.border:SetBackdrop({
		edgeFile = "Interface\\Tooltips\\UI-Tooltip-Border",
		edgeSize = 9,
		insets = { left = 2, right = 2, top = 2, bottom = 2 },
	});
	mirror.tooltip = CreateFrame("Button", "ASDropsMirrorTooltip" .. mirrorCount, button);
	ASDropsKeepOnTop(mirror.tooltip);
	mirror.tooltip:SetAllPoints(button);
	mirror.tooltip:SetFrameLevel(button:GetFrameLevel() + 7);
	mirror.tooltip:EnableMouse(true);
	mirror.tooltip:SetScript("OnEnter", function()
		local item = this.item;
		if ( not item ) then return; end
		GameTooltip:SetOwner(this, "ANCHOR_RIGHT");
		if ( item.kind == "bossdown" ) then
			GameTooltip:SetText("A Pretty Rock", 1, 0.8, 0.2);
			GameTooltip:AddLine("Nothing of value was dropped, but you found a pretty rock.", 0.9, 0.9, 0.9, 1);
			if ( item.name and item.name ~= "" ) then GameTooltip:AddLine("Boss: " .. item.name); end
		else
			local itemLink = item.link or item.itemReference;
			if ( not itemLink and item.name and type(GetItemInfo) == "function" ) then
				local ok, _, resolvedLink = pcall(GetItemInfo, item.name);
				if ( ok and resolvedLink ) then itemLink = resolvedLink; item.link = resolvedLink; end
			end
			if ( itemLink ) then GameTooltip:SetHyperlink(itemLink);
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
	end);
	mirror.tooltip:SetScript("OnLeave", function() GameTooltip:Hide(); end);
	mirrorByButton[button] = mirror;
	return mirror;
end

local function UpdateBagMirror()
	local rowItems = ASDropsLiveItems;
	if ( type(rowItems) ~= "table" and type(ASDropsDB) == "table" ) then rowItems = ASDropsDB.items; end
	if ( type(rowItems) ~= "table" ) then rowItems = {}; end
	local visibleItems = {};
	for i = 1, table.getn(rowItems) do
		local item = rowItems[i];
		if ( type(item) == "table" ) then
			table.insert(visibleItems, item);
		end
	end
	mirroredItems = table.getn(visibleItems);
	local itemIndex = 1;
	foundSlots = 0;
	visibleCopies = 0;
	for frameSlot = 16, 1, -1 do
		local button = GetGlobal("ContainerFrame1Item" .. frameSlot);
		if ( button ) then
			foundSlots = foundSlots + 1;
			local item = visibleItems[itemIndex];
			local mirror = GetMirror(button);
			if ( item ) then
				local texture = item.icon;
				if ( not texture and ASDROPS_LOOT_ICONS ) then texture = ASDROPS_LOOT_ICONS[item.name]; end
				mirror.item = item;
				mirror.icon:SetTexture(texture or "Interface\\Icons\\INV_Misc_QuestionMark");
				local red, green, blue = RarityColor(item.rarity or "Common");
				mirror.border:SetBackdropBorderColor(red, green, blue, 1);
				mirror.icon:Show();
				mirror.border:Show();
				mirror.tooltip.item = item;
				mirror.tooltip:Show();
				visibleCopies = visibleCopies + 1;
				itemIndex = itemIndex + 1;
			else
				mirror.item = nil;
				mirror.icon:Hide();
				mirror.border:Hide();
				mirror.tooltip.item = nil;
				mirror.tooltip:Hide();
			end
		end
	end
end

SLASH_ASDROPSBAG1 = "/asdropsbag";
SlashCmdList["ASDROPSBAG"] = function(message)
	if ( string.lower(message or "") ~= "debug" ) then
		DEFAULT_CHAT_FRAME:AddMessage("ASDrops bag mirror: use /asdropsbag debug to inspect its status.", 1, 0.8, 0.2);
		return;
	end
	DEFAULT_CHAT_FRAME:AddMessage(string.format("ASDrops bag mirror: %d row loot items, %d bag slots found, %d copies shown.",
		mirroredItems, foundSlots, visibleCopies), 0.7, 0.9, 1);
	if ( foundSlots == 0 ) then
		DEFAULT_CHAT_FRAME:AddMessage("Open the backpack first; its ContainerFrame1Item slots are created when shown.", 1, 0.8, 0.2);
	end
end;

local updater = CreateFrame("Frame", "ASDropsMirrorUpdater");
ASDropsKeepOnTop(updater);
updater:RegisterEvent("VARIABLES_LOADED");
updater:RegisterEvent("PLAYER_ENTERING_WORLD");
updater:RegisterEvent("BAG_UPDATE");
updater:SetScript("OnEvent", function() UpdateBagMirror(); end);
updater:SetScript("OnUpdate", function()
	updateElapsed = updateElapsed + (arg1 or 0);
	if ( updateElapsed < 0.25 ) then return; end
	updateElapsed = 0;
	UpdateBagMirror();
end);
