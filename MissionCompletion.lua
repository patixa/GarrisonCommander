local me, ns = ...
local addon=ns.addon --#addon
local L=ns.L
local D=ns.D
local C=ns.C
local AceGUI=ns.AceGUI
local _G=_G
--@debug@
--if LibDebug() then LibDebug() end
--@end-debug@
local xprint=ns.xprint
local new, del, copy =ns.new,ns.del,ns.copy
local GMF=GarrisonMissionFrame
local GMFMissions=GarrisonMissionFrameMissions
local G=C_Garrison
local GARRISON_CURRENCY=GARRISON_CURRENCY
ns.missionautocompleting=false
local pairs=pairs
local format=format
local strsplit=strsplit
local generated
local salvages={
114120,114119,114116}
local module=addon:NewSubClass('MissionCompletion') --#Module
function module:GenerateMissionCompleteList(title)
	local w=AceGUI:Create("GCMCList")
	w:SetTitle(title)
	w:SetCallback("OnClose", function(self) self:Release() ns.missionautocompleting=nil end)
	return w
end
local missions={}
local states={}
local currentMission
local rewards={
	items={},
	followerBase={},
	followerXP=setmetatable({},{__index=function() return 0 end}),
	currencies=setmetatable({},{__index=function(t,k) rawset(t,k,{icon="",qt=0}) return t[k] end}),
}
local scroller
local report
local timer
local function stopTimer()
	if (timer) then
		module:CancelTimer(timer)
		timer=nil
	end
end
local function startTimer(delay,event,...)
	delay=delay or 0.2
	event=event or "LOOP"
	stopTimer()
	timer=module:ScheduleRepeatingTimer("MissionAutoComplete",delay,event,...)
	--@alpha@
	addon:Dprint("Timer rearmed for",event,delay)
	--@end-alpha@
end
function module:MissionsCleanup()
	stopTimer()
	GMF.MissionTab.MissionList.CompleteDialog:Hide()
	GMF.MissionComplete:Hide()
	GMF.MissionCompleteBackground:Hide()
	GMF.MissionComplete.currentIndex = nil
	GMF.MissionTab:Show()
	GarrisonMissionList_UpdateMissions()
	-- Re-enable "view" button
	GMFMissions.CompleteDialog.BorderFrame.ViewButton:SetEnabled(true)
	ns.missionautocompleting=nil
	GarrisonMissionFrame_SelectTab(1)
	GarrisonMissionFrame_CheckCompleteMissions()
end
function module:OnInitialized(start)
	self:RegisterEvent("GARRISON_MISSION_BONUS_ROLL_LOOT","MissionAutoComplete")
	self:RegisterEvent("GARRISON_MISSION_BONUS_ROLL_COMPLETE","MissionAutoComplete")
	self:RegisterEvent("GARRISON_MISSION_COMPLETE_RESPONSE","MissionAutoComplete")
	self:RegisterEvent("GARRISON_FOLLOWER_XP_CHANGED","MissionAutoComplete")
end
function module:CloseReport()
	if report then pcall(report.Close,report) end
end
function module:MissionComplete(this,button)
	GMFMissions.CompleteDialog.BorderFrame.ViewButton:SetEnabled(false) -- Disabling standard Blizzard Completion
	missions=G.GetCompleteMissions()
	if (missions and #missions > 0) then
		ns.missionautocompleting=true
		report=self:GenerateMissionCompleteList("Missions' results")
		--report:SetPoint("TOPLEFT",GMFMissions.CompleteDialog.BorderFrame)
		--report:SetPoint("BOTTOMRIGHT",GMFMissions.CompleteDialog.BorderFrame)
		report:SetParent(GMF)
		report:SetPoint("TOP",GMF)
		report:SetPoint("BOTTOM",GMF)
		report:SetWidth(500)
		report:SetCallback("OnClose",function() return module:MissionsCleanup() end)
		wipe(rewards.followerBase)
		wipe(rewards.followerXP)
		wipe(rewards.currencies)
		wipe(rewards.items)
		for i=1,#missions do
			for k,v in pairs(missions[i].followers) do
				rewards.followerBase[v]=self:GetFollowerData(v,'qLevel')
			end
			local m=missions[i]
			local _
			_,_,_,m.successChance,_,_,m.xpBonus,m.resourceMultiplier,m.goldMultiplier=G.GetPartyMissionInfo(m.missionID)
		end
		currentMission=tremove(missions)
		ns.CompletedMissions[currentMission.missionID]=currentMission
		self:MissionAutoComplete("INIT")
	end
end
function module:MissionAutoComplete(event,ID,arg1,arg2,arg3,arg4)
-- C_Garrison.MarkMissionComplete Mark mission as complete and prepare it for bonus roll, da chiamare solo in caso di successo
-- C_Garrison.MissionBonusRoll
--@alpha@
	self:Dprint("evt",event,ID,arg1 or'',arg2 or '',arg3 or '')
--@end-alpha@
	if event=="LOOT" then
		return self:MissionsPrintResults()
	end

	if (event =="LOOP" or event=="INIT") then
		ID=currentMission and currentMission.missionID or "none"
		arg1=currentMission and currentMission.state or "none"
	end
	-- GARRISON_FOLLOWER_XP_CHANGED: followerID, xpGained, actualXp, newLevel, quality
	if (event=="GARRISON_FOLLOWER_XP_CHANGED") then
		if (arg1 > 0) then
			--report:AddFollower(ID,arg1,arg2)
			rewards.followerXP[ID]=rewards.followerXP[ID]+tonumber(arg1) or 0
		end
		return
	-- GARRISON_MISSION_BONUS_ROLL_LOOT: itemID
	elseif (event=="GARRISON_MISSION_BONUS_ROLL_LOOT") then
		if (currentMission) then
			rewards.items[format("%d:%s",currentMission.missionID,ID)]=1
		else
			rewards.items[format("%d:%s",0,ID)]=1
		end
		return
	-- GARRISON_MISSION_COMPLETE_RESPONSE: missionID, requestCompleted, succeeded
	elseif (event=="GARRISON_MISSION_COMPLETE_RESPONSE") then
		if (not arg1) then
			-- We need to call server again
			currentMission.state=0
		elseif (arg2) then -- success, we need to roll
			currentMission.state=1
		else -- failure, just print results
			currentMission.state=2
		end
		startTimer(0.1)
		return
	-- GARRISON_MISSION_BONUS_ROLL_COMPLETE: missionID, requestCompleted; happens after C_Garrison.MissionBonusRoll
	elseif (event=="GARRISON_MISSION_BONUS_ROLL_COMPLETE") then
		if (not arg1) then
			-- We need to call server again
			currentMission.state=1
		else
			currentMission.state=3
		end
		startTimer(0.1)
		return
	else -- event == LOOP
		if (currentMission) then
			local step=currentMission.state or -1
			if (step<1) then
				step=0
				currentMission.state=0
				currentMission.goldMultiplier=currentMission.goldMultiplier or 1
				currentMission.xp=select(2,G.GetMissionInfo(currentMission.missionID))
				report:AddMissionButton(currentMission)
			end
			if (step==0) then
				--@alpha@
				self:Dprint("Fired mission complete for",currentMission.missionID)
				--@end-alpha@
				G.MarkMissionComplete(currentMission.missionID)
				startTimer(2)
			elseif (step==1) then
				--@alpha@
				self:Dprint("Fired bonus roll complete for",currentMission.missionID)
				--@end-alpha@
				G.MissionBonusRoll(currentMission.missionID)
				startTimer(2)
			elseif (step>=2) then
				self:GetMissionResults(step==3)
				self:RefreshFollowerStatus()
				currentMission=tremove(missions)
				if currentMission then
					ns.CompletedMissions[currentMission.missionID]=currentMission
				end
				startTimer()
				return
			end
			currentMission.state=step
		else
			report:AddButton(L["Building Final report"],function() addon:MissionsPrintResult() end)
			startTimer(1,"LOOT")
		end
	end
end
function module:GetMissionResults(success)
	stopTimer()
	if (success) then
		report:AddMissionResult(currentMission.missionID,true)
		PlaySound("UI_Garrison_Mission_Complete_Mission_Success")
	else
		report:AddMissionResult(currentMission.missionID,false)
		PlaySound("UI_Garrison_Mission_Complete_Encounter_Fail")
	end
	if success then
		local resourceMultiplier=currentMission.resourceMultiplier or 1
		local goldMultiplier=currentMission.goldMultiplier or 1
		for k,v in pairs(currentMission.rewards) do
			v.quantity=v.quantity or 0
			if v.currencyID then
				rewards.currencies[v.currencyID].icon=v.icon
				if v.currencyID == 0 then
					rewards.currencies[v.currencyID].qt=rewards.currencies[v.currencyID].qt+v.quantity * goldMultiplier
				elseif v.currencyID == GARRISON_CURRENCY then
					rewards.currencies[v.currencyID].qt=rewards.currencies[v.currencyID].qt+v.quantity * resourceMultiplier
				else
					rewards.currencies[v.currencyID].qt=rewards.currencies[v.currencyID].qt+v.quantity
				end
			elseif v.itemID then
				GetItemInfo(v.itemID) -- Triggering the cache
				rewards.items[format("%d:%s",currentMission.missionID,v.itemID)]=1
			end
		end
	end
end
function module:MissionsPrintResults(success)
	stopTimer()
	self:FollowerCacheInit()
--@debug@
	--self:Dump("Ended Mission",rewards)
--@end-debug@
	for k,v in pairs(rewards.currencies) do
		if k == 0 then
			-- Money reward
			report:AddIconText(v.icon,GetMoneyString(v.qt))
		elseif k == GARRISON_CURRENCY then
			-- Garrison currency reward
			report:AddIconText(v.icon,GetCurrencyLink(k),v.qt)
		else
			-- Other currency reward
			report:AddIconText(v.icon,GetCurrencyLink(k),v.qt)
		end
	end
	local items=new()
	for k,v in pairs(rewards.items) do
		local missionid,itemid=strsplit(":",k)
		if (not items[itemid]) then
			items[itemid]=1
		else
			items[itemid]=items[itemid]+1
		end
	end
	for itemid,qt in pairs(items) do
		report:AddItem(itemid,qt)
	end
	del(items)
	for k,v in pairs(rewards.followerXP) do
		report:AddFollower(k,v,self:GetFollowerData(k,'qLevel') > rewards.followerBase[k])
	end
end
