-- ============================================================================
-- MiniGameBase - 小游戏基类
-- Project Smith / P1-C1
--
-- 定义所有小游戏的统一生命周期接口。
-- 子类通过 MiniGameBase.Extend() 创建，只需覆写需要的方法。
-- ============================================================================

local MiniGameBase = {}
MiniGameBase.__index = MiniGameBase

--- 创建一个继承自 MiniGameBase 的子类
---@param overrides table|nil 要覆写的方法集合
---@return table 子类原型表
function MiniGameBase.Extend(overrides)
    local cls = setmetatable({}, { __index = MiniGameBase })
    cls.__index = cls
    if overrides then
        for k, v in pairs(overrides) do
            cls[k] = v
        end
    end
    return cls
end

--- 创建子类实例
---@return table
function MiniGameBase:new()
    local instance = setmetatable({}, self)
    -- 默认字段
    instance.finished_ = false
    instance.score_ = 0.0      -- 0.0 ~ 1.0
    instance.rating_ = "Poor"  -- Perfect/Great/Good/Poor
    instance.container_ = nil  -- UI 容器
    instance.config_ = nil     -- 初始化配置
    return instance
end

--- 初始化小游戏
---@param config table { difficulty:number, materialTier:number, facilityLevel:number, container:Widget }
function MiniGameBase:init(config)
    self.config_ = config
    self.container_ = config.container
    self.finished_ = false
    self.score_ = 0.0
    self.rating_ = "Poor"
end

--- 每帧更新（计时/动画/判定）
---@param dt number 帧间隔（秒）
function MiniGameBase:update(dt)
    -- 子类覆写
end

--- 触摸/鼠标按下
---@param x number 屏幕坐标 X
---@param y number 屏幕坐标 Y
function MiniGameBase:onTouchStart(x, y)
    -- 子类覆写
end

--- 触摸/鼠标移动
---@param x number 屏幕坐标 X
---@param y number 屏幕坐标 Y
function MiniGameBase:onTouchMove(x, y)
    -- 子类覆写
end

--- 触摸/鼠标释放
---@param x number 屏幕坐标 X
---@param y number 屏幕坐标 Y
function MiniGameBase:onTouchEnd(x, y)
    -- 子类覆写
end

--- 获取评分结果
---@return table { score:number(0.0~1.0), rating:string }
function MiniGameBase:getScore()
    return {
        score = self.score_,
        rating = self.rating_,
    }
end

--- 标记小游戏结束
---@param score number 0.0 ~ 1.0
---@param rating string "Perfect"|"Great"|"Good"|"Poor"
function MiniGameBase:finish(score, rating)
    self.score_ = score
    self.rating_ = rating
    self.finished_ = true
end

--- 小游戏是否已结束
---@return boolean
function MiniGameBase:isFinished()
    return self.finished_
end

--- 清理资源
function MiniGameBase:cleanup()
    -- 子类覆写以清理 NanoVG 资源等
    self.container_ = nil
    self.config_ = nil
end

return MiniGameBase
