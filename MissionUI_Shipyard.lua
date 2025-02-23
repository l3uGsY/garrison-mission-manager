local function GarrisonShipyardMap_UpdateMissions_More()
   local self = GarrisonShipyardFrame.MissionTab.MissionList
   if not self:IsVisible() then return end

   local missions = self.missions
   local mission_frames = self.missionFrames

   if addon_env.top_for_mission_dirty then
      wipe(top_for_mission)
      addon_env.top_for_mission_dirty = false
   end

   local filtered_followers = addon_env.GetFilteredFollowers(Enum_GarrisonFollowerType_FollowerType_6_0_Boat)
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
               gmm_button = addon_env.CreateButton('ShipyardMissionList' .. i, frame, i, 80, 40, "TOP", frame, "BOTTOM", 0, 10, false)
               gmm_button:SetScript("OnClick", ShipyardMissionList_PartyButtonOnClick)
            end

            frame.offerSecondsRemaining = mission.offerEndTime and mission.offerEndTime - GetTime()
            frame.OfferTime:SetText(frame.offerSecondsRemaining and SecondsToTime(frame.offerSecondsRemaining))

            local cant_complete = mission.cost > oil or mission.numFollowers > filtered_followers.free
            if cant_complete then
               frame:SetAlpha(0.3)
               gmm_button:SetText()
            else
               more_missions_to_cache = addon_env.UpdateMissionListButton(mission, filtered_followers, frame, gmm_button, more_missions_to_cache, oil)
            end
            gmm_button:Show()
            frame:Show()
         end
      end
   end

   if more_missions_to_cache and more_missions_to_cache > 0 then
      After(0.001, GarrisonShipyardMap_UpdateMissions_More)
   end
end
hooksecurefunc("GarrisonShipyardMap_UpdateMissions", GarrisonShipyardMap_UpdateMissions_More)