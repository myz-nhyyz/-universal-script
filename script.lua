-- Context: Luau (Roblox Client Executor - Heroes Battlegrounds Edition v17 - FIXED)
-- Architecture: Fixed 4-M1 Sequential Kill Aura + Range Check + Non-Interrupting Void Kill
--               + Anti-Void OFF by default + Guarded Toggle Init + Nova Hub Fluent UI.

local Players = game:GetService("Players")
local RunService = game:GetService("RunService")
local UserInputService = game:GetService("UserInputService")
local TweenService = game:GetService("TweenService")
local Workspace = game:GetService("Workspace")
local CoreGui = game:GetService("CoreGui")
local VirtualInputManager = game:GetService("VirtualInputManager")

local LocalPlayer = Players.LocalPlayer
local Camera = Workspace.CurrentCamera

-- // CONFIGURATION & STATE (ALL COMBAT / VOID / MOVEMENT TOGGLES DEFAULT TO FALSE)
local Config = {
    ScriptRunning = true,
    UIInitialized = false,     -- Chặn tuyệt đối việc tự kích hoạt tính năng khi vừa execute script

    -- Heroes Battlegrounds Specials (FIXED)
    KillAuraEnabled = false,
    KillAuraRange = 16,        -- Chỉ đánh khi có địch trong tầm (không tự vung tay khóa M1 khi đứng không)
    KillAuraDelay = 0.24,      -- Nhịp đánh chuẩn giữa từng đòn M1 (1 -> 2 -> 3 -> 4)
    AntiStunEnabled = false,   -- Full Multi-Layer Anti-Stun (v8 Immunity Engine)
    AutoVoidKill = false,      -- Chỉ kéo xuống Void khi thực sự có khớp Grab Weld nối với địch
    VoidHoldTime = 1.35,
    AntiVoidEnabled = true,   -- Đã tắt mặc định khi mới execute script (trước đây để true)

    -- Combat / Target
    AimbotWidgetOpen = false,
    AimbotActive = false,
    AimPart = "Head",
    SelectedPlayer = nil,
    AutoTargetEnabled = false,
    TargetFreeMove = false,    -- Đã tắt mặc định
    TargetMode = "Behind",     -- "Behind" | "Orbit" | "Random" | "Below" | "Upper" | "Front"
    OrbitSpeed = 15,
    TargetRange = 5.5,

    -- Movement
    FlyEnabled = false,
    FlyMode = "FloorPad",      -- "FloorPad" | "LoopPulse"
    FlySpeed = 65,
    InfJumpEnabled = false,
    InfJumpMode = "FlyPadStep", -- "FlyPadStep" | "ParabolicCFrame" | "MicroBounce"
    InvisibleEnabled = false,
    InvisMode = "RootJointBreak", -- "RootJointBreak" | "UndergroundC0" | "SeatDesync"
    SpeedEnabled = false,
    WalkSpeed = 50,
    JumpBoostEnabled = false,
    JumpPower = 100,

    -- Visuals
    ESPEnabled = false,
}

local State = {
    Char = nil,
    Root = nil,
    Hum = nil,
    CharConnections = {},

    -- Kill Aura Combo State
    KillAuraLoopRunning = false,
    ComboStage = 1,
    LastHitTick = 0,

    -- Live Sniffed M1 Log (Captures any RemoteEvent / RemoteFunction call when you punch manually)
    SniffedLogs = {},
    LastSniffedText = "Chưa có log. Hãy đánh thường (M1) 1-2 cái rồi bấm nút Copy này!",

    -- Void Kill & Anti-Void State
    LastSafeCFrame = nil,
    VoidKillActive = false,
    VoidReturnCFrame = nil,
    GrabbedEnemy = nil,
    LastSkillCastTick = 0,

    -- Combat / Movement State
    FlyPad = nil,
    InfJumpArcActive = false,
    InfJumpArcTimer = 0,
    LastJumpTime = 0,
    OrbitAngle = 0,
    FreeMoveOffset = Vector3.zero,
    LockedAimbotPlayer = nil,
    InvisData = { Seat = nil, SavedC0 = nil, HiddenParts = {} },
    ESPObjects = {},
    LastESPRefresh = 0,
    ToggleRegistry = {},
    PinnedButtons = {},
    Connections = {},
}

-- Animation ID cho chuỗi 4 đòn M1 chuẩn của Hero Battlegrounds (từ hook.lua)
local M1ComboAnims = {
    [1] = "rbxassetid://11605699401",
    [2] = "rbxassetid://11605701169",
    [3] = "rbxassetid://11605702519",
    [4] = "rbxassetid://11605703871",
}

-- // 0. ANTI-KICK + PASSIVE REMOTE SNIFFER HOOK (KHÔNG CHẶN HAY SỬA ARGS CỦA SKILL)
pcall(function()
    if hookmetamethod and getnamecallmethod and checkcaller then
        local oldNamecall
        oldNamecall = hookmetamethod(game, "__namecall", function(self, ...)
            if Config.ScriptRunning and not checkcaller() then
                local method = getnamecallmethod()
                if (method == "Kick" or method == "kick") and self == LocalPlayer then
                    return nil
                end
                if (method == "FireServer" or method == "InvokeServer") and (self:IsA("RemoteEvent") or self:IsA("RemoteFunction")) then
                    local rName = string.lower(self.Name)
                    if not string.find(rName, "sound") and not string.find(rName, "camera") and not string.find(rName, "footstep") then
                        local args = {...}
                        local firstArg = tostring(args[1] or "")
                        -- Ghi nhận thời điểm người chơi bấm tung chiêu (Skill 1, 2, 3, 4) để Void Kill / Kill Aura nhường nhịp
                        if firstArg ~= "LeftClick" and firstArg ~= "LeftClickRelease" and firstArg ~= "animval" then
                            State.LastSkillCastTick = tick()
                        end

                        local parts = {}
                        for i = 1, select("#", ...) do
                            local v = args[i]
                            if typeof(v) == "table" then
                                local tStr = "{"
                                for k, tv in pairs(v) do
                                    tStr = tStr .. tostring(k) .. "=" .. tostring(tv) .. ","
                                end
                                tStr = tStr .. "}"
                                table.insert(parts, tStr)
                            else
                                table.insert(parts, typeof(v) .. "(" .. tostring(v) .. ")")
                            end
                        end
                        local entry = string.format("[%s] %s(%s)", method, self:GetFullName(), table.concat(parts, ", "))
                        State.LastSniffedText = entry
                        table.insert(State.SniffedLogs, 1, entry)
                        if #State.SniffedLogs > 15 then
                            table.remove(State.SniffedLogs)
                        end
                    end
                end
            end
            return oldNamecall(self, ...)
        end)
    end
end)

-- // CLEAN RELEASE FUNCTION (Restores Normal M1 Punching Immediately When Kill Aura Is Turned OFF)
local function releaseM1State()
    pcall(function()
        local char = LocalPlayer.Character
        local main = char and char:FindFirstChild("Main")
        local rem = main and main:FindFirstChild("RemoteEvent")
        if rem then
            rem:FireServer("LeftClickRelease", true)
        end
    end)
end

-- // HELPER: TÌM MỤC TIÊU GẦN NHẤT TRONG TẦM KILL AURA (BAO GỒM CẢ PLAYER VÀ NPC TRONG WORKSPACE.LIVE)
local function getClosestEnemyForAura(maxDist)
    local myChar = State.Char or LocalPlayer.Character
    local myRoot = State.Root or (myChar and myChar:FindFirstChild("HumanoidRootPart"))
    if not myChar or not myRoot then return nil, nil end

    local bestModel, bestRoot = nil, nil
    local shortest = maxDist

    local liveFolder = Workspace:FindFirstChild("Live")
    if liveFolder then
        for _, model in ipairs(liveFolder:GetChildren()) do
            if model ~= myChar and model:IsA("Model") then
                local eRoot = model:FindFirstChild("HumanoidRootPart")
                local eHum = model:FindFirstChildOfClass("Humanoid")
                if eRoot and eHum and eHum.Health > 0 then
                    local d = (eRoot.Position - myRoot.Position).Magnitude
                    if d <= shortest then
                        shortest = d
                        bestModel = model
                        bestRoot = eRoot
                    end
                end
            end
        end
    end

    for _, plr in ipairs(Players:GetPlayers()) do
        if plr ~= LocalPlayer and plr.Character then
            local eRoot = plr.Character:FindFirstChild("HumanoidRootPart")
            local eHum = plr.Character:FindFirstChildOfClass("Humanoid")
            if eRoot and eHum and eHum.Health > 0 then
                local d = (eRoot.Position - myRoot.Position).Magnitude
                if d <= shortest then
                    shortest = d
                    bestModel = plr.Character
                    bestRoot = eRoot
                end
            end
        end
    end

    return bestModel, bestRoot
end

-- // KIỂM TRA NHÂN VẬT ĐANG DÙNG SKILL (TRÁNH KILL AURA & VOID KILL NGẮT CHIÊU)
local function isCharacterUsingSkill(char)
    if not char then return false end
    if (tick() - State.LastSkillCastTick) < 0.45 then
        return true
    end
    for _, child in ipairs(char:GetChildren()) do
        local n = string.lower(child.Name)
        if n == "usingmove" or n == "skill" or n == "casting" or n == "action" or n == "move" then
            return true
        end
    end
    if char:GetAttribute("UsingMove") == true or char:GetAttribute("InSkill") == true then
        return true
    end
    return false
end

-- // FIXED KILL AURA LOOP (ĐÁNH ĐỦ 4 ĐÒN M1 TUẦN TỰ + GÂY DAME THẬT + KHÔNG TỰ ĐÁNH KHI KHÔNG CÓ ĐỊCH)
-- Nguyên nhân bản cũ bị kẹt M1 lần 1 và không gây dame:
--   1. Bản cũ chạy `for v6 = 1, 4 do remote:FireServer("LeftClick", ..., v6, ...) end` trong cùng 1 frame (0 giây)
--      rồi lập tức bắn `"LeftClickRelease"` sau 0.08s. Server nhận LeftClickRelease liên tục nên ép nhân vật
--      reset về đòn M1 số 1 mãi mãi, không bao giờ sang được đòn 2, 3, 4.
--   2. Bản cũ truyền Vector3.new(math.random(10,40)...) làm hướng đánh bị lệch hoàn toàn khỏi vị trí địch nên mất hitbox.
--   3. Bản cũ bắn remote liên tục kể cả khi không có địch xung quanh, làm bạn bấm chuột trái tự đánh cũng bị kẹt ở M1 đầu.
local function startKillAuraLoop()
    if State.KillAuraLoopRunning then return end
    State.KillAuraLoopRunning = true

    task.spawn(function()
        while Config.ScriptRunning and Config.KillAuraEnabled do
            local char = LocalPlayer.Character
            local root = char and char:FindFirstChild("HumanoidRootPart")
            local hum = char and char:FindFirstChildOfClass("Humanoid")
            local main = char and char:FindFirstChild("Main")
            local remote = main and main:FindFirstChild("RemoteEvent")

            if char and root and hum and hum.Health > 0 and remote and not State.VoidKillActive and not isCharacterUsingSkill(char) then
                local enemyModel, enemyRoot = getClosestEnemyForAura(Config.KillAuraRange)

                if enemyModel and enemyRoot then
                    -- Nếu quá 1.4s chưa đánh tiếp thì quay lại đòn M1 số 1
                    local now = tick()
                    if (now - State.LastHitTick) > 1.4 then
                        State.ComboStage = 1
                    end
                    State.LastHitTick = now

                    local stage = State.ComboStage
                    local aimPos = enemyRoot.Position
                    local aimCF = CFrame.new(root.Position, Vector3.new(aimPos.X, root.Position.Y, aimPos.Z))

                    -- Tự xoay ngang mặt về phía mục tiêu nếu không bật AutoTarget để hitbox M1 trúng 100%
                    if not Config.AutoTargetEnabled and (Vector3.new(aimPos.X, root.Position.Y, aimPos.Z) - root.Position).Magnitude > 0.1 then
                        root.CFrame = aimCF
                    end

                    pcall(function()
                        -- 1. Gửi gói LeftClick đúng thứ tự đòn hiện tại (1 -> 2 -> 3 -> 4) và tọa độ thực của mục tiêu
                        remote:FireServer("LeftClick", true, aimPos, stage, false, 1)

                        -- 2. Đồng bộ gói animval chuẩn của Hero Battlegrounds để server tính hitbox & sát thương
                        local animArgs = {
                            [1] = "animval",
                            [2] = M1ComboAnims[stage] or M1ComboAnims[1],
                            [3] = 0.1,
                            [4] = stage,
                            [6] = CFrame.new(root.Position, aimPos),
                            [9] = false
                        }
                        remote:FireServer(unpack(animArgs))
                    end)

                    -- Chuyển sang đòn tiếp theo trong chuỗi 4 M1: 1 -> 2 -> 3 -> 4
                    State.ComboStage = (stage % 4) + 1

                    if stage == 4 then
                        -- Chỉ nhả LeftClickRelease sau khi đã hoàn tất đòn M1 thứ 4!
                        task.wait(0.12)
                        pcall(function()
                            remote:FireServer("LeftClickRelease", true)
                        end)
                        task.wait(math.max(Config.KillAuraDelay + 0.14, 0.35))
                    else
                        task.wait(math.max(Config.KillAuraDelay, 0.18))
                    end
                else
                    -- Không có mục tiêu trong tầm: không spam remote để người chơi tự đánh/tung skill bình thường
                    task.wait(0.06)
                end
            else
                task.wait(0.06)
            end
        end

        State.KillAuraLoopRunning = false
        releaseM1State()
    end)
end

-- // FULL ANTI-STUN ENGINE (v8 Immunity Engine - Protects Character.Main & Active Skills!)
local StunKeywords = {
    "stun", "stuns", "nojump", "nospeed", "slow", "knockback", "ragdoll", "freeze",
    "frozen", "dizz", "paralyz", "hitstun", "cantmove", "disabled",
    "anchor", "heavy", "slam", "downed", "endlag", "m1cooldown"
}

local function isStunName(str)
    local lower = string.lower(str)
    if lower == "main" or lower == "remoteevent" or lower == "animate" or lower == "humanoid" or lower == "humanoidrootpart" then
        return false
    end
    for i = 1, #StunKeywords do
        if string.find(lower, StunKeywords[i], 1, true) then
            return true
        end
    end
    return false
end

local function cleanStunInstance(inst)
    if not Config.ScriptRunning or not Config.AntiStunEnabled or not inst then return end
    if inst.Name == "Main" or inst:IsA("RemoteEvent") or inst:IsA("LocalScript") or inst:IsA("Script") or inst:IsA("Folder") then
        return
    end
    -- Chỉ xóa BodyMover nếu tên của nó là tên hiệu ứng khống chế/knockback để không làm hỏng các chiêu lướt/bay của bạn
    if inst:IsA("BodyVelocity") or inst:IsA("BodyPosition") or inst:IsA("BodyAngularVelocity")
        or inst:IsA("BodyGyro") or inst:IsA("LinearVelocity") or inst:IsA("VectorForce") or inst:IsA("AlignPosition") then
        if inst.Name ~= "NovaMover" and not State.VoidKillActive and isStunName(inst.Name) then
            task.defer(function() pcall(function() inst:Destroy() end) end)
        end
    elseif (inst:IsA("BoolValue") or inst:IsA("StringValue") or inst:IsA("NumberValue")
        or inst:IsA("IntValue") or inst:IsA("ObjectValue") or inst:IsA("Accessory"))
        and isStunName(inst.Name) then
        task.defer(function() pcall(function() inst:Destroy() end) end)
    end
end

local function enforceOldFullAntiStun(char, root, hum)
    if not char or not root or not hum then return end

    if root.Anchored and not isCharacterUsingSkill(char) then root.Anchored = false end
    for _, part in ipairs(char:GetChildren()) do
        if part:IsA("BasePart") and part.Anchored and not isCharacterUsingSkill(char) then
            part.Anchored = false
        end
    end

    if hum.PlatformStand then hum.PlatformStand = false end
    if hum.Sit then hum.Sit = false end
    hum.AutoRotate = true
    hum:SetStateEnabled(Enum.HumanoidStateType.Ragdoll, false)
    hum:SetStateEnabled(Enum.HumanoidStateType.FallingDown, false)
    hum:SetStateEnabled(Enum.HumanoidStateType.Physics, false)
    hum:SetStateEnabled(Enum.HumanoidStateType.Jumping, true)

    local curState = hum:GetState()
    if curState == Enum.HumanoidStateType.Ragdoll
        or curState == Enum.HumanoidStateType.FallingDown
        or curState == Enum.HumanoidStateType.Physics
        or curState == Enum.HumanoidStateType.PlatformStanding then
        hum:ChangeState(Enum.HumanoidStateType.Running)
    end

    local targetWS = Config.SpeedEnabled and Config.WalkSpeed or 16
    if hum.WalkSpeed < targetWS then
        hum.WalkSpeed = targetWS
    end
    local targetJP = Config.JumpBoostEnabled and Config.JumpPower or 50
    if hum.UseJumpPower and hum.JumpPower < targetJP then
        hum.JumpPower = targetJP
    end

    for _, child in ipairs(char:GetChildren()) do
        cleanStunInstance(child)
    end
    for _, child in ipairs(root:GetChildren()) do
        cleanStunInstance(child)
    end

    for attrName, attrVal in pairs(char:GetAttributes()) do
        if isStunName(attrName) and attrVal == true then
            char:SetAttribute(attrName, false)
        end
    end
    for attrName, attrVal in pairs(hum:GetAttributes()) do
        if isStunName(attrName) and attrVal == true then
            hum:SetAttribute(attrName, false)
        end
    end
end

-- // FIXED GRAB DETECTION CHO VOID KILL (KHÔNG BẮT NHẦM KHI ĐANG TUNG SKILL THƯỜNG)
-- Nguyên nhân bản cũ bật Void Kill lên là không xài được skill:
--   Hàm `scanProximityGrab()` cũ có dòng: `local isGrabbed = eHum.PlatformStand or (eHum:GetState() == Enum.HumanoidStateType.Physics)`
--   Chỉ cần có bất kỳ kẻ địch nào đứng gần <= 5.8 studs đang bị choáng/ngã (PlatformStand), bản cũ tưởng nhầm là đã Grab
--   nên lập tức dịch chuyển bạn xuống đáy vực (-500), làm hủy toàn bộ các skill bạn vừa bấm!
--   Sửa lại: Chỉ kích hoạt Void Kill khi thực sự có khớp nối vật lý (Weld / WeldConstraint / Motor6D / ObjectValue Grab)
--   nối trực tiếp giữa nhân vật của bạn và nhân vật địch.
local function checkGrabJoint(inst)
    local myChar = State.Char
    local myRoot = State.Root
    if not myChar or not myRoot then return nil end

    if inst:IsA("Weld") or inst:IsA("WeldConstraint") or inst:IsA("Motor6D") or inst:IsA("JointInstance") then
        if not inst.Enabled then return nil end
        local p0, p1 = inst.Part0, inst.Part1
        if p0 and p1 then
            if p0:IsDescendantOf(myChar) and not p1:IsDescendantOf(myChar) then
                local model = p1:FindFirstAncestorOfClass("Model")
                local plr = model and Players:GetPlayerFromCharacter(model)
                if plr and plr ~= LocalPlayer then
                    return plr
                end
            elseif p1:IsDescendantOf(myChar) and not p0:IsDescendantOf(myChar) then
                local model = p0:FindFirstAncestorOfClass("Model")
                local plr = model and Players:GetPlayerFromCharacter(model)
                if plr and plr ~= LocalPlayer then
                    return plr
                end
            end
        end
    elseif inst:IsA("ObjectValue") then
        local lowerName = string.lower(inst.Name)
        if string.find(lowerName, "grab") or string.find(lowerName, "victim") then
            if inst.Value and inst.Value:IsA("Model") then
                return Players:GetPlayerFromCharacter(inst.Value)
            elseif inst.Value and inst.Value:IsA("Player") then
                return inst.Value
            end
        end
    end
    return nil
end

-- // TRIGGER VOID KILL SEQUENCE
local function executeVoidKillSequence(enemyPlayer)
    if not Config.ScriptRunning or State.VoidKillActive or not Config.AutoVoidKill then return end
    if not enemyPlayer or not enemyPlayer.Character then return end
    local myRoot = State.Root
    local myHum = State.Hum
    if not myRoot or not myHum or myHum.Health <= 0 then return end

    State.VoidKillActive = true
    State.GrabbedEnemy = enemyPlayer
    State.VoidReturnCFrame = State.LastSafeCFrame or myRoot.CFrame

    local voidHeight = Workspace.FallenPartsDestroyHeight
    if voidHeight ~= voidHeight or voidHeight < -10000 or voidHeight > 500 then
        voidHeight = -500
    end
    local safeHoverY = voidHeight + 42
    local dropXZ = Vector3.new(myRoot.Position.X, safeHoverY, myRoot.Position.Z)

    task.spawn(function()
        -- Chờ 0.12s để animation bắt/chụp của skill khóa chặt mục tiêu trước khi kéo xuống vực
        task.wait(0.12)

        local startTime = tick()
        local maxDuration = Config.VoidHoldTime

        while (tick() - startTime) < maxDuration and Config.ScriptRunning and Config.AutoVoidKill and State.Root and State.Hum and State.Hum.Health > 0 do
            local eChar = enemyPlayer and enemyPlayer.Character
            local eRoot = eChar and eChar:FindFirstChild("HumanoidRootPart")
            local eHum = eChar and eChar:FindFirstChildOfClass("Humanoid")

            State.Root.CFrame = CFrame.new(dropXZ) * CFrame.Angles(math.rad(-85), 0, 0)
            State.Root.AssemblyLinearVelocity = Vector3.zero
            State.Root.AssemblyAngularVelocity = Vector3.zero

            if (tick() - startTime) > 0.35 then
                if not eRoot or not eHum or eHum.Health <= 0 or eRoot.Position.Y <= (voidHeight + 8) then
                    break
                end
                if (eRoot.Position - State.Root.Position).Magnitude > 22 then
                    break
                end
            end

            RunService.Heartbeat:Wait()
        end

        if State.Root and State.VoidReturnCFrame then
            for i = 1, 5 do
                State.Root.CFrame = State.VoidReturnCFrame + Vector3.new(0, 3, 0)
                State.Root.AssemblyLinearVelocity = Vector3.zero
                State.Root.AssemblyAngularVelocity = Vector3.zero
                RunService.RenderStepped:Wait()
            end
        end

        State.GrabbedEnemy = nil
        State.VoidKillActive = false
    end)
end

local function scanProximityGrab()
    if not Config.ScriptRunning or not Config.AutoVoidKill or State.VoidKillActive then return end
    local myChar = State.Char
    local myRoot = State.Root
    local myHum = State.Hum
    if not myChar or not myRoot or not myHum then return end

    -- Quét các khớp Weld thực tế nối giữa nhân vật mình và nhân vật địch trong phạm vi gần
    for _, plr in ipairs(Players:GetPlayers()) do
        if plr ~= LocalPlayer and plr.Character then
            local eRoot = plr.Character:FindFirstChild("HumanoidRootPart")
            local eHum = plr.Character:FindFirstChildOfClass("Humanoid")
            if eRoot and eHum and eHum.Health > 0 then
                local dist = (eRoot.Position - myRoot.Position).Magnitude
                if dist <= 7.5 then
                    local hasRealGrabWeld = false
                    for _, child in ipairs(plr.Character:GetDescendants()) do
                        if (child:IsA("Weld") or child:IsA("WeldConstraint") or child:IsA("Motor6D")) and child.Enabled then
                            local p0, p1 = child.Part0, child.Part1
                            if (p0 and p0:IsDescendantOf(myChar)) or (p1 and p1:IsDescendantOf(myChar)) then
                                hasRealGrabWeld = true
                                break
                            end
                        end
                    end
                    if not hasRealGrabWeld then
                        for _, child in ipairs(myChar:GetDescendants()) do
                            if (child:IsA("Weld") or child:IsA("WeldConstraint") or child:IsA("Motor6D")) and child.Enabled then
                                local p0, p1 = child.Part0, child.Part1
                                if (p0 and p0:IsDescendantOf(plr.Character)) or (p1 and p1:IsDescendantOf(plr.Character)) then
                                    hasRealGrabWeld = true
                                    break
                                end
                            end
                        end
                    end
                    if hasRealGrabWeld then
                        executeVoidKillSequence(plr)
                        return
                    end
                end
            end
        end
    end
end

local function bindCharacter(char)
    for _, c in ipairs(State.CharConnections) do
        pcall(function() c:Disconnect() end)
    end
    State.CharConnections = {}

    if not char or not Config.ScriptRunning then return end
    State.Char = char
    State.Root = char:WaitForChild("HumanoidRootPart", 5)
    State.Hum = char:WaitForChild("Humanoid", 5)

    if not State.Root or not State.Hum then return end

    table.insert(State.CharConnections, char.DescendantAdded:Connect(function(inst)
        if not Config.ScriptRunning then return end
        if Config.AntiStunEnabled then
            cleanStunInstance(inst)
        end
        if Config.AutoVoidKill and not State.VoidKillActive then
            task.defer(function()
                local victim = checkGrabJoint(inst)
                if victim then
                    executeVoidKillSequence(victim)
                end
            end)
        end
    end))

    table.insert(State.CharConnections, char.AttributeChanged:Connect(function(attrName)
        if Config.ScriptRunning and Config.AntiStunEnabled and isStunName(attrName) then
            if char:GetAttribute(attrName) == true then
                char:SetAttribute(attrName, false)
            end
        end
    end))

    table.insert(State.CharConnections, State.Hum.AttributeChanged:Connect(function(attrName)
        if Config.ScriptRunning and Config.AntiStunEnabled and isStunName(attrName) then
            if State.Hum:GetAttribute(attrName) == true then
                State.Hum:SetAttribute(attrName, false)
            end
        end
    end))

    table.insert(State.CharConnections, State.Hum.StateChanged:Connect(function(_, newState)
        if Config.ScriptRunning and Config.AntiStunEnabled then
            if newState == Enum.HumanoidStateType.Ragdoll
                or newState == Enum.HumanoidStateType.FallingDown
                or newState == Enum.HumanoidStateType.Physics
                or newState == Enum.HumanoidStateType.PlatformStanding then
                State.Hum:ChangeState(Enum.HumanoidStateType.Running)
            end
        end
    end))
end

if LocalPlayer.Character then
    task.spawn(bindCharacter, LocalPlayer.Character)
end
table.insert(State.Connections, LocalPlayer.CharacterAdded:Connect(bindCharacter))

-- // SAFE GUI PARENTING
local function getGuiParent()
    local success, res = pcall(function()
        return (gethui and gethui()) or CoreGui
    end)
    if success and res then return res end
    return LocalPlayer:WaitForChild("PlayerGui")
end

for _, name in ipairs({"OllieBenchUI", "OllieFluentUI", "NovaHubUI"}) do
    local old = getGuiParent():FindFirstChild(name)
    if old then old:Destroy() end
end

-- // DRAG ENGINE
local function makeDraggable(dragHandle, targetFrame, onTapCallback)
    local dragging = false
    local dragInput = nil
    local dragStart = nil
    local startPos = nil
    local movedBeyondThreshold = false

    dragHandle.InputBegan:Connect(function(input)
        if input.UserInputType == Enum.UserInputType.MouseButton1 or input.UserInputType == Enum.UserInputType.Touch then
            dragging = true
            movedBeyondThreshold = false
            dragStart = input.Position
            startPos = targetFrame.Position

            input.Changed:Connect(function()
                if input.UserInputState == Enum.UserInputState.End then
                    if dragging then
                        dragging = false
                        if not movedBeyondThreshold and onTapCallback then
                            onTapCallback()
                        end
                    end
                end
            end)
        end
    end)

    dragHandle.InputChanged:Connect(function(input)
        if input.UserInputType == Enum.UserInputType.MouseMovement or input.UserInputType == Enum.UserInputType.Touch then
            dragInput = input
        end
    end)

    table.insert(State.Connections, UserInputService.InputChanged:Connect(function(input)
        if input == dragInput and dragging then
            local delta = input.Position - dragStart
            if delta.Magnitude > 6 then
                movedBeyondThreshold = true
            end
            targetFrame.Position = UDim2.new(
                startPos.X.Scale,
                startPos.X.Offset + delta.X,
                startPos.Y.Scale,
                startPos.Y.Offset + delta.Y
            )
        end
    end))
end

local function findNearestValidPlayer()
    local myRoot = State.Root
    local refPos = myRoot and myRoot.Position or Camera.CFrame.Position
    local closestPlayer = nil
    local shortestDist = math.huge

    for _, plr in ipairs(Players:GetPlayers()) do
        if plr ~= LocalPlayer and plr.Character then
            local tRoot = plr.Character:FindFirstChild("HumanoidRootPart")
            local tHum = plr.Character:FindFirstChildOfClass("Humanoid")
            if tRoot and tHum and tHum.Health > 0 then
                local dist = (tRoot.Position - refPos).Magnitude
                if dist < shortestDist then
                    shortestDist = dist
                    closestPlayer = plr
                end
            end
        end
    end
    return closestPlayer
end

-- // SHARED CAMERA FLOOR PAD & INVISIBLE CLEANUP HELPERS
local function ensureFlyPad()
    if State.FlyPad and State.FlyPad.Parent then return State.FlyPad end
    local pad = Instance.new("Part")
    pad.Name = "CameraOcclusionPart"
    pad.Size = Vector3.new(6.5, 1.2, 6.5)
    pad.Transparency = 1
    pad.Anchored = true
    pad.CanCollide = true
    pad.Parent = Camera
    State.FlyPad = pad
    return pad
end

local function clearFlyPad()
    if State.FlyPad then
        State.FlyPad:Destroy()
        State.FlyPad = nil
    end
end

local function getRootMotor(char)
    local lowerTorso = char:FindFirstChild("LowerTorso")
    if lowerTorso and lowerTorso:FindFirstChild("Root") then
        return lowerTorso.Root
    end
    local hrp = char:FindFirstChild("HumanoidRootPart")
    if hrp and hrp:FindFirstChild("RootJoint") then
        return hrp.RootJoint
    end
    return nil
end

local function cleanupInvisible()
    local char = State.Char
    if State.InvisData.Seat then
        State.InvisData.Seat:Destroy()
        State.InvisData.Seat = nil
    end
    if char then
        local motor = getRootMotor(char)
        if motor and State.InvisData.SavedC0 then
            motor.C0 = State.InvisData.SavedC0
            State.InvisData.SavedC0 = nil
        end
        for _, v in ipairs(State.InvisData.HiddenParts) do
            if v and v.Parent then
                v.LocalTransparencyModifier = 0
                v.CanCollide = true
            end
        end
    end
    State.InvisData.HiddenParts = {}
end

-- // UI ROOT
local ScreenGui = Instance.new("ScreenGui")
ScreenGui.Name = "NovaHubUI"
ScreenGui.ResetOnSpawn = false
ScreenGui.IgnoreGuiInset = true
ScreenGui.ZIndexBehavior = Enum.ZIndexBehavior.Sibling
ScreenGui.Parent = getGuiParent()

-- // 1. FLOATING NOVA HUB "N" APP ICON
local AppIcon = Instance.new("TextButton")
AppIcon.Name = "NovaFloatingIcon"
AppIcon.Size = UDim2.new(0, 42, 0, 42)
AppIcon.Position = UDim2.new(0, 20, 0.45, 0)
AppIcon.BackgroundColor3 = Color3.fromRGB(0, 0, 0)
AppIcon.BackgroundTransparency = 0
AppIcon.Text = "N"
AppIcon.TextColor3 = Color3.fromRGB(255, 255, 255)
AppIcon.Font = Enum.Font.GothamBlack
AppIcon.TextSize = 22
AppIcon.AutoButtonColor = false
AppIcon.Parent = ScreenGui

local IconCorner = Instance.new("UICorner", AppIcon)
IconCorner.CornerRadius = UDim.new(0, 10)

local IconStroke = Instance.new("UIStroke", AppIcon)
IconStroke.Color = Color3.fromRGB(45, 45, 50)
IconStroke.Thickness = 1.2

local StatusDot = Instance.new("Frame")
StatusDot.Size = UDim2.new(0, 7, 0, 7)
StatusDot.Position = UDim2.new(1, -9, 0, 3)
StatusDot.BackgroundColor3 = Color3.fromRGB(65, 225, 120)
StatusDot.BorderSizePixel = 0
StatusDot.Parent = AppIcon
Instance.new("UICorner", StatusDot).CornerRadius = UDim.new(1, 0)

-- // 2. DEDICATED AIMBOT POP-UP MINI WINDOW
local AimbotPopup = Instance.new("Frame")
AimbotPopup.Name = "AimbotStickyPopup"
AimbotPopup.Size = UDim2.new(0, 155, 0, 58)
AimbotPopup.Position = UDim2.new(0.82, -75, 0.35, 0)
AimbotPopup.BackgroundColor3 = Color3.fromRGB(16, 17, 20)
AimbotPopup.BackgroundTransparency = 0.1
AimbotPopup.BorderSizePixel = 0
AimbotPopup.Visible = false
AimbotPopup.Active = true
AimbotPopup.Parent = ScreenGui
Instance.new("UICorner", AimbotPopup).CornerRadius = UDim.new(0, 8)

local AimPopupStroke = Instance.new("UIStroke", AimbotPopup)
AimPopupStroke.Color = Color3.fromRGB(65, 70, 85)
AimPopupStroke.Thickness = 1.2

local AimPopBtn = Instance.new("TextButton")
AimPopBtn.Size = UDim2.new(1, -12, 0, 28)
AimPopBtn.Position = UDim2.new(0, 6, 0, 6)
AimPopBtn.BackgroundColor3 = Color3.fromRGB(36, 40, 48)
AimPopBtn.Text = "Aimbot: OFF"
AimPopBtn.TextColor3 = Color3.fromRGB(240, 245, 255)
AimPopBtn.Font = Enum.Font.GothamBold
AimPopBtn.TextSize = 12
AimPopBtn.AutoButtonColor = false
AimPopBtn.Parent = AimbotPopup
Instance.new("UICorner", AimPopBtn).CornerRadius = UDim.new(0, 6)

local AimTargetLabel = Instance.new("TextLabel")
AimTargetLabel.Size = UDim2.new(1, -12, 0, 16)
AimTargetLabel.Position = UDim2.new(0, 6, 0, 37)
AimTargetLabel.BackgroundTransparency = 1
AimTargetLabel.Text = "Target: None"
AimTargetLabel.TextColor3 = Color3.fromRGB(165, 175, 195)
AimTargetLabel.Font = Enum.Font.GothamSemibold
AimTargetLabel.TextSize = 10
AimTargetLabel.TextTruncate = Enum.TextTruncate.AtEnd
AimTargetLabel.Parent = AimbotPopup

local function setAimbotActiveState(enable)
    Config.AimbotActive = enable
    if enable then
        State.LockedAimbotPlayer = findNearestValidPlayer()
        if State.LockedAimbotPlayer then
            AimPopBtn.Text = "Aimbot: ON"
            AimPopBtn.BackgroundColor3 = Color3.fromRGB(45, 135, 220)
            AimPopupStroke.Color = Color3.fromRGB(70, 180, 255)
            AimTargetLabel.Text = "Locked: " .. State.LockedAimbotPlayer.Name
            AimTargetLabel.TextColor3 = Color3.fromRGB(115, 215, 255)
        else
            Config.AimbotActive = false
            AimPopBtn.Text = "Aimbot: OFF"
            AimPopBtn.BackgroundColor3 = Color3.fromRGB(125, 45, 45)
            AimPopupStroke.Color = Color3.fromRGB(210, 75, 75)
            AimTargetLabel.Text = "No Target Found!"
            AimTargetLabel.TextColor3 = Color3.fromRGB(255, 120, 120)
        end
    else
        State.LockedAimbotPlayer = nil
        AimPopBtn.Text = "Aimbot: OFF"
        AimPopBtn.BackgroundColor3 = Color3.fromRGB(36, 40, 48)
        AimPopupStroke.Color = Color3.fromRGB(65, 70, 85)
        AimTargetLabel.Text = "Target: None"
        AimTargetLabel.TextColor3 = Color3.fromRGB(165, 175, 195)
    end
end

makeDraggable(AimbotPopup, AimbotPopup, nil)
makeDraggable(AimPopBtn, AimbotPopup, function()
    setAimbotActiveState(not Config.AimbotActive)
end)

-- // 3. FLUENT ACRYLIC MAIN WINDOW (NOVA HUB v17)
local NormalSize = UDim2.new(0, 560, 0, 360)

local MainFrame = Instance.new("Frame")
MainFrame.Size = NormalSize
MainFrame.Position = UDim2.new(0.5, -280, 0.5, -180)
MainFrame.BackgroundColor3 = Color3.fromRGB(20, 21, 25)
MainFrame.BackgroundTransparency = 0.08
MainFrame.BorderSizePixel = 0
MainFrame.Active = true
MainFrame.Parent = ScreenGui
Instance.new("UICorner", MainFrame).CornerRadius = UDim.new(0, 8)

local MainStroke = Instance.new("UIStroke", MainFrame)
MainStroke.Color = Color3.fromRGB(58, 62, 72)
MainStroke.Transparency = 0.3
MainStroke.Thickness = 1

local TopBar = Instance.new("Frame")
TopBar.Size = UDim2.new(1, 0, 0, 38)
TopBar.BackgroundTransparency = 1
TopBar.Active = true
TopBar.Parent = MainFrame

local TopLogo = Instance.new("TextLabel")
TopLogo.Size = UDim2.new(0, 22, 0, 22)
TopLogo.Position = UDim2.new(0, 14, 0.5, -11)
TopLogo.BackgroundColor3 = Color3.fromRGB(0, 0, 0)
TopLogo.Text = "N"
TopLogo.TextColor3 = Color3.fromRGB(255, 255, 255)
TopLogo.Font = Enum.Font.GothamBlack
TopLogo.TextSize = 13
TopLogo.Parent = TopBar
Instance.new("UICorner", TopLogo).CornerRadius = UDim.new(0, 5)

local HubTitle = Instance.new("TextLabel")
HubTitle.Size = UDim2.new(0, 75, 1, 0)
HubTitle.Position = UDim2.new(0, 42, 0, 0)
HubTitle.BackgroundTransparency = 1
HubTitle.Text = "Nova Hub"
HubTitle.TextColor3 = Color3.fromRGB(245, 247, 252)
HubTitle.Font = Enum.Font.GothamBold
HubTitle.TextSize = 13
HubTitle.TextXAlignment = Enum.TextXAlignment.Left
HubTitle.Parent = TopBar

local GreenBadge = Instance.new("TextLabel")
GreenBadge.Size = UDim2.new(0, 16, 0, 16)
GreenBadge.Position = UDim2.new(0, 112, 0.5, -8)
GreenBadge.BackgroundColor3 = Color3.fromRGB(45, 195, 100)
GreenBadge.Text = "⚡"
GreenBadge.TextColor3 = Color3.fromRGB(255, 255, 255)
GreenBadge.Font = Enum.Font.GothamBold
GreenBadge.TextSize = 9
GreenBadge.Parent = TopBar
Instance.new("UICorner", GreenBadge).CornerRadius = UDim.new(1, 0)

local SubTitle = Instance.new("TextLabel")
SubTitle.Size = UDim2.new(0, 230, 1, 0)
SubTitle.Position = UDim2.new(0, 134, 0, 0)
SubTitle.BackgroundTransparency = 1
SubTitle.Text = "Heroes Battlegrounds v17 (Fixed)"
SubTitle.TextColor3 = Color3.fromRGB(155, 165, 180)
SubTitle.Font = Enum.Font.Gotham
SubTitle.TextSize = 12
SubTitle.TextXAlignment = Enum.TextXAlignment.Left
SubTitle.Parent = TopBar

-- // 3 TOP-RIGHT WINDOW BUTTONS: [—] Hide Menu | [□] Maximize/Enlarge Menu | [×] Unload Script
local MinBtn = Instance.new("TextButton")
MinBtn.Size = UDim2.new(0, 34, 0, 28)
MinBtn.Position = UDim2.new(1, -108, 0, 5)
MinBtn.BackgroundTransparency = 1
MinBtn.Text = "—"
MinBtn.TextColor3 = Color3.fromRGB(185, 190, 200)
MinBtn.Font = Enum.Font.Gotham
MinBtn.TextSize = 12
MinBtn.Parent = TopBar

local MaxBtn = Instance.new("TextButton")
MaxBtn.Size = UDim2.new(0, 34, 0, 28)
MaxBtn.Position = UDim2.new(1, -72, 0, 5)
MaxBtn.BackgroundTransparency = 1
MaxBtn.Text = "□"
MaxBtn.TextColor3 = Color3.fromRGB(185, 190, 200)
MaxBtn.Font = Enum.Font.GothamBold
MaxBtn.TextSize = 13
MaxBtn.Parent = TopBar

local ExitBtn = Instance.new("TextButton")
ExitBtn.Size = UDim2.new(0, 34, 0, 28)
ExitBtn.Position = UDim2.new(1, -36, 0, 5)
ExitBtn.BackgroundTransparency = 1
ExitBtn.Text = "×"
ExitBtn.TextColor3 = Color3.fromRGB(235, 95, 95)
ExitBtn.Font = Enum.Font.GothamBold
ExitBtn.TextSize = 18
ExitBtn.Parent = TopBar

local isMaximized = false

local function toggleMenu()
    if not Config.ScriptRunning then return end
    MainFrame.Visible = not MainFrame.Visible
    StatusDot.BackgroundColor3 = MainFrame.Visible and Color3.fromRGB(65, 225, 120) or Color3.fromRGB(230, 75, 75)
end

local function toggleMaximizeMenu()
    if not Config.ScriptRunning then return end
    isMaximized = not isMaximized
    local vp = Camera.ViewportSize
    local targetW = isMaximized and math.min(720, vp.X - 30) or 560
    local targetH = isMaximized and math.min(460, vp.Y - 30) or 360

    TweenService:Create(MainFrame, TweenInfo.new(0.22, Enum.EasingStyle.Quad, Enum.EasingDirection.Out), {
        Size = UDim2.new(0, targetW, 0, targetH),
        Position = UDim2.new(0.5, -math.floor(targetW / 2), 0.5, -math.floor(targetH / 2))
    }):Play()
    MaxBtn.TextColor3 = isMaximized and Color3.fromRGB(70, 180, 255) or Color3.fromRGB(185, 190, 200)
end

local function unloadEntireScript()
    Config.ScriptRunning = false
    Config.FlyEnabled = false
    Config.InfJumpEnabled = false
    Config.AutoTargetEnabled = false
    Config.KillAuraEnabled = false
    Config.AutoVoidKill = false
    Config.AntiVoidEnabled = false
    Config.AntiStunEnabled = false
    Config.AimbotActive = false
    Config.ESPEnabled = false

    pcall(releaseM1State)
    pcall(cleanupInvisible)
    pcall(clearFlyPad)

    if State.Hum then
        pcall(function()
            State.Hum.WalkSpeed = 16
            State.Hum.JumpPower = 50
            State.Hum:SetStateEnabled(Enum.HumanoidStateType.Ragdoll, true)
            State.Hum:SetStateEnabled(Enum.HumanoidStateType.FallingDown, true)
        end)
    end
    if State.Root then
        pcall(function()
            State.Root.AssemblyLinearVelocity = Vector3.zero
        end)
    end

    for _, c in ipairs(State.CharConnections) do
        pcall(function() c:Disconnect() end)
    end
    State.CharConnections = {}

    for _, c in ipairs(State.Connections) do
        pcall(function() c:Disconnect() end)
    end
    State.Connections = {}

    for _, obj in pairs(State.ESPObjects) do
        pcall(function() if obj.Highlight then obj.Highlight:Destroy() end end)
        pcall(function() if obj.Billboard then obj.Billboard:Destroy() end end)
    end
    State.ESPObjects = {}

    if ScreenGui and ScreenGui.Parent then
        ScreenGui:Destroy()
    end
end

MinBtn.MouseButton1Click:Connect(toggleMenu)
MaxBtn.MouseButton1Click:Connect(toggleMaximizeMenu)
ExitBtn.MouseButton1Click:Connect(unloadEntireScript)

makeDraggable(TopBar, MainFrame, nil)
makeDraggable(AppIcon, AppIcon, toggleMenu)

local Sidebar = Instance.new("Frame")
Sidebar.Size = UDim2.new(0, 150, 1, -48)
Sidebar.Position = UDim2.new(0, 10, 0, 42)
Sidebar.BackgroundTransparency = 1
Sidebar.Parent = MainFrame

local SidebarLayout = Instance.new("UIListLayout", Sidebar)
SidebarLayout.Padding = UDim.new(0, 4)
SidebarLayout.SortOrder = Enum.SortOrder.LayoutOrder

local ContentArea = Instance.new("Frame")
ContentArea.Size = UDim2.new(1, -178, 1, -48)
ContentArea.Position = UDim2.new(0, 168, 0, 42)
ContentArea.BackgroundTransparency = 1
ContentArea.Parent = MainFrame

local SectionHeader = Instance.new("TextLabel")
SectionHeader.Size = UDim2.new(1, 0, 0, 32)
SectionHeader.Position = UDim2.new(0, 4, 0, 0)
SectionHeader.BackgroundTransparency = 1
SectionHeader.Text = "Combat"
SectionHeader.TextColor3 = Color3.fromRGB(245, 247, 252)
SectionHeader.Font = Enum.Font.GothamBold
SectionHeader.TextSize = 22
SectionHeader.TextXAlignment = Enum.TextXAlignment.Left
SectionHeader.Parent = ContentArea

local SidebarButtons = {}

local function createTab(name, iconChar)
    local TabBtn = Instance.new("TextButton")
    TabBtn.Size = UDim2.new(1, 0, 0, 34)
    TabBtn.BackgroundColor3 = Color3.fromRGB(45, 48, 56)
    TabBtn.BackgroundTransparency = 1
    TabBtn.Text = ""
    TabBtn.AutoButtonColor = false
    TabBtn.Parent = Sidebar
    Instance.new("UICorner", TabBtn).CornerRadius = UDim.new(0, 6)

    local CyanBar = Instance.new("Frame")
    CyanBar.Size = UDim2.new(0, 3, 0, 16)
    CyanBar.Position = UDim2.new(0, 0, 0.5, -8)
    CyanBar.BackgroundColor3 = Color3.fromRGB(60, 180, 255)
    CyanBar.BorderSizePixel = 0
    CyanBar.Visible = false
    CyanBar.Parent = TabBtn
    Instance.new("UICorner", CyanBar).CornerRadius = UDim.new(1, 0)

    local IconLbl = Instance.new("TextLabel")
    IconLbl.Size = UDim2.new(0, 24, 0, 24)
    IconLbl.Position = UDim2.new(0, 10, 0.5, -12)
    IconLbl.BackgroundTransparency = 1
    IconLbl.Text = iconChar
    IconLbl.TextColor3 = Color3.fromRGB(175, 182, 195)
    IconLbl.Font = Enum.Font.GothamBold
    IconLbl.TextSize = 13
    IconLbl.Parent = TabBtn

    local TextLbl = Instance.new("TextLabel")
    TextLbl.Size = UDim2.new(1, -40, 1, 0)
    TextLbl.Position = UDim2.new(0, 36, 0, 0)
    TextLbl.BackgroundTransparency = 1
    TextLbl.Text = name
    TextLbl.TextColor3 = Color3.fromRGB(175, 182, 195)
    TextLbl.Font = Enum.Font.GothamMedium
    TextLbl.TextSize = 12
    TextLbl.TextXAlignment = Enum.TextXAlignment.Left
    TextLbl.Parent = TabBtn

    local Page = Instance.new("ScrollingFrame")
    Page.Size = UDim2.new(1, 0, 1, -40)
    Page.Position = UDim2.new(0, 0, 0, 40)
    Page.BackgroundTransparency = 1
    Page.ScrollBarThickness = 2
    Page.ScrollBarImageColor3 = Color3.fromRGB(70, 175, 255)
    Page.Visible = false
    Page.CanvasSize = UDim2.new(0, 0, 0, 0)
    Page.AutomaticCanvasSize = Enum.AutomaticSize.Y
    Page.Parent = ContentArea

    local Layout = Instance.new("UIListLayout", Page)
    Layout.Padding = UDim.new(0, 8)
    Layout.SortOrder = Enum.SortOrder.LayoutOrder

    local Pad = Instance.new("UIPadding", Page)
    Pad.PaddingBottom = UDim.new(0, 12)
    Pad.PaddingRight = UDim.new(0, 6)

    local tabData = {Btn = TabBtn, Bar = CyanBar, Text = TextLbl, Icon = IconLbl, Page = Page, Name = name}
    table.insert(SidebarButtons, tabData)

    local function activateTab()
        SectionHeader.Text = name
        for _, t in ipairs(SidebarButtons) do
            t.Page.Visible = false
            t.Bar.Visible = false
            TweenService:Create(t.Btn, TweenInfo.new(0.15), {BackgroundTransparency = 1}):Play()
            t.Text.TextColor3 = Color3.fromRGB(175, 182, 195)
            t.Icon.TextColor3 = Color3.fromRGB(175, 182, 195)
        end
        Page.Visible = true
        CyanBar.Visible = true
        TweenService:Create(TabBtn, TweenInfo.new(0.15), {BackgroundTransparency = 0.65}):Play()
        TextLbl.TextColor3 = Color3.fromRGB(245, 247, 252)
        IconLbl.TextColor3 = Color3.fromRGB(60, 180, 255)
    end

    TabBtn.MouseButton1Click:Connect(activateTab)

    if #SidebarButtons == 1 then
        activateTab()
    end
    return Page
end

-- // FLUENT CARD ROW + PILL SWITCH TOGGLE + PIN SHORTCUT
local pinCount = 0
local function addFeatureToggle(parent, id, label, shortName, defaultState, callback)
    defaultState = (defaultState == true)
    local Card = Instance.new("Frame")
    Card.Size = UDim2.new(1, 0, 0, 42)
    Card.BackgroundColor3 = Color3.fromRGB(32, 34, 40)
    Card.BackgroundTransparency = 0.25
    Card.BorderSizePixel = 0
    Card.Parent = parent
    Instance.new("UICorner", Card).CornerRadius = UDim.new(0, 6)

    local CardStroke = Instance.new("UIStroke", Card)
    CardStroke.Color = Color3.fromRGB(52, 56, 66)
    CardStroke.Transparency = 0.4
    CardStroke.Thickness = 1

    local Label = Instance.new("TextLabel")
    Label.Size = UDim2.new(1, -115, 1, 0)
    Label.Position = UDim2.new(0, 14, 0, 0)
    Label.BackgroundTransparency = 1
    Label.Text = label
    Label.TextColor3 = Color3.fromRGB(230, 234, 242)
    Label.Font = Enum.Font.GothamMedium
    Label.TextSize = 13
    Label.TextXAlignment = Enum.TextXAlignment.Left
    Label.Parent = Card

    local PinBtn = Instance.new("TextButton")
    PinBtn.Size = UDim2.new(0, 36, 0, 22)
    PinBtn.Position = UDim2.new(1, -96, 0.5, -11)
    PinBtn.BackgroundColor3 = Color3.fromRGB(40, 43, 52)
    PinBtn.BackgroundTransparency = 0.2
    PinBtn.Text = "PIN"
    PinBtn.TextColor3 = Color3.fromRGB(150, 165, 190)
    PinBtn.Font = Enum.Font.GothamBold
    PinBtn.TextSize = 9
    PinBtn.AutoButtonColor = false
    PinBtn.Parent = Card
    Instance.new("UICorner", PinBtn).CornerRadius = UDim.new(0, 4)

    local SwitchTrack = Instance.new("TextButton")
    SwitchTrack.Size = UDim2.new(0, 42, 0, 22)
    SwitchTrack.Position = UDim2.new(1, -52, 0.5, -11)
    SwitchTrack.BackgroundColor3 = defaultState and Color3.fromRGB(55, 170, 255) or Color3.fromRGB(42, 45, 54)
    SwitchTrack.Text = ""
    SwitchTrack.AutoButtonColor = false
    SwitchTrack.Parent = Card
    Instance.new("UICorner", SwitchTrack).CornerRadius = UDim.new(1, 0)

    local SwitchStroke = Instance.new("UIStroke", SwitchTrack)
    SwitchStroke.Color = defaultState and Color3.fromRGB(80, 190, 255) or Color3.fromRGB(75, 80, 95)
    SwitchStroke.Thickness = 1

    local Knob = Instance.new("Frame")
    Knob.Size = UDim2.new(0, 16, 0, 16)
    Knob.Position = defaultState and UDim2.new(1, -19, 0.5, -8) or UDim2.new(0, 3, 0.5, -8)
    Knob.BackgroundColor3 = defaultState and Color3.fromRGB(255, 255, 255) or Color3.fromRGB(165, 170, 182)
    Knob.BorderSizePixel = 0
    Knob.Parent = SwitchTrack
    Instance.new("UICorner", Knob).CornerRadius = UDim.new(1, 0)

    local ClickZone = Instance.new("TextButton")
    ClickZone.Size = UDim2.new(1, -105, 1, 0)
    ClickZone.BackgroundTransparency = 1
    ClickZone.Text = ""
    ClickZone.Parent = Card

    local state = defaultState

    local function syncVisuals()
        TweenService:Create(SwitchTrack, TweenInfo.new(0.18, Enum.EasingStyle.Quad, Enum.EasingDirection.Out), {
            BackgroundColor3 = state and Color3.fromRGB(55, 170, 255) or Color3.fromRGB(42, 45, 54)
        }):Play()
        TweenService:Create(SwitchStroke, TweenInfo.new(0.18), {
            Color = state and Color3.fromRGB(80, 190, 255) or Color3.fromRGB(75, 80, 95)
        }):Play()
        TweenService:Create(Knob, TweenInfo.new(0.18, Enum.EasingStyle.Quad, Enum.EasingDirection.Out), {
            Position = state and UDim2.new(1, -19, 0.5, -8) or UDim2.new(0, 3, 0.5, -8),
            BackgroundColor3 = state and Color3.fromRGB(255, 255, 255) or Color3.fromRGB(165, 170, 182)
        }):Play()

        local floatBtn = State.PinnedButtons[id]
        if floatBtn then
            floatBtn.BackgroundColor3 = state and Color3.fromRGB(45, 145, 225) or Color3.fromRGB(16, 17, 22)
            floatBtn.Text = shortName .. "\n" .. (state and "ON" or "OFF")
        end
    end

    local function setFeatureState(newState)
        if not Config.UIInitialized then return end
        state = (newState == true)
        syncVisuals()
        callback(state)
    end

    SwitchTrack.MouseButton1Click:Connect(function() setFeatureState(not state) end)
    ClickZone.MouseButton1Click:Connect(function() setFeatureState(not state) end)

    PinBtn.MouseButton1Click:Connect(function()
        if State.PinnedButtons[id] then
            State.PinnedButtons[id]:Destroy()
            State.PinnedButtons[id] = nil
            PinBtn.BackgroundColor3 = Color3.fromRGB(40, 43, 52)
            PinBtn.Text = "PIN"
            PinBtn.TextColor3 = Color3.fromRGB(150, 165, 190)
        else
            pinCount = (pinCount % 7) + 1
            local FloatBtn = Instance.new("TextButton")
            FloatBtn.Name = "Pin_" .. id
            FloatBtn.Size = UDim2.new(0, 52, 0, 36)
            FloatBtn.Position = UDim2.new(0, 68, 0.22, pinCount * 42)
            FloatBtn.BackgroundColor3 = state and Color3.fromRGB(45, 145, 225) or Color3.fromRGB(16, 17, 22)
            FloatBtn.BackgroundTransparency = 0.1
            FloatBtn.Text = shortName .. "\n" .. (state and "ON" or "OFF")
            FloatBtn.TextColor3 = Color3.fromRGB(240, 245, 255)
            FloatBtn.Font = Enum.Font.GothamBold
            FloatBtn.TextSize = 10
            FloatBtn.AutoButtonColor = false
            FloatBtn.Parent = ScreenGui
            Instance.new("UICorner", FloatBtn).CornerRadius = UDim.new(0, 8)

            local fStroke = Instance.new("UIStroke", FloatBtn)
            fStroke.Color = Color3.fromRGB(70, 175, 255)
            fStroke.Thickness = 1.2

            State.PinnedButtons[id] = FloatBtn
            PinBtn.BackgroundColor3 = Color3.fromRGB(55, 145, 220)
            PinBtn.Text = "UNPIN"
            PinBtn.TextColor3 = Color3.fromRGB(255, 255, 255)

            makeDraggable(FloatBtn, FloatBtn, function()
                setFeatureState(not state)
            end)
        end
    end)

    State.ToggleRegistry[id] = setFeatureState
end

-- // FLUENT CARD DROPDOWN BUILDER
local function addDropdown(parent, label, options, defaultIndex, callback)
    local isOpen = false
    local selectedValue = options[defaultIndex or 1] or "None"

    local Container = Instance.new("Frame")
    Container.Size = UDim2.new(1, 0, 0, 44)
    Container.BackgroundColor3 = Color3.fromRGB(32, 34, 40)
    Container.BackgroundTransparency = 0.25
    Container.BorderSizePixel = 0
    Container.ClipsDescendants = true
    Container.Parent = parent
    Instance.new("UICorner", Container).CornerRadius = UDim.new(0, 6)

    local CardStroke = Instance.new("UIStroke", Container)
    CardStroke.Color = Color3.fromRGB(52, 56, 66)
    CardStroke.Transparency = 0.4
    CardStroke.Thickness = 1

    local HeaderBtn = Instance.new("TextButton")
    HeaderBtn.Size = UDim2.new(1, 0, 0, 44)
    HeaderBtn.BackgroundTransparency = 1
    HeaderBtn.Text = ""
    HeaderBtn.AutoButtonColor = false
    HeaderBtn.Parent = Container

    local TitleLbl = Instance.new("TextLabel")
    TitleLbl.Size = UDim2.new(0.55, -14, 1, 0)
    TitleLbl.Position = UDim2.new(0, 14, 0, 0)
    TitleLbl.BackgroundTransparency = 1
    TitleLbl.Text = label
    TitleLbl.TextColor3 = Color3.fromRGB(230, 234, 242)
    TitleLbl.Font = Enum.Font.GothamMedium
    TitleLbl.TextSize = 13
    TitleLbl.TextXAlignment = Enum.TextXAlignment.Left
    TitleLbl.Parent = HeaderBtn

    local SelectBox = Instance.new("Frame")
    SelectBox.Size = UDim2.new(0.42, -14, 0, 28)
    SelectBox.Position = UDim2.new(0.58, 0, 0.5, -14)
    SelectBox.BackgroundColor3 = Color3.fromRGB(40, 43, 50)
    SelectBox.BackgroundTransparency = 0.15
    SelectBox.BorderSizePixel = 0
    SelectBox.Parent = HeaderBtn
    Instance.new("UICorner", SelectBox).CornerRadius = UDim.new(0, 5)

    local BoxStroke = Instance.new("UIStroke", SelectBox)
    BoxStroke.Color = Color3.fromRGB(65, 70, 82)
    BoxStroke.Thickness = 1

    local ValueLbl = Instance.new("TextLabel")
    ValueLbl.Size = UDim2.new(1, -28, 1, 0)
    ValueLbl.Position = UDim2.new(0, 10, 0, 0)
    ValueLbl.BackgroundTransparency = 1
    ValueLbl.Text = tostring(selectedValue)
    ValueLbl.TextColor3 = Color3.fromRGB(215, 220, 230)
    ValueLbl.Font = Enum.Font.GothamMedium
    ValueLbl.TextSize = 12
    ValueLbl.TextXAlignment = Enum.TextXAlignment.Left
    ValueLbl.TextTruncate = Enum.TextTruncate.AtEnd
    ValueLbl.Parent = SelectBox

    local Chevron = Instance.new("TextLabel")
    Chevron.Size = UDim2.new(0, 20, 1, 0)
    Chevron.Position = UDim2.new(1, -22, 0, 0)
    Chevron.BackgroundTransparency = 1
    Chevron.Text = "⌄"
    Chevron.TextColor3 = Color3.fromRGB(170, 175, 190)
    Chevron.Font = Enum.Font.GothamBold
    Chevron.TextSize = 14
    Chevron.Parent = SelectBox

    local ListFrame = Instance.new("ScrollingFrame")
    ListFrame.Size = UDim2.new(1, -20, 0, 110)
    ListFrame.Position = UDim2.new(0, 10, 0, 46)
    ListFrame.BackgroundColor3 = Color3.fromRGB(24, 26, 31)
    ListFrame.BackgroundTransparency = 0.1
    ListFrame.BorderSizePixel = 0
    ListFrame.ScrollBarThickness = 2
    ListFrame.ScrollBarImageColor3 = Color3.fromRGB(70, 175, 255)
    ListFrame.CanvasSize = UDim2.new(0, 0, 0, 0)
    ListFrame.AutomaticCanvasSize = Enum.AutomaticSize.Y
    ListFrame.Parent = Container
    Instance.new("UICorner", ListFrame).CornerRadius = UDim.new(0, 5)

    local ListPadding = Instance.new("UIPadding", ListFrame)
    ListPadding.PaddingTop = UDim.new(0, 4)
    ListPadding.PaddingBottom = UDim.new(0, 4)
    ListPadding.PaddingLeft = UDim.new(0, 4)
    ListPadding.PaddingRight = UDim.new(0, 4)

    local ListLayout = Instance.new("UIListLayout", ListFrame)
    ListLayout.Padding = UDim.new(0, 3)
    ListLayout.SortOrder = Enum.SortOrder.LayoutOrder

    local currentOptions = options

    local function setOpen(openState)
        isOpen = openState
        local count = math.clamp(#currentOptions, 1, 4)
        local listHeight = count * 27 + 8
        ListFrame.Size = UDim2.new(1, -20, 0, listHeight)
        local targetHeight = isOpen and (54 + listHeight) or 44

        TweenService:Create(Container, TweenInfo.new(0.18, Enum.EasingStyle.Quad, Enum.EasingDirection.Out), {
            Size = UDim2.new(1, 0, 0, targetHeight)
        }):Play()
        TweenService:Create(BoxStroke, TweenInfo.new(0.18), {
            Color = isOpen and Color3.fromRGB(65, 175, 255) or Color3.fromRGB(65, 70, 82)
        }):Play()
        Chevron.Text = isOpen and "⌃" or "⌄"
    end

    local function rebuildItems(newList)
        currentOptions = newList or currentOptions
        for _, child in ipairs(ListFrame:GetChildren()) do
            if child:IsA("TextButton") then child:Destroy() end
        end

        for _, opt in ipairs(currentOptions) do
            local isSelected = (opt == selectedValue)
            local ItemBtn = Instance.new("TextButton")
            ItemBtn.Size = UDim2.new(1, 0, 0, 24)
            ItemBtn.BackgroundColor3 = isSelected and Color3.fromRGB(45, 52, 65) or Color3.fromRGB(30, 32, 38)
            ItemBtn.BackgroundTransparency = isSelected and 0.1 or 0.4
            ItemBtn.Text = "   " .. tostring(opt)
            ItemBtn.TextColor3 = isSelected and Color3.fromRGB(255, 255, 255) or Color3.fromRGB(185, 190, 205)
            ItemBtn.Font = isSelected and Enum.Font.GothamSemibold or Enum.Font.Gotham
            ItemBtn.TextSize = 12
            ItemBtn.TextXAlignment = Enum.TextXAlignment.Left
            ItemBtn.AutoButtonColor = false
            ItemBtn.Parent = ListFrame
            Instance.new("UICorner", ItemBtn).CornerRadius = UDim.new(0, 4)

            local AccentBar = Instance.new("Frame")
            AccentBar.Size = UDim2.new(0, 3, 0, 14)
            AccentBar.Position = UDim2.new(0, 3, 0.5, -7)
            AccentBar.BackgroundColor3 = Color3.fromRGB(60, 180, 255)
            AccentBar.BorderSizePixel = 0
            AccentBar.Visible = isSelected
            AccentBar.Parent = ItemBtn
            Instance.new("UICorner", AccentBar).CornerRadius = UDim.new(1, 0)

            ItemBtn.MouseButton1Click:Connect(function()
                selectedValue = opt
                ValueLbl.Text = tostring(selectedValue)
                rebuildItems(currentOptions)
                setOpen(false)
                callback(selectedValue)
            end)
        end
    end

    rebuildItems(options)
    HeaderBtn.MouseButton1Click:Connect(function() setOpen(not isOpen) end)

    return {
        Refresh = function(newOptions)
            currentOptions = newOptions
            if not table.find(currentOptions, selectedValue) then
                selectedValue = currentOptions[1] or "None"
                ValueLbl.Text = tostring(selectedValue)
                callback(selectedValue)
            end
            rebuildItems(currentOptions)
            if isOpen then setOpen(true) end
        end
    }
end

local function addButton(parent, text, callback)
    local Btn = Instance.new("TextButton")
    Btn.Size = UDim2.new(1, 0, 0, 38)
    Btn.BackgroundColor3 = Color3.fromRGB(45, 95, 165)
    Btn.BackgroundTransparency = 0.1
    Btn.Text = text
    Btn.TextColor3 = Color3.fromRGB(255, 255, 255)
    Btn.Font = Enum.Font.GothamBold
    Btn.TextSize = 12
    Btn.Parent = parent
    Instance.new("UICorner", Btn).CornerRadius = UDim.new(0, 6)

    local Stroke = Instance.new("UIStroke", Btn)
    Stroke.Color = Color3.fromRGB(90, 175, 255)
    Stroke.Transparency = 0.2
    Stroke.Thickness = 1.2

    Btn.MouseButton1Click:Connect(function()
        callback(Btn)
    end)
    return Btn
end

local function addSlider(parent, label, minVal, maxVal, defaultVal, callback)
    local Holder = Instance.new("Frame")
    Holder.Size = UDim2.new(1, 0, 0, 48)
    Holder.BackgroundColor3 = Color3.fromRGB(32, 34, 40)
    Holder.BackgroundTransparency = 0.25
    Holder.Active = true
    Holder.Parent = parent
    Instance.new("UICorner", Holder).CornerRadius = UDim.new(0, 6)

    local Stroke = Instance.new("UIStroke", Holder)
    Stroke.Color = Color3.fromRGB(52, 56, 66)
    Stroke.Transparency = 0.4
    Stroke.Thickness = 1

    local TextLbl = Instance.new("TextLabel")
    TextLbl.Size = UDim2.new(1, -28, 0, 22)
    TextLbl.Position = UDim2.new(0, 14, 0, 4)
    TextLbl.BackgroundTransparency = 1
    TextLbl.Text = label .. ":  " .. tostring(defaultVal)
    TextLbl.TextColor3 = Color3.fromRGB(230, 234, 242)
    TextLbl.Font = Enum.Font.GothamMedium
    TextLbl.TextSize = 12
    TextLbl.TextXAlignment = Enum.TextXAlignment.Left
    TextLbl.Parent = Holder

    local BarBg = Instance.new("Frame")
    BarBg.Size = UDim2.new(1, -28, 0, 8)
    BarBg.Position = UDim2.new(0, 14, 0, 30)
    BarBg.BackgroundColor3 = Color3.fromRGB(20, 22, 26)
    BarBg.Active = true
    BarBg.Parent = Holder
    Instance.new("UICorner", BarBg).CornerRadius = UDim.new(1, 0)

    local BarFill = Instance.new("Frame")
    local initPct = math.clamp((defaultVal - minVal) / (maxVal - minVal), 0, 1)
    BarFill.Size = UDim2.new(initPct, 0, 1, 0)
    BarFill.BackgroundColor3 = Color3.fromRGB(60, 175, 255)
    BarFill.Parent = BarBg
    Instance.new("UICorner", BarFill).CornerRadius = UDim.new(1, 0)

    local dragging = false
    local function updateSlide(input)
        local rel = math.clamp((input.Position.X - BarBg.AbsolutePosition.X) / BarBg.AbsoluteSize.X, 0, 1)
        BarFill.Size = UDim2.new(rel, 0, 1, 0)
        local val = math.floor((minVal + (maxVal - minVal) * rel) * 100) / 100
        TextLbl.Text = label .. ":  " .. tostring(val)
        callback(val)
    end

    BarBg.InputBegan:Connect(function(input)
        if input.UserInputType == Enum.UserInputType.MouseButton1 or input.UserInputType == Enum.UserInputType.Touch then
            dragging = true
            updateSlide(input)
        end
    end)
    table.insert(State.Connections, UserInputService.InputEnded:Connect(function(input)
        if input.UserInputType == Enum.UserInputType.MouseButton1 or input.UserInputType == Enum.UserInputType.Touch then
            dragging = false
        end
    end))
    table.insert(State.Connections, UserInputService.InputChanged:Connect(function(input)
        if dragging and (input.UserInputType == Enum.UserInputType.MouseMovement or input.UserInputType == Enum.UserInputType.Touch) then
            updateSlide(input)
        end
    end))
end

-- // CREATE SIDEBAR TABS
local TabCombat = createTab("Combat", "⚔")
local TabTarget = createTab("AutoFarm", "◇")
local TabVoid   = createTab("Void & Safety", "🌀")
local TabMove   = createTab("LocalPlayer", "👤")
local TabVisual = createTab("Settings", "⚙")

local function triggerUndetectedInfJump()
    if not Config.ScriptRunning or not Config.InfJumpEnabled then return end
    local now = tick()
    if now - State.LastJumpTime < 0.14 then return end
    State.LastJumpTime = now

    local root = State.Root
    local hum = State.Hum
    if not root or not hum or hum.Health <= 0 then return end

    hum:SetStateEnabled(Enum.HumanoidStateType.Ragdoll, false)
    hum:SetStateEnabled(Enum.HumanoidStateType.FallingDown, false)

    State.InfJumpArcActive = true
    State.InfJumpArcTimer = now
end

-- // 3-MODE INVISIBLE ENGINE
local function toggleInvisible(enable)
    cleanupInvisible()
    if not enable or not Config.ScriptRunning then return end

    local char = State.Char
    local root = State.Root
    local hum = State.Hum
    if not char or not root or not hum then return end

    State.InvisData.HiddenParts = {}
    for _, v in ipairs(char:GetDescendants()) do
        if v:IsA("BasePart") and v.Name ~= "HumanoidRootPart" then
            table.insert(State.InvisData.HiddenParts, v)
        end
    end

    if Config.InvisMode == "RootJointBreak" then
        local savedCF = root.CFrame
        local motor = getRootMotor(char)
        if motor then
            State.InvisData.SavedC0 = motor.C0
            motor.C0 = motor.C0 * CFrame.new(0, 600, 0)
        end
        for _, v in ipairs(State.InvisData.HiddenParts) do
            v.LocalTransparencyModifier = 0.65
            v.CanCollide = false
        end
        root.Transparency = 0.5
        root.CanCollide = false
        root.CFrame = savedCF

    elseif Config.InvisMode == "UndergroundC0" then
        local motor = getRootMotor(char)
        if motor then
            State.InvisData.SavedC0 = motor.C0
            motor.C0 = motor.C0 * CFrame.new(0, -14, 0)
        end
        for _, v in ipairs(State.InvisData.HiddenParts) do
            v.CanCollide = false
            v.LocalTransparencyModifier = 0.65
        end
        root.Transparency = 0.5

    elseif Config.InvisMode == "SeatDesync" then
        local savedCF = root.CFrame
        root.CFrame = savedCF * CFrame.new(0, 50000, 0)
        task.wait(0.12)
        local seat = Instance.new("Seat")
        seat.Size = Vector3.new(1, 1, 1)
        seat.Transparency = 1
        seat.CanCollide = false
        seat.Name = "InvisProxy"
        seat.Parent = Camera
        seat.CFrame = savedCF

        local weld = Instance.new("Weld")
        weld.Part0 = seat
        weld.Part1 = root
        weld.Parent = seat

        root.CFrame = savedCF
        for _, v in ipairs(State.InvisData.HiddenParts) do
            v.LocalTransparencyModifier = 0.6
        end
        State.InvisData.Seat = seat
    end
end

-- // 1. POPULATE COMBAT TAB
addFeatureToggle(TabCombat, "KillAura", "Kill Aura (Fixed 4-M1 Combo + Hitbox)", "KAURA", false, function(v)
    Config.KillAuraEnabled = v
    if v then
        State.ComboStage = 1
        startKillAuraLoop()
    else
        releaseM1State()
    end
end)

addSlider(TabCombat, "Kill Aura Range (Studs)", 6, 30, 16, function(v)
    Config.KillAuraRange = v
end)

addSlider(TabCombat, "Kill Aura M1 Cadence (0.24 = Default)", 0.12, 0.45, 0.24, function(v)
    Config.KillAuraDelay = v
end)

addButton(TabCombat, "📋 COPY LOG THÔNG SỐ M1 (Bấm sau khi đánh thường 1 cái)", function(btn)
    local fullReport = "=== NOVA HUB M1 REMOTE REPORT ===\n"
    local char = LocalPlayer.Character
    if char then
        local remList = {}
        for _, v in ipairs(char:GetDescendants()) do
            if v:IsA("RemoteEvent") or v:IsA("RemoteFunction") then
                table.insert(remList, v:GetFullName() .. " (" .. v.ClassName .. ")")
            end
        end
        fullReport = fullReport .. "Character Remotes: " .. (#remList > 0 and table.concat(remList, " | ") or "None") .. "\n"
    end
    fullReport = fullReport .. "Captured Calls:\n" .. (#State.SniffedLogs > 0 and table.concat(State.SniffedLogs, "\n") or State.LastSniffedText)

    local copied = false
    pcall(function()
        if setclipboard then
            setclipboard(fullReport)
            copied = true
        elseif toclipboard then
            toclipboard(fullReport)
            copied = true
        end
    end)

    if copied then
        btn.Text = "✅ ĐÃ COPY VÀO CLIPBOARD! (Dán Ctrl+V gửi cho tôi)"
        btn.BackgroundColor3 = Color3.fromRGB(40, 150, 85)
    else
        btn.Text = "⚠️ Executor không có setclipboard (Xem F9 Console)"
        print(fullReport)
    end
    task.delay(2.5, function()
        if btn and btn.Parent then
            btn.Text = "📋 COPY LOG THÔNG SỐ M1 (Bấm sau khi đánh thường 1 cái)"
            btn.BackgroundColor3 = Color3.fromRGB(45, 95, 165)
        end
    end)
end)

addFeatureToggle(TabCombat, "AntiStun", "Anti-Stun (Full Immunity v8)", "ASTUN", false, function(v)
    Config.AntiStunEnabled = v
    if v and State.Char and State.Root and State.Hum then
        enforceOldFullAntiStun(State.Char, State.Root, State.Hum)
    end
end)

addFeatureToggle(TabCombat, "AimbotPopup", "Aimbot (Open Sticky Pop-Up)", "AIM", false, function(v)
    Config.AimbotWidgetOpen = v
    AimbotPopup.Visible = v
    if not v then setAimbotActiveState(false) end
end)

addDropdown(TabCombat, "Select Aimbot Part", {"Head", "HumanoidRootPart"}, 1, function(part)
    Config.AimPart = part
end)

-- // 2. POPULATE AUTOFARM / AUTOTARGET TAB
local function getPlayerNames()
    local list = {}
    for _, p in ipairs(Players:GetPlayers()) do
        if p ~= LocalPlayer then table.insert(list, p.Name) end
    end
    if #list == 0 then table.insert(list, "None") end
    return list
end

local currentTargetList = getPlayerNames()
Config.SelectedPlayer = currentTargetList[1]

addFeatureToggle(TabTarget, "AutoTarget", "AutoFarm Player (Zero-Delay Lock)", "TAR", false, function(v)
    Config.AutoTargetEnabled = v
    State.FreeMoveOffset = Vector3.zero
    if not v and State.Root then
        State.Root.AssemblyLinearVelocity = Vector3.zero
    end
end)

addFeatureToggle(TabTarget, "TargetFreeMove", "Free Move While Targeting", "TMOVE", false, function(v)
    Config.TargetFreeMove = v
    if not v then State.FreeMoveOffset = Vector3.zero end
end)

local PlayerDropdown = addDropdown(TabTarget, "Select a player to autofarm", currentTargetList, 1, function(selected)
    Config.SelectedPlayer = selected
    State.FreeMoveOffset = Vector3.zero
end)

addDropdown(TabTarget, "Select target mode", {"Behind", "Orbit", "Random", "Below", "Upper", "Front"}, 1, function(mode)
    Config.TargetMode = mode
    State.FreeMoveOffset = Vector3.zero
end)

addSlider(TabTarget, "Orbit / Random Speed", 1, 60, 15, function(v)
    Config.OrbitSpeed = v
end)

addSlider(TabTarget, "Target Range (Distance)", 1, 40, 5.5, function(v)
    Config.TargetRange = v
end)

addFeatureToggle(TabTarget, "TeleportPlayer", "Instant Teleport To Player", "TP", false, function(v)
    if v then
        local targetPlr = Players:FindFirstChild(Config.SelectedPlayer or "")
        local myRoot = State.Root
        local tRoot = targetPlr and targetPlr.Character and targetPlr.Character:FindFirstChild("HumanoidRootPart")
        if myRoot and tRoot then
            myRoot.CFrame = tRoot.CFrame * CFrame.new(0, 0, 3)
            myRoot.AssemblyLinearVelocity = Vector3.zero
        end
        task.delay(0.15, function()
            if State.ToggleRegistry["TeleportPlayer"] then
                State.ToggleRegistry["TeleportPlayer"](false)
            end
        end)
    end
end)

-- // 3. POPULATE VOID & SAFETY TAB (ANTI-VOID DEFAULT OFF!)
addFeatureToggle(TabVoid, "AutoVoidKill", "Auto Void Kill (Skill-Safe Grab Detect)", "VOIDK", false, function(v)
    Config.AutoVoidKill = v
    if not v then
        State.VoidKillActive = false
    end
end)

addSlider(TabVoid, "Void Hold Duration (Seconds)", 0.5, 3.5, 1.35, function(v)
    Config.VoidHoldTime = v
end)

addButton(TabVoid, "Manual Trigger Void Drop (Test / Instant)", function()
    local wasEnabled = Config.AutoVoidKill
    Config.AutoVoidKill = true
    executeVoidKillSequence(findNearestValidPlayer())
    Config.AutoVoidKill = wasEnabled
end)

addFeatureToggle(TabVoid, "AntiVoid", "Anti-Void (Auto Rescue & Bounce)", "AVOID", false, function(v)
    Config.AntiVoidEnabled = v
end)

-- // 4. POPULATE LOCALPLAYER (MOVEMENT) TAB
addFeatureToggle(TabMove, "Fly", "LoopFly (Anti-Ragdoll Pad)", "FLY", false, function(v)
    Config.FlyEnabled = v
    if not v then
        clearFlyPad()
        if State.Root then State.Root.AssemblyLinearVelocity = Vector3.zero end
    end
end)

addDropdown(TabMove, "Select Fly Bypass Mode", {"FloorPad", "LoopPulse"}, 1, function(opt)
    Config.FlyMode = opt
end)

addSlider(TabMove, "Fly Speed", 10, 300, 65, function(v)
    Config.FlySpeed = v
end)

addFeatureToggle(TabMove, "InfJump", "Infinite Jump (FlyPad Bypass)", "INFJ", false, function(v)
    Config.InfJumpEnabled = v
    if not v then
        State.InfJumpArcActive = false
        if not Config.FlyEnabled and not Config.AutoTargetEnabled then
            clearFlyPad()
        end
    end
end)

addDropdown(TabMove, "Select InfJump Bypass", {"FlyPadStep", "ParabolicCFrame", "MicroBounce"}, 1, function(opt)
    Config.InfJumpMode = opt
end)

addFeatureToggle(TabMove, "Invisible", "Invisible (Multi-Bypass)", "INVIS", false, function(v)
    Config.InvisibleEnabled = v
    toggleInvisible(v)
end)

addDropdown(TabMove, "Select Invisible Mode", {"RootJointBreak", "UndergroundC0", "SeatDesync"}, 1, function(opt)
    Config.InvisMode = opt
    if Config.InvisibleEnabled then toggleInvisible(true) end
end)

addFeatureToggle(TabMove, "Speed", "WalkSpeed Boost", "SPD", false, function(v)
    Config.SpeedEnabled = v
    if not v and State.Hum then State.Hum.WalkSpeed = 16 end
end)

addSlider(TabMove, "WalkSpeed", 16, 250, 50, function(v)
    Config.WalkSpeed = v
end)

addFeatureToggle(TabMove, "JumpBoost", "JumpPower Boost", "JMP", false, function(v)
    Config.JumpBoostEnabled = v
    if not v and State.Hum then
        State.Hum.UseJumpPower = true
        State.Hum.JumpPower = 50
    end
end)

addSlider(TabMove, "JumpPower", 50, 350, 100, function(v)
    Config.JumpPower = v
end)

-- // 5. POPULATE SETTINGS & ESP TAB
addFeatureToggle(TabVisual, "ESP", "Player ESP (Throttled Zero-Lag)", "ESP", false, function(v)
    Config.ESPEnabled = v
    if not v then
        for _, obj in pairs(State.ESPObjects) do
            if obj.Highlight then obj.Highlight:Destroy() end
            if obj.Billboard then obj.Billboard:Destroy() end
        end
        State.ESPObjects = {}
    end
end)

addButton(TabVisual, "Refresh Player Dropdown", function()
    PlayerDropdown.Refresh(getPlayerNames())
end)

addButton(TabVisual, "Unload & Remove Script (Same as × Button)", function()
    unloadEntireScript()
end)

-- Mở khóa UI sau khi đã tạo xong toàn bộ nút (đảm bảo 100% không có tính năng nào tự bật khi vừa execute)
Config.KillAuraEnabled = false
Config.AutoVoidKill = false
Config.AntiVoidEnabled = false
Config.UIInitialized = true

table.insert(State.Connections, Players.PlayerAdded:Connect(function()
    task.wait(0.2)
    if Config.ScriptRunning then PlayerDropdown.Refresh(getPlayerNames()) end
end))

table.insert(State.Connections, Players.PlayerRemoving:Connect(function(leavingPlr)
    if not Config.ScriptRunning then return end
    if State.LockedAimbotPlayer == leavingPlr then
        setAimbotActiveState(false)
    end
    if State.ESPObjects[leavingPlr] then
        pcall(function() State.ESPObjects[leavingPlr].Highlight:Destroy() end)
        pcall(function() State.ESPObjects[leavingPlr].Billboard:Destroy() end)
        State.ESPObjects[leavingPlr] = nil
    end
    task.wait(0.2)
    PlayerDropdown.Refresh(getPlayerNames())
end))

-- // THROTTLED ESP MANAGER
local function updateESP()
    if not Config.ScriptRunning or not Config.ESPEnabled then return end
    local now = tick()
    if now - State.LastESPRefresh < 0.12 then return end
    State.LastESPRefresh = now

    local myRoot = State.Root
    for _, plr in ipairs(Players:GetPlayers()) do
        if plr ~= LocalPlayer then
            local char = plr.Character
            local root = char and char:FindFirstChild("HumanoidRootPart")
            local hum = char and char:FindFirstChildOfClass("Humanoid")

            if char and root and hum and hum.Health > 0 then
                if not State.ESPObjects[plr] or State.ESPObjects[plr].Char ~= char then
                    if State.ESPObjects[plr] then
                        pcall(function() State.ESPObjects[plr].Highlight:Destroy() end)
                        pcall(function() State.ESPObjects[plr].Billboard:Destroy() end)
                    end

                    local hl = Instance.new("Highlight")
                    hl.FillColor = Color3.fromRGB(60, 180, 255)
                    hl.OutlineColor = Color3.fromRGB(255, 255, 255)
                    hl.FillTransparency = 0.55
                    hl.Adornee = char
                    hl.Parent = ScreenGui

                    local bb = Instance.new("BillboardGui")
                    bb.Size = UDim2.new(0, 150, 0, 40)
                    bb.StudsOffset = Vector3.new(0, 3.5, 0)
                    bb.AlwaysOnTop = true
                    bb.Adornee = root
                    bb.Parent = ScreenGui

                    local txt = Instance.new("TextLabel", bb)
                    txt.Size = UDim2.new(1, 0, 1, 0)
                    txt.BackgroundTransparency = 1
                    txt.TextColor3 = Color3.fromRGB(115, 215, 255)
                    txt.TextStrokeTransparency = 0
                    txt.Font = Enum.Font.GothamBold
                    txt.TextSize = 11

                    State.ESPObjects[plr] = {Char = char, Highlight = hl, Billboard = bb, Label = txt}
                end

                local dist = myRoot and math.floor((myRoot.Position - root.Position).Magnitude) or 0
                State.ESPObjects[plr].Label.Text = string.format("%s [%d HP]\n[%dm]", plr.Name, math.floor(hum.Health), dist)
            elseif State.ESPObjects[plr] then
                pcall(function() State.ESPObjects[plr].Highlight:Destroy() end)
                pcall(function() State.ESPObjects[plr].Billboard:Destroy() end)
                State.ESPObjects[plr] = nil
            end
        end
    end
end

-- // FLIGHT DIRECTION HELPER
local function getFlightDirection(hum)
    local moveDir = Vector3.zero
    local camCF = Camera.CFrame

    if UserInputService:IsKeyDown(Enum.KeyCode.W) then moveDir = moveDir + camCF.LookVector end
    if UserInputService:IsKeyDown(Enum.KeyCode.S) then moveDir = moveDir - camCF.LookVector end
    if UserInputService:IsKeyDown(Enum.KeyCode.D) then moveDir = moveDir + camCF.RightVector end
    if UserInputService:IsKeyDown(Enum.KeyCode.A) then moveDir = moveDir - camCF.RightVector end
    if UserInputService:IsKeyDown(Enum.KeyCode.Space) then moveDir = moveDir + Vector3.new(0, 1, 0) end
    if UserInputService:IsKeyDown(Enum.KeyCode.LeftControl) then moveDir = moveDir - Vector3.new(0, 1, 0) end

    if moveDir.Magnitude == 0 and hum.MoveDirection.Magnitude > 0 then
        local flatLook = Vector3.new(camCF.LookVector.X, 0, camCF.LookVector.Z)
        if flatLook.Magnitude > 0.01 then
            flatLook = flatLook.Unit
            local forwardDot = hum.MoveDirection:Dot(flatLook)
            local rightVec = Vector3.new(camCF.RightVector.X, 0, camCF.RightVector.Z).Unit
            local rightDot = hum.MoveDirection:Dot(rightVec)
            moveDir = (camCF.LookVector * forwardDot) + (camCF.RightVector * rightDot)
        else
            moveDir = hum.MoveDirection
        end
    end

    if moveDir.Magnitude > 0 then return moveDir.Unit end
    return Vector3.zero
end

-- // ZERO-LAG CORE RENDERSTEPPED LOOP
table.insert(State.Connections, RunService.RenderStepped:Connect(function(dt)
    if not Config.ScriptRunning then return end
    local char = State.Char
    local root = State.Root
    local hum = State.Hum

    if Config.AntiStunEnabled and char and root and hum then
        enforceOldFullAntiStun(char, root, hum)
    end

    if Config.InvisibleEnabled then
        for i = 1, #State.InvisData.HiddenParts do
            local p = State.InvisData.HiddenParts[i]
            if p then p.CanCollide = false end
        end
    end

    if Config.AutoTargetEnabled and root and hum and not State.VoidKillActive then
        local targetPlr = Players:FindFirstChild(Config.SelectedPlayer or "")
        local tRoot = targetPlr and targetPlr.Character and targetPlr.Character:FindFirstChild("HumanoidRootPart")

        if tRoot then
            hum:SetStateEnabled(Enum.HumanoidStateType.Ragdoll, false)
            hum:SetStateEnabled(Enum.HumanoidStateType.FallingDown, false)

            local r = Config.TargetRange
            local targetPos = tRoot.Position
            local targetCF = tRoot.CFrame
            local basePos

            if Config.TargetMode == "Orbit" then
                State.OrbitAngle = (State.OrbitAngle + dt * Config.OrbitSpeed) % (math.pi * 2)
                basePos = targetPos + Vector3.new(math.cos(State.OrbitAngle) * r, 0, math.sin(State.OrbitAngle) * r)
            elseif Config.TargetMode == "Random" then
                local theta = math.random() * math.pi * 2
                local phi = math.acos(2 * math.random() - 1)
                local randRadius = math.max(1.5, r * (0.45 + 0.55 * math.random()))
                basePos = targetPos + Vector3.new(
                    randRadius * math.sin(phi) * math.cos(theta),
                    randRadius * math.cos(phi) * 0.75,
                    randRadius * math.sin(phi) * math.sin(theta)
                )
            elseif Config.TargetMode == "Behind" then
                basePos = (targetCF * CFrame.new(0, 0, r)).Position
            elseif Config.TargetMode == "Front" then
                basePos = (targetCF * CFrame.new(0, 0, -r)).Position
            elseif Config.TargetMode == "Below" then
                basePos = targetPos - Vector3.new(0, r, 0)
            elseif Config.TargetMode == "Upper" then
                basePos = targetPos + Vector3.new(0, r, 0)
            end

            if Config.TargetFreeMove then
                local moveInput = hum.MoveDirection
                local verticalInput = 0
                if UserInputService:IsKeyDown(Enum.KeyCode.Space) then verticalInput = 1 end
                if UserInputService:IsKeyDown(Enum.KeyCode.LeftControl) then verticalInput = -1 end

                local totalInput = moveInput + Vector3.new(0, verticalInput, 0)
                local moveSpd = Config.SpeedEnabled and Config.WalkSpeed or 26

                if totalInput.Magnitude > 0.05 then
                    State.FreeMoveOffset = State.FreeMoveOffset + (totalInput * moveSpd * dt)
                    local maxWeave = math.max(r * 1.5, 6)
                    if State.FreeMoveOffset.Magnitude > maxWeave then
                        State.FreeMoveOffset = State.FreeMoveOffset.Unit * maxWeave
                    end
                else
                    State.FreeMoveOffset = State.FreeMoveOffset:Lerp(Vector3.zero, math.clamp(dt * 8, 0, 1))
                end
            else
                State.FreeMoveOffset = Vector3.zero
            end

            local finalPos = basePos + State.FreeMoveOffset
            root.CFrame = CFrame.lookAt(finalPos, targetPos)
            root.AssemblyLinearVelocity = Vector3.zero
            root.AssemblyAngularVelocity = Vector3.zero

            local pad = ensureFlyPad()
            pad.CFrame = CFrame.new(root.Position - Vector3.new(0, (hum.HipHeight + (root.Size.Y / 2) + 0.5), 0))
        end
    end

    if Config.AimbotActive and State.LockedAimbotPlayer then
        local tChar = State.LockedAimbotPlayer.Character
        local aimPart = tChar and (tChar:FindFirstChild(Config.AimPart) or tChar:FindFirstChild("HumanoidRootPart"))
        if aimPart then
            Camera.CFrame = CFrame.lookAt(Camera.CFrame.Position, aimPart.Position)
        end
    end
end))

-- // ZERO-LAG CORE HEARTBEAT LOOP
table.insert(State.Connections, RunService.Heartbeat:Connect(function(dt)
    if not Config.ScriptRunning then return end
    local char = State.Char
    local root = State.Root
    local hum = State.Hum

    if root and hum and hum.Health > 0 then
        local voidY = Workspace.FallenPartsDestroyHeight
        if voidY ~= voidY or voidY < -10000 or voidY > 500 then voidY = -500 end

        if not State.VoidKillActive then
            if hum.FloorMaterial ~= Enum.Material.Air and root.Position.Y > (voidY + 95) then
                State.LastSafeCFrame = root.CFrame
            end

            if Config.AntiVoidEnabled and root.Position.Y < (voidY + 65) then
                if State.LastSafeCFrame then
                    root.CFrame = State.LastSafeCFrame + Vector3.new(0, 5, 0)
                else
                    root.CFrame = CFrame.new(0, 60, 0)
                end
                root.AssemblyLinearVelocity = Vector3.new(0, 15, 0)
            end
        end

        if Config.AutoVoidKill and not State.VoidKillActive then
            scanProximityGrab()
        end

        if Config.AntiStunEnabled and char then
            enforceOldFullAntiStun(char, root, hum)
        elseif Config.SpeedEnabled then
            hum.WalkSpeed = Config.WalkSpeed
        end

        if Config.JumpBoostEnabled then
            hum.UseJumpPower = true
            hum.JumpPower = Config.JumpPower
        end

        if Config.InfJumpEnabled and not Config.FlyEnabled and not Config.AutoTargetEnabled and not State.VoidKillActive then
            hum:SetStateEnabled(Enum.HumanoidStateType.Ragdoll, false)
            hum:SetStateEnabled(Enum.HumanoidStateType.FallingDown, false)

            local elapsed = tick() - State.InfJumpArcTimer
            if State.InfJumpArcActive and elapsed < 0.22 then
                local pad = ensureFlyPad()
                local footOffset = hum.HipHeight + (root.Size.Y / 2) + (pad.Size.Y / 2) - 0.04
                local liftSpeed = Config.JumpBoostEnabled and (Config.JumpPower * 0.45) or 28

                if Config.InfJumpMode == "FlyPadStep" then
                    local decay = math.clamp(1 - (elapsed / 0.22), 0.15, 1)
                    root.CFrame = root.CFrame + Vector3.new(0, liftSpeed * decay * dt, 0)
                    root.AssemblyLinearVelocity = Vector3.new(root.AssemblyLinearVelocity.X, 0.2, root.AssemblyLinearVelocity.Z)
                    pad.CFrame = CFrame.new(root.Position - Vector3.new(0, footOffset, 0))
                elseif Config.InfJumpMode == "ParabolicCFrame" then
                    clearFlyPad()
                    local decay = math.clamp(1 - (elapsed / 0.22), 0.1, 1)
                    root.CFrame = root.CFrame + Vector3.new(0, (liftSpeed * 1.15) * decay * dt, 0)
                    root.AssemblyLinearVelocity = Vector3.new(root.AssemblyLinearVelocity.X, 0, root.AssemblyLinearVelocity.Z)
                elseif Config.InfJumpMode == "MicroBounce" then
                    pad.CFrame = CFrame.new(root.Position - Vector3.new(0, footOffset, 0))
                    if elapsed < 0.05 then
                        root.AssemblyLinearVelocity = Vector3.new(root.AssemblyLinearVelocity.X, liftSpeed * 1.4, root.AssemblyLinearVelocity.Z)
                    end
                end
            else
                State.InfJumpArcActive = false
                if hum:GetState() == Enum.HumanoidStateType.Freefall then
                    local pad = ensureFlyPad()
                    local footOffset = hum.HipHeight + (root.Size.Y / 2) + (pad.Size.Y / 2) - 0.02
                    if (math.floor(tick() * 10) % 4 == 0) then
                        pad.CFrame = CFrame.new(root.Position - Vector3.new(0, footOffset, 0))
                    else
                        pad.CFrame = CFrame.new(0, 999999, 0)
                    end
                else
                    clearFlyPad()
                end
            end
        end

        if Config.FlyEnabled and not Config.AutoTargetEnabled and not State.VoidKillActive then
            hum:SetStateEnabled(Enum.HumanoidStateType.Ragdoll, false)
            hum:SetStateEnabled(Enum.HumanoidStateType.FallingDown, false)

            local moveDir = getFlightDirection(hum)
            if Config.FlyMode == "FloorPad" then
                root.CFrame = root.CFrame + (moveDir * Config.FlySpeed * dt)
                root.AssemblyLinearVelocity = Vector3.new(0, 0.1, 0)
                local pad = ensureFlyPad()
                local footOffset = hum.HipHeight + (root.Size.Y / 2) + (pad.Size.Y / 2) - 0.05
                pad.CFrame = CFrame.new(root.Position - Vector3.new(0, footOffset, 0))
            elseif Config.FlyMode == "LoopPulse" then
                local pad = ensureFlyPad()
                local footOffset = hum.HipHeight + (root.Size.Y / 2) + (pad.Size.Y / 2)
                pad.CFrame = CFrame.new(root.Position - Vector3.new(0, footOffset, 0))
                root.AssemblyLinearVelocity = (moveDir * Config.FlySpeed) + Vector3.new(0, 2.5, 0)
            end
        elseif not Config.FlyEnabled and not Config.AutoTargetEnabled and not Config.InfJumpEnabled then
            clearFlyPad()
        end
    end

    updateESP()
end))

-- // INPUT TRIGGERS
table.insert(State.Connections, UserInputService.JumpRequest:Connect(function()
    triggerUndetectedInfJump()
end))

table.insert(State.Connections, UserInputService.InputBegan:Connect(function(input, gpe)
    if not Config.ScriptRunning then return end
    if not gpe and input.KeyCode == Enum.KeyCode.LeftAlt then
        toggleMenu()
    end
    if not gpe and input.KeyCode == Enum.KeyCode.Space and Config.InfJumpEnabled then
        triggerUndetectedInfJump()
    end
end))

task.spawn(function()
    while Config.ScriptRunning and ScreenGui and ScreenGui.Parent do
        local pGui = LocalPlayer:FindFirstChildOfClass("PlayerGui")
        local touchGui = pGui and pGui:FindFirstChild("TouchGui")
        local frame = touchGui and touchGui:FindFirstChild("TouchControlFrame")
        local jumpBtn = frame and frame:FindFirstChild("JumpButton")
        if jumpBtn and not jumpBtn:GetAttribute("NovaHooked") then
            jumpBtn:SetAttribute("NovaHooked", true)
            table.insert(State.Connections, jumpBtn.InputBegan:Connect(function(input)
                if Config.ScriptRunning and input.UserInputType == Enum.UserInputType.Touch and Config.InfJumpEnabled then
                    triggerUndetectedInfJump()
                end
            end))
        end
        task.wait(2)
    end
end)
