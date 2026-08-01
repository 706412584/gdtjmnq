-- ============================================================================
-- TutorialManager - 首单交互教程
-- ============================================================================

local EventBus = require("Core.EventBus")
local GameState = require("Core.GameState")

local TutorialManager = {}

local FIRST_ORDER_ID = "ORD_T1_001"

local STAGES = {
    accept_order = true,
    choose_material = true,
    ore_select = true,
    forging = true,
    polishing = true,
    collect_result = true,
    complete = true,
}

local function GetData()
    local data = GameState.GetTutorial()
    if not STAGES[data.stage] then
        return { stage = "accept_order", completed = false }
    end
    return data
end

function TutorialManager.IsActive()
    return not GetData().completed
end

function TutorialManager.IsFirstOrder(orderId)
    return TutorialManager.IsActive() and orderId == FIRST_ORDER_ID
end

function TutorialManager.GetStage()
    return GetData().stage
end

function TutorialManager.IsStage(stage)
    return TutorialManager.IsActive() and GetData().stage == stage
end

function TutorialManager.Advance(stage)
    if not TutorialManager.IsActive() or not STAGES[stage] then
        return false
    end

    local data = GetData()
    if data.stage == stage then
        return false
    end

    GameState.SetTutorial({ stage = stage, completed = stage == "complete" })
    EventBus.Emit("tutorial_stage_changed", { stage = stage })
    print("[TutorialManager] Stage: " .. stage)
    return true
end

function TutorialManager.Complete()
    if not TutorialManager.IsActive() then return end
    GameState.CompleteTutorial()
    EventBus.Emit("tutorial_completed", { orderId = FIRST_ORDER_ID })
    print("[TutorialManager] First-order tutorial completed")
end

function TutorialManager.ResetForFirstOrder()
    if not TutorialManager.IsActive() then return end
    GameState.SetTutorial({ stage = "accept_order", completed = false })
    EventBus.Emit("tutorial_stage_changed", { stage = "accept_order" })
    print("[TutorialManager] Reset after first-order cancellation")
end

function TutorialManager.GetMessage(stage)
    local messages = {
        accept_order = "先接下猎户的委托。首单会带你熟悉完整锻造流程。",
        choose_material = "首单使用粗料即可。确认材料品质后，材料会立即扣除。",
        ore_select = "先挑出杂质最少的矿石。跟随界面提示操作，失误可免费重试一次。",
        forging = "锻打要跟住节拍。宁可稳住节奏，也不要连续抢拍。",
        polishing = "最后研磨开刃。保持操作直到进度完成，成品就能交付。",
        collect_result = "首件作品完成。查看品质和奖励后，返回工坊继续经营。",
    }
    return messages[stage] or ""
end

return TutorialManager
