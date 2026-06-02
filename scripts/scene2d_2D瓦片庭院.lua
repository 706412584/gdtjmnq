-- ============================================================================
-- scene2d_2D瓦片庭院.lua — UrhoX 原生 2D 场景节点
-- 修复方案：瓦片用 customMaterial+DiffUnlit+GetSubimage；角色用 textureRect UV裁剪
-- SpriteSheet2D:new() 不被支持，已全部绕过
---@diagnostic disable: undefined-global
-- ============================================================================

local M = {}

-- ── 工具函数 ──

--- 获取一个 pow2 纹理的 Sprite2D 作为 dummy（customMaterial 模式需要一个基底 Sprite）
local dummySprite_ = nil
local function getDummySprite()
    if dummySprite_ then return dummySprite_ end
    -- 使用第一个瓦片集（pow2 纹理）作为 dummy 来源
    dummySprite_ = cache:GetResource("Sprite2D", "image/topdown-basic/TX_Tileset_Grass.png")
    return dummySprite_
end

--- 为指定瓦片创建裁剪材质（customMaterial + DiffUnlit.xml）
--- tileSize: 像素大小, img: Image对象, sx,sy: 起始像素坐标
local function createTileMaterial(img, sx, sy, tileSize)
    -- 裁剪子图
    local subImg = img:GetSubimage(IntRect(sx, sy, sx + tileSize, sy + tileSize))
    if not subImg then return nil end

    -- 创建 Texture2D 并写入数据
    local tex = Texture2D:new()
    tex:SetNumLevels(1)
    tex:SetFilterMode(FILTER_NEAREST)
    tex:SetAddressMode(COORD_U, ADDRESS_CLAMP)
    tex:SetAddressMode(COORD_V, ADDRESS_CLAMP)
    tex:SetData(subImg)

    -- 创建无光照材质
    local mat = Material:new()
    mat:SetTechnique(0, cache:GetResource("Technique", "Techniques/DiffUnlit.xml"))
    mat:SetTexture(0, tex)  -- TU_DIFFUSE = 0
    mat:SetShaderParameter("MatDiffColor", Variant(Color(1, 1, 1, 1)))
    return mat
end

--- 设置角色精灵（textureRect 模式，避开 non-pow2 问题）
--- sheetPath: 精灵表 PNG 路径
--- frameIdx: 帧索引（从0开始）
--- frameCount: 总帧数
--- frameW, frameH: 每帧像素尺寸
local function setCharFrame(spr, sheetPath, frameIdx, frameCount, flipX)
    local sprite2d = cache:GetResource("Sprite2D", sheetPath)
    if not sprite2d then return end

    spr:SetSprite(sprite2d)
    spr:SetUseTextureRect(true)

    -- 计算 UV 坐标
    local u0 = frameIdx / frameCount
    local u1 = (frameIdx + 1) / frameCount

    -- Y 翻转：Rect(u0, 1.0, u1, 0.0) 因引擎 UV 坐标系
    if flipX then
        -- flipX = 交换 U0/U1
        spr.textureRect = Rect(u1, 1.0, u0, 0.0)
    else
        spr.textureRect = Rect(u0, 1.0, u1, 0.0)
    end
end

-- ── 构建场景 ──

function M.Build(scene_)
    local nodes = {}

    -- ═══ 瓦片地图：用 customMaterial + DiffUnlit + Image:GetSubimage ═══
    do
        local tileSize = 32
        local cols = 20
        local originX, originY, tileW = 0, 4.16, 0.32
        local tilesets = {
            "image/topdown-basic/TX_Tileset_Grass.png",
            "image/topdown-basic/TX_Tileset_Stone_Ground.png",
            "image/topdown-basic/TX_Tileset_Wall.png",
        }

        -- 预加载 Image 对象和列数
        local tileImages = {}
        local tileCols = {}
        for i, path in ipairs(tilesets) do
            local img = cache:GetResource("Image", path)
            tileImages[i] = img
            if img then
                tileCols[i] = math.max(1, math.floor(img:GetWidth() / tileSize))
            else
                tileCols[i] = 1
            end
        end

        -- 材质缓存（避免重复创建相同瓦片的材质）
        local matCache = {}

        local dummy = getDummySprite()

        local data = {
            131185, 131185, 131185, 131185, 131185, 131185, 131185, 131185, 131185, 131185, 131185, 131185, 131185, 131185, 131185, 131185, 131185, 131185, 131185, 131185,
            131185, 0, 12, 0, 13, 0, 14, 0, 0, 0, 0, 0, 0, 6, 0, 12, 0, 13, 0, 131185,
            131185, 0, 12, 0, 13, 0, 14, 0, 0, 0, 0, 0, 0, 6, 0, 12, 0, 13, 0, 131185,
            131185, 0, 12, 0, 65536, 65537, 65537, 65537, 65537, 65537, 65537, 65537, 65537, 65537, 65537, 65538, 0, 13, 0, 131185,
            131185, 0, 12, 0, 65544, 65545, 65545, 65548, 65545, 65545, 65574, 65545, 65540, 65545, 65545, 65546, 0, 13, 0, 131185,
            131185, 0, 12, 0, 65544, 65566, 65545, 65545, 65545, 65545, 65548, 65545, 65545, 65574, 65545, 65546, 0, 13, 0, 131185,
            131185, 0, 12, 0, 65544, 65540, 65545, 65545, 65566, 65545, 65545, 65545, 65545, 65548, 65545, 65546, 0, 13, 0, 131185,
            131185, 0, 12, 0, 65544, 65545, 65574, 65545, 65540, 65545, 65545, 65566, 65545, 65545, 65545, 65546, 0, 13, 0, 131185,
            131185, 0, 12, 0, 65544, 65545, 65548, 65545, 65545, 65574, 65545, 65540, 65545, 65545, 65566, 65546, 0, 13, 0, 131185,
            131185, 0, 12, 0, 65552, 65553, 65553, 65553, 65553, 65553, 65553, 65553, 65553, 65553, 65553, 65554, 0, 13, 0, 131185,
            131185, 0, 12, 0, 13, 0, 14, 0, 0, 0, 0, 0, 0, 6, 0, 12, 0, 13, 0, 131185,
            131185, 0, 12, 0, 13, 0, 14, 0, 0, 0, 0, 0, 0, 6, 0, 12, 0, 13, 0, 131185,
            131185, 131185, 131185, 131185, 131185, 131185, 131185, 131185, 131185, 131185, 131185, 131185, 131185, 131185, 131185, 131185, 131185, 131185, 131185, 131185,
        }

        for i = 1, #data do
            local v = data[i]
            if v >= 0 then
                local tsetIdx = math.floor(v / 65536) % 256
                local tileIdx = v % 65536
                local tsetLua = tsetIdx + 1  -- Lua 1-based

                local img = tileImages[tsetLua]
                if img and dummy then
                    -- 缓存 key
                    local cacheKey = tsetLua .. "_" .. tileIdx
                    local mat = matCache[cacheKey]
                    if not mat then
                        local numCols = tileCols[tsetLua]
                        local sx = (tileIdx % numCols) * tileSize
                        local sy = math.floor(tileIdx / numCols) * tileSize
                        mat = createTileMaterial(img, sx, sy, tileSize)
                        matCache[cacheKey] = mat
                    end

                    if mat then
                        local col = (i - 1) % cols
                        local row = math.floor((i - 1) / cols)
                        local t = scene_:CreateChild("tile_" .. i)
                        t:SetPosition2D(originX + (col + 0.5) * tileW, originY - (row + 0.5) * tileW)
                        local s = t:CreateComponent("StaticSprite2D")
                        s.layer = 0
                        s.sprite = dummy
                        s.useDrawRect = true
                        s.drawRect = Rect(-tileW / 2, -tileW / 2, tileW / 2, tileW / 2)
                        s.customMaterial = mat
                    end
                end
            end
        end
    end

    -- ═══ 独立容器 Props（树木、木桶、建筑等）— textureRect 从 512x512 纹理裁切 ═══
    -- 关键：customMaterial 与 textureRect 互斥，props 用 textureRect（非 pow2 子图 WebGL 兼容）
    do
        -- 坐标转换：CSS像素 × 0.01 = 世界米（布局编辑器视口 640×416 = 6.4×4.16m）
        -- worldX = (left + w/2) * 0.01, worldY = 4.16 - (top + h/2) * 0.01
        -- drawW = w * 0.01, drawH = h * 0.01
        local propsData = {
            -- { x, y, dw, dh, tex, u0, v0, u1, v1 }
            { 0.7835, 3.2384, 0.8295, 1.0241, "image/topdown-basic/TX_Plant.png", 0.0461, 0.0271, 0.2709, 0.3046 },
            { 5.6735, 3.2486, 0.6964, 1.0036, "image/topdown-basic/TX_Plant.png", 0.3144, 0.0325, 0.5031, 0.3045 },
            { 0.7681, 0.9136, 0.6349, 0.9627, "image/topdown-basic/TX_Plant.png", 0.5764, 0.0602, 0.7356, 0.3014 },
            { 5.6582, 0.9649, 0.8295, 1.0241, "image/topdown-basic/TX_Plant.png", 0.0461, 0.0271, 0.2709, 0.3046 },
            { 1.7768, 3.3305, 0.4813, 0.4301, "image/topdown-basic/TX_Plant.png", 0.4219, 0.3613, 0.5159, 0.4453 },
            { 5.0181, 3.4073, 0.4096, 0.3584, "image/topdown-basic/TX_Plant.png", 0.6758, 0.3711, 0.7558, 0.4411 },
            { 1.1777, 0.4323, 0.3892, 0.3277, "image/topdown-basic/TX_Plant.png", 0.3047, 0.3711, 0.3807, 0.4351 },
            { 5.5250, 0.4886, 0.3994, 0.4608, "image/topdown-basic/TX_Plant.png", 0.5508, 0.3633, 0.6288, 0.4533 },
            { 1.7000, 2.5727, 0.3277, 0.4711, "image/topdown-basic/TX_Props.png", 0.3125, 0.0352, 0.3765, 0.1272 },
            { 1.1317, 1.6100, 0.2151, 0.3482, "image/topdown-basic/TX_Props.png", 0.3223, 0.4238, 0.3643, 0.4918 },
            { 5.0642, 2.5625, 0.3789, 0.7373, "image/topdown-basic/TX_Props.png", 0.8691, 0.0410, 0.9431, 0.1850 },
            { 4.9976, 0.7959, 0.3277, 0.5837, "image/topdown-basic/TX_Props.png", 0.5625, 0.3086, 0.6265, 0.4226 },
            { 1.1214, 0.9239, 0.2765, 0.3277, "image/topdown-basic/TX_Props.png", 0.1934, 0.3125, 0.2474, 0.3765 },
            { 3.2772, 3.5865, 0.8193, 0.6554, "image/topdown-basic/TX_Struct.png", 0.7969, 0.0527, 0.9569, 0.1807 },
        }

        for i, p in ipairs(propsData) do
            local wx, wy, dw, dh, texPath, u0, v0, u1, v1 = p[1], p[2], p[3], p[4], p[5], p[6], p[7], p[8], p[9]
            local sprite2d = cache:GetResource("Sprite2D", texPath)
            if sprite2d then
                local n = scene_:CreateChild("prop_" .. i)
                n:SetPosition2D(wx, wy)
                local spr = n:CreateComponent("StaticSprite2D")
                spr.blendMode = BLEND_ALPHA
                spr.layer = 5  -- 介于瓦片(0)和角色(10)之间
                spr:SetSprite(sprite2d)
                spr:SetUseTextureRect(true)
                -- Rect(uLeft, vBottom, uRight, vTop): V=0=图顶, V=1=图底
                -- v0=srcY/512(图上方,小值)=quad顶部, v1=(srcY+srcH)/512(图下方,大值)=quad底部
                spr.textureRect = Rect(u0, v1, u1, v0)
                spr.useDrawRect = true
                spr.drawRect = Rect(-dw / 2, -dh / 2, dw / 2, dh / 2)
            end
        end
    end

    -- ═══ 碰撞体（8个精确碰撞体 + 4面边界墙）═══
    -- 来自布局编辑器导出的原始碰撞数据
    do
        -- 8 个场景内精确碰撞体（树木、建筑等障碍物）
        local colliders = {
            { name = "collider_vxld7di3", x = 0.7886, y = 2.8595, w = 0.2253, h = 0.1843 },
            { name = "collider_qq438qgo", x = 5.6735, y = 2.8799, w = 0.2048, h = 0.1843 },
            { name = "collider_v9svssv9", x = 0.7681, y = 0.586,  w = 0.1843, h = 0.1843 },
            { name = "collider_b657cd7y", x = 5.6633, y = 0.586,  w = 0.2253, h = 0.1843 },
            { name = "collider_rpic8tbr", x = 1.7,    y = 2.5112, w = 0.2867, h = 0.3072 },
            { name = "collider_wsk57e8c", x = 1.1317, y = 1.5486, w = 0.1741, h = 0.1843 },
            { name = "collider_wczc26qy", x = 5.0642, y = 2.3269, w = 0.297,  h = 0.2253 },
            { name = "collider_ybg33qjw", x = 4.9976, y = 0.6269, w = 0.2867, h = 0.2253 },
        }
        for _, c in ipairs(colliders) do
            local n = scene_:CreateChild(c.name)
            n:SetPosition2D(c.x, c.y)
            local body = n:CreateComponent("RigidBody2D")
            body.bodyType = BT_STATIC
            local shape = n:CreateComponent("CollisionBox2D")
            shape:SetSize(c.w, c.h)
            shape.density = 1.0
            shape.categoryBits = 1
            shape.maskBits = 65535
            n:SetVar("tag", Variant("obstacle"))
            nodes[c.name] = n
        end

        -- 4 面边界墙（防止角色移出地图）
        local sceneW, sceneH = 6.4, 4.16
        local thickness = 0.4
        local walls = {
            { name = "wall_top",    x = sceneW / 2, y = sceneH + thickness / 2, w = sceneW + thickness * 2, h = thickness },
            { name = "wall_bottom", x = sceneW / 2, y = -thickness / 2,          w = sceneW + thickness * 2, h = thickness },
            { name = "wall_left",   x = -thickness / 2, y = sceneH / 2,          w = thickness, h = sceneH + thickness * 2 },
            { name = "wall_right",  x = sceneW + thickness / 2, y = sceneH / 2,  w = thickness, h = sceneH + thickness * 2 },
        }
        for _, wall in ipairs(walls) do
            local n = scene_:CreateChild(wall.name)
            n:SetPosition2D(wall.x, wall.y)
            local body = n:CreateComponent("RigidBody2D")
            body.bodyType = BT_STATIC
            local shape = n:CreateComponent("CollisionBox2D")
            shape:SetSize(wall.w, wall.h)
            shape.categoryBits = 1
            shape.maskBits = 65535
            n:SetVar("tag", Variant("obstacle"))
            nodes[wall.name] = n
        end
    end

    -- ═══ 敌人（textureRect 模式）═══
    do
        local n = scene_:CreateChild("enemy2d_pizmmnvi")
        n:SetPosition2D(4.8338, 2.0298)
        nodes["enemy2d_pizmmnvi"] = n
        local spr = n:CreateComponent("StaticSprite2D")
        spr.blendMode = BLEND_ALPHA
        spr.layer = 10
        spr.useDrawRect = true
        spr.drawRect = Rect(-0.4097, -0.4097, 0.4097, 0.4097)
        -- 用 textureRect 设置初始帧
        setCharFrame(spr, "image/topdown-basic/chars/Orc-Idle.png", 0, 6, false)
        local body = n:CreateComponent("RigidBody2D")
        body.bodyType = BT_DYNAMIC
        body.fixedRotation = true
        body.gravityScale = 0
        local shape = n:CreateComponent("CollisionBox2D")
        shape:SetSize(0.35, 0.35)
        shape:SetCenter(0, -0.10)  -- 偏移到脚部区域
        shape.categoryBits = 8
        shape.maskBits = 35
        shape.density = 1.0
        n:SetVar("spawnX", Variant(4.8338))
    end

    -- ═══ 玩家（textureRect 模式）═══
    do
        local n = scene_:CreateChild("charactercontroller2d_alob7hhu")
        n:SetPosition2D(2.8675, 2.0298)
        nodes["charactercontroller2d_alob7hhu"] = n
        local spr = n:CreateComponent("StaticSprite2D")
        spr.blendMode = BLEND_ALPHA
        spr.layer = 10
        spr.useDrawRect = true
        spr.drawRect = Rect(-0.4097, -0.4097, 0.4097, 0.4097)
        -- 用 textureRect 设置初始帧
        setCharFrame(spr, "image/topdown-basic/chars/Soldier-Idle.png", 0, 6, false)
        local body = n:CreateComponent("RigidBody2D")
        body.bodyType = BT_DYNAMIC
        body.fixedRotation = true
        body.gravityScale = 0
        local shape = n:CreateComponent("CollisionBox2D")
        shape:SetSize(0.40, 0.40)
        shape:SetCenter(0, -0.12)  -- 偏移到脚部区域
        shape.categoryBits = 2
        shape.maskBits = 89
        shape.density = 1.0
    end

    -- 导出 setCharFrame 供 logic 使用
    M.setCharFrame = setCharFrame

    return nodes
end

return M
