-- ============================================================================
-- 《问道长生》世界数据配置 (区域/怪物/灵宠/试炼/任务)
-- 数据来源: docs/game-design-values.md §9, §10, §11, §13
-- ============================================================================

local M = {}

-- ============================================================================
-- 9.1 探索区域
-- ============================================================================
-- unlockTier/unlockSub: 解锁所需大境界阶数/小境界索引
-- ============================================================================
M.AREAS = {
    { id = "yunwu",    name = "云雾山",   levelRange = { 1, 10 },  drops = { "灵草", "矿石" },          unlockTier = 1, unlockSub = 1, desc = "云雾缭绕的山脉，适合初入修行之人历练。" },
    { id = "tianque",  name = "天阙遗迹", levelRange = { 10, 20 }, drops = { "功法残页", "灵石" },       unlockTier = 3, unlockSub = 1, desc = "上古遗迹，危机四伏但机缘不少。" },
    { id = "donghai",  name = "东海海滨", levelRange = { 15, 25 }, drops = { "海珠", "灵贝" },           unlockTier = 4, unlockSub = 1, desc = "东海之滨，海妖出没之地。" },
    { id = "fushan",   name = "夫山遗迹", levelRange = { 20, 30 }, drops = { "古器碎片", "秘境钥匙" },   unlockTier = 5, unlockSub = 1, desc = "神秘的上古大能洞府遗址。" },
}

-- ============================================================================
-- 9.2 怪物列表
-- ============================================================================
-- areaId: 所属区域id
-- levelRange: 建议等级范围
-- isBoss: 是否Boss
-- ============================================================================
M.MONSTERS = {
    { id = 1,  name = "野狼",     areaId = "yunwu",   levelRange = { 1, 5 },   isBoss = false },
    { id = 2,  name = "山贼",     areaId = "yunwu",   levelRange = { 3, 8 },   isBoss = false },
    { id = 3,  name = "毒蛇",     areaId = "yunwu",   levelRange = { 5, 10 },  isBoss = false },
    { id = 4,  name = "骷髅兵",   areaId = "tianque", levelRange = { 8, 12 },  isBoss = false },
    { id = 5,  name = "树妖",     areaId = "yunwu",   levelRange = { 10, 15 }, isBoss = false },
    { id = 6,  name = "火虎",     areaId = "tianque", levelRange = { 12, 18 }, isBoss = false },
    { id = 7,  name = "石魔",     areaId = "tianque", levelRange = { 15, 20 }, isBoss = false },
    { id = 8,  name = "狐妖",     areaId = "donghai", levelRange = { 18, 22 }, isBoss = false },
    { id = 9,  name = "怨灵",     areaId = "tianque", levelRange = { 20, 25 }, isBoss = false },
    { id = 10, name = "熔岩魔像", areaId = "fushan",  levelRange = { 22, 28 }, isBoss = false },
    { id = 11, name = "蜘蛛精",   areaId = "yunwu",   levelRange = { 10, 15 }, isBoss = false },
    { id = 12, name = "僵尸",     areaId = "tianque", levelRange = { 12, 18 }, isBoss = false },
    { id = 13, name = "天狗",     areaId = "donghai", levelRange = { 18, 22 }, isBoss = false },
    { id = 14, name = "金鹰",     areaId = "donghai", levelRange = { 15, 20 }, isBoss = false },
    { id = 15, name = "冰熊",     areaId = "donghai", levelRange = { 20, 25 }, isBoss = false },
    { id = 16, name = "邪僧",     areaId = "fushan",  levelRange = { 22, 28 }, isBoss = false },
    { id = 17, name = "螳螂精",   areaId = "yunwu",   levelRange = { 8, 12 },  isBoss = false },
    { id = 18, name = "地狱犬",   areaId = "fushan",  levelRange = { 25, 30 }, isBoss = false },
    { id = 19, name = "刺客",     areaId = "fushan",  levelRange = { 20, 25 }, isBoss = false },
    { id = 20, name = "龙Boss",   areaId = "fushan",  levelRange = { 30, 30 }, isBoss = true },
}

-- ============================================================================
-- 10.1 灵宠列表
-- ============================================================================
-- quality: 品质key (common/uncommon/rare/epic/legend/mythic)
-- role: 攻击/防御/辅助
-- ============================================================================
M.PETS = {
    { id = 1,  name = "白狐",         quality = "uncommon", role = "辅助", skill = "灵狐附体",   image = "image/pet_01_whitefox.png",     desc = "温顺灵巧的白狐幼崽，能提升主人闪避" },
    { id = 2,  name = "灵兔",         quality = "common",   role = "辅助", skill = "月华护盾",   image = "image/pet_02_rabbit.png",       desc = "通灵玉兔，月光下能为主人提供护盾" },
    { id = 3,  name = "火鸟",         quality = "rare",     role = "攻击", skill = "烈焰冲击",   image = "image/pet_03_firebird.png",     desc = "浴火而生的灵鸟，能释放火焰攻击" },
    { id = 4,  name = "青龙",         quality = "epic",     role = "攻击", skill = "龙息吐纳",   image = "image/pet_04_greendragon.png",  desc = "青龙幼崽，龙族血脉提升修炼速度" },
    { id = 5,  name = "蝴蝶",         quality = "common",   role = "辅助", skill = "迷梦粉尘",   image = "image/pet_05_butterfly.png",    desc = "如玉般通透的蝴蝶，可使敌人昏迷" },
    { id = 6,  name = "黑猫",         quality = "uncommon", role = "辅助", skill = "暗影潜行",   image = "image/pet_06_blackcat.png",     desc = "神秘黑猫，能隐入暗影辅助偷袭" },
    { id = 7,  name = "仙鹤",         quality = "rare",     role = "辅助", skill = "仙鹤引路",   image = "image/pet_07_crane.png",        desc = "仙家之鹤，能引领主人寻找机缘" },
    { id = 8,  name = "雷貂",         quality = "rare",     role = "攻击", skill = "雷光闪击",   image = "image/pet_08_thundermink.png",  desc = "体蕴雷电的灵貂，速度极快" },
    { id = 9,  name = "水鱼",         quality = "uncommon", role = "防御", skill = "治愈水泡",   image = "image/pet_09_waterfish.png",    desc = "水系灵鱼，能在战斗中治愈主人" },
    { id = 10, name = "灵鹿",         quality = "uncommon", role = "辅助", skill = "草木回春",   image = "image/pet_10_deer.png",         desc = "灵山之鹿，精通草木之道" },
    { id = 11, name = "玄龟",         quality = "rare",     role = "防御", skill = "龟甲壁障",   image = "image/pet_11_turtle.png",       desc = "万年灵龟，防御力极其强大" },
    { id = 12, name = "灵鼠",         quality = "common",   role = "辅助", skill = "寻宝嗅觉",   image = "image/pet_12_mouse.png",        desc = "机灵小鼠，擅长发现隐藏宝物" },
    { id = 13, name = "蜗牛",         quality = "common",   role = "防御", skill = "缓速结界",   image = "image/pet_13_snail.png",        desc = "通体如玉的蜗牛，能减缓敌人速度" },
    { id = 14, name = "金鸟",         quality = "legend",   role = "辅助", skill = "鹏翼天击",   image = "image/pet_14_goldbird.png",     desc = "大鹏一展翅，天地为之震颤" },
    { id = 15, name = "冰狐",         quality = "rare",     role = "攻击", skill = "冰封千里",   image = "image/pet_15_icefox.png",       desc = "极寒之狐，能冻结大范围敌人" },
    -- 四神兽 (神话)
    { id = 16, name = "青龙",         quality = "mythic",   role = "攻击", skill = "苍龙七宿",   image = "image/pet_16_qinglong.png",     desc = "东方神兽，掌管春雷万物生长，龙威震慑一切妖邪" },
    { id = 17, name = "白虎",         quality = "mythic",   role = "攻击", skill = "虎啸山林",   image = "image/pet_17_baihu.png",        desc = "西方神兽，主杀伐之力，虎啸一声百兽臣服" },
    { id = 18, name = "朱雀",         quality = "mythic",   role = "攻击", skill = "涅槃天火",   image = "image/pet_18_zhuque.png",       desc = "南方神兽，浴火重生永恒不灭，天火焚尽一切" },
    { id = 19, name = "玄武",         quality = "mythic",   role = "防御", skill = "龟蛇玄甲",   image = "image/pet_19_xuanwu.png",       desc = "北方神兽，龟蛇合体固若金汤，万法不侵" },
}

-- ============================================================================
-- 11. 试炼列表
-- ============================================================================
M.TRIALS = {
    { id = "wanyao",   name = "万妖塔",   type = "闯关", maxFloor = 100, rewards = { "灵石x200", "培元丹x3" },     unlockTier = nil, desc = "逐层挑战妖兽，层数越高奖励越丰厚。" },
    { id = "mijing",   name = "秘境试炼", type = "限时", timeLimit = 1800, rewards = { "功法残页x1", "灵石x500" },  unlockTier = nil, desc = "限时击败尽可能多的敌人，按击杀数结算奖励。" },
    { id = "shengsi",  name = "生死擂台", type = "生存", maxFloor = nil, rewards = { "洗髓丹x1", "灵石x300" },      unlockTier = nil, desc = "无尽波次的敌人来袭，坚持越久奖励越多。" },
    { id = "xianmo",   name = "仙魔战场", type = "闯关", maxFloor = 50,  rewards = { "仙石x10", "天材地宝x1" },    unlockTier = 4,   desc = "仙魔两族交战之地，需金丹期以上方可进入。" },
}

-- ============================================================================
-- 13. 任务定义
-- ============================================================================

-- 13.2 主线任务
M.MAIN_QUESTS = {
    { id = "mq1", name = "初入修途", desc = "完成角色创建",       condition = "创角完成",  reward = "灵石x200",   rewardItems = { ["灵石"] = 200 } },
    { id = "mq2", name = "首次修炼", desc = "洞府静修1次",        condition = "静修1次",   reward = "培元丹x3",   rewardItems = { ["培元丹"] = 3 } },
    { id = "mq3", name = "出师下山", desc = "首次游历",           condition = "游历1次",   reward = "灵石x300",   rewardItems = { ["灵石"] = 300 } },
    { id = "mq4", name = "筑基之路", desc = "修为达到5000",       condition = "修为>=5000", reward = "筑基丹x1",  rewardItems = { ["筑基丹"] = 1 } },
    { id = "mq5", name = "首入坊市", desc = "购买任意物品",       condition = "购买1件",   reward = "灵石x100",   rewardItems = { ["灵石"] = 100 } },
}

-- 13.1 每日任务模板
M.DAILY_QUESTS = {
    { id = "dq1", name = "每日修炼", desc = "静修1次",        maxProgress = 1, reward = "灵石x50",   rewardItems = { ["灵石"] = 50 } },
    { id = "dq2", name = "采集灵草", desc = "采集灵草3株",    maxProgress = 3, reward = "灵草x5",    rewardItems = { ["灵草"] = 5 } },
    { id = "dq3", name = "击败妖兽", desc = "击败任意妖兽5只", maxProgress = 5, reward = "灵石x100",  rewardItems = { ["灵石"] = 100 } },
    { id = "dq4", name = "炼丹修行", desc = "成功炼丹1次",    maxProgress = 1, reward = "培元丹x2",  rewardItems = { ["培元丹"] = 2 } },
}

-- ============================================================================
-- 辅助函数
-- ============================================================================

--- 根据id获取区域
---@param id string
---@return table|nil
function M.GetArea(id)
    for _, a in ipairs(M.AREAS) do
        if a.id == id then return a end
    end
    return nil
end

--- 获取指定区域的怪物列表
---@param areaId string
---@return table
function M.GetMonstersByArea(areaId)
    local result = {}
    for _, m in ipairs(M.MONSTERS) do
        if m.areaId == areaId then
            result[#result + 1] = m
        end
    end
    return result
end

--- 根据id获取灵宠
---@param id number
---@return table|nil
function M.GetPet(id)
    return M.PETS[id]
end

--- 根据id获取试炼
---@param id string
---@return table|nil
function M.GetTrial(id)
    for _, t in ipairs(M.TRIALS) do
        if t.id == id then return t end
    end
    return nil
end

return M
