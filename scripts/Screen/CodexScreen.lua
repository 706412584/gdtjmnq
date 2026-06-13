-- ============================================================================
-- CodexScreen - 名器图鉴界面（基于 Layout Editor 布局）
-- Project Smith / P2-C3
--
-- 功能：
--   1. 展示所有武器配方（18格网格，12个武器 + 6个空位隐藏）
--   2. 已解锁的武器显示详情（图片、名称、品质）
--   3. 未解锁的武器显示问号占位
--   4. 左侧分类筛选（全部/按武器线）
--   5. 返回主界面按钮
-- ============================================================================

local Layout         = require("ui_CodexScreen_名器图鉴")
local GameState      = require("Core.GameState")
local WeaponRecipes  = require("Config.WeaponRecipes")
local ScreenRouter   = require("Utils.ScreenRouter")

local CodexScreen = {}

-- ============================================================================
-- 武器图片映射
-- ============================================================================

local WEAPON_IMAGES = {
    WEAPON_001 = "image/weapon_001_hunter_knife.png",
    WEAPON_002 = "image/weapon_002_guard_blade.png",
    WEAPON_003 = "image/weapon_003_mountain_cleaver.png",
    WEAPON_004 = "image/weapon_004_ranger_sword.png",
    WEAPON_005 = "image/weapon_005_legion_breaker.png",
    WEAPON_006 = "image/weapon_006_azure_sword.png",
    WEAPON_007 = "image/weapon_007_fortress_greatsword.png",
    WEAPON_008 = "image/weapon_008_peak_cleaver.png",
    WEAPON_009 = "image/weapon_009_meteoric_saber.png",
    WEAPON_010 = "image/weapon_010_imperial_decree.png",
    WEAPON_011 = "image/weapon_011_guild_ceremonial.png",
    WEAPON_012 = "image/weapon_012_frostgleam_reforged.png",
}

-- 品质等级映射（根据 tier 或手动指定）
local QUALITY_GRADES = {
    [1] = { text = "寻", color = "#3A322B", borderColor = "#3A322B" },
    [2] = { text = "良", color = "#3A322B", borderColor = "#3A322B" },
    [3] = { text = "名", color = "#4F7A63", borderColor = "#4F7A63" },
    [4] = { text = "逸", color = "#C9A45A", borderColor = "#C9A45A" },
    [5] = { text = "神", color = "#C96A2B", borderColor = "#C96A2B" },
}

-- ============================================================================
-- 网格 Cell 定义（18 cells, 3 rows × 6 columns）
-- 每个 cell 占 10 个连续 base-36 ID：
--   +0=cell, +1=sr(border), +2=ph, +3=sr(inner), +4=sl(img),
--   +5=sl(overlay, locked only), +6=tx(???, locked only),
--   +7=tx(name), +8=sr(badge), +9=tx(grade)
-- "locked" 标记表示布局中存在 +5/+6 覆盖层元素
-- ============================================================================

local CELL_DEFS = {
    -- Row 1 (unlocked style: no +5/+6 overlay elements)
    { cellId = "cell_1a", borderId = "sr_1b", imgId = "sl_1e", nameId = "tx_1h", badgeBgId = "sr_1i", gradeId = "tx_1j" },
    { cellId = "cell_1k", borderId = "sr_1l", imgId = "sl_1o", nameId = "tx_1r", badgeBgId = "sr_1s", gradeId = "tx_1t" },
    { cellId = "cell_1u", borderId = "sr_1v", imgId = "sl_1y", nameId = "tx_21", badgeBgId = "sr_22", gradeId = "tx_23" },
    { cellId = "cell_24", borderId = "sr_25", imgId = "sl_28", nameId = "tx_2b", badgeBgId = "sr_2c", gradeId = "tx_2d" },
    { cellId = "cell_2e", borderId = "sr_2f", imgId = "sl_2i", nameId = "tx_2l", badgeBgId = "sr_2m", gradeId = "tx_2n" },
    { cellId = "cell_2o", borderId = "sr_2p", imgId = "sl_2s", nameId = "tx_2v", badgeBgId = "sr_2w", gradeId = "tx_2x" },
    -- Row 2 (cell_2y=unlocked style; rest=locked style with overlay)
    { cellId = "cell_2y", borderId = "sr_2z", imgId = "sl_32", nameId = "tx_35", badgeBgId = "sr_36", gradeId = "tx_37" },
    { cellId = "cell_38", borderId = "sr_39", imgId = "sl_3d", overlayId = "tx_3e", nameId = "tx_3f", badgeBgId = "sr_3g", gradeId = "tx_3h", locked = true },
    { cellId = "cell_3i", borderId = "sr_3j", imgId = "sl_3n", overlayId = "tx_3o", nameId = "tx_3p", badgeBgId = "sr_3q", gradeId = "tx_3r", locked = true },
    { cellId = "cell_3s", borderId = "sr_3t", imgId = "sl_3x", overlayId = "tx_3y", nameId = "tx_3z", badgeBgId = "sr_40", gradeId = "tx_41", locked = true },
    { cellId = "cell_42", borderId = "sr_43", imgId = "sl_47", overlayId = "tx_48", nameId = "tx_49", badgeBgId = "sr_4a", gradeId = "tx_4b", locked = true },
    { cellId = "cell_4c", borderId = "sr_4d", imgId = "sl_4h", overlayId = "tx_4i", nameId = "tx_4j", badgeBgId = "sr_4k", gradeId = "tx_4l", locked = true },
    -- Row 3 (all locked style)
    { cellId = "cell_4m", borderId = "sr_4n", imgId = "sl_4r", overlayId = "tx_4s", nameId = "tx_4t", badgeBgId = "sr_4u", gradeId = "tx_4v", locked = true },
    { cellId = "cell_4w", borderId = "sr_4x", imgId = "sl_51", overlayId = "tx_52", nameId = "tx_53", badgeBgId = "sr_54", gradeId = "tx_55", locked = true },
    { cellId = "cell_56", borderId = "sr_57", imgId = "sl_5b", overlayId = "tx_5c", nameId = "tx_5d", badgeBgId = "sr_5e", gradeId = "tx_5f", locked = true },
    { cellId = "cell_5g", borderId = "sr_5h", imgId = "sl_5l", overlayId = "tx_5m", nameId = "tx_5n", badgeBgId = "sr_5o", gradeId = "tx_5p", locked = true },
    { cellId = "cell_5q", borderId = "sr_5r", imgId = "sl_5v", overlayId = "tx_5w", nameId = "tx_5x", badgeBgId = "sr_5y", gradeId = "tx_5z", locked = true },
    { cellId = "cell_60", borderId = "sr_61", imgId = "sl_65", overlayId = "tx_66", nameId = "tx_67", badgeBgId = "sr_68", gradeId = "tx_69", locked = true },
}

-- 左侧分类按钮 IDs
-- 布局8个分类，实际数据4条武器线：short_blade/long_sword/heavy_sword/ceremony_blade
local CAT_DEFS = {
    { catId = "cat_f",  labelId = "tx_h",  bgId = "sr_g",  key = "all",            label = "全部" },
    { catId = "cat_i",  labelId = "tx_k",  bgId = "sr_j",  key = "short_blade",    label = "短刃" },
    { catId = "cat_l",  labelId = "tx_n",  bgId = "sr_m",  key = "long_sword",     label = "长剑" },
    { catId = "cat_o",  labelId = "tx_q",  bgId = "sr_p",  key = "heavy_sword",    label = "重剑" },
    { catId = "cat_r",  labelId = "tx_t",  bgId = "sr_s",  key = "ceremony_blade", label = "礼剑" },
    { catId = "cat_u",  labelId = "tx_w",  bgId = "sr_v",  key = "extra1" },
    { catId = "cat_x",  labelId = "tx_z",  bgId = "sr_y",  key = "extra2" },
    { catId = "cat_10", labelId = "tx_12", bgId = "sr_11", key = "extra3" },
}

-- ============================================================================
-- Screen 接口
-- ============================================================================

---@param container table UI 容器
---@param params table|nil
---@return table screen
function CodexScreen.Create(container, params)
    local screen = {}

    -- 构建布局
    local root = Layout.Build()
    container:AddChild(root)

    -- 获取已解锁图鉴
    local unlockedSet = {}
    local codexList = GameState.GetCodex()
    for i = 1, #codexList do
        unlockedSet[codexList[i]] = true
    end

    -- 获取所有武器配方
    local allRecipes = WeaponRecipes.GetAll()

    -- 按武器线分组
    local lineGroups = {}
    for i = 1, #allRecipes do
        local recipe = allRecipes[i]
        local line = recipe.line
        if not lineGroups[line] then
            lineGroups[line] = {}
        end
        lineGroups[line][#lineGroups[line] + 1] = recipe
    end

    -- 当前筛选
    local currentFilter = "all"

    -- ----------------------------------------------------------------
    -- 顶部栏绑定
    -- ----------------------------------------------------------------
    local backBtn = root:FindById("plate_3")
    if backBtn then
        backBtn.props.onClick = function()
            ScreenRouter.GoTo("home")
        end
    end

    local statsLabel = root:FindById("tx_7")

    -- ----------------------------------------------------------------
    -- 获取筛选后的武器列表
    -- ----------------------------------------------------------------
    local function GetFilteredRecipes()
        if currentFilter == "all" then
            return allRecipes
        end
        return lineGroups[currentFilter] or {}
    end

    -- ----------------------------------------------------------------
    -- 计算武器品质 tier
    -- ----------------------------------------------------------------
    local function GetWeaponTier(recipe)
        -- 根据配方 tier 字段或按顺序推断
        if recipe.tier then return recipe.tier end
        -- 默认按解锁章节推断品质
        local ch = recipe.unlockChapter or 1
        if ch <= 1 then return 2 end       -- 良
        if ch <= 2 then return 3 end       -- 名
        if ch <= 3 then return 4 end       -- 逸
        return 5                            -- 神
    end

    -- ----------------------------------------------------------------
    -- 刷新网格内容
    -- ----------------------------------------------------------------
    local function RefreshGrid()
        local filtered = GetFilteredRecipes()
        local totalWeapons = #allRecipes
        local totalUnlocked = #codexList

        -- 更新统计文字
        if statsLabel then
            local pct = totalWeapons > 0 and math.floor(totalUnlocked / totalWeapons * 1000) / 10 or 0
            statsLabel.text = "已录  " .. totalUnlocked .. " / " .. totalWeapons .. "  ·  完成度 " .. pct .. "%"
        end

        -- 遍历所有 cell
        for idx = 1, #CELL_DEFS do
            local def = CELL_DEFS[idx]
            local cell = root:FindById(def.cellId)
            if not cell then goto continue end

            local recipe = filtered[idx]

            if not recipe then
                -- 没有对应武器数据，隐藏此 cell
                cell.visible = false
                goto continue
            end

            -- 显示 cell
            cell.visible = true

            local isUnlocked = unlockedSet[recipe.id] == true
            local border = root:FindById(def.borderId)
            local img = root:FindById(def.imgId)
            local nameLabel = root:FindById(def.nameId)
            local badgeBg = root:FindById(def.badgeBgId)
            local gradeLabel = root:FindById(def.gradeId)
            -- locked-style cells 有覆盖层文字 "???"
            local overlay = def.overlayId and root:FindById(def.overlayId) or nil

            if isUnlocked then
                -- 已解锁：显示武器图片、名称、品质
                local tier = GetWeaponTier(recipe)
                local grade = QUALITY_GRADES[tier] or QUALITY_GRADES[2]

                if border then
                    border.borderColor = grade.borderColor
                end
                if img then
                    local imgPath = WEAPON_IMAGES[recipe.id]
                    if imgPath then
                        img.backgroundImage = imgPath
                        img.backgroundFit = "contain"
                        img.backgroundColor = "rgba(0,0,0,0)"
                    end
                end
                -- 隐藏 "???" 覆盖层文字
                if overlay then
                    overlay.visible = false
                end
                if nameLabel then
                    nameLabel.text = recipe.name or "???"
                    nameLabel.fontColor = "#f1e5cc"
                end
                if badgeBg then
                    badgeBg.backgroundColor = grade.color
                end
                if gradeLabel then
                    gradeLabel.text = grade.text
                    gradeLabel.fontColor = "#f1e5cc"
                end
            else
                -- 未解锁：问号占位，暗色调
                if border then
                    border.borderColor = "#3A322B"
                end
                if img then
                    -- 清除布局预设的武器图片，用暗色背景替代
                    img.backgroundImage = ""
                    img.backgroundColor = "#3d3522"
                end
                -- 显示 "???" 覆盖层文字（仅 locked-style cells 有此元素）
                if overlay then
                    overlay.visible = true
                end
                if nameLabel then
                    nameLabel.text = "?????"
                    nameLabel.fontColor = "#3a322b"
                end
                if badgeBg then
                    badgeBg.backgroundColor = "#3A322B"
                end
                if gradeLabel then
                    gradeLabel.text = "?"
                    gradeLabel.fontColor = "#3a322b"
                end
            end

            ::continue::
        end
    end

    -- ----------------------------------------------------------------
    -- 分类按钮交互
    -- ----------------------------------------------------------------
    local ACTIVE_BG = "#C96A2B"
    local ACTIVE_TEXT = "#f1e5cc"
    local INACTIVE_BG = "rgba(0,0,0,0)"
    local INACTIVE_TEXT = "#1f1a17"

    local function SetCategoryActive(activeKey)
        currentFilter = activeKey
        for i = 1, #CAT_DEFS do
            local catDef = CAT_DEFS[i]
            local bg = root:FindById(catDef.bgId)
            local lbl = root:FindById(catDef.labelId)
            if catDef.key == activeKey then
                if bg then bg.backgroundColor = ACTIVE_BG end
                if lbl then lbl.fontColor = ACTIVE_TEXT end
            else
                if bg then bg.backgroundColor = INACTIVE_BG end
                if lbl then lbl.fontColor = INACTIVE_TEXT end
            end
        end
        RefreshGrid()
    end

    -- 绑定分类按钮点击
    for i = 1, #CAT_DEFS do
        local catDef = CAT_DEFS[i]
        local catBtn = root:FindById(catDef.catId)
        if catBtn then
            local key = catDef.key
            catBtn.props.onClick = function()
                SetCategoryActive(key)
            end
        end
    end

    -- 隐藏无数据的 extra 分类按钮
    for i = 1, #CAT_DEFS do
        local catDef = CAT_DEFS[i]
        if catDef.key == "extra1" or catDef.key == "extra2" or catDef.key == "extra3" then
            local catBtn = root:FindById(catDef.catId)
            if catBtn then catBtn.visible = false end
        end
    end

    -- ----------------------------------------------------------------
    -- 初始化
    -- ----------------------------------------------------------------
    -- 更新分类标签文本（显示每个分类下的武器数量）
    local function UpdateCategoryLabels()
        for i = 1, #CAT_DEFS do
            local catDef = CAT_DEFS[i]
            if not catDef.label then goto next_cat end

            local lbl = root:FindById(catDef.labelId)
            if not lbl then goto next_cat end

            if catDef.key == "all" then
                lbl.text = catDef.label .. " · " .. #allRecipes
            else
                local group = lineGroups[catDef.key]
                local count = group and #group or 0
                lbl.text = catDef.label .. " · " .. count
            end

            ::next_cat::
        end
    end

    UpdateCategoryLabels()
    SetCategoryActive("all")

    -- ----------------------------------------------------------------
    -- Destroy
    -- ----------------------------------------------------------------
    function screen.Destroy()
        -- 静态页面，无需清理
    end

    return screen
end

return CodexScreen
