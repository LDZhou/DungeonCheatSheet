local addonName, addon = ...
local L = addon.L
local AceConfig = LibStub("AceConfig-3.0")
local AceConfigDialog = LibStub("AceConfigDialog-3.0")
local AceDBOptions = LibStub("AceDBOptions-3.0")

local function ApplyAppearanceChange()
    if addon.isTesting then
        local testData = {
            name = L["[Test Window, Please Drag Me]"],
            targets = {
                {name = L["Test Target 1"], note = L["This is a test note.\nYou can drag the window by holding the top title bar."]},
                {name = L["Test Target 2"], note = L["Click to test collapse"]}
            }
        }
        addon:ShowWindow(testData)
    else
        addon:CheckInstance()
    end
end

-- ==========================================
-- 主选项表：用 childGroups = "tab" 自动生成标签页
-- ==========================================
local options = {
    type = "group",
    name = "Dungeon Cheatsheet",
    childGroups = "tab",
    args = {
        -- ===== 第一个标签页：设置 =====
        settings_tab = {
            type = "group",
            name = L["Settings"],
            order = 1,
            args = {
                quick_actions = {
                    type = "group",
                    name = L["Quick Actions"],
                    inline = true,
                    order = 1,
                    args = {
                        open_editor = {
                            type = "execute",
                            name = L["Open Dungeon & Target Editor"],
                            desc = L[" Type /dcs to open this settings page directly."],
                            func = function()
                                AceConfigDialog:Close("DungeonCheatsheet")
                                addon:OpenEditor()
                            end,
                            width = "normal",
                            order = 1,
                        },
                        help_text = {
                            type = "description",
                            name = L[" Type /dcs to open this settings page directly."],
                            width = "normal",
                            order = 2,
                        }
                    }
                },
                behavior = {
                    type = "group",
                    name = L["Behavior & Interaction"],
                    inline = true,
                    order = 2,
                    args = {
                        smart_expand = {
                            type = "toggle",
                            name = L["Enable Smart Expand (Auto-expand notes based on your current target/boss)"],
                            width = "full",
                            get = function() return addon.db.profile.settings.smartExpand end,
                            set = function(info, val) addon.db.profile.settings.smartExpand = val end,
                            order = 1,
                        },
                        lock_window = {
                            type = "toggle",
                            name = L["Lock Window (Prevent dragging)"],
                            width = "full",
                            get = function() return addon.db.profile.settings.locked end,
                            set = function(info, val) 
                                addon.db.profile.settings.locked = val
                                addon:UpdateWindowLock()
                            end,
                            order = 2,
                        }
                    }
                },
                chat_output = {
                    type = "group",
                    name = L["Chat Output"],
                    inline = true,
                    order = 2.5,
                    args = {
                        enable_chat_send = {
                            type = "toggle",
                            name = L["Enable sending guide to chat channel"],
                            width = "full",
                            get = function() return addon.db.profile.settings.enableChatSend end,
                            set = function(info, val)
                                addon.db.profile.settings.enableChatSend = val
                                addon:CheckInstance() -- 刷新窗口以显示/隐藏小喇叭
                            end,
                            order = 1,
                        },
                        chat_channel = {
                            type = "select",
                            name = L["Send to"],
                            values = {
                                ["SAY"] = L["Say"],
                                ["PARTY"] = L["Party"],
                                ["RAID"] = L["Raid"],
                                ["INSTANCE_CHAT"] = L["Instance"],
                            },
                            get = function() return addon.db.profile.settings.chatChannel end,
                            set = function(info, val) addon.db.profile.settings.chatChannel = val end,
                            hidden = function() return not addon.db.profile.settings.enableChatSend end, -- 没打勾时隐藏
                            order = 2,
                        }
                    }
                },
                appearance = {
                    type = "group",
                    name = L["Appearance & Testing"],
                    inline = true,
                    order = 3,
                    args = {
                        font = {
                            type = "select",
                            name = L["Select Font"],
                            values = {
                                [STANDARD_TEXT_FONT] = L["System Default (Quest Font)"],
                                [DAMAGE_TEXT_FONT] = L["Damage Text"],
                                ["Fonts\\ARHei.ttf"] = L["Chat Frame Bold"]
                            },
                            get = function() return addon.db.profile.settings.font end,
                            set = function(info, val) addon.db.profile.settings.font = val; ApplyAppearanceChange() end,
                            order = 1,
                        },
                        fontSize = {
                            type = "range",
                            name = L["Font Size"],
                            min = 10, max = 30, step = 1,
                            get = function() return addon.db.profile.settings.fontSize end,
                            set = function(info, val) addon.db.profile.settings.fontSize = val; ApplyAppearanceChange() end,
                            order = 2,
                        },
                        collapsedAlpha = {
                            type = "range",
                            name = L["Collapsed Alpha"],
                            min = 0.1, max = 1.0, step = 0.05,
                            get = function() return addon.db.profile.settings.collapsedAlpha end,
                            set = function(info, val) addon.db.profile.settings.collapsedAlpha = val; ApplyAppearanceChange() end,
                            order = 3,
                        },
                        bgColor = {
                            type = "color",
                            name = L["Background Color & Alpha"],
                            hasAlpha = true,
                            get = function()
                                local s = addon.db.profile.settings
                                return s.bgR, s.bgG, s.bgB, s.bgA
                            end,
                            set = function(info, r, g, b, a)
                                local s = addon.db.profile.settings
                                s.bgR, s.bgG, s.bgB, s.bgA = r, g, b, a
                                ApplyAppearanceChange()
                            end,
                            order = 4,
                        },
                        singleExpand = {
                            type = "toggle",
                            name = L["Only allow one expanded item at a time"],
                            width = "full",
                            get = function() return addon.db.profile.settings.singleExpand end,
                            set = function(info, val) 
                                addon.db.profile.settings.singleExpand = val 
                                ApplyAppearanceChange() 
                            end,
                            order = 4.5,
                        },
                        test_btn = {
                            type = "execute",
                            name = L["Show Test Window on Screen (For dragging and previewing)"],
                            width = "full",
                            func = function()
                                addon.isTesting = true 
                                ApplyAppearanceChange()
                            end,
                            order = 5,
                        },
                        close_test_btn = {
                            type = "execute",
                            name = L["Close Test Window"],
                            width = "full",
                            func = function() 
                                addon.isTesting = false 
                                addon:CheckInstance() 
                            end,
                            order = 6,
                        },
                        minimap_btn = {
                            type = "toggle",
                            name = L["Show Minimap Button"] or "显示小地图按钮",
                            width = "full",
                            get = function() return not addon.db.profile.minimap.hide end,
                            set = function(info, val)
                                addon.db.profile.minimap.hide = not val
                                if addon.db.profile.minimap.hide then
                                    LibStub("LibDBIcon-1.0"):Hide("DungeonCheatsheet")
                                else
                                    LibStub("LibDBIcon-1.0"):Show("DungeonCheatsheet")
                                end
                            end,
                            order = 7,
                        }
                    }
                }
            }
        },
        -- ===== 第二个标签页：配置文件（在 ADDON_LOADED 中动态插入） =====
    }
}

-- ==========================================
-- ADDON_LOADED：把 Profiles 作为第二个标签页插入选项表，然后注册
-- ==========================================
local eventFrame = CreateFrame("Frame")
eventFrame:RegisterEvent("ADDON_LOADED")
eventFrame:SetScript("OnEvent", function(self, event, arg1)
    if arg1 == addonName then
        -- 将 AceDBOptions 的配置文件表作为第二个标签页
        local profileOptions = AceDBOptions:GetOptionsTable(addon.db)
        profileOptions.order = 2
        options.args.profiles_tab = profileOptions
        profileOptions.args.reset.hidden = true -- 隐藏重置按钮，避免误操作

        AceConfig:RegisterOptionsTable("DungeonCheatsheet", options)
        
        self:UnregisterEvent("ADDON_LOADED")
    end
end)

-- ==========================================
-- 打开主界面：AceConfigDialog 独立窗口（免疫taint）
-- ==========================================
function addon:OpenMainGUI()
    AceConfigDialog:Open("DungeonCheatsheet")
end

-- ==========================================
-- 斜杠命令 /dcs
-- ==========================================
SLASH_DUNGEONCHEATSHEET1 = "/dcs"
SlashCmdList["DUNGEONCHEATSHEET"] = function(msg)
    msg = msg and string.lower(strtrim(msg)) or ""
    
    if msg == "lock" then
        addon.db.profile.settings.locked = not addon.db.profile.settings.locked
        addon:UpdateWindowLock()
        
        LibStub("AceConfigRegistry-3.0"):NotifyChange("DungeonCheatsheet")
        
        if addon.db.profile.settings.locked then
            print("|cff00ff00[DungeonCheatsheet]|r " .. L["Window is now LOCKED."])
        else
            print("|cffffaa00[DungeonCheatsheet]|r " .. L["Window is now UNLOCKED."])
        end
    else
        if InCombatLockdown() then
            print("|cffff0000[DungeonCheatsheet] 战斗中无法打开设置面板。|r")
        else
            addon:OpenMainGUI()
        end
    end
end