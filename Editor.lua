local addonName, addon = ...
local L = addon.L
local AceGUI = LibStub("AceGUI-3.0")

local exportSelections = {}

-- ==========================================
-- 难度选项预设表（两级：先选类型，再选难度）
-- ==========================================
local DIFF_INFO = {
    [""]   = { short = "" },
    ["1"]  = { short = L["Normal"] },
    ["2"]  = { short = L["Heroic"] },
    ["23"] = { short = L["Mythic"] },
    ["8"]  = { short = L["Mythic+"] },
    ["24"] = { short = L["Timewalking"] },
    ["14"] = { short = L["Normal"] },
    ["15"] = { short = L["Heroic"] },
    ["16"] = { short = L["Mythic"] },
    ["17"] = { short = L["LFR"] },
    ["33"] = { short = L["Timewalking"] },
}

local INSTANCE_TYPE_LIST = {
    [""] = L["Any (No Filter)"],
    ["dungeon"] = L["Dungeon"],
    ["raid"] = L["Raid"],
}
local INSTANCE_TYPE_ORDER = {"", "dungeon", "raid"}

local DUNGEON_DIFF_LIST = {
    [""]   = L["Any Difficulty"],
    ["1"]  = L["Normal"],
    ["2"]  = L["Heroic"],
    ["23"] = L["Mythic"],
    ["8"]  = L["Mythic+"],
    ["24"] = L["Timewalking"],
}
local DUNGEON_DIFF_ORDER = {"", "1", "2", "23", "8", "24"}

local RAID_DIFF_LIST = {
    [""]   = L["Any Difficulty"],
    ["17"] = L["LFR"],
    ["14"] = L["Normal"],
    ["15"] = L["Heroic"],
    ["16"] = L["Mythic"],
    ["33"] = L["Timewalking"],
}
local RAID_DIFF_ORDER = {"", "17", "14", "15", "16", "33"}

-- 根据 difficultyId 反推属于哪个类型
local DUNGEON_IDS = {["1"]=true, ["2"]=true, ["23"]=true, ["8"]=true, ["24"]=true}
local RAID_IDS    = {["17"]=true, ["14"]=true, ["15"]=true, ["16"]=true, ["33"]=true}

local function GetInstTypeFromDiffId(diffId)
    if not diffId or diffId == "" then return "" end
    if DUNGEON_IDS[diffId] then return "dungeon" end
    if RAID_IDS[diffId] then return "raid" end
    return ""
end

local function GetDiffShortName(difficultyId)
    local info = DIFF_INFO[difficultyId or ""]
    return info and info.short or ""
end

-- 创建两级难度选择控件，添加到 container 中
-- currentDiffId: 当前已选的 difficultyId
-- onChanged(diffId, shortName): 选择变化时的回调
local function CreateDifficultyDropdowns(container, currentDiffId, onChanged)
    local currentType = GetInstTypeFromDiffId(currentDiffId)

    local typeDropdown = AceGUI:Create("Dropdown")
    typeDropdown:SetLabel(L["Instance Type"])
    typeDropdown:SetRelativeWidth(0.5)
    typeDropdown:SetList(INSTANCE_TYPE_LIST, INSTANCE_TYPE_ORDER)
    typeDropdown:SetValue(currentType)
    container:AddChild(typeDropdown)

    local diffDropdown = AceGUI:Create("Dropdown")
    diffDropdown:SetLabel(L["Difficulty"])
    diffDropdown:SetRelativeWidth(0.5)

    -- 根据当前类型设置难度列表
    local function UpdateDiffList(instType, keepValue)
        if instType == "dungeon" then
            diffDropdown:SetList(DUNGEON_DIFF_LIST, DUNGEON_DIFF_ORDER)
        elseif instType == "raid" then
            diffDropdown:SetList(RAID_DIFF_LIST, RAID_DIFF_ORDER)
        else
            diffDropdown:SetList({[""] = L["Any Difficulty"]}, {""})
        end
        if keepValue then
            diffDropdown:SetValue(keepValue)
        else
            diffDropdown:SetValue("")
            -- 不在这里调用 onChanged，等用户手动选难度时再触发
        end
    end

    UpdateDiffList(currentType, currentDiffId)
    container:AddChild(diffDropdown)

    typeDropdown:SetCallback("OnValueChanged", function(_, _, val)
        UpdateDiffList(val) -- 切换类型时重置难度
    end)

    diffDropdown:SetCallback("OnValueChanged", function(_, _, val)
        onChanged(val, GetDiffShortName(val))
    end)
end

-- ==========================================
-- 注册系统确认弹窗
-- ==========================================
StaticPopupDialogs["DCS_CONFIRM_DELETE_TARGET"] = {
    text = L["Are you sure you want to delete this target?"],
    button1 = YES,
    button2 = NO,
    OnAccept = function(self, data)
        local cat = data.addon.db.profile.categories[data.catIndex]
        if cat then
            local inst = cat.instances[data.instIndex]
            if inst then
                table.remove(inst.targets, data.targetIndex)
            end
        end
        data.frame:RefreshTree(data.catIndex .. "\001" .. data.instIndex)
        data.addon:CheckInstance()
    end,
    timeout = 0, whileDead = true, hideOnEscape = true, preferredIndex = 3,
}

StaticPopupDialogs["DCS_CONFIRM_DELETE_INST"] = {
    text = L["Are you sure you want to delete this dungeon and all its contents?"],
    button1 = YES,
    button2 = NO,
    OnAccept = function(self, data)
        local cat = data.addon.db.profile.categories[data.catIndex]
        if cat then
            table.remove(cat.instances, data.instIndex)
        end
        data.frame:RefreshTree(tostring(data.catIndex))
        data.addon:CheckInstance()
    end,
    timeout = 0, whileDead = true, hideOnEscape = true, preferredIndex = 3,
}

StaticPopupDialogs["DCS_CONFIRM_DELETE_CAT"] = {
    text = L["Are you sure you want to delete this category and all its contents?"],
    button1 = YES,
    button2 = NO,
    OnAccept = function(self, data)
        table.remove(data.addon.db.profile.categories, data.catIndex)
        data.frame:RefreshTree("new_cat")
        data.addon:CheckInstance()
    end,
    timeout = 0, whileDead = true, hideOnEscape = true, preferredIndex = 3,
}

-- ==========================================
-- 数据导入导出编解码
-- ==========================================
local function EncodeStr(str)
    if not str then return "" end
    str = tostring(str)
    str = str:gsub("%%", "%%P")
    str = str:gsub(";", "%%S")
    str = str:gsub("\n", "%%N")
    return str
end

local function DecodeStr(str)
    if not str then return "" end
    str = str:gsub("%%N", "\n")
    str = str:gsub("%%S", ";")
    str = str:gsub("%%P", "%%")
    return str
end

-- DCS4 格式：带分类层级 + 难度
local function GenerateExportCode(catList)
    local parts = {"DCS4"}
    table.insert(parts, tostring(#catList))
    for _, cat in ipairs(catList) do
        table.insert(parts, EncodeStr(cat.name))
        local instCount = cat.instances and #cat.instances or 0
        table.insert(parts, tostring(instCount))
        for _, inst in ipairs(cat.instances or {}) do
            table.insert(parts, EncodeStr(inst.name))
            table.insert(parts, EncodeStr(inst.id))
            table.insert(parts, inst.isActive == false and "0" or "1")
            table.insert(parts, EncodeStr(inst.difficulty or ""))
            table.insert(parts, EncodeStr(inst.difficultyId or ""))
            local tCount = inst.targets and #inst.targets or 0
            table.insert(parts, tostring(tCount))
            for _, t in ipairs(inst.targets or {}) do
                table.insert(parts, EncodeStr(t.name))
                table.insert(parts, EncodeStr(t.note))
                table.insert(parts, EncodeStr(t.encounterId or ""))
            end
        end
    end
    return table.concat(parts, ";")
end

-- 解析导入代码，兼容 DCS1/DCS2/DCS3/DCS4
-- 返回: success, resultType("categories" | "instances"), data
local function ParseImportCode(str)
    if not str or str == "" then return false, "Code is empty" end
    local parts = {strsplit(";", str)}
    local version = parts[1]

    if version == "DCS4" then
        -- ===== DCS4: 带分类 + 难度 =====
        local numCats = tonumber(parts[2])
        if not numCats then return false, "Invalid category count" end
        local newCategories = {}
        local i = 3
        for c = 1, numCats do
            if i > #parts then return false, "Incomplete category data" end
            local catName = DecodeStr(parts[i])
            local instCount = tonumber(parts[i+1])
            if not instCount then return false, "Invalid instance count" end
            local cat = { name = catName, instances = {} }
            i = i + 2
            for ii = 1, instCount do
                if i + 5 > #parts then return false, "Incomplete instance data" end
                local instName = DecodeStr(parts[i])
                local instId = DecodeStr(parts[i+1])
                local isActive = (parts[i+2] == "1")
                local difficulty = DecodeStr(parts[i+3])
                local difficultyId = DecodeStr(parts[i+4])
                local tCount = tonumber(parts[i+5])
                if not tCount then return false, "Invalid target count" end
                local inst = { name = instName, id = instId, isActive = isActive, difficulty = difficulty, difficultyId = difficultyId, targets = {} }
                i = i + 6
                for t = 1, tCount do
                    if i + 2 > #parts then return false, "Incomplete target data" end
                    table.insert(inst.targets, {
                        name = DecodeStr(parts[i]),
                        note = DecodeStr(parts[i+1]),
                        encounterId = DecodeStr(parts[i+2])
                    })
                    i = i + 3
                end
                table.insert(cat.instances, inst)
            end
            table.insert(newCategories, cat)
        end
        return true, "categories", newCategories

    elseif version == "DCS3" then
        -- ===== DCS3: 带分类，无难度 =====
        local numCats = tonumber(parts[2])
        if not numCats then return false, "Invalid category count" end
        local newCategories = {}
        local i = 3
        for c = 1, numCats do
            if i > #parts then return false, "Incomplete category data" end
            local catName = DecodeStr(parts[i])
            local instCount = tonumber(parts[i+1])
            if not instCount then return false, "Invalid instance count" end
            local cat = { name = catName, instances = {} }
            i = i + 2
            for ii = 1, instCount do
                if i + 3 > #parts then return false, "Incomplete instance data" end
                local instName = DecodeStr(parts[i])
                local instId = DecodeStr(parts[i+1])
                local isActive = (parts[i+2] == "1")
                local tCount = tonumber(parts[i+3])
                if not tCount then return false, "Invalid target count" end
                local inst = { name = instName, id = instId, isActive = isActive, targets = {} }
                i = i + 4
                for t = 1, tCount do
                    if i + 2 > #parts then return false, "Incomplete target data" end
                    table.insert(inst.targets, {
                        name = DecodeStr(parts[i]),
                        note = DecodeStr(parts[i+1]),
                        encounterId = DecodeStr(parts[i+2])
                    })
                    i = i + 3
                end
                table.insert(cat.instances, inst)
            end
            table.insert(newCategories, cat)
        end
        return true, "categories", newCategories

    elseif version == "DCS1" or version == "DCS2" then
        -- ===== DCS1/DCS2: 旧格式，返回副本列表 =====
        local newInstances = {}
        local i = 2
        while i <= #parts do
            local instName = DecodeStr(parts[i])
            local instId = DecodeStr(parts[i+1])
            local isActive = (parts[i+2] == "1")
            local tCount = tonumber(parts[i+3])
            if not tCount then break end
            local inst = { name = instName, id = instId, isActive = isActive, targets = {} }
            i = i + 4
            for j = 1, tCount do
                if version == "DCS1" then
                    if i + 1 > #parts then return false, "Incomplete target data" end
                    table.insert(inst.targets, { name = DecodeStr(parts[i]), note = DecodeStr(parts[i+1]) })
                    i = i + 2
                else -- DCS2
                    if i + 2 > #parts then return false, "Incomplete target data" end
                    table.insert(inst.targets, { name = DecodeStr(parts[i]), note = DecodeStr(parts[i+1]), encounterId = DecodeStr(parts[i+2]) })
                    i = i + 3
                end
            end
            table.insert(newInstances, inst)
        end
        return true, "instances", newInstances
    else
        return false, "Invalid format"
    end
end

-- ==========================================
-- 打开编辑器 UI
-- ==========================================
function addon:OpenEditor()
    if addon.editorFrame then 
        addon.editorFrame:Show()
        addon.editorFrame:RefreshTree()
        return 
    end

    local frame = AceGUI:Create("Frame")
    frame:SetTitle(L["DungeonCheatsheet - Dungeon & Target Editor"])
    frame:SetLayout("Fill")
    frame:SetWidth(750)
    frame:SetHeight(550)
    addon.editorFrame = frame
    
    frame:SetCallback("OnClose", function(widget) 
        widget:Hide() 
        addon:CheckInstance()
        if not InCombatLockdown() then
            addon:OpenMainGUI()
        end
    end)

    local treeGroup = AceGUI:Create("TreeGroup")
    treeGroup:SetLayout("Flow")
    treeGroup:SetTreeWidth(220)
    frame:AddChild(treeGroup)
    frame.treeGroup = treeGroup

    -- ==========================================
    -- 构建三层树状列表
    -- 顶层: new_cat, import_export, 分类1, 分类2, ...
    -- 分类下: [+ 新建副本], 副本1, 副本2, ...
    -- 副本下: 目标1, 目标2, ...
    -- ==========================================
    function frame:RefreshTree(selectedPath)
        local treeData = {}
        
        table.insert(treeData, { value = "new_cat", text = "|cff00ff00" .. L["[+ New Category]"] .. "|r" })
        table.insert(treeData, { value = "import_export", text = "|cff00ccff" .. L["[<=> Import & Export]"] .. "|r" })
        
        for ci, cat in ipairs(addon.db.profile.categories) do
            local catName = (cat.name and cat.name ~= "") and cat.name or L["Unnamed Category"]
            local catNode = {
                value = tostring(ci),
                text = "|cffffcc00" .. catName .. "|r",
                children = {}
            }
            -- 每个分类下的第一个子节点：[+ 新建副本]
            table.insert(catNode.children, {
                value = "new",
                text = "|cff00ff00" .. L["[+ New Dungeon]"] .. "|r"
            })
            -- 副本列表
            for ii, inst in ipairs(cat.instances or {}) do
                local instDisplayName = addon:GetInstDisplayName(inst)
                local statusStr = (inst.isActive == false) and " |cff888888" .. L["[Hidden]"] .. "|r" or ""
                local instNode = {
                    value = tostring(ii),
                    text = instDisplayName .. statusStr,
                    children = {}
                }
                -- 目标列表
                if inst.targets then
                    for ti, target in ipairs(inst.targets) do
                        local targetName = (target.name and target.name ~= "") and target.name or L["Unnamed Target"]
                        table.insert(instNode.children, { value = tostring(ti), text = targetName })
                    end
                end
                table.insert(catNode.children, instNode)
            end
            table.insert(treeData, catNode)
        end
        
        treeGroup:SetTree(treeData)
        if selectedPath then
            treeGroup:SelectByPath(selectedPath)
        end
    end

    -- ==========================================
    -- 右侧面板：根据选中节点渲染内容
    -- 路径解析:
    --   "new_cat"                    → 新建分类
    --   "import_export"              → 导入导出
    --   "ci"                         → 管理分类
    --   "ci\001new"                  → 新建副本
    --   "ci\001ii"                   → 管理副本
    --   "ci\001ii\001ti"             → 编辑目标
    -- ==========================================
    treeGroup:SetCallback("OnGroupSelected", function(widget, event, group)
        widget:ReleaseChildren()
        
        local scroll = AceGUI:Create("ScrollFrame")
        scroll:SetLayout("Flow")
        scroll:SetFullWidth(true)
        scroll:SetFullHeight(true)
        widget:AddChild(scroll)

        -- ========== 新建分类 ==========
        if group == "new_cat" then
            local title = AceGUI:Create("Heading")
            title:SetText(L["New Category"])
            title:SetFullWidth(true)
            scroll:AddChild(title)

            local nameEdit = AceGUI:Create("EditBox")
            nameEdit:SetLabel(L["Category Name"])
            nameEdit:SetFullWidth(true)
            scroll:AddChild(nameEdit)

            local addBtn = AceGUI:Create("Button")
            addBtn:SetText(L["Save & Add Category"])
            addBtn:SetFullWidth(true)
            addBtn:SetCallback("OnClick", function()
                local nameStr = nameEdit:GetText()
                if nameStr and nameStr ~= "" then
                    table.insert(addon.db.profile.categories, {
                        name = nameStr,
                        instances = {}
                    })
                    local newIndex = #addon.db.profile.categories
                    frame:RefreshTree(tostring(newIndex))
                else
                    print("|cffff0000[DungeonCheatsheet] " .. L["Please enter a category name!"] .. "|r")
                end
            end)
            scroll:AddChild(addBtn)

        -- ========== 导入导出 ==========
        elseif group == "import_export" then
            local title = AceGUI:Create("Heading")
            title:SetText(L["Data Import & Export"])
            title:SetFullWidth(true)
            scroll:AddChild(title)

            -- 导出区：按分类勾选
            local exportGroup = AceGUI:Create("InlineGroup")
            exportGroup:SetTitle(L["Batch Export (Generate code to share with friends)"])
            exportGroup:SetLayout("Flow")
            exportGroup:SetFullWidth(true)
            scroll:AddChild(exportGroup)

            if #addon.db.profile.categories == 0 then
                local emptyLabel = AceGUI:Create("Label")
                emptyLabel:SetText(L["No categories available for export."])
                exportGroup:AddChild(emptyLabel)
            else
                local selectAllBtn = AceGUI:Create("Button")
                selectAllBtn:SetText(L["Select All / Deselect All"])
                selectAllBtn:SetFullWidth(true)
                exportGroup:AddChild(selectAllBtn)

                local exportCheckboxes = {}
                local isAllSelected = false
                selectAllBtn:SetCallback("OnClick", function()
                    isAllSelected = not isAllSelected
                    for i, cb in ipairs(exportCheckboxes) do
                        cb:SetValue(isAllSelected)
                        exportSelections[i] = isAllSelected
                    end
                end)

                for i, cat in ipairs(addon.db.profile.categories) do
                    local instCount = cat.instances and #cat.instances or 0
                    local cb = AceGUI:Create("CheckBox")
                    cb:SetLabel((cat.name or L["Unnamed Category"]) .. " (" .. instCount .. ")")
                    cb:SetValue(exportSelections[i] or false)
                    cb:SetCallback("OnValueChanged", function(_, _, val) exportSelections[i] = val end)
                    table.insert(exportCheckboxes, cb)
                    exportGroup:AddChild(cb)
                end

                local genBtn = AceGUI:Create("Button")
                genBtn:SetText(L["Generate Export Code"])
                genBtn:SetFullWidth(true)

                local codeBox = AceGUI:Create("MultiLineEditBox")
                codeBox:SetLabel(L["Generated Export Code:"])
                codeBox:SetFullWidth(true)
                codeBox:SetNumLines(4)
                codeBox:DisableButton(true)

                genBtn:SetCallback("OnClick", function()
                    local toExport = {}
                    for i, selected in pairs(exportSelections) do
                        if selected and addon.db.profile.categories[i] then
                            table.insert(toExport, addon.db.profile.categories[i])
                        end
                    end
                    if #toExport == 0 then
                        codeBox:SetText(L["Please select at least one dungeon to export above!"])
                    else
                        codeBox:SetText(GenerateExportCode(toExport))
                        codeBox:HighlightText()
                        codeBox:SetFocus()
                    end
                end)
                exportGroup:AddChild(genBtn)
                exportGroup:AddChild(codeBox)
            end

            -- 导入区
            local importGroup = AceGUI:Create("InlineGroup")
            importGroup:SetTitle(L["Import Dungeon (Paste code shared by friends)"])
            importGroup:SetLayout("Flow")
            importGroup:SetFullWidth(true)
            scroll:AddChild(importGroup)

            local importBox = AceGUI:Create("MultiLineEditBox")
            importBox:SetLabel(L["Paste code here:"])
            importBox:SetFullWidth(true)
            importBox:SetNumLines(4)
            importBox:DisableButton(true)
            importGroup:AddChild(importBox)

            local importBtn = AceGUI:Create("Button")
            importBtn:SetText(L["Verify & Import"])
            importBtn:SetFullWidth(true)
            importBtn:SetCallback("OnClick", function()
                local code = importBox:GetText()
                local success, resultType, data = ParseImportCode(code)
                if success then
                    if resultType == "categories" then
                        -- DCS3/DCS4: 直接添加分类
                        for _, newCat in ipairs(data) do
                            table.insert(addon.db.profile.categories, newCat)
                        end
                        importBox:SetText(string.format(L["Import successful! Added %d categories."], #data))
                    else
                        -- DCS1/DCS2: 放到第一个分类（默认）
                        if #addon.db.profile.categories == 0 then
                            table.insert(addon.db.profile.categories, { name = L["Default"], instances = {} })
                        end
                        local defaultCat = addon.db.profile.categories[1]
                        for _, newInst in ipairs(data) do
                            table.insert(defaultCat.instances, newInst)
                        end
                        importBox:SetText(string.format(L["Import successful! Added %d dungeons to '%s'."], #data, defaultCat.name))
                    end
                    exportSelections = {}
                    frame:RefreshTree("import_export")
                    addon:CheckInstance()
                else
                    importBox:SetText(L["Import failed: "] .. tostring(resultType))
                end
            end)
            importGroup:AddChild(importBtn)

        -- ========== 分类/副本/目标详情 ==========
        else
            local path = {strsplit("\001", group)}
            local catIndex = tonumber(path[1])
            local sub = path[2]        -- nil | "new" | instIndex
            local targetIdx = path[3]  -- nil | targetIndex

            if not catIndex then return end
            local cat = addon.db.profile.categories[catIndex]
            if not cat then return end

            if not sub then
                -- ========== 管理分类 ==========
                local title = AceGUI:Create("Heading")
                title:SetText(L["Manage Category"])
                title:SetFullWidth(true)
                scroll:AddChild(title)

                local nameEdit = AceGUI:Create("EditBox")
                nameEdit:SetLabel(L["Category Name"])
                nameEdit:SetText(cat.name)
                nameEdit:SetFullWidth(true)
                nameEdit:SetCallback("OnEnterPressed", function(_, _, text)
                    cat.name = text
                    frame:RefreshTree(tostring(catIndex))
                end)
                scroll:AddChild(nameEdit)

                local hugeSpacer = AceGUI:Create("Label")
                hugeSpacer:SetText(string.rep("\n", 12))
                hugeSpacer:SetFullWidth(true)
                scroll:AddChild(hugeSpacer)

                local delCatBtn = AceGUI:Create("Button")
                delCatBtn:SetText(L["Delete this Category & All Contents"])
                delCatBtn:SetFullWidth(true)
                delCatBtn:SetCallback("OnClick", function()
                    local dialog = StaticPopup_Show("DCS_CONFIRM_DELETE_CAT")
                    if dialog then
                        dialog.data = { catIndex = catIndex, frame = frame, addon = addon }
                    end
                end)
                scroll:AddChild(delCatBtn)

            elseif sub == "new" then
                -- ========== 在此分类中新建副本 ==========
                local title = AceGUI:Create("Heading")
                title:SetText(L["New Dungeon"])
                title:SetFullWidth(true)
                scroll:AddChild(title)

                local nameEdit = AceGUI:Create("EditBox")
                nameEdit:SetLabel(L["Dungeon Name"])
                nameEdit:SetRelativeWidth(0.5)
                scroll:AddChild(nameEdit)

                local idEdit = AceGUI:Create("EditBox")
                idEdit:SetLabel(L["Dungeon ID (Optional)"])
                idEdit:SetRelativeWidth(0.5)
                scroll:AddChild(idEdit)

                local selectedDiffId = ""
                local selectedDiffShort = ""
                CreateDifficultyDropdowns(scroll, "", function(diffId, shortName)
                    selectedDiffId = diffId
                    selectedDiffShort = shortName
                end)

                local getInfoBtn = AceGUI:Create("Button")
                getInfoBtn:SetText(L["Print current dungeon info in chat (Manual input required)"])
                getInfoBtn:SetFullWidth(true)
                getInfoBtn:SetCallback("OnClick", function()
                    local n, _, dID, dName, _, _, _, i = GetInstanceInfo()
                    if i then
                        print("|cff00ff00[DungeonCheatsheet]|r " .. L["Current Dungeon: "] .. "|cffffff00" .. n .. "|r" .. L[" | Dungeon ID: "] .. "|cffffff00" .. i .. "|r" .. L[" | Difficulty: "] .. "|cffffff00" .. (dName or "?") .. "|r")
                    else
                        print("|cffff0000[DungeonCheatsheet]|r " .. L["You are not currently in a dungeon"])
                    end
                end)
                scroll:AddChild(getInfoBtn)

                local addBtn = AceGUI:Create("Button")
                addBtn:SetText(L["Save & Add Dungeon"])
                addBtn:SetFullWidth(true)
                addBtn:SetCallback("OnClick", function()
                    local nameStr = nameEdit:GetText()
                    if nameStr and nameStr ~= "" then
                        cat.instances = cat.instances or {}
                        table.insert(cat.instances, {
                            name = nameStr,
                            id = idEdit:GetText() or "",
                            difficultyId = selectedDiffId,
                            difficulty = selectedDiffShort,
                            isActive = true,
                            targets = {}
                        })
                        local newInstIndex = #cat.instances
                        frame:RefreshTree(catIndex .. "\001" .. newInstIndex)
                        addon:CheckInstance()
                    else
                        print("|cffff0000[DungeonCheatsheet] " .. L["Please enter a dungeon name!"] .. "|r")
                    end
                end)
                scroll:AddChild(addBtn)

            else
                local instIndex = tonumber(sub)
                if not instIndex then return end
                local inst = (cat.instances or {})[instIndex]
                if not inst then return end
                local targetIndex = tonumber(targetIdx)

                if targetIndex then
                    -- ========== 编辑目标 ==========
                    local target = inst.targets[targetIndex]
                    if not target then return end

                    local title = AceGUI:Create("Heading")
                    title:SetText(L["Edit Target: "] .. (target.name or L["Unnamed"]))
                    title:SetFullWidth(true)
                    scroll:AddChild(title)

                    local nameCtrlGroup = AceGUI:Create("SimpleGroup")
                    nameCtrlGroup:SetLayout("Flow")
                    nameCtrlGroup:SetFullWidth(true)
                    scroll:AddChild(nameCtrlGroup)

                    local nameEdit = AceGUI:Create("EditBox")
                    nameEdit:SetLabel(L["Target Name"])
                    nameEdit:SetText(target.name)
                    nameEdit:SetRelativeWidth(0.75)
                    nameEdit:SetCallback("OnEnterPressed", function(_, _, text)
                        target.name = text
                        frame:RefreshTree(catIndex .. "\001" .. instIndex .. "\001" .. targetIndex)
                        addon:CheckInstance()
                    end)
                    nameCtrlGroup:AddChild(nameEdit)

                    local delTargetBtn = AceGUI:Create("Button")
                    delTargetBtn:SetText(L["Delete Target"])
                    delTargetBtn:SetRelativeWidth(0.24)
                    delTargetBtn:SetCallback("OnClick", function()
                        local dialog = StaticPopup_Show("DCS_CONFIRM_DELETE_TARGET")
                        if dialog then
                            dialog.data = {
                                catIndex = catIndex,
                                instIndex = instIndex,
                                targetIndex = targetIndex,
                                frame = frame,
                                addon = addon
                            }
                        end
                    end)
                    nameCtrlGroup:AddChild(delTargetBtn)

                    local encounterIdEdit = AceGUI:Create("EditBox")
                    encounterIdEdit:SetLabel(L["Encounter ID (Optional)"])
                    encounterIdEdit:SetText(target.encounterId)
                    encounterIdEdit:SetFullWidth(true)
                    encounterIdEdit:SetCallback("OnEnterPressed", function(_, _, text)
                        target.encounterId = text
                        addon:CheckInstance()
                    end)
                    scroll:AddChild(encounterIdEdit)

                    local noteEdit = AceGUI:Create("MultiLineEditBox")
                    noteEdit:SetLabel(L["Text Note (Auto-saved)"])
                    noteEdit:SetText(target.note)
                    noteEdit:SetFullWidth(true)
                    noteEdit:SetNumLines(16)
                    noteEdit:DisableButton(true)
                    noteEdit:SetCallback("OnTextChanged", function(_, _, text)
                        target.note = text
                        addon:CheckInstance()
                    end)
                    scroll:AddChild(noteEdit)

                else
                    -- ========== 管理副本 ==========
                    local title = AceGUI:Create("Heading")
                    title:SetText(L["Manage Dungeon"])
                    title:SetFullWidth(true)
                    scroll:AddChild(title)

                    local nameEdit = AceGUI:Create("EditBox")
                    nameEdit:SetLabel(L["Dungeon Name"])
                    nameEdit:SetText(inst.name)
                    nameEdit:SetRelativeWidth(0.5)
                    nameEdit:SetCallback("OnEnterPressed", function(_, _, text)
                        inst.name = text
                        frame:RefreshTree(catIndex .. "\001" .. instIndex)
                        addon:CheckInstance()
                    end)
                    scroll:AddChild(nameEdit)

                    local idEdit = AceGUI:Create("EditBox")
                    idEdit:SetLabel(L["Dungeon ID"])
                    idEdit:SetText(inst.id)
                    idEdit:SetRelativeWidth(0.5)
                    idEdit:SetCallback("OnEnterPressed", function(_, _, text)
                        inst.id = text
                        addon:CheckInstance()
                    end)
                    scroll:AddChild(idEdit)

                    CreateDifficultyDropdowns(scroll, inst.difficultyId or "", function(diffId, shortName)
                        inst.difficultyId = diffId
                        inst.difficulty = shortName
                        frame:RefreshTree(catIndex .. "\001" .. instIndex)
                        addon:CheckInstance()
                    end)

                    local getInfoBtn = AceGUI:Create("Button")
                    getInfoBtn:SetText(L["Print current dungeon info in chat (Manual modify required)"])
                    getInfoBtn:SetFullWidth(true)
                    getInfoBtn:SetCallback("OnClick", function()
                        local n, _, dID, dName, _, _, _, i = GetInstanceInfo()
                        if i then
                            print("|cff00ff00[DungeonCheatsheet]|r " .. L["Current Dungeon: "] .. "|cffffff00" .. n .. "|r" .. L[" | Dungeon ID: "] .. "|cffffff00" .. i .. "|r" .. L[" | Difficulty: "] .. "|cffffff00" .. (dName or "?") .. "|r")
                        else
                            print("|cffff0000[DungeonCheatsheet]|r " .. L["You are not currently in a dungeon"])
                        end
                    end)
                    scroll:AddChild(getInfoBtn)

                    local activeCheck = AceGUI:Create("CheckBox")
                    activeCheck:SetLabel(L["Activate this dungeon (Uncheck to hide on screen)"])
                    activeCheck:SetValue(inst.isActive ~= false)
                    activeCheck:SetFullWidth(true)
                    activeCheck:SetCallback("OnValueChanged", function(_, _, val)
                        inst.isActive = val
                        frame:RefreshTree(catIndex .. "\001" .. instIndex)
                        addon:CheckInstance()
                    end)
                    scroll:AddChild(activeCheck)

                    -- 移动到其他分类
                    if #addon.db.profile.categories > 1 then
                        local moveDropdown = AceGUI:Create("Dropdown")
                        moveDropdown:SetLabel(L["Move to Category"])
                        moveDropdown:SetRelativeWidth(0.5)
                        local catList = {}
                        for ci, c in ipairs(addon.db.profile.categories) do
                            if ci ~= catIndex then
                                catList[tostring(ci)] = c.name or L["Unnamed Category"]
                            end
                        end
                        moveDropdown:SetList(catList)
                        moveDropdown:SetCallback("OnValueChanged", function(_, _, targetCatIdx)
                            targetCatIdx = tonumber(targetCatIdx)
                            if not targetCatIdx then return end
                            local targetCat = addon.db.profile.categories[targetCatIdx]
                            if not targetCat then return end
                            -- 从当前分类移除
                            table.remove(cat.instances, instIndex)
                            -- 添加到目标分类
                            targetCat.instances = targetCat.instances or {}
                            table.insert(targetCat.instances, inst)
                            local newInstIdx = #targetCat.instances
                            frame:RefreshTree(targetCatIdx .. "\001" .. newInstIdx)
                            addon:CheckInstance()
                        end)
                        scroll:AddChild(moveDropdown)
                    end

                    local spacer = AceGUI:Create("Label")
                    spacer:SetText("\n\n")
                    spacer:SetFullWidth(true)
                    scroll:AddChild(spacer)

                    local addTargetBtn = AceGUI:Create("Button")
                    addTargetBtn:SetText(L["+ Add New Target to this Dungeon"])
                    addTargetBtn:SetFullWidth(true)
                    addTargetBtn:SetCallback("OnClick", function()
                        inst.targets = inst.targets or {}
                        table.insert(inst.targets, {name = L["New Target"], note = ""})
                        frame:RefreshTree(catIndex .. "\001" .. instIndex)
                        addon:CheckInstance()
                        UIErrorsFrame:AddMessage(L["Created successfully!"], 0.0, 1.0, 0.0)
                    end)
                    scroll:AddChild(addTargetBtn)

                    local hugeSpacer = AceGUI:Create("Label")
                    hugeSpacer:SetText(string.rep("\n", 5))
                    hugeSpacer:SetFullWidth(true)
                    scroll:AddChild(hugeSpacer)

                    local delInstBtn = AceGUI:Create("Button")
                    delInstBtn:SetText(L["Delete this Dungeon & All Contents"])
                    delInstBtn:SetFullWidth(true)
                    delInstBtn:SetCallback("OnClick", function()
                        local dialog = StaticPopup_Show("DCS_CONFIRM_DELETE_INST")
                        if dialog then
                            dialog.data = {
                                catIndex = catIndex,
                                instIndex = instIndex,
                                frame = frame,
                                addon = addon
                            }
                        end
                    end)
                    scroll:AddChild(delInstBtn)
                end
            end
        end
        
        local bottomSpacer = AceGUI:Create("Icon")
        bottomSpacer:SetImageSize(1, 150)
        bottomSpacer:SetFullWidth(true)
        scroll:AddChild(bottomSpacer)
    end)

    frame:RefreshTree("new_cat")
end