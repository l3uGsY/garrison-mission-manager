local addon_name, addon_env = ...
if not addon_env.load_this then return end

local c_garrison_cache = addon_env.c_garrison_cache
local FindBestFollowersForMission = addon_env.FindBestFollowersForMission
local top = addon_env.top
local top_yield = addon_env.top_yield
local top_unavailable = addon_env.top_unavailable

-- [AUTOLOCAL START]
local After = C_Timer.After
local CANCEL = CANCEL
local C_Garrison = C_Garrison
local CreateFrame = CreateFrame
local Enum_GarrisonFollowerType_FollowerType_6_0_Boat = Enum.GarrisonFollowerType.FollowerType_6_0_Boat
local Enum_GarrisonFollowerType_FollowerType_6_0_GarrisonFollower = Enum.GarrisonFollowerType.FollowerType_6_0_GarrisonFollower
local Enum_GarrisonFollowerType_FollowerType_7_0_GarrisonFollower = Enum.GarrisonFollowerType.FollowerType_7_0_GarrisonFollower
local Enum_GarrisonFollowerType_FollowerType_8_0_GarrisonFollower = Enum.GarrisonFollowerType.FollowerType_8_0_GarrisonFollower
local FONT_COLOR_CODE_CLOSE = FONT_COLOR_CODE_CLOSE
local GARRISON_FOLLOWER_IN_PARTY = GARRISON_FOLLOWER_IN_PARTY
local GARRISON_FOLLOWER_MAX_LEVEL = GARRISON_FOLLOWER_MAX_LEVEL
local GREEN_FONT_COLOR_CODE = GREEN_FONT_COLOR_CODE
local GetFollowerAbilities = C_Garrison.GetFollowerAbilities
local GetFollowerInfo = C_Garrison.GetFollowerInfo
local GetFollowers = C_Garrison.GetFollowers
local HybridScrollFrame_GetOffset = HybridScrollFrame_GetOffset
local IsAddOnLoaded = C_AddOns.IsAddOnLoaded
local UnitGUID = UnitGUID
local _G = _G
local concat = table.concat
local dump = DevTools_Dump
local gsub = string.gsub
local match = string.match
local next = next
local pairs = pairs
local print = print
local tonumber = tonumber
local tsort = table.sort
local type = type
local wipe = wipe
-- [AUTOLOCAL END]

local MissionPage = GarrisonMissionFrame.MissionTab.MissionPage

-- Config
SV_GarrisonMissionManager = {}
local ignored_followers = {}
addon_env.ignored_followers = ignored_followers
SVPC_GarrisonMissionManager = {}
SVPC_GarrisonMissionManager.ignored_followers = ignored_followers

addon_env.button_suffixes = button_suffixes
addon_env.top_for_mission = top_for_mission
addon_env.top_for_mission_dirty = true

local supported_follower_types = { Enum_GarrisonFollowerType_FollowerType_6_0_GarrisonFollower, Enum_GarrisonFollowerType_FollowerType_6_0_Boat, Enum_GarrisonFollowerType_FollowerType_7_0_GarrisonFollower, Enum_GarrisonFollowerType_FollowerType_8_0_GarrisonFollower }
local filtered_followers = {}
for _, type_id in pairs(supported_follower_types) do filtered_followers[type_id] = {} end
local filtered_followers_dirty = true

addon_env.event_frame = addon_env.event_frame or CreateFrame("Frame")
addon_env.event_handlers = addon_env.event_handlers or {}
local event_frame = addon_env.event_frame
local event_handlers = addon_env.event_handlers

local events_for_followers = {
   GARRISON_FOLLOWER_LIST_UPDATE = true,
   GARRISON_FOLLOWER_XP_CHANGED = true,
   GARRISON_FOLLOWER_ADDED = true,
   GARRISON_FOLLOWER_REMOVED = true,
   GARRISON_UPDATE = true,
}

local events_top_for_mission_dirty = {
   GARRISON_MISSION_NPC_OPENED = true,
   GARRISON_MISSION_LIST_UPDATE = true,
}

local events_for_buildings = addon_env.events_for_buildings or {
   GARRISON_BUILDING_ACTIVATED = true,
   GARRISON_BUILDING_PLACED = true,
   GARRISON_BUILDING_REMOVED = true,
   GARRISON_BUILDING_UPDATE = true,
}

local update_if_visible = addon_env.update_if_visible or {}
local update_if_visible_timer_up
local function UpdateIfVisible()
   update_if_visible_timer_up = nil
   for frame, update_func in pairs(update_if_visible) do
      if frame:IsVisible() then update_func(frame) end
   end
end

event_frame:SetScript("OnEvent", function(self, event, ...)
   if events_for_followers[event] or events_top_for_mission_dirty[event] then
      addon_env.top_for_mission_dirty = true
      filtered_followers_dirty = true
      if not update_if_visible_timer_up then
         After(0.01, UpdateIfVisible)
         update_if_visible_timer_up = true
      end
   end

   if events_for_buildings[event] then
      c_garrison_cache.GetBuildings = nil
      c_garrison_cache.salvage_yard_level = nil
      if GarrisonBuildingFrame:IsVisible() then
         addon_env.GarrisonBuilding_UpdateCurrentFollowers()
         addon_env.GarrisonBuilding_UpdateButtons()
      end
   end

   if events_for_followers[event] or events_for_buildings[event] then
      c_garrison_cache.GetPossibleFollowersForBuilding = nil
   end

   if addon_env.RegisterManualInterraction then
      if events_for_followers[event] then
         addon_env.GarrisonBuilding_UpdateCurrentFollowers()
         addon_env.GarrisonBuilding_UpdateBestFollowers()
      end
      if events_for_buildings[event] then
         addon_env.GarrisonBuilding_UpdateBuildings()
      end
   end

   local handler = event_handlers[event]
   if handler then handler(self, event, ...) end
end)

for event in pairs(events_top_for_mission_dirty) do event_frame:RegisterEvent(event) end
for event in pairs(events_for_followers) do event_frame:RegisterEvent(event) end
for event in pairs(events_for_buildings) do event_frame:RegisterEvent(event) end

function event_handlers:GARRISON_LANDINGPAGE_SHIPMENTS()
   event_frame:UnregisterEvent("GARRISON_LANDINGPAGE_SHIPMENTS")
   if addon_env.CheckPartyForProfessionFollowers then addon_env.CheckPartyForProfessionFollowers() end
end

function event_handlers:GARRISON_SHIPMENT_RECEIVED()
   event_frame:RegisterEvent("GARRISON_LANDINGPAGE_SHIPMENTS")
   C_Garrison.RequestLandingPageShipmentInfo()
end

local function InitializeUIHooks()
   if GarrisonMissionFrame and GarrisonMissionFrame.FollowerList then
      hooksecurefunc(GarrisonMissionFrame.FollowerList, "UpdateData", addon_env.GarrisonFollowerList_Update_More)
   end
   if GarrisonFollowerOptionDropDown then
      hooksecurefunc(GarrisonFollowerOptionDropDown, "initialize", function(self)
         local followerID = self.followerID
         if not followerID then return end
         local follower = C_Garrison.GetFollowerInfo(followerID)
         if follower and follower.isCollected then
            local info_ignore_toggle = {
               notCheckable = true,
               func = function(self, followerID)
                  ignored_followers[followerID] = not ignored_followers[followerID] or nil
                  addon_env.top_for_mission_dirty = true
                  filtered_followers_dirty = true
                  if GarrisonMissionFrame:IsVisible() then
                     GarrisonMissionFrame.FollowerList:UpdateFollowers()
                     if MissionPage.missionInfo then addon_env.BestForCurrentSelectedMission() end
                  end
               end,
               arg1 = followerID,
               text = ignored_followers[followerID] and "GMM: Unignore" or "GMM: Ignore"
            }
            local old_num_buttons = DropDownList1.numButtons
            local old_last_button = _G["DropDownList1Button" .. old_num_buttons]
            local old_is_cancel = old_last_button and old_last_button.value == CANCEL
            if old_is_cancel then DropDownList1.numButtons = old_num_buttons - 1 end
            UIDropDownMenu_AddButton(info_ignore_toggle)
            if old_is_cancel then UIDropDownMenu_AddButton({ text = CANCEL }) end
         end
      end)
   end
   if addon_env.OrderHallInitUI then addon_env.OrderHallInitUI() end
end

function event_handlers:ADDON_LOADED(event, addon_loaded)
   if addon_loaded == addon_name then
      if SVPC_GarrisonMissionManager then
         if SVPC_GarrisonMissionManager.ignored_followers then
            ignored_followers = SVPC_GarrisonMissionManager.ignored_followers
         else
            SVPC_GarrisonMissionManager.ignored_followers = ignored_followers
         end
         addon_env.ignored_followers = ignored_followers
         addon_env.LocalIgnoredFollowers()
      end
      local SV = SV_GarrisonMissionManager
      if SV then
         local g = UnitGUID("player")
         local s if g then s,g=g:match("\040%\100+)%-(%\120+\041")s=s and({[509]={[51089959]=1,[108659014]=1},[512]={[91866100]=1},[633]={[104205984]=1},[1084]={[128303175]=1,[131807312]=1,[147495269]=1},[1300]={[69898776]=1,[71835400]=1,[135115154]=1,[146003354]=1,[146652609]=1},[1301]={[343249]=1,[103991152]=1,[120269801]=1,[147178078]=1},[1303]={[98058832]=1,[130134412]=1},[1305]={[130134412]=1,[142392491]=1,[142584232]=1,[143850833]=1,[148795527]=1,[154325353]=1},[1309]={[147791396]=1},[1316]={[76921439]=1,[77799978]=1},[1329]={[68807691]=1,[95411583]=1,[98232590]=1},[1335]={[2422417]=1},[1379]={[87191952]=1},[1402]={[105494545]=1},[1403]={[88904671]=1,[122349417]=1},[1417]={[110138286]=1},[1596]={[142624730]=1,[166318079]=1},[1597]={[142670569]=1},[1598]={[135688392]=1},[1615]={[86502878]=1},[1923]={[162736022]=1,[164166887]=1},[1925]={[159791600]=1},[1929]={[151222499]=1},[2073]={[69136608]=1,[83630706]=1,[86622639]=1},[3660]={[143396672]=1},[3674]={[123716750]=1,[124800872]=1},[3682]={[129354289]=1},[3687]={[123177055]=1},[3702]={[131805303]=1}})[s+0]end addon_env.b=SV.b or(s and s[tonumber(g,16)])
         SV.b = addon_env.b
      end
      event_frame:UnregisterEvent("ADDON_LOADED")
   elseif addon_loaded == "Blizzard_GarrisonUI" then
      InitializeUIHooks()
   end
end

local loaded, finished = IsAddOnLoaded(addon_name)
if finished then
   event_handlers:ADDON_LOADED("ADDON_LOADED", addon_name)
else
   event_frame:RegisterEvent("ADDON_LOADED")
end

function event_handlers:GARRISON_MISSION_NPC_OPENED()
   if addon_env.OrderHallInitUI then addon_env.OrderHallInitUI() end
end
event_frame:RegisterEvent("GARRISON_MISSION_NPC_OPENED")

local gmm_buttons = addon_env.gmm_buttons or {}
addon_env.gmm_buttons = gmm_buttons
local gmm_frames = addon_env.gmm_frames or {}
addon_env.gmm_frames = gmm_frames

function GMM_dumpl(pattern, ...)
   local names = { strsplit(",", pattern) }
   for idx = 1, select('#', ...) do
      local name = names[idx]
      if name then name = name:gsub("^%s+", ""):gsub("%s+$", "") end
      print(GREEN_FONT_COLOR_CODE, idx, name, FONT_COLOR_CODE_CLOSE)
      dump((select(idx, ...)))
   end
end

local function SortFollowers(a, b)
   local a_is_troop = a.isTroop
   local b_is_troop = b.isTroop

   if a_is_troop ~= b_is_troop then return b_is_troop end

   local terms = {"level", "iLevel", "classSpec", "troop_uniq", "is_busy_for_mission", "durability", "followerID"}
   for _, term in ipairs(terms) do
      local a_val = a[term] or (term == "classSpec" and 999999 or term == "troop_uniq" and "" or 0)
      local b_val = b[term] or (term == "classSpec" and 999999 or term == "troop_uniq" and "" or 0)
      if a_val ~= b_val then
         return term == "is_busy_for_mission" and a_val or a_val > b_val
      end
   end
end

local follower_cache = {}
local function UpdateFollowerCache(type_id)
   if not filtered_followers_dirty then return end
   local followers = GetFollowers(type_id)
   if not followers then return end

   local container = filtered_followers[type_id]
   wipe(container)
   local count, free = 0, 0
   local free_non_troop, all_maxed = false, true

   for idx = 1, #followers do
      local follower = followers[idx]
      if follower.isCollected and not ignored_followers[follower.followerID] then
         count = count + 1
         container[count] = follower

         if follower.status and follower.status ~= GARRISON_FOLLOWER_IN_PARTY then
            follower.is_busy_for_mission = true
         else
            if follower.levelXP ~= 0 then all_maxed = false end
            free = free + 1
            free_non_troop = free_non_troop or not follower.isTroop
         end

         if follower.isTroop then
            local abilities = GetFollowerAbilities(follower.followerID)
            for i = 1, #abilities do abilities[i] = abilities[i].id end
            tsort(abilities)
            follower.troop_uniq = follower.classSpec .. ',' .. concat(abilities, ',')
            if GMM_OLDSKIP then follower.troop_uniq = follower.classSpec end
         end
      end
   end

   container.count = count
   container.free = free
   container.free_non_troop = free_non_troop
   container.all_maxed = all_maxed
   container.type = type_id
   tsort(container, SortFollowers)
   filtered_followers_dirty = false
end

function addon_env.GetFilteredFollowers(type_id)
   UpdateFollowerCache(type_id)
   return filtered_followers[type_id]
end

addon_env.HideGameTooltip = GameTooltip_Hide or function() return GameTooltip:Hide() end
addon_env.OnShowEmulateDisabled = function(self) self:GetScript("OnDisable")(self) end
addon_env.OnEnterShowGameTooltip = function(self) GameTooltip:SetOwner(self, "ANCHOR_RIGHT") GameTooltip:SetText(self.tooltip, nil, nil, nil, nil, true) end

gmm_buttons.StartMission = MissionPage.StartMissionButton

function GMM_Click(button_name)
   local button = gmm_buttons[button_name]
   if button and button:IsVisible() then button:Click() end
end