local addon_name, addon_env = ...
if not addon_env.load_this then return end

-- Confused about mix of CamelCase and_underscores?
-- Camel case comes from copypasta of how Blizzard calls returns/fields in their code and deriveates
-- Underscore are my own variables

-- [AUTOLOCAL START]
local After = C_Timer.After
local Enum_GarrisonFollowerType_FollowerType_6_0_Boat = Enum.GarrisonFollowerType.FollowerType_6_0_Boat
local GARRISON_SHIP_OIL_CURRENCY = GARRISON_SHIP_OIL_CURRENCY
local GetCurrencyInfo = C_CurrencyInfo.GetCurrencyInfo
local GetFollowerSoftCap = C_Garrison.GetFollowerSoftCap
local GetItemInfoInstant = C_Item.GetItemInfoInstant
local GetNumActiveFollowers = C_Garrison.GetNumActiveFollowers
local UnitGUID = UnitGUID
local match = string.match
local pairs = pairs
local print = print
local tinsert = table.insert
local tsort = table.sort
local wipe = wipe
-- [AUTOLOCAL END]

local Widget = addon_env.Widget
local gmm_buttons = addon_env.gmm_buttons
local top_for_mission = addon_env.top_for_mission
local GetFilteredFollowers = addon_env.GetFilteredFollowers
local UpdateMissionListButton = addon_env.UpdateMissionListButton

local MissionPage = GarrisonShipyardFrame.MissionTab.MissionPage

local function ShipyardMissionList_PartyButtonOnClick(self)
   if addon_env.RegisterManualInterraction then addon_env.RegisterManualInterraction() end
   addon_env.mission_page_pending_click = "ShipyardMissionPage1"
   return self:GetParent():Click()
end

local shipyard_mission_list_gmm_button_template = {
   "Button", nil, "UIPanelButtonTemplate",
   Width = 80, Height = 40, FrameLevelOffset = 3, Scale = 0.60,
   OnClick = ShipyardMissionList_PartyButtonOnClick,
}
local shipyard_mission_list_gmm_loot_template = {
   "Button", nil, "UIPanelButtonTemplate",
   Width = 40, Height = 40, FrameLevelOffset = 3, Scale = 0.75,
   OnClick = ShipyardMissionList_PartyButtonOnClick,
   Hide = 1,
}

local loot_frames = {}

local function GarrisonShipyardMap_UpdateMissions_More()
   local self = GarrisonShipyardFrame.MissionTab.MissionList
   if not self:IsVisible() then return end

   local missions = self.missions
   local mission_frames = self.missionFrames

   if addon_env.top_for_mission_dirty then
      wipe(top_for_mission)
      addon_env.top_for_mission_dirty = false
   end

   local filtered_followers = GetFilteredFollowers(Enum_GarrisonFollowerType_FollowerType_6_0_Boat)
   local more_missions_to_cache
   local oil = GetCurrencyInfo(GARRISON_SHIP_OIL_CURRENCY).quantity

   for i = 1, #missions do
      local mission = missions[i]
      local frame = mission_frames[i]
      if frame then
         if mission.offeredGarrMissionTextureID ~= 0 and not mission.inProgress and not mission.canStart then
            frame:Hide()
         else
            local gmm_button = gmm_buttons['ShipyardMissionList' .. i]
            if not gmm_button then
               gmm_button = CreateButton('ShipyardMissionList' .. i, frame, i, 80, 40, "TOP", frame, "BOTTOM", 0, 10, false)
               gmm_button:SetScript("OnClick", ShipyardMissionList_PartyButtonOnClick)
            end
            -- Rest of logic remains similar
         end
      end
   end
end
hooksecurefunc("GarrisonShipyardMap_UpdateMissions", GarrisonShipyardMap_UpdateMissions_More)

   if more_missions_to_cache and more_missions_to_cache > 0 then
      After(0.001, GarrisonShipyardMap_UpdateMissions_More)
   end
end
hooksecurefunc("GarrisonShipyardMap_UpdateMissions", GarrisonShipyardMap_UpdateMissions_More)

local function ShipyardInitUI()
   local prefix = "Shipyard" -- hardcoded, because it is used in OUR frame names and should be static for GMM_Click
   local follower_type = Enum_GarrisonFollowerType_FollowerType_6_0_Boat
   local o = addon_env.InitGMMFollowerOptions({
      follower_type                = follower_type,
      gmm_prefix                   = prefix,
      custom_mission_list          = true
   })

   addon_env.MissionPage_ButtonsInit(follower_type)

   ShipyardInitUI = nil
end
ShipyardInitUI()

local BestForCurrentSelectedMission = addon_env.BestForCurrentSelectedMission
hooksecurefunc(GarrisonShipyardFrame, "ShowMission", function()
   BestForCurrentSelectedMission(Enum_GarrisonFollowerType_FollowerType_6_0_Boat, MissionPage, "ShipyardMissionPage")
end)

gmm_buttons.StartShipyardMission = MissionPage.StartMissionButton

local spec_count = {}
local spec_name = {}
local spec_list = {}
-- GossipFrameSharedMixin => GossipFrameMixin
hooksecurefunc(GossipFrame, "Update", function(...)
   local guid = UnitGUID("npc")
   if not (guid and (match(guid, "^Creature%-0%-%d+%-%d+%-%d+%-94429%-") or match(guid, "^Creature%-0%-%d+%-%d+%-%d+%-95002%-"))) then return end

   local filtered_followers = GetFilteredFollowers(Enum_GarrisonFollowerType_FollowerType_6_0_Boat)
   wipe(spec_count)
   for idx = 1, #filtered_followers do
      local follower = filtered_followers[idx]
      local spec = follower.classSpec
      local prev_count = spec_count[spec] or 0
      spec_count[spec] = prev_count + 1
      spec_name[spec] = follower.className
   end
   wipe(spec_list)
   for spec in pairs(spec_name) do tinsert(spec_list, spec) end
   tsort(spec_list)
   for idx = 1, #spec_list do
      local spec = spec_list[idx]
      print(spec_name[spec] .. ": " .. spec_count[spec])
   end

   local max_followers = GetFollowerSoftCap(Enum_GarrisonFollowerType_FollowerType_6_0_Boat)
   local num_active_followers = GetNumActiveFollowers(Enum_GarrisonFollowerType_FollowerType_6_0_Boat)
   print(GARRISON_FLEET .. ": " .. num_active_followers .. "/" .. max_followers)
end)
