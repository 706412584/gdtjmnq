-- ============================================================================
-- scene2d_2D瓦片庭院.lua — UrhoX 原生 2D 场景节点（由 layout-editor 生成）
-- 坐标已按 PIXEL_SIZE=0.01 + Y 翻转换算为世界米。
---@diagnostic disable: undefined-global
-- ============================================================================

local M = {}

-- 构建 2D 场景节点，返回 id->Node 表供 logic 引用。
-- scene_ 由 main.lua 传入（已挂 Octree + PhysicsWorld2D）。
function M.Build(scene_)
    local nodes = {}
    -- TileMap2D tilemap2d_3s7u0vwu: 逐格 StaticSprite2D（运行时按纹理宽切图，sheetCols = floor(texWidth/tileSize)）
    do
        local tileSize = 32
        local cols = 20
        local originX, originY, tileW = 0, 4.16, 0.32
        local tilesets = { "image/topdown-basic/TX_Tileset_Grass.png", "image/topdown-basic/TX_Tileset_Stone_Ground.png", "image/topdown-basic/TX_Tileset_Wall.png" }
        nodes["__tiles_tilemap2d_3s7u0vwu"] = {}
        local sheets = nodes["__tiles_tilemap2d_3s7u0vwu"]
        local function tileSprite(tsetIdx, tileIdx)
            local entry = sheets[tsetIdx]
            if entry == nil then
                local tex = cache:GetResource("Texture2D", tilesets[tsetIdx])
                if not tex then sheets[tsetIdx] = false return nil end
                local sheet = SpriteSheet2D:new()
                sheet:SetTexture(tex)
                entry = { sheet = sheet, cols = math.max(1, math.floor(tex:GetWidth() / tileSize)), defined = {} }
                sheets[tsetIdx] = entry
            elseif entry == false then
                return nil
            end
            local name = "tile_" .. tileIdx
            if not entry.defined[tileIdx] then
                local sx = (tileIdx % entry.cols) * tileSize
                local sy = math.floor(tileIdx / entry.cols) * tileSize
                entry.sheet:DefineSprite(name, IntRect(sx, sy, sx + tileSize, sy + tileSize), Vector2(0.5, 0.5))
                entry.defined[tileIdx] = true
            end
            return entry.sheet:GetSprite(name)
        end
        local data = {
            131185, 131185, 131185, 131185, 131185, 131185, 131185, 131185, 131185, 131185, 131185, 131185, 131185, 131185, 131185, 131185, 131185, 131185, 131185, 131185, 131185, 0, 12, 0,
            13, 0, 14, 0, 0, 0, 0, 0, 0, 6, 0, 12, 0, 13, 0, 131185, 131185, 0, 12, 0, 13, 0, 14, 0,
            0, 0, 0, 0, 0, 6, 0, 12, 0, 13, 0, 131185, 131185, 0, 12, 0, 65536, 65537, 65537, 65537, 65537, 65537, 65537, 65537,
            65537, 65537, 65537, 65538, 0, 13, 0, 131185, 131185, 0, 12, 0, 65544, 65545, 65545, 65548, 65545, 65545, 65574, 65545, 65540, 65545, 65545, 65546,
            0, 13, 0, 131185, 131185, 0, 12, 0, 65544, 65566, 65545, 65545, 65545, 65545, 65548, 65545, 65545, 65574, 65545, 65546, 0, 13, 0, 131185,
            131185, 0, 12, 0, 65544, 65540, 65545, 65545, 65566, 65545, 65545, 65545, 65545, 65548, 65545, 65546, 0, 13, 0, 131185, 131185, 0, 12, 0,
            65544, 65545, 65574, 65545, 65540, 65545, 65545, 65566, 65545, 65545, 65545, 65546, 0, 13, 0, 131185, 131185, 0, 12, 0, 65544, 65545, 65548, 65545,
            65545, 65574, 65545, 65540, 65545, 65545, 65566, 65546, 0, 13, 0, 131185, 131185, 0, 12, 0, 65552, 65553, 65553, 65553, 65553, 65553, 65553, 65553,
            65553, 65553, 65553, 65554, 0, 13, 0, 131185, 131185, 0, 12, 0, 13, 0, 14, 0, 0, 0, 0, 0, 0, 6, 0, 12,
            0, 13, 0, 131185, 131185, 0, 12, 0, 13, 0, 14, 0, 0, 0, 0, 0, 0, 6, 0, 12, 0, 13, 0, 131185,
            131185, 131185, 131185, 131185, 131185, 131185, 131185, 131185, 131185, 131185, 131185, 131185, 131185, 131185, 131185, 131185, 131185, 131185, 131185, 131185,
        }
        for i = 1, #data do
            local v = data[i]
            if v >= 0 then
                local tsetIdx = math.floor(v / 65536) % 256
                local tileIdx = v % 65536
                local spr = tileSprite(tsetIdx + 1, tileIdx)
                if spr then
                    local col = (i - 1) % cols
                    local row = math.floor((i - 1) / cols)
                    local t = scene_:CreateChild("tilemap2d_3s7u0vwu_t" .. i)
                    t:SetPosition2D(originX + (col + 0.5) * tileW, originY - (row + 0.5) * tileW)
                    local s = t:CreateComponent("StaticSprite2D")
                    s.layer = 0
                    s.sprite = spr
                end
            end
        end
    end
    do
        local n = scene_:CreateChild("collider2d_vxld7di3")
        n:SetPosition2D(0.7886, 2.8595)
        nodes["collider2d_vxld7di3"] = n
        local body = n:CreateComponent("RigidBody2D")
        body.bodyType = BT_STATIC
        local shape = n:CreateComponent("CollisionBox2D")
        shape:SetSize(0.2253, 0.1843)
        shape.categoryBits = 1
        shape.maskBits = 65535
        shape.density = 1.0
        n:SetVar("tag", Variant("obstacle"))
    end
    do
        local n = scene_:CreateChild("collider2d_qq438qgo")
        n:SetPosition2D(5.6735, 2.8799)
        nodes["collider2d_qq438qgo"] = n
        local body = n:CreateComponent("RigidBody2D")
        body.bodyType = BT_STATIC
        local shape = n:CreateComponent("CollisionBox2D")
        shape:SetSize(0.2048, 0.1843)
        shape.categoryBits = 1
        shape.maskBits = 65535
        shape.density = 1.0
        n:SetVar("tag", Variant("obstacle"))
    end
    do
        local n = scene_:CreateChild("collider2d_v9svssv9")
        n:SetPosition2D(0.7681, 0.586)
        nodes["collider2d_v9svssv9"] = n
        local body = n:CreateComponent("RigidBody2D")
        body.bodyType = BT_STATIC
        local shape = n:CreateComponent("CollisionBox2D")
        shape:SetSize(0.1843, 0.1843)
        shape.categoryBits = 1
        shape.maskBits = 65535
        shape.density = 1.0
        n:SetVar("tag", Variant("obstacle"))
    end
    do
        local n = scene_:CreateChild("collider2d_b657cd7y")
        n:SetPosition2D(5.6633, 0.586)
        nodes["collider2d_b657cd7y"] = n
        local body = n:CreateComponent("RigidBody2D")
        body.bodyType = BT_STATIC
        local shape = n:CreateComponent("CollisionBox2D")
        shape:SetSize(0.2253, 0.1843)
        shape.categoryBits = 1
        shape.maskBits = 65535
        shape.density = 1.0
        n:SetVar("tag", Variant("obstacle"))
    end
    do
        local n = scene_:CreateChild("collider2d_rpic8tbr")
        n:SetPosition2D(1.7, 2.5112)
        nodes["collider2d_rpic8tbr"] = n
        local body = n:CreateComponent("RigidBody2D")
        body.bodyType = BT_STATIC
        local shape = n:CreateComponent("CollisionBox2D")
        shape:SetSize(0.2867, 0.3072)
        shape.categoryBits = 1
        shape.maskBits = 65535
        shape.density = 1.0
        n:SetVar("tag", Variant("obstacle"))
    end
    do
        local n = scene_:CreateChild("collider2d_wsk57e8c")
        n:SetPosition2D(1.1317, 1.5486)
        nodes["collider2d_wsk57e8c"] = n
        local body = n:CreateComponent("RigidBody2D")
        body.bodyType = BT_STATIC
        local shape = n:CreateComponent("CollisionBox2D")
        shape:SetSize(0.1741, 0.1843)
        shape.categoryBits = 1
        shape.maskBits = 65535
        shape.density = 1.0
        n:SetVar("tag", Variant("obstacle"))
    end
    do
        local n = scene_:CreateChild("collider2d_wczc26qy")
        n:SetPosition2D(5.0642, 2.3269)
        nodes["collider2d_wczc26qy"] = n
        local body = n:CreateComponent("RigidBody2D")
        body.bodyType = BT_STATIC
        local shape = n:CreateComponent("CollisionBox2D")
        shape:SetSize(0.297, 0.2253)
        shape.categoryBits = 1
        shape.maskBits = 65535
        shape.density = 1.0
        n:SetVar("tag", Variant("obstacle"))
    end
    do
        local n = scene_:CreateChild("collider2d_ybg33qjw")
        n:SetPosition2D(4.9976, 0.6269)
        nodes["collider2d_ybg33qjw"] = n
        local body = n:CreateComponent("RigidBody2D")
        body.bodyType = BT_STATIC
        local shape = n:CreateComponent("CollisionBox2D")
        shape:SetSize(0.2867, 0.2253)
        shape.categoryBits = 1
        shape.maskBits = 65535
        shape.density = 1.0
        n:SetVar("tag", Variant("obstacle"))
    end
    do
        local n = scene_:CreateChild("enemy2d_pizmmnvi")
        n:SetPosition2D(4.8338, 2.0298)
        nodes["enemy2d_pizmmnvi"] = n
        local spr = n:CreateComponent("StaticSprite2D")
        spr.blendMode = BLEND_ALPHA
        spr.layer = 10
        local sheet = cache:GetResource("SpriteSheet2D", "image/Sprites/Orc_Idle.xml")
        if sheet then spr.sprite = sheet:GetSprite("Orc_Idle_0") end
        spr.useDrawRect = true
        spr.drawRect = Rect(-0.4097, -0.4097, 0.4097, 0.4097)
        local body = n:CreateComponent("RigidBody2D")
        body.bodyType = BT_DYNAMIC
        body.fixedRotation = true
        body.gravityScale = 0
        local shape = n:CreateComponent("CollisionBox2D")
        shape:SetSize(0.5735, 0.6964)
        shape.categoryBits = 8
        shape.maskBits = 35
        shape.density = 1.0
        n:SetVar("spawnX", Variant(4.8338))
    end
    do
        local n = scene_:CreateChild("charactercontroller2d_alob7hhu")
        n:SetPosition2D(2.8675, 2.0298)
        nodes["charactercontroller2d_alob7hhu"] = n
        local spr = n:CreateComponent("StaticSprite2D")
        spr.blendMode = BLEND_ALPHA
        spr.layer = 10
        local sheet = cache:GetResource("SpriteSheet2D", "image/Sprites/Soldier_Idle.xml")
        if sheet then spr.sprite = sheet:GetSprite("Soldier_Idle_0") end
        spr.useDrawRect = true
        spr.drawRect = Rect(-0.4097, -0.4097, 0.4097, 0.4097)
        local body = n:CreateComponent("RigidBody2D")
        body.bodyType = BT_DYNAMIC
        body.fixedRotation = true
        body.gravityScale = 0
        local shape = n:CreateComponent("CollisionBox2D")
        shape:SetSize(0.8193, 0.8193)
        shape.categoryBits = 2
        shape.maskBits = 89
        shape.density = 1.0
    end
    return nodes
end

return M
