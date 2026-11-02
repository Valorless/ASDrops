-- Settings window and minimap button.
-- Row visibility: ASDropsDB.barHidden (loot bar) and ASDropsZoneDB.hidden (missing row, also /asmissing hide).
-- Missing-row options (all default off) live in ASDropsZoneDB: showCollected, greyCollected, checkCollected.
-- The minimap button angle is saved in ASDropsDB.minimapAngle.
local window;
local mmButton;
local checkboxes = {};
local DEFAULT_ANGLE = 140;

local function MainDB()
	if ( type(ASDropsDB) ~= "table" ) then ASDropsDB = ASDropReminderDB or {}; end
	return ASDropsDB;
end

local function ZoneDB()
	if ( type(ASDropsZoneDB) ~= "table" ) then ASDropsZoneDB = {}; end
	if ( type(ASDropsZoneDB.zones) ~= "table" ) then ASDropsZoneDB.zones = {}; end
	return ASDropsZoneDB;
end

local OPTIONS = {
	{ key = "barShown", label = "Show the loot bar", tip = "Show or hide the row of loot received this run.",
		get = function() return not MainDB().barHidden; end,
		set = function(on) MainDB().barHidden = (not on) and true or nil; if ( ASDropsRefreshBar ) then ASDropsRefreshBar(); end end },
	{ key = "missingShown", label = "Show the missing-items row", tip = "Show or hide the row of items from this zone that you haven't collected yet.",
		get = function() return not ZoneDB().hidden; end,
		set = function(on) ZoneDB().hidden = (not on) and true or false; if ( ASDropsRefreshMissing ) then ASDropsRefreshMissing(); end end },
	{ key = "showCollected", label = "Show collected items", gap = true,
		tip = "Also list the zone's items you have already collected in the missing-items row, in boss order.",
		get = function() return ZoneDB().showCollected and true or false; end,
		set = function(on) ZoneDB().showCollected = on and true or false; if ( ASDropsRefreshMissing ) then ASDropsRefreshMissing(); end end },
	{ key = "greyCollected", label = "Greyscale collected items", needsCollected = true,
		tip = "Draw collected items in grey. Only used while 'Show collected items' is on.",
		get = function() return ZoneDB().greyCollected and true or false; end,
		set = function(on) ZoneDB().greyCollected = on and true or false; if ( ASDropsRefreshMissing ) then ASDropsRefreshMissing(); end end },
	{ key = "checkCollected", label = "Green checkmark on collected items", needsCollected = true,
		tip = "Put a green checkmark on collected items. Only used while 'Show collected items' is on.",
		get = function() return ZoneDB().checkCollected and true or false; end,
		set = function(on) ZoneDB().checkCollected = on and true or false; if ( ASDropsRefreshMissing ) then ASDropsRefreshMissing(); end end },
};

local function UpdateCheckboxes()
	if ( not window ) then return; end
	local collectedOn = ZoneDB().showCollected and true or false;
	for i = 1, table.getn(OPTIONS) do
		local option = OPTIONS[i];
		local box = checkboxes[option.key];
		box:SetChecked(option.get() and 1 or nil);
		local text = getglobal(box:GetName() .. "Text");
		if ( option.needsCollected and not collectedOn ) then
			box:Disable();
			if ( text ) then text:SetTextColor(0.5, 0.5, 0.5); end
		else
			box:Enable();
			if ( text ) then text:SetTextColor(1, 0.82, 0); end
		end
	end
end

local function CreateCheckbox(option, index, y)
	local box = CreateFrame("CheckButton", "ASDropsSettingsCheck" .. index, window, "UICheckButtonTemplate");
	ASDropsKeepOnTop(box);
	box:SetWidth(26);
	box:SetHeight(26);
	box:SetPoint("TOPLEFT", window, "TOPLEFT", 16, y);
	local text = getglobal(box:GetName() .. "Text");
	if ( text ) then text:SetText(option.label); end
	box.option = option;
	box:SetScript("OnClick", function()
		this.option.set(this:GetChecked() and true or false);
		UpdateCheckboxes();
	end);
	box:SetScript("OnEnter", function()
		GameTooltip:SetOwner(this, "ANCHOR_RIGHT");
		GameTooltip:SetText(this.option.label, 1, 0.82, 0);
		GameTooltip:AddLine(this.option.tip, 0.9, 0.9, 0.9, 1);
		GameTooltip:Show();
	end);
	box:SetScript("OnLeave", function() GameTooltip:Hide(); end);
	checkboxes[option.key] = box;
end

local function CreateWindow()
	window = CreateFrame("Frame", "ASDropsSettingsFrame", UIParent);
	ASDropsKeepOnTop(window);
	window:SetWidth(300);
	window:SetHeight(230);
	window:SetPoint("CENTER", UIParent, "CENTER", 0, 60);
	window:SetFrameStrata("DIALOG");
	window:SetBackdrop({
		bgFile = "Interface\\DialogFrame\\UI-DialogBox-Background",
		edgeFile = "Interface\\DialogFrame\\UI-DialogBox-Border",
		tile = true, tileSize = 32, edgeSize = 32,
		insets = { left = 11, right = 12, top = 12, bottom = 11 },
	});
	window:SetMovable(true);
	window:EnableMouse(true);
	window:SetClampedToScreen(true);
	window:RegisterForDrag("LeftButton");
	window:SetScript("OnDragStart", function() this:StartMoving(); end);
	window:SetScript("OnDragStop", function() this:StopMovingOrSizing(); end);
	window:Hide();
	table.insert(UISpecialFrames, "ASDropsSettingsFrame");
	window:SetScript("OnShow", UpdateCheckboxes);

	local title = window:CreateFontString(nil, "OVERLAY", "GameFontNormal");
	title:SetPoint("TOP", window, "TOP", 0, -16);
	title:SetText("ASDrops settings");
	local close = CreateFrame("Button", "ASDropsSettingsClose", window, "UIPanelCloseButton");
	ASDropsKeepOnTop(close);
	close:SetPoint("TOPRIGHT", window, "TOPRIGHT", -6, -6);

	local rowsLabel = window:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall");
	rowsLabel:SetPoint("TOPLEFT", window, "TOPLEFT", 20, -42);
	rowsLabel:SetText("Rows");
	local y = -54;
	for i = 1, table.getn(OPTIONS) do
		local option = OPTIONS[i];
		if ( option.gap ) then
			y = y - 10;
			local missingLabel = window:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall");
			missingLabel:SetPoint("TOPLEFT", window, "TOPLEFT", 20, y - 2);
			missingLabel:SetText("Missing-items row");
			y = y - 14;
		end
		CreateCheckbox(option, i, y);
		y = y - 28;
	end
	window:SetHeight(-y + 22);
	UpdateCheckboxes();
end

function ASDropsToggleSettings()
	if ( not window ) then CreateWindow(); end
	if ( window:IsShown() ) then window:Hide(); else window:Show(); end
end

local function SquareMinimap()
	if ( type(IsAddOnLoaded) ~= "function" ) then return false; end
	local ok, loaded = pcall(IsAddOnLoaded, "SurvivorsDragonUi");
	return ok and loaded and true or false;
end

local function PlaceMinimapButton()
	local angle = tonumber(MainDB().minimapAngle) or DEFAULT_ANGLE;
	local a = math.rad(angle);
	local c, s = math.cos(a), math.sin(a);
	local half = (Minimap:GetWidth() or 140) / 2;
	local x, y;
	if ( SquareMinimap() ) then
		local r = half + 6;
		local m = math.max(math.abs(c), math.abs(s));
		x, y = c * r / m, s * r / m;
	else
		local r = half + 10;
		x, y = c * r, s * r;
	end
	mmButton:ClearAllPoints();
	mmButton:SetPoint("CENTER", Minimap, "CENTER", x, y);
end

local function CreateMinimapButton()
	if ( not Minimap ) then return; end
	mmButton = CreateFrame("Button", "ASDropsMinimapButton", Minimap);
	ASDropsKeepOnTop(mmButton);
	mmButton:SetWidth(31);
	mmButton:SetHeight(31);
	mmButton:SetFrameStrata("MEDIUM");
	mmButton:SetFrameLevel((Minimap:GetFrameLevel() or 1) + 8);
	mmButton:RegisterForClicks("LeftButtonUp");
	mmButton:RegisterForDrag("LeftButton");
	local icon = mmButton:CreateTexture(nil, "ARTWORK");
	icon:SetWidth(20);
	icon:SetHeight(20);
	icon:SetPoint("CENTER", mmButton, "CENTER", 0, 1);
	icon:SetTexture("Interface\\Icons\\INV_Misc_Bag_11");
	local border = mmButton:CreateTexture(nil, "OVERLAY");
	border:SetTexture("Interface\\Minimap\\MiniMap-TrackingBorder");
	border:SetWidth(53);
	border:SetHeight(53);
	border:SetPoint("TOPLEFT", mmButton, "TOPLEFT", 0, 0);
	mmButton:SetHighlightTexture("Interface\\Minimap\\UI-Minimap-ZoomButton-Highlight");
	mmButton:SetScript("OnClick", function()
		GameTooltip:Hide();
		ASDropsToggleSettings();
	end);
	mmButton:SetScript("OnEnter", function()
		GameTooltip:SetOwner(this, "ANCHOR_LEFT");
		GameTooltip:AddLine("ASDrops", 1, 0.82, 0);
		GameTooltip:AddLine("Click: open or close the settings", 0.9, 0.9, 0.9);
		GameTooltip:AddLine("Drag: move round the minimap", 0.6, 0.6, 0.6);
		GameTooltip:Show();
	end);
	mmButton:SetScript("OnLeave", function() GameTooltip:Hide(); end);
	mmButton:SetScript("OnDragStart", function()
		GameTooltip:Hide();
		this.dragging = true;
	end);
	mmButton:SetScript("OnDragStop", function() this.dragging = nil; end);
	mmButton:SetScript("OnUpdate", function()
		if ( not this.dragging ) then return; end
		local x, y = GetCursorPosition();
		local scale = Minimap:GetEffectiveScale();
		local cx, cy = Minimap:GetCenter();
		local dx, dy = x / scale - cx, y / scale - cy;
		local deg = math.deg((math.atan2 or math.atan)(dy, dx));
		if ( deg < 0 ) then deg = deg + 360; end
		MainDB().minimapAngle = deg;
		PlaceMinimapButton();
	end);
	PlaceMinimapButton();
	mmButton:Show();
end

local starter = CreateFrame("Frame", "ASDropsSettingsEvents");
ASDropsKeepOnTop(starter);
starter:RegisterEvent("PLAYER_ENTERING_WORLD");
starter:SetScript("OnEvent", function()
	if ( not mmButton ) then CreateMinimapButton(); end
	if ( window ) then UpdateCheckboxes(); end
end);
