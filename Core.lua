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
            windowWidth = 300,
            windowPoint = "RIGHT",
            windowX = -300,
            windowY = 50,
            minimapPos = 225,

            enableChatSend = false,
            chatChannel = "PARTY",
        },
        minimap = {
            hide = false,
            minimapPos = 135,
        },

        categories = {}
    }
}

-- ==========================================
-- 新增：数据结构校验函数，防止配置文件重置时 categories 丢失
-- ==========================================
function addon:ValidateDB()
    local L = addon.L
    if not addon.db.profile.categories then
        addon.db.profile.categories = {}
    end
    if #addon.db.profile.categories == 0 then
        table.insert(addon.db.profile.categories, { name = L["Default"], instances = {} })
    end
end

addon.frame:RegisterEvent("ADDON_LOADED")
addon.frame:RegisterEvent("PLAYER_ENTERING_WORLD")
addon.frame:RegisterEvent("ZONE_CHANGED_NEW_AREA")
addon.frame:RegisterEvent("PLAYER_TARGET_CHANGED")
addon.frame:RegisterEvent("ENCOUNTER_START")


addon.frame:SetScript("OnEvent", function(self, event, arg1, arg2)
    if event == "ADDON_LOADED" and arg1 == addonName then
        addon.db = AceDB:New("DungeonCheatsheetDB", defaultDB, true)

        -- ========== 旧数据迁移 ==========
        local L = addon.L
        if addon.db.profile.instances and #addon.db.profile.instances > 0 then
            addon.db.profile.categories = {}
            table.insert(addon.db.profile.categories, 1, {
                name = L["Default"],
                instances = addon.db.profile.instances
            })
            addon.db.profile.instances = nil
        end
        
        -- 初始化或迁移完成后，统一执行校验补全
        addon:ValidateDB()

        -- =======================================================
        -- 标准小地图按钮 (LibDBIcon) 集中初始化
        -- =======================================================
        local LDB = LibStub("LibDataBroker-1.1", true)
        local icon = LibStub("LibDBIcon-1.0", true)

        if LDB and icon then
            local DungeonCheatsheetLDB = LDB:NewDataObject("DungeonCheatsheet", {
                type = "data source",
                text = "Dungeon Cheatsheet",
                icon = "Interface\\Icons\\INV_Scroll_03",
                OnClick = function(self, button)
                    if button == "LeftButton" then
                        if InCombatLockdown() then
                            print("|cffff0000[DungeonCheatsheet]|r 战斗中无法打开设置面板。")
                        else
                            addon:OpenMainGUI()
                        end
                    end
                end,
                OnTooltipShow = function(tooltip)
                    tooltip:AddLine("Dungeon Cheatsheet")
                    tooltip:AddLine(L["Left-click to open settings"] or "左键点击打开设置", 1, 1, 1)
                end,
            })
            -- 注册按钮，并绑定配置表里的坐标数据
            icon:Register("DungeonCheatsheet", DungeonCheatsheetLDB, addon.db.profile.minimap)
        else
            -- 核心排错：如果没有显示，一定会在聊天框报出这行红字！
            print("|cffff0000[DungeonCheatsheet] 错误：缺少 LibDataBroker 或 LibDBIcon 库文件，小地图按钮加载失败！请检查 Libs 文件夹。|r")
        end
        -- =======================================================

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
    addon:ValidateDB() -- 核心修复：切换/重置配置后，立刻校验补全数据
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

