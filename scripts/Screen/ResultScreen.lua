---@diagnostic disable: assign-type-mismatch, return-type-mismatch
-- ============================================================================
-- ResultScreen - 结算界面（Layout 迁移版）
-- Project Smith / P1-D4
--
-- 展示锻造结果:
--   - 武器名称 + 品质等级
--   - 各维度评分条
--   - 总评级
--   - 客户评语
--   - 获得奖励
--   - 交付/广告双倍/入图鉴按钮
-- ============================================================================

local UI = require("urhox-libs/UI")
local ScreenRouter = require("Utils.ScreenRouter")
local SFXManager = require("Utils.SFXManager")
local Layout = require("ui_ResultScreen_结算界面")

local ResultScreen = {}

-- ============================================================================
-- 品质颜色映射
-- ============================================================================

local TIER_COLORS = {
    [0] = "#808080",  -- 凡品 - 灰
    [1] = "#4F7A63",  -- 良品 - 绿
    [2] = "#64B4DC",  -- 上品 - 蓝
    [3] = "#B478DC",  -- 珍品 - 紫
    [4] = "#FFC83C",  -- 名器 - 金
    [5] = "#FF6464",  -- 传世 - 红金
}

-- 步骤名称映射
local STEP_NAMES = {
    ore_select = "选矿去杂",
    forging    = "锻打塑形",
    polishing  = "研磨开刃",
    smelting   = "控火熔炼",
    quenching  = "淬火时机",
    assembly   = "组装装饰",
}

-- 评分条颜色（按维度）
local BAR_COLORS = {
    "#4F7A63",  -- 成型 - 绿
    "#C96A2B",  -- 锋利 - 橙
    "#C9A45A",  -- 韵律 - 金
    "#3A322B",  -- 稀有 - 褐
}

-- 武器图片映射
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

-- ============================================================================
-- Screen 接口
-- ============================================================================

--- 创建结算界面
---@param container table UI 容器
---@param params table { result }
---@return table screen
function ResultScreen.Create(container, params)
    local screen = {}

    local result = params and params.result
    if not result then
        container:AddChild(UI.Panel {
            width = "100%", height = "100%",
            justifyContent = "center", alignItems = "center",
            children = {
                ---@diagnostic disable-next-line: param-type-mismatch
                UI.Label { text = "结算数据异常", fontSize = 16, fontColor = "#E94560" },
                UI.Button {
                    text = "返回工坊",
                    onClick = function() ScreenRouter.GoTo("home") end,
                },
            },
        })
        return screen
    end

    -- ----------------------------------------------------------------
    -- 构建布局
    -- ----------------------------------------------------------------

    local root = Layout.Build()
    container:AddChild(root)

    -- ----------------------------------------------------------------
    -- 解析数据
    -- ----------------------------------------------------------------

    local tierInfo   = result.qualityTier or { name = "?", tier = 0 }
    local tierColor  = TIER_COLORS[tierInfo.tier] or "#E8E0D0"
    local finalScore = result.finalScore or 0
    local stepScores = result.stepScores or {}

    -- ----------------------------------------------------------------
    -- 绑定武器展示区
    -- ----------------------------------------------------------------

    -- 武器图
    local weaponImg = root:FindById("ph_l2_d")
    if weaponImg then
        local imgPath = result.weaponId and WEAPON_IMAGES[result.weaponId]
        if imgPath then
            weaponImg.backgroundImage = imgPath
        end
    end

    -- 武器名
    local weaponNameLabel = root:FindById("tx_f")
    if weaponNameLabel then
        weaponNameLabel.text = result.weaponName or "未知武器"
    end

    -- 品质标签
    local qualityLabel = root:FindById("tx_g")
    if qualityLabel then
        qualityLabel.text = "· " .. tierInfo.name .. " ·"
        qualityLabel.fontColor = tierColor
    end

    -- 标题
    local titleLabel = root:FindById("tx_2")
    if titleLabel then
        if tierInfo.tier >= 4 then
            titleLabel.text = "名 器 · 出 炉"
        elseif tierInfo.tier >= 3 then
            titleLabel.text = "佳 作 · 出 炉"
        else
            titleLabel.text = "作 品 · 完 成"
        end
    end

    -- ----------------------------------------------------------------
    -- 绑定评分条（最多4个维度）
    -- ----------------------------------------------------------------

    -- 评分行 IDs: row_p, row_v, row_11, row_17
    -- 维度名 IDs: tx_q, tx_w, tx_12, tx_18
    -- 进度条填充 IDs: sr_t, sr_z, sr_15, sr_1b
    -- 分数文字 IDs: tx_u, tx_10, tx_16, tx_1c

    local rowIds = { "row_p", "row_v", "row_11", "row_17" }
    local nameIds = { "tx_q", "tx_w", "tx_12", "tx_18" }
    local fillIds = { "sr_t", "sr_z", "sr_15", "sr_1b" }
    local scoreIds = { "tx_u", "tx_10", "tx_16", "tx_1c" }
    local maxBarWidth = 880  -- 进度条最大宽度（布局中约 879.88）

    for i = 1, 4 do
        local row = root:FindById(rowIds[i])
        if row then
            if i <= #stepScores then
                -- 有数据，显示该行
                row.visible = true
                local s = stepScores[i]
                local stepName = STEP_NAMES[s.stepType] or s.stepType or ("步骤 " .. i)
                local scoreVal = math.floor((s.score or 0) * 100 + 0.5)

                local nameLabel = root:FindById(nameIds[i])
                if nameLabel then nameLabel.text = stepName end

                local fill = root:FindById(fillIds[i])
                if fill then
                    fill.width = math.floor(scoreVal / 100 * maxBarWidth)
                    fill.backgroundColor = BAR_COLORS[i] or "#4F7A63"
                end

                local scoreTx = root:FindById(scoreIds[i])
                if scoreTx then
                    scoreTx.text = scoreVal .. " / 100"
                    scoreTx.fontColor = BAR_COLORS[i] or "#4F7A63"
                end
            else
                -- 无数据，隐藏该行
                row.visible = false
            end
        end
    end

    -- ----------------------------------------------------------------
    -- 总评级
    -- ----------------------------------------------------------------

    local totalBadge = root:FindById("sr_1f")
    if totalBadge then
        totalBadge.backgroundColor = tierColor
    end

    local totalLabel = root:FindById("tx_1g")
    if totalLabel then
        totalLabel.text = tierInfo.name .. " · " .. tostring(math.floor(finalScore + 0.5)) .. " 分"
    end

    -- ----------------------------------------------------------------
    -- 客户评语
    -- ----------------------------------------------------------------

    local reviewerLabel = root:FindById("tx_1n")
    if reviewerLabel then
        local reviewer = result.customerName or "铁匠铺"
        reviewerLabel.text = reviewer .. " · 评语"
    end

    local reviewText = root:FindById("tx_1o")
    if reviewText then
        local comment = result.comment or "不错的作品。"
        reviewText.text = "\"" .. comment .. "\""
    end

    -- ----------------------------------------------------------------
    -- 奖励显示
    -- ----------------------------------------------------------------

    -- 铜钱
    local coinsValue = root:FindById("tx_24")
    if coinsValue then
        coinsValue.text = "+" .. tostring(result.rewardCoins or 0)
    end

    -- 声望
    local fameValue = root:FindById("tx_29")
    if fameValue then
        fameValue.text = "+" .. tostring(result.rewardFame or 0)
    end

    -- 熟练度（第三个奖励槽）
    local skillLabel = root:FindById("tx_2d")
    local skillValue = root:FindById("tx_2e")
    if skillLabel then skillLabel.text = "熟练度" end
    if skillValue then
        skillValue.text = "+" .. tostring(result.skillExp or 0)
    end

    -- 第四个奖励槽（剧情碎片/额外材料）
    local bonusLabel = root:FindById("tx_2i")
    local bonusValue = root:FindById("tx_2j")
    local bonusMats = result.bonusMaterials or {}
    local hasBonus = false
    for mat, count in pairs(bonusMats) do
        if bonusLabel then bonusLabel.text = mat end
        if bonusValue then bonusValue.text = "x " .. tostring(count) end
        hasBonus = true
        break  -- 只显示第一个额外奖励
    end
    if not hasBonus then
        -- 隐藏第四个槽
        local rew4 = root:FindById("rew_2f")
        if rew4 then rew4.visible = false end
    end

    -- 首次锻造：显示入图鉴按钮
    local codexBtn = root:FindById("plate_1v")
    if codexBtn then
        codexBtn.visible = result.isFirstForge == true
    end

    -- ----------------------------------------------------------------
    -- 按钮事件
    -- ----------------------------------------------------------------

    -- 交付订单
    local deliverBtn = root:FindById("plate_1p")
    if deliverBtn then
        deliverBtn.props.onClick = function()
            ScreenRouter.GoTo("home")
        end
    end

    -- 广告双倍奖励
    local adBtn = root:FindById("plate_1s")
    if adBtn then
        adBtn.props.onClick = function()
            -- TODO: 播放广告逻辑
            print("[ResultScreen] Ad double reward requested")
            ScreenRouter.GoTo("home")
        end
    end

    -- 入图鉴
    if codexBtn then
        codexBtn.props.onClick = function()
            ScreenRouter.GoTo("codex")
        end
    end

    -- ----------------------------------------------------------------
    -- 音效
    -- ----------------------------------------------------------------

    SFXManager.StopAllLoops()
    SFXManager.Play(SFXManager.SFX.FORGE_COMPLETE, 0.8)

    if tierInfo.tier >= 3 then
        SFXManager.Play(SFXManager.SFX.QUALITY_UP, 0.5)
    end

    if result.isFirstForge then
        SFXManager.Play(SFXManager.SFX.UI_SUCCESS, 0.4)
    end

    print("[ResultScreen] Displayed: " .. (result.weaponName or "?")
        .. " | " .. tierInfo.name
        .. " | Score=" .. tostring(math.floor(finalScore + 0.5)))

    return screen
end

return ResultScreen
