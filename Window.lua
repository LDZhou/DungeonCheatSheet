local addonName, addon = ...

local mainWindow = CreateFrame("Frame", "DungeonCheatsheetWindow", UIParent)
mainWindow:SetSize(300, 400)
mainWindow:SetPoint("RIGHT", -150, 0)
mainWindow:SetMovable(true)
mainWindow:EnableMouse(true)
mainWindow:RegisterForDrag("LeftButton")
mainWindow:SetScript("OnDragStart", mainWindow.StartMoving)
-- 当拖拽结束时，不仅停止移动，还要把新坐标存进数据库
mainWindow:SetScript("OnDragStop", function(self)
    self:StopMovingOrSizing()
    if addon.db then
        local point, _, _, xOfs, yOfs = self:GetPoint()
        addon.db.profile.settings.windowPoint = point
        addon.db.profile.settings.windowX = xOfs
        addon.db.profile.settings.windowY = yOfs
    end
end)
mainWindow:SetResizable(true)
mainWindow:SetResizeBounds(150, 50, 600, 800)

mainWindow.bg = mainWindow:CreateTexture(nil, "BACKGROUND")
mainWindow.bg:SetAllPoints(true)
mainWindow:Hide()

local titleText = mainWindow:CreateFontString(nil, "OVERLAY", "GameFontHighlightLarge")
titleText:SetPoint("TOP", 0, -10)

local targetFrames = {}

-- ==========================================
-- 右下角缩放手柄 (仅在非锁定时显示)
-- ==========================================
local resizeHandle = CreateFrame("Button", nil, mainWindow)
resizeHandle:SetSize(16, 16)
resizeHandle:SetPoint("BOTTOMRIGHT", 0, 0)
resizeHandle:SetNormalTexture("Interface\\ChatFrame\\UI-ChatIM-SizeGrabber-Up")
resizeHandle:SetHighlightTexture("Interface\\ChatFrame\\UI-ChatIM-SizeGrabber-Highlight")
resizeHandle:SetPushedTexture("Interface\\ChatFrame\\UI-ChatIM-SizeGrabber-Down")
resizeHandle:EnableMouse(true)

resizeHandle:SetScript("OnMouseDown", function(self, button)
    if button == "LeftButton" then
        mainWindow:StartSizing("BOTTOMRIGHT")
    end
end)

resizeHandle:SetScript("OnMouseUp", function(self, button)
    mainWindow:StopMovingOrSizing()
    -- 保存宽度到数据库
    if addon.db then
        addon.db.profile.settings.windowWidth = math.floor(mainWindow:GetWidth())
    end
end)

-- ==========================================
-- 锁定按钮 (紧贴缩放手柄左侧，悬停时才显示)
-- ==========================================
local lockBtn = CreateFrame("Button", nil, mainWindow)
lockBtn:SetSize(16, 16)
lockBtn:SetPoint("BOTTOMRIGHT", mainWindow, "BOTTOMRIGHT", -18, 1)
lockBtn:Hide()
lockBtn:EnableMouse(true)

-- 使用 WoW 内置的 LFG 锁图标纹理
local lockTex = lockBtn:CreateTexture(nil, "ARTWORK")
lockTex:SetAllPoints()
lockBtn.icon = lockTex

-- 高亮效果：鼠标移到锁按钮上时稍微变亮
lockBtn:SetScript("OnEnter", function(self)
    self.icon:SetAlpha(1.0)
end)
lockBtn:SetScript("OnLeave", function(self)
    self.icon:SetAlpha(0.75)
end)

-- 点击切换锁定状态
lockBtn:SetScript("OnClick", function()
    if not addon.db then return end
    addon.db.profile.settings.locked = not addon.db.profile.settings.locked
    addon:UpdateWindowLock()
    -- 通知 AceConfig 刷新设置面板 UI
    local AceConfigRegistry = LibStub("AceConfigRegistry-3.0", true)
    if AceConfigRegistry then
        AceConfigRegistry:NotifyChange("DungeonCheatsheet")
    end
    -- 聊天框提示
    local L = addon.L
    if addon.db.profile.settings.locked then
        print("|cff00ff00[DungeonCheatsheet]|r " .. L["Window is now LOCKED."])
    else
        print("|cffffaa00[DungeonCheatsheet]|r " .. L["Window is now UNLOCKED."])
    end
end)

local function UpdateLockVisual()
    if not addon.db then return end
    local isLocked = addon.db.profile.settings.locked
    if isLocked then
        -- 锁定状态：金色锁图标
        lockTex:SetTexture("Interface\\LFGFRAME\\UI-LFG-ICON-LOCK")
        lockTex:SetVertexColor(1, 0.8, 0, 1)
        lockTex:SetDesaturated(false)
        resizeHandle:Hide()
    else
        -- 解锁状态：绿色半透明锁图标
        lockTex:SetTexture("Interface\\LFGFRAME\\UI-LFG-ICON-LOCK")
        lockTex:SetVertexColor(0.5, 1, 0.5, 1)
        lockTex:SetDesaturated(true)
        resizeHandle:Show()
    end
    lockTex:SetAlpha(0.75)
end

-- ==========================================
-- 鼠标悬停检测：只在鼠标在窗口范围内时显示锁按钮
-- 使用 OnUpdate 轮询 IsMouseOver，兼容子控件遮挡
-- ==========================================
local hoverWatcher = CreateFrame("Frame", nil, mainWindow)
hoverWatcher:Hide()

hoverWatcher:SetScript("OnUpdate", function(self, elapsed)
    self.timer = (self.timer or 0) + elapsed
    if self.timer < 0.1 then return end
    self.timer = 0

    if mainWindow:IsShown() and mainWindow:IsMouseOver() then
        if not lockBtn:IsShown() then
            UpdateLockVisual()
            lockBtn:Show()
        end
    else
        if lockBtn:IsShown() and not lockBtn:IsMouseOver() then
            lockBtn:Hide()
        end
    end
end)

mainWindow:HookScript("OnShow", function() hoverWatcher:Show() end)
mainWindow:HookScript("OnHide", function() hoverWatcher:Hide() end)



-- ==========================================
-- 核心排版函数
-- ==========================================
local function UpdateLayout()
    local currentY = -40
    local db = addon.db.profile.settings
    local windowWidth = mainWindow:GetWidth()
    
    mainWindow.bg:SetColorTexture(db.bgR, db.bgG, db.bgB, db.bgA)
    titleText:SetWidth(windowWidth - 20)

    for i, frame in ipairs(targetFrames) do
        -- 【关键修复】使用 inUse 代替 IsShown() 判断
        if frame.inUse then
            frame:Show()
            frame:ClearAllPoints()
            frame:SetPoint("TOPLEFT", 10, currentY)
            frame:SetWidth(windowWidth - 20)
            
            frame.titleBtn:GetFontString():SetFont(db.font, db.fontSize + 2, "OUTLINE")
            frame.noteText:SetFont(db.font, db.fontSize, "NONE")
            frame.noteText:SetWidth(windowWidth - 40)
            
            -- 【黑科技】强制重新填入文本，迫使引擎基于最新宽度立即计算换行高度
            frame.noteText:SetText(frame.targetData.note)

            if frame.isExpanded then
                frame:SetAlpha(1.0)
                
                -- 判断是否启用了发送到聊天频道
                if db.enableChatSend then
                    frame.speakerBtn:Show()
                    frame.speakerBtn:ClearAllPoints()
                    frame.speakerBtn:SetPoint("TOPLEFT", frame.titleBtn, "BOTTOMLEFT", 10, -5)
                    
                    frame.noteText:ClearAllPoints()
                    -- 文本靠右侧挪出 20 像素的距离给小喇叭
                    frame.noteText:SetPoint("TOPLEFT", frame.speakerBtn, "TOPRIGHT", 4, 0)
                    frame.noteText:SetPoint("TOPRIGHT", frame.titleBtn, "BOTTOMRIGHT", -10, -5)
                    frame.noteText:SetWidth(windowWidth - 40 - 20)
                else
                    frame.speakerBtn:Hide()
                    frame.noteText:ClearAllPoints()
                    frame.noteText:SetPoint("TOPLEFT", frame.titleBtn, "BOTTOMLEFT", 10, -5)
                    frame.noteText:SetPoint("TOPRIGHT", frame.titleBtn, "BOTTOMRIGHT", -10, -5)
                    frame.noteText:SetWidth(windowWidth - 40)
                end

                frame.noteText:Show()
                
                -- 黑科技强制重排版...
                frame.noteText:SetText(frame.targetData.note)
                
                local textHeight = frame.noteText:GetStringHeight()
                -- 兜底保险...
                if textHeight == 0 and frame.targetData.note and frame.targetData.note ~= "" then
                    textHeight = db.fontSize * 2
                end
                
                -- 如果文本高度不如小喇叭高，至少保证能包住小喇叭（16像素）
                textHeight = math.max(textHeight, 16)
                
                frame:SetHeight(30 + textHeight + 10)
            else
                frame:SetAlpha(db.collapsedAlpha)
                frame.speakerBtn:Hide()
                frame.noteText:Hide()
                frame:SetHeight(30)
            end
            currentY = currentY - frame:GetHeight() - 5
        else
            frame:Hide()
        end
    end
    mainWindow:SetHeight(math.abs(currentY) + 10)
end

-- ==========================================
-- 窗口大小改变时重新排版 (拖拽缩放时实时自适应)
-- ==========================================
mainWindow:SetScript("OnSizeChanged", function(self, width, height)
    -- 只有宽度发生变化时才重新排版（避免 SetHeight 导致的无限循环死锁）
    if self.lastWidth ~= width then
        self.lastWidth = width
        -- 延迟一帧，彻底避开引擎渲染时差导致的文本重排版问题
        C_Timer.After(0, function()
            if addon.db and targetFrames[1] and targetFrames[1].inUse then
                UpdateLayout() -- 直接复用主排版函数，不再写两遍逻辑
            end
        end)
    end
end)

function addon:ShowWindow(instanceData)
    -- 从数据库恢复窗口宽度
    if addon.db and addon.db.profile.settings.windowWidth then
        mainWindow:SetWidth(addon.db.profile.settings.windowWidth)
    end

    -- 【新增】从数据库恢复窗口位置
    if addon.db and addon.db.profile.settings.windowPoint then
        mainWindow:ClearAllPoints()
        mainWindow:SetPoint(
            addon.db.profile.settings.windowPoint, 
            addon.db.profile.settings.windowX, 
            addon.db.profile.settings.windowY
        )
    end

    titleText:SetText(addon:GetInstDisplayName(instanceData))
    
    -- 【关键修复】重置在用状态
    for _, f in ipairs(targetFrames) do f.inUse = false end
    
    if instanceData.targets then
        for i, target in ipairs(instanceData.targets) do
            local frame = targetFrames[i]
            if not frame then
                frame = CreateFrame("Frame", nil, mainWindow)
                
                local btn = CreateFrame("Button", nil, frame)
                btn:SetPoint("TOPLEFT", 0, 0)
                btn:SetPoint("TOPRIGHT", 0, 0)
                btn:SetHeight(30)
                
                btn:SetNormalFontObject("GameFontNormal")
                btn:SetText(" ")
                btn:GetFontString():SetPoint("LEFT", 5, 0)
                
                frame.titleBtn = btn

                -- 新增：小喇叭发送按钮
                local speakerBtn = CreateFrame("Button", nil, frame)
                speakerBtn:SetSize(16, 16)
                -- 使用暴雪自带的聊天气泡图标
                speakerBtn:SetNormalTexture("Interface\\ChatFrame\\UI-ChatIcon-Chat-Up")
                speakerBtn:SetPushedTexture("Interface\\ChatFrame\\UI-ChatIcon-Chat-Down")
                speakerBtn:SetHighlightTexture("Interface\\Buttons\\UI-Common-MouseHilight", "ADD")
                
                speakerBtn:SetScript("OnClick", function()
                    local text = frame.targetData.note or ""
                    if text == "" then return end
                    
                    if InCombatLockdown() then
                        print("|cffff0000[DungeonCheatsheet]|r " .. (addon.L["Cannot send message during combat."] or "战斗中无法发送消息。"))
                        return
                    end
                    
                    text = string.gsub(text, "|", "｜")
                    text = string.gsub(text, "\r\n", "\n")
                    text = string.gsub(text, "\n", " ｜ ")
                    
                    local channel = addon.db.profile.settings.chatChannel or "PARTY"
                    local ok, err = pcall(SendChatMessage, "[攻略] " .. text, channel)
                    if not ok then
                        print("|cffff0000[DungeonCheatsheet]|r " .. (addon.L["Failed to send message: "] or "发送失败：") .. tostring(err))
                    end
                end)
                frame.speakerBtn = speakerBtn

                -- 调整原本的文本框
                local note = frame:CreateFontString(nil, "OVERLAY", "GameFontHighlight")
                note:SetJustifyH("LEFT")
                note:SetWordWrap(true)
                frame.noteText = note
                
                targetFrames[i] = frame
            end
            
            frame.targetData = target 
            frame.inUse = true -- 【标记该框体正在被使用】
            frame.isExpanded = (i == 1)
            
            frame.titleBtn:SetScript("OnClick", function()
                if addon.db.profile.settings.singleExpand then
                    local wasExpanded = frame.isExpanded
                    for _, f in ipairs(targetFrames) do f.isExpanded = false end
                    frame.isExpanded = not wasExpanded
                else
                    frame.isExpanded = not frame.isExpanded
                end
                UpdateLayout()
            end)
            
            frame.titleBtn:SetText("> " .. target.name)
        end
    end
    
    -- 【核心修复】必须先显示主窗口，再进行排版，确保坐标能正常锚定！
    mainWindow:Show()
    UpdateLayout()
    UpdateLockVisual()
end

function addon:HideWindow()
    mainWindow:Hide()
end

-- ==========================================
-- 智能匹配并展开目标 (支持名字模糊匹配和首领战ID精准匹配)
-- ==========================================
function addon:SmartExpandTarget(unitName, encounterId)
    if not mainWindow:IsShown() or not unitName then return end
    
    local safeName = unitName and strlower(unitName) or ""
    if safeName == "" then return end

    
    for i, frame in ipairs(targetFrames) do
        if frame:IsShown() and frame.targetData then
            local tData = frame.targetData
            local matchFound = false
            
            if tData.encounterId and tData.encounterId ~= "" and encounterId and tData.encounterId == tostring(encounterId) then
                matchFound = true
            elseif tData.name and tData.name ~= "" then
                local n1 = strlower(tData.name)
                if string.find(n1, safeName, 1, true) or string.find(safeName, n1, 1, true) then
                    matchFound = true
                end
            end
            
            if matchFound then
                if addon.db.profile.settings.singleExpand then
                    if not frame.isExpanded then
                        for _, f in ipairs(targetFrames) do f.isExpanded = false end
                        frame.isExpanded = true
                        UpdateLayout()
                    end
                else
                    if not frame.isExpanded then
                        frame.isExpanded = true
                        UpdateLayout()
                    end
                end
                break
            end
        end
    end
end

-- ==========================================
-- 窗口锁定控制
-- ==========================================
function addon:UpdateWindowLock()
    local isLocked = addon.db.profile.settings.locked
    mainWindow:SetMovable(not isLocked)
    mainWindow:SetResizable(not isLocked)
    UpdateLockVisual()
end