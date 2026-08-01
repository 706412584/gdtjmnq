---@diagnostic disable: param-type-mismatch
-- ============================================================================
-- WeeklyScreen - 周目标与声望榜
-- ============================================================================

local UI = require("urhox-libs/UI")
local WeeklyGoal = require("Core.WeeklyGoal")
local Leaderboard = require("Core.Leaderboard")
local ScreenRouter = require("Utils.ScreenRouter")
local SFXManager = require("Utils.SFXManager")

local WeeklyScreen = {}

local function RewardText(reward)
    local parts = {}
    if (reward.coins or 0) > 0 then parts[#parts + 1] = "铜钱 " .. reward.coins end
    if (reward.fame or 0) > 0 then parts[#parts + 1] = "声望 " .. reward.fame end
    return #parts > 0 and table.concat(parts, " · ") or "无"
end

function WeeklyScreen.Create(container, params)
    local screen = {}
    local goalRows = {}
    local rankRows = {}

    local title = UI.Label {
        text = "周目标与声望榜",
        fontSize = 30,
        fontColor = "#D4A574",
        fontWeight = 700,
    }
    local remainLabel = UI.Label {
        text = "本周剩余 " .. WeeklyGoal.GetTimeRemainingText(),
        fontSize = 16,
        fontColor = "#A0937D",
    }
    local rankStatus = UI.Label {
        text = "正在读取声望榜…",
        fontSize = 16,
        fontColor = "#A0937D",
    }

    local goalList = UI.Panel {
        width = "100%",
        flexDirection = "column",
        gap = 10,
    }
    local rankList = UI.Panel {
        width = "100%",
        flexDirection = "column",
        gap = 6,
    }

    local function RefreshGoals()
        local goals = WeeklyGoal.GetGoals()
        for i = 1, #goals do
            local goal = goals[i]
            local row = goalRows[i]
            if row then
                row.title.text = goal.title
                row.detail.text = goal.description .. "  " .. goal.progress .. "/" .. goal.target
                row.reward.text = "奖励：" .. RewardText(goal.reward)
                if goal.claimed then
                    row.button:SetDisabled(true)
                    row.button:SetText("已领取")
                elseif goal.completed then
                    row.button:SetDisabled(false)
                    row.button:SetText("领取")
                else
                    row.button:SetDisabled(true)
                    row.button:SetText("进行中")
                end
            end
        end
    end

    local goals = WeeklyGoal.GetGoals()
    for i = 1, #goals do
        local index = i
        local titleLabel = UI.Label { fontSize = 18, fontColor = "#E8E0D0", fontWeight = 700 }
        local detailLabel = UI.Label { fontSize = 14, fontColor = "#A0937D" }
        local rewardLabel = UI.Label { fontSize = 14, fontColor = "#4ECDC4" }
        local claimButton = UI.Button {
            text = "进行中",
            variant = "primary",
            height = 38,
            onClick = function()
                local ok, err = WeeklyGoal.ClaimReward(index)
                if ok then
                    SFXManager.Play(SFXManager.SFX.UI_COIN, 0.5)
                    UI.Toast.Show("周目标奖励已领取", { duration = 2 })
                    RefreshGoals()
                else
                    SFXManager.Play(SFXManager.SFX.UI_FAIL, 0.4)
                    UI.Toast.Show(tostring(err), { type = "warning", duration = 2 })
                end
            end,
        }
        goalRows[i] = { title = titleLabel, detail = detailLabel, reward = rewardLabel, button = claimButton }
        goalList:AddChild(UI.Panel {
            width = "100%",
            minHeight = 92,
            borderWidth = 1,
            borderColor = "#3D2B1F",
            borderRadius = 6,
            backgroundColor = "rgba(26,26,46,0.78)",
            flexDirection = "row",
            alignItems = "center",
            justifyContent = "space-between",
            paddingHorizontal = 14,
            children = {
                UI.Panel {
                    flexGrow = 1,
                    flexShrink = 1,
                    flexDirection = "column",
                    gap = 4,
                    children = { titleLabel, detailLabel, rewardLabel },
                },
                claimButton,
            },
        })
    end

    for i = 1, 8 do
        local label = UI.Label { text = "", fontSize = 15, fontColor = "#E8E0D0" }
        rankRows[i] = label
        rankList:AddChild(label)
    end

    local function RefreshRanks()
        rankStatus.text = "正在读取声望榜…"
        for i = 1, #rankRows do rankRows[i].text = "" end
        Leaderboard.FetchRankList("fame", #rankRows, function(entries)
            if #entries == 0 then
                rankStatus.text = "暂未取得排行榜数据"
                return
            end
            rankStatus.text = "声望榜"
            for i = 1, #entries do
                local entry = entries[i]
                local marker = entry.isMe and "  你" or ""
                rankRows[i].text = string.format("%d. %s   声望 %d%s", entry.rank, entry.nickname, entry.score, marker)
                rankRows[i].fontColor = entry.isMe and "#4ECDC4" or "#E8E0D0"
            end
        end)
    end

    local root = UI.Panel {
        width = "100%",
        height = "100%",
        flexDirection = "column",
        paddingTop = "4%",
        paddingBottom = "4%",
        paddingLeft = "5%",
        paddingRight = "5%",
        gap = 16,
        backgroundColor = "#12100E",
        children = {
            UI.Panel {
                width = "100%",
                flexDirection = "row",
                justifyContent = "space-between",
                alignItems = "center",
                children = {
                    UI.Button {
                        text = "返回工坊",
                        variant = "secondary",
                        height = 42,
                        onClick = function() ScreenRouter.GoTo("home") end,
                    },
                    UI.Panel { flexDirection = "column", alignItems = "center", children = { title, remainLabel } },
                    UI.Button {
                        text = "刷新榜单",
                        variant = "primary",
                        height = 42,
                        onClick = function()
                            SFXManager.Play(SFXManager.SFX.UI_TAP, 0.3)
                            RefreshRanks()
                        end,
                    },
                },
            },
            UI.Panel {
                width = "100%",
                flexGrow = 1,
                flexShrink = 1,
                flexDirection = "row",
                gap = 18,
                children = {
                    UI.Panel {
                        width = "58%",
                        flexDirection = "column",
                        gap = 10,
                        children = {
                            UI.Label { text = "本周委托", fontSize = 22, fontColor = "#D4A574", fontWeight = 700 },
                            goalList,
                        },
                    },
                    UI.Panel {
                        flexGrow = 1,
                        flexShrink = 1,
                        borderWidth = 1,
                        borderColor = "#3D2B1F",
                        borderRadius = 6,
                        backgroundColor = "rgba(26,26,46,0.78)",
                        paddingHorizontal = 16,
                        paddingVertical = 14,
                        flexDirection = "column",
                        gap = 10,
                        children = { rankStatus, rankList },
                    },
                },
            },
        },
    }
    container:AddChild(root)
    RefreshGoals()
    RefreshRanks()

    function screen.Update(dt)
        if WeeklyGoal.CheckRefresh() then
            remainLabel.text = "本周剩余 " .. WeeklyGoal.GetTimeRemainingText()
            RefreshGoals()
        end
    end
    return screen
end

return WeeklyScreen
