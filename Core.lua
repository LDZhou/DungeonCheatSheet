local addonName, addon = ...
addon.frame = CreateFrame("Frame")
local AceDB = LibStub("AceDB-3.0")

local defaultDB = {
    profile = {
        settings = {
            fontSize = 14,
            font = STANDARD_TEXT_FONT,
            collapsedAlpha = 0.5,
            bgR = 0, bgG = 0, bgB = 0, bgA = 0.6,
            smartExpand = true,
            singleExpand = true,
            locked = false,
            windowWidth = 300
        },
        categories = {}  -- 新结构：{ { name="分类名", instances={...} }, ... }
    }
}

addon.frame:RegisterEvent("ADDON_LOADED")
addon.frame:RegisterEvent("PLAYER_ENTERING_WORLD")
addon.frame:RegisterEvent("ZONE_CHANGED_NEW_AREA")
addon.frame:RegisterEvent("PLAYER_TARGET_CHANGED")
addon.frame:RegisterEvent("ENCOUNTER_START")

addon.frame:SetScript("OnEvent", function(self, event, arg1, arg2)
    if event == "ADDON_LOADED" and arg1 == addonName then
        addon.db = AceDB:New("DungeonCheatsheetDB", defaultDB, true)

        -- ========== 旧数据迁移：instances[] -> categories[].instances[] ==========
        local L = addon.L
        if addon.db.profile.instances and #addon.db.profile.instances > 0 then
            -- 旧版有 instances 数据，迁移到第一个分类
            if not addon.db.profile.categories or #addon.db.profile.categories == 0 then
                addon.db.profile.categories = {}
            end
            -- 创建"默认"分类，把旧副本全部放进去
            table.insert(addon.db.profile.categories, 1, {
                name = L["Default"],
                instances = addon.db.profile.instances
            })
            addon.db.profile.instances = nil
        end
        -- 如果迁移后/全新安装后没有任何分类，创建一个空的默认分类
        if not addon.db.profile.categories or #addon.db.profile.categories == 0 then
            addon.db.profile.categories = { { name = L["Default"], instances = {} } }
        end

        addon.db.RegisterCallback(addon, "OnProfileChanged", "RefreshConfig")
        addon.db.RegisterCallback(addon, "OnProfileCopied", "RefreshConfig")
        addon.db.RegisterCallback(addon, "OnProfileReset", "RefreshConfig")

    elseif event == "PLAYER_ENTERING_WORLD" or event == "ZONE_CHANGED_NEW_AREA" then
        addon:CheckInstance()
        if event == "PLAYER_ENTERING_WORLD" then
            addon:UpdateWindowLock()
        end
    elseif event == "PLAYER_TARGET_CHANGED" then
        if addon.db.profile.settings.smartExpand and UnitExists("target") then
            addon:SmartExpandTarget(UnitName("target"))
        end
    elseif event == "ENCOUNTER_START" then
        local encounterID = arg1
        local encounterName = arg2
        if addon.db.profile.settings.smartExpand and encounterName then
            addon:SmartExpandTarget(encounterName, tostring(encounterID))
        end
    end
end)

function addon:RefreshConfig()
    addon:CheckInstance()
    addon:UpdateWindowLock()
    if addon.editorFrame and addon.editorFrame:IsShown() then
        addon.editorFrame:RefreshTree("new_cat")
    end
end

-- ========== 副本显示名（带难度后缀） ==========
function addon:GetInstDisplayName(inst)
    local name = (inst.name and inst.name ~= "") and inst.name or addon.L["Unnamed Dungeon"]
    if inst.difficulty and inst.difficulty ~= "" then
        return name .. "(" .. inst.difficulty .. ")"
    end
    return name
end

-- ========== 遍历所有分类下的所有副本来匹配当前区域 ==========
function addon:CheckInstance()
    local name, _, difficultyID, _, _, _, _, id = GetInstanceInfo()
    local matchedInstance = nil

    if id or name then
        for _, cat in ipairs(addon.db.profile.categories) do
            for _, inst in ipairs(cat.instances or {}) do
                -- 先匹配副本名/副本ID
                local nameOrIdMatch = false
                if (inst.id and inst.id ~= "" and tostring(id) == inst.id) or 
                   (inst.name and inst.name ~= "" and name == inst.name) then
                    nameOrIdMatch = true
                end
                
                if nameOrIdMatch and inst.isActive ~= false then
                    -- 再匹配难度：如果副本设置了难度ID，必须一致才算匹配
                    if inst.difficultyId and inst.difficultyId ~= "" then
                        if tostring(difficultyID) == inst.difficultyId then
                            matchedInstance = inst
                        end
                        -- 难度不匹配时不选中，继续找下一个
                    else
                        -- 没填难度ID：任何难度都匹配
                        matchedInstance = inst
                    end
                end
                if matchedInstance then break end
            end
            if matchedInstance then break end
        end
    end

    if matchedInstance then
        addon:ShowWindow(matchedInstance)
    else
        addon:HideWindow()
    end
end