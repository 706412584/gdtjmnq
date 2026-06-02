-- ============================================================================
-- logic_2D瓦片庭院.lua — 2D 玩法逻辑（对照 GameRuntime.ts）
-- Update 驱动玩家移动/敌人 AI/相机/平台/计时；PhysicsBeginContact2D 处理拾取/受击/到达终点。
---@diagnostic disable: undefined-global
-- ============================================================================

local M = {}

M.config = {
    rules = { maxHp = 3, winCondition = "none", goalTag = "goal" },
    mode = "topdown",
    sceneW = 6.4, sceneH = 4.16,
    camera = { followTargetId = "", zoom = 1, smooth = 0.1, deadZoneWidth = 0, deadZoneHeight = 0, lockBounds = true },
    player = { id = "charactercontroller2d_alob7hhu", speed = 0.9, jumpForce = 0, canShoot = false, weaponDamage = 1, anims = { idle = { sheet = "Soldier_Idle", count = 6, fps = 8 }, walk = { sheet = "Soldier_Walk", count = 8, fps = 12 } } },
    enemies = {
        { id = "enemy2d_pizmmnvi", behavior = "patrol", speed = 0.35, patrolRange = 1.6, detectRange = 2.2, damage = 1, hp = 3, attackOnContact = true, anims = { idle = { sheet = "Orc_Idle", count = 6, fps = 8 }, walk = { sheet = "Orc_Walk", count = 8, fps = 12 } } },
    },
    pickups = {
    },
    platforms = {
    },
    breakables = {
    },
    portals = {
    },
    sounds = {
    },
    timers = {
    },
    animSprites = {
    },
    spawners = {
    },
    weapon = { speed = 0.09, damage = 1, cooldown = 18, life = 90, sizeM = 0.12 },
    weaponColor = { 0.9922, 0.8784, 0.2784 },
}

M.nodes = {}
M.state = { hp = M.config.rules.maxHp, score = 0, grounded = false, groundCount = 0, gameOver = false, facingRight = true, enemyDir = {}, enemyHp = {}, breakHp = {}, platPhase = {}, timers = {}, timerShown = {}, anim = {}, actorAnim = {}, soundFired = {}, bullets = {}, bulletSeq = 0, fireCd = 0, spawners = {} }

-- ── 初始化：缓存节点引用 + 初始状态 ──
function M.Init(scene_, nodes, hud)
    M.scene = scene_
    M.nodes = nodes
    M.hud = hud
    local cfg = M.config
    for _, e in ipairs(cfg.enemies) do
        M.state.enemyDir[e.id] = 1
        M.state.enemyHp[e.id] = e.hp
    end
    for _, br in ipairs(cfg.breakables) do M.state.breakHp[br.id] = br.hp end
    for _, sp in ipairs(cfg.spawners) do M.state.spawners[sp.id] = { timer = 0, alive = 0, spawned = 0 } end
    for _, mp in ipairs(cfg.platforms) do M.state.platPhase[mp.id] = 0 end
    for _, t in ipairs(cfg.timers) do M.state.timers[t.id] = t.duration M.state.timerShown[t.id] = math.ceil(t.duration) end
    M.SyncHud()
end

function M.SyncHud()
    if M.hud and M.hud.OnHpChange then M.hud.OnHpChange(M.state.hp, M.config.rules.maxHp) end
    if M.hud and M.hud.OnScoreChange then M.hud.OnScoreChange(M.state.score) end
end

local function nodeOf(id) return M.nodes[id] end

-- ── 每帧主循环 ──
function M.Update(dt)
    if M.state.gameOver then return end
    M.UpdatePlayer(dt)
    M.UpdateShooting(dt)
    M.UpdateBullets(dt)
    M.UpdateSpawners(dt)
    M.UpdateEnemies(dt)
    M.UpdatePlatforms(dt)
    M.UpdateTimers(dt)
    M.UpdateAnims(dt)
    M.UpdateCamera(dt)
    if M.config.rules.winCondition == "clearEnemies" then M.CheckClear() end
end

function M.UpdatePlayer(dt)
    local cfg = M.config.player
    if not cfg then return end
    local node = nodeOf(cfg.id)
    if not node then return end
    local body = node:GetComponent("RigidBody2D")
    if not body then return end
    local moveX, moveY = 0, 0
    -- 键盘 + GameHUD 摇杆
    if input:GetKeyDown(KEY_A) or input:GetKeyDown(KEY_LEFT) then moveX = -1 end
    if input:GetKeyDown(KEY_D) or input:GetKeyDown(KEY_RIGHT) then moveX = 1 end
    if M.joystick then
        local jx, jy = M.joystick:getMovement()
        if math.abs(jx) > 0.2 then moveX = jx end
        if math.abs(jy) > 0.2 then moveY = jy end
    end
    if input:GetKeyDown(KEY_W) or input:GetKeyDown(KEY_UP) then moveY = 1 end
    if input:GetKeyDown(KEY_S) or input:GetKeyDown(KEY_DOWN) then moveY = -1 end
    local vx, vy = moveX * cfg.speed, moveY * cfg.speed
    if vx ~= 0 and vy ~= 0 then local inv = 0.70710678 vx = vx * inv vy = vy * inv end
    body.linearVelocity = Vector2(vx, vy)
    if moveX ~= 0 then M.state.facingRight = moveX > 0 end
    local animState = (moveX ~= 0 or moveY ~= 0) and "walk" or "idle"
    local spr = node:GetComponent("StaticSprite2D")
    if spr then spr.flipX = not M.state.facingRight end
    M.PlayActorAnim(cfg.id, cfg.anims, animState, dt)
end

-- 玩家射击：canShoot 时按 J/开火键发射子弹（BT_DYNAMIC, trigger, 朝向飞行）。
function M.UpdateShooting(dt)
    local cfg = M.config.player
    if not cfg or not cfg.canShoot then return end
    local w = M.config.weapon
    if not w then return end
    if M.state.fireCd > 0 then M.state.fireCd = M.state.fireCd - dt end
    local fire = input:GetKeyDown(KEY_J) or input:GetKeyDown(KEY_K) or (M.shootButton and M.shootButton.isPressed)
    if not fire or M.state.fireCd > 0 then return end
    local pn = nodeOf(cfg.id)
    if not pn then return end
    M.state.fireCd = w.cooldown / 60
    M.state.bulletSeq = M.state.bulletSeq + 1
    local id = "__bullet_" .. M.state.bulletSeq
    local dir = M.state.facingRight and 1 or -1
    local pp = pn:GetPosition2D()
    local b = M.scene:CreateChild(id)
    b:SetPosition2D(pp.x + dir * 0.3, pp.y)
    local spr = b:CreateComponent("StaticSprite2D")
    spr.layer = 15
    spr.sprite = cache:GetResource("Sprite2D", "image/game2d/_placeholder.png")
    spr.color = Color(M.config.weaponColor[1], M.config.weaponColor[2], M.config.weaponColor[3], 1)
    spr.useDrawRect = true
    spr.drawRect = Rect(-w.sizeM/2, -w.sizeM/2, w.sizeM/2, w.sizeM/2)
    local body = b:CreateComponent("RigidBody2D")
    body.bodyType = BT_DYNAMIC
    body.gravityScale = 0
    body.bullet = true
    local shape = b:CreateComponent("CollisionCircle2D")
    shape.radius = w.sizeM / 2
    shape.trigger = true
    shape.categoryBits = 32
    shape.maskBits = 1 + 8
    body.linearVelocity = Vector2(dir * w.speed, 0)
    M.nodes[id] = b
    M.state.bullets[id] = w.life / 60
end

-- 子弹寿命衰减：到期移除。
function M.UpdateBullets(dt)
    for id, life in pairs(M.state.bullets) do
        life = life - dt
        if life <= 0 then M.RemoveBullet(id) else M.state.bullets[id] = life end
    end
end

function M.RemoveBullet(id)
    local n = M.nodes[id]
    if n then n:Remove() end
    M.nodes[id] = nil
    M.state.bullets[id] = nil
end

function M.UpdateEnemies(dt)
    local player = M.config.player and nodeOf(M.config.player.id) or nil
    for _, e in ipairs(M.config.enemies) do
        if M.state.enemyHp[e.id] and M.state.enemyHp[e.id] > 0 then
            local node = nodeOf(e.id)
            local body = node and node:GetComponent("RigidBody2D")
            if body then
                local vx, vy = 0, 0
                local moving = false
                if e.behavior == "static" then
                    -- 站桩
                elseif e.behavior == "chase" and player then
                    local pp = player:GetPosition2D()
                    local np = node:GetPosition2D()
                    local dx, dy = pp.x - np.x, pp.y - np.y
                    local dist = math.sqrt(dx*dx + dy*dy)
                    if dist <= e.detectRange and dist > 0.0001 then
                        vx = dx / dist * e.speed
                        if M.config.mode == "topdown" then vy = dy / dist * e.speed end
                        M.state.enemyDir[e.id] = dx >= 0 and 1 or -1
                        moving = true
                    else
                        vx = M.state.enemyDir[e.id] * e.speed moving = e.patrolRange > 0
                    end
                else
                    -- patrol：出生点左右 patrolRange/2 往返
                    local sp = node:GetVar("spawnX"):GetFloat()
                    local np = node:GetPosition2D()
                    local half = e.patrolRange / 2
                    if np.x > sp + half then M.state.enemyDir[e.id] = -1 end
                    if np.x < sp - half then M.state.enemyDir[e.id] = 1 end
                    vx = M.state.enemyDir[e.id] * e.speed
                    moving = e.patrolRange > 0
                end
                if M.config.mode == "topdown" then
                    body.linearVelocity = Vector2(vx, vy)
                else
                    body.linearVelocity = Vector2(vx, body.linearVelocity.y)
                end
                local spr = node:GetComponent("StaticSprite2D")
                if spr then spr.flipX = (M.state.enemyDir[e.id] < 0) end
                M.PlayActorAnim(e.id, e.anims, moving and "walk" or "idle", dt)
            end
        end
    end
end

-- 生成点：按 interval(帧→秒) 周期克隆敌人模板，受 maxAlive / total 限制。
function M.UpdateSpawners(dt)
    for _, sp in ipairs(M.config.spawners) do
        if sp.enemyRef then
            local st = M.state.spawners[sp.id]
            st.timer = st.timer + dt
            local needTotal = sp.total <= 0 or st.spawned < sp.total
            if st.timer >= sp.interval / 60 and st.alive < sp.maxAlive and needTotal then
                st.timer = 0
                M.SpawnEnemy(sp)
            end
        end
    end
end

-- 克隆敌人模板节点到生成点，复制其行为/数值/动画（用 spawner_id 派生唯一 id）。
function M.SpawnEnemy(sp)
    local tmpl = nil
    for _, e in ipairs(M.config.enemies) do if e.id == sp.enemyRef then tmpl = e break end end
    if not tmpl then return end
    local tnode = nodeOf(sp.enemyRef)
    if not tnode then return end
    local st = M.state.spawners[sp.id]
    st.spawned = st.spawned + 1
    st.alive = st.alive + 1
    local id = sp.id .. "_e" .. st.spawned
    local clone = tnode:Clone()
    clone:SetName(id)
    clone:SetPosition2D(sp.x, sp.y)
    M.nodes[id] = clone
    clone:SetVar("spawnX", Variant(sp.x))
    -- 注册为一个独立敌人（复制模板数值），纳入 AI/受击循环
    local e = { id = id, behavior = tmpl.behavior, speed = tmpl.speed, patrolRange = tmpl.patrolRange, detectRange = tmpl.detectRange, damage = tmpl.damage, hp = tmpl.hp, attackOnContact = tmpl.attackOnContact, anims = tmpl.anims, spawnerId = sp.id }
    M.config.enemies[#M.config.enemies + 1] = e
    M.state.enemyDir[id] = 1
    M.state.enemyHp[id] = tmpl.hp
end

function M.UpdatePlatforms(dt)
    for _, mp in ipairs(M.config.platforms) do
        local node = nodeOf(mp.id)
        if node then
            M.state.platPhase[mp.id] = M.state.platPhase[mp.id] + mp.speed * 0.02
            local t = (math.sin(M.state.platPhase[mp.id]) + 1) / 2
            local base = node:GetVar("baseX"):GetFloat()
            local baseY = node:GetVar("baseY"):GetFloat()
            node:SetPosition2D(base + mp.dx * (t - 0.5), baseY + mp.dy * (t - 0.5))
        end
    end
end

function M.UpdateTimers(dt)
    for _, t in ipairs(M.config.timers) do
        local remain = M.state.timers[t.id]
        if remain and remain > 0 then
            remain = remain - dt
            if remain < 0 then remain = 0 end
            M.state.timers[t.id] = remain
            local shown = math.ceil(remain)
            if shown ~= M.state.timerShown[t.id] then
                M.state.timerShown[t.id] = shown
                if M.hud and M.hud.OnTimerTick then M.hud.OnTimerTick(t.id, shown) end
            end
            if remain <= 0 then
                if t.action == "win" then M.GameOver("win", "timer")
                elseif t.action == "lose" then M.GameOver("lose", "timer") end
            end
        end
    end
end

-- 装饰帧动画（SpriteAnimation 节点）：按 fps 循环切帧。
function M.UpdateAnims(dt)
    for _, a in ipairs(M.config.animSprites) do
        local node = nodeOf(a.id)
        local spr = node and node:GetComponent("StaticSprite2D")
        if spr and a.count > 1 then
            local st = M.state.anim[a.id] or { t = 0, f = 0 }
            st.t = st.t + dt
            if st.t >= 1 / a.fps then
                st.t = st.t - 1 / a.fps
                st.f = (st.f + 1) % a.count
                local sheet = cache:GetResource("SpriteSheet2D", "image/Sprites/" .. a.sheet .. ".xml")
                if sheet then spr.sprite = sheet:GetSprite(a.sheet .. "_" .. st.f) end
            end
            M.state.anim[a.id] = st
        end
    end
end

-- 角色/敌人状态机帧动画：按当前状态(idle/walk/jump)选 anims 表里的 sheet 逐帧播放。
-- anims = { idle = { sheet, count, fps }, walk = {...}, jump = {...} }；状态缺失则回退 idle。
function M.PlayActorAnim(id, anims, stateName, dt)
    if not anims then return end
    local clip = anims[stateName] or anims.idle or anims.walk
    if not clip or not clip.sheet then return end
    local node = nodeOf(id)
    local spr = node and node:GetComponent("StaticSprite2D")
    if not spr then return end
    local st = M.state.actorAnim[id]
    if not st or st.name ~= stateName then st = { name = stateName, t = 0, f = 0 } end
    local count = clip.count or 1
    if count > 1 then
        st.t = st.t + dt
        local frameDur = 1 / (clip.fps or 10)
        if st.t >= frameDur then
            st.t = st.t - frameDur
            st.f = (st.f + 1) % count
        end
    else
        st.f = 0
    end
    local sheet = cache:GetResource("SpriteSheet2D", "image/Sprites/" .. clip.sheet .. ".xml")
    if sheet then
        local s = sheet:GetSprite(clip.sheet .. "_" .. st.f)
        if s then spr.sprite = s end
    end
    M.state.actorAnim[id] = st
end

function M.UpdateCamera(dt)
    local cam = M.cameraNode
    if not cam then return end
    local cfg = M.config.camera
    local targetId = cfg.followTargetId ~= "" and cfg.followTargetId or (M.config.player and M.config.player.id)
    local target = targetId and nodeOf(targetId) or nil
    if not target then return end
    local tp = target:GetPosition2D()
    local cp = cam:GetPosition2D()
    local s = math.min(1.0, cfg.smooth)
    local nx = cp.x + (tp.x - cp.x) * s
    local ny = cp.y + (tp.y - cp.y) * s
    if cfg.lockBounds then
        local halfW = M.orthoSize * (graphics.width / graphics.height) * 0.5
        local halfH = M.orthoSize * 0.5
        if nx < halfW then nx = halfW end
        if nx > M.config.sceneW - halfW then nx = M.config.sceneW - halfW end
        if ny < halfH then ny = halfH end
        if ny > M.config.sceneH - halfH then ny = M.config.sceneH - halfH end
    end
    cam:SetPosition2D(nx, ny)
end

-- ── 碰撞回调（由 main.lua 转发）──
-- began=true 来自 PhysicsBeginContact2D，began=false 来自 PhysicsEndContact2D。
-- 脚底 sensor(categoryBits=4) 与地面接触用接触计数维护 grounded（支持同时踩多块平台，
-- 见 binding guide 16.5）；其余拾取/受击/到达/传送/音效仅在 began=true 时处理一次。
function M.OnContact(nodeA, nodeB, shapeA, shapeB, began)
    -- 脚底传感器 → grounded（用接触计数，begin +1 / end -1）
    local catA = shapeA and shapeA.categoryBits or 0
    local catB = shapeB and shapeB.categoryBits or 0
    if catA == 4 or catB == 4 then
        if began then M.state.groundCount = M.state.groundCount + 1
        else M.state.groundCount = math.max(0, M.state.groundCount - 1) end
        M.state.grounded = M.state.groundCount > 0
        return
    end
    if not began then return end
    if M.state.gameOver then return end
    local playerId = M.config.player and M.config.player.id
    if not playerId then return end
    local a = nodeA and nodeA:GetName() or ""
    local b = nodeB and nodeB:GetName() or ""
    -- 子弹 vs 敌人 / 可破坏物（任一侧是子弹）
    if M.OnProjectileContact(a, b) then return end
    local other = nil
    if a == playerId then other = b elseif b == playerId then other = a else return end
    -- 拾取
    for _, pk in ipairs(M.config.pickups) do
        if pk.id == other then
            if pk.score > 0 then M.state.score = M.state.score + pk.score end
            if pk.heal > 0 then M.state.hp = math.min(M.config.rules.maxHp, M.state.hp + pk.heal) end
            M.SyncHud()
            if pk.consume then local n = nodeOf(pk.id) if n then n:Remove() end end
            return
        end
    end
    -- 敌人接触受击
    for _, e in ipairs(M.config.enemies) do
        if e.id == other and e.attackOnContact and (M.state.enemyHp[e.id] or 0) > 0 then M.DamagePlayer(e.damage) return end
    end
    -- 终点触发器
    local n = nodeOf(other)
    if n and n:GetVar("tag"):GetString() == M.config.rules.goalTag and M.config.rules.winCondition == "reachGoal" then
        M.GameOver("win", "reachGoal")
    end
    -- 传送门
    for _, pt in ipairs(M.config.portals) do
        if pt.id == other and pt.targetX ~= nil and pt.targetY ~= nil then
            local pn = nodeOf(playerId)
            if pn then pn:SetPosition2D(pt.targetX, pt.targetY) end
        end
    end
    -- 音效触发
    for _, sd in ipairs(M.config.sounds) do
        if sd.id == other and sd.sound ~= "" and not M.state.soundFired[sd.id] then
            if sd.once then M.state.soundFired[sd.id] = true end
            if M.hud and M.hud.OnPlaySound then M.hud.OnPlaySound(sd.sound) end
        end
    end
end

-- 子弹命中敌人/可破坏物：扣血、计分、移除子弹。返回 true 表示已处理。
function M.OnProjectileContact(a, b)
    local bulletName, otherName = nil, nil
    if M.state.bullets[a] then bulletName, otherName = a, b
    elseif M.state.bullets[b] then bulletName, otherName = b, a
    else return false end
    -- 敌人
    for _, e in ipairs(M.config.enemies) do
        if e.id == otherName and (M.state.enemyHp[e.id] or 0) > 0 then
            M.state.enemyHp[e.id] = M.state.enemyHp[e.id] - (M.config.player and M.config.player.weaponDamage or 1)
            if M.state.enemyHp[e.id] <= 0 then
                local en = nodeOf(e.id) if en then en:Remove() end
                if e.spawnerId and M.state.spawners[e.spawnerId] then M.state.spawners[e.spawnerId].alive = math.max(0, M.state.spawners[e.spawnerId].alive - 1) end
            end
            M.RemoveBullet(bulletName)
            return true
        end
    end
    -- 可破坏物
    for _, br in ipairs(M.config.breakables) do
        if br.id == otherName and (M.state.breakHp[br.id] or 0) > 0 then
            M.state.breakHp[br.id] = M.state.breakHp[br.id] - (M.config.player and M.config.player.weaponDamage or 1)
            if M.state.breakHp[br.id] <= 0 then
                if br.score > 0 then M.state.score = M.state.score + br.score M.SyncHud() end
                local bn = nodeOf(br.id) if bn then bn:Remove() end
            end
            M.RemoveBullet(bulletName)
            return true
        end
    end
    return false
end

function M.DamagePlayer(amount)
    if M.state.gameOver then return end
    M.state.hp = math.max(0, M.state.hp - amount)
    M.SyncHud()
    if M.state.hp <= 0 then M.GameOver("lose", "hp") end
end

function M.CheckClear()
    local total, dead = 0, 0
    for _, e in ipairs(M.config.enemies) do
        total = total + 1
        if (M.state.enemyHp[e.id] or 0) <= 0 then dead = dead + 1 end
    end
    if total > 0 and dead == total then M.GameOver("win", "clearEnemies") end
end

function M.GameOver(result, reason)
    if M.state.gameOver then return end
    M.state.gameOver = true
    if M.hud and M.hud.OnGameOver then M.hud.OnGameOver(result, reason) end
end

return M
