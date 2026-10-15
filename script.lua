-- Context: Luau (Roblox Client Executor - Heroes Battlegrounds Edition v22)
-- Architecture:
--   1. Auto-Void Always ON upon execution.
--   2. Full 34+ Grab Skill Void Kill Engine (Phantom Shot 2nd-hit, Sub Zero Ground-only,
--      MINE Multi-Target instant chain TP, Pierce The Heavens 3-target sweep, BLAST AWAY touch-loop).
--   3. Anti-Skill Desync Engine (Spawns translucent Ghost Illusion at combat spot, locks Camera to Ghost,
--      teleports real HumanoidRootPart 450 studs away overriding AutoTarget until enemy skill ends).
--   4. Real Map Tree Wall Combo Engine + Live Tree Object Scanner & Path Copier.

local Players = game:GetService("Players")
local RunService = game:GetService("RunService")
local UserInputService = game:GetService("UserInputService")
local TweenService = game:GetService("TweenService")
local Workspace = game:GetService("Workspace")
local CoreGui = game:GetService("CoreGui")

local LocalPlayer = Players.LocalPlayer
local Camera = Workspace.CurrentCamera

-- // CONFIGURATION & STATE
local Config = {
    ScriptRunning = true,
    UIInitialized = false,

    -- 1. Void Kill & Special Skill Mechanics
    SkillLoggerEnabled = true,
    AutoVoidKill = true,
    AntiVoidEnabled = true, -- LUÔN BẬT SẴN MỖI KHI EXECUTE SCRIPT
    VoidStartupDelay = 0.18,
    VoidMaxHoldTime = 1.75,
    VoidDepthOffset = 38,

    -- Multi-Target Selection cho MINE / BLAST AWAY / Pierce The Heavens
    SelectedMineTargets = {},
    MineSelectAll = true,

    -- 2. Anti-Skill (Ảo ảnh mờ giữ Camera + Nhân vật gốc bay ra xa né Skill)
    AntiSkillEnabled = false,
    AntiSkillDetectRange = 34,
    AntiSkillSafeOffset = Vector3.new(0, 450, 0),

    -- 3. Wall Combo (Mượn Cây thật của Map đặt trước mặt / sau lưng địch để kích hoạt Wall Combo)
    WallComboEnabled = false,
    WallComboTriggerMode = "AutoOnM1AndG", -- "AutoOnM1AndG" | "HoldAlwaysInFront"
    WallComboDistance = 4.5,

    -- 4. Combat & AutoTarget
    AntiStunEnabled = false,
    AimbotWidgetOpen = false,
    AimbotActive = false,
    AimPart = "Head",
    SelectedPlayer = nil,
    AutoTargetEnabled = false,
    TargetFreeMove = false,
    TargetMode = "Behind", -- "Behind" | "Orbit" | "Random" | "Below" | "Upper" | "Front"
    OrbitSpeed = 15,
    TargetRange = 5.5,

    -- 5. Movement & Visuals
    FlyEnabled = false,
    FlyMode = "FloorPad", -- "FloorPad" | "LoopPulse"
    FlySpeed = 65,
    InfJumpEnabled = false,
    InfJumpMode = "FlyPadStep", -- "FlyPadStep" | "ParabolicCFrame" | "MicroBounce"
    InvisibleEnabled = false,
    InvisMode = "RootJointBreak", -- "RootJointBreak" | "UndergroundC0" | "SeatDesync"
    SpeedEnabled = false,
    WalkSpeed = 50,
    JumpBoostEnabled = false,
    JumpPower = 100,
    ESPEnabled = false,
}

-- // DANH SÁCH 34+ SKILL VOID KILL
local StandardGrabSkills = {
    "quintuple smash",
    "shadow whip",
    "lightning crush",
    "whiplash",
    "blackout clutch",
    "azure grab",
    "ember assault",
    "peaking scorch",
    "infernal assault",
    "glacial cinder",
    "hell assault",
    "cluster spark",
    "freezeburn wave",
    "blazing soul",
    "explosion combo",
    "blast cataput",
    "blast catapult",
    "eruption dive",
    "recipro assault",
    "deteriorate",
    "scatter",
    "turbo release",
    "jet storm",
    "renovation",
    "stone weaponry",
    "calamity",
    "disfigruation",
    "disfiguration",
    "twin talons",
    "crimson heaven",
    "plume",
    "razor blitz",
    "assasin's eclipse",
    "assassin's eclipse",
}

local State = {
    Char = nil,
    Root = nil,
    Hum = nil,
    Animator = nil,
    CharConnections = {},

    -- Skill 1->4 Logger & Special Trackers
    DetectedSlotNames = { ["1"] = "Chưa quét", ["2"] = "Chưa quét", ["3"] = "Chưa quét", ["4"] = "Chưa quét" },
    SkillHistoryLogs = {},
    LastKeyPressed = nil,
    LastSkillName = "None",
    LastSkillCastTick = 0,
    CurrentSkillAnimTrack = nil,
    CopyBtnRef = nil,
    SlotStatusLabel = nil,
    TreeStatusLabel = nil,

    -- Phantom Shot 2-hit state
    PhantomShotStage = 0,
    PhantomShotFirstTick = 0,

    -- Void Kill State
    LastSafeCFrame = nil,
    VoidKillActive = false,
    VoidDropTargetCF = nil,
    VoidReturnCFrame = nil,
    AlreadyGrabbedInSession = {},

    -- Anti-Skill State
    AntiSkillEvading = false,
    AntiSkillGhostModel = nil,
    AntiSkillAnchorCF = nil,
    AntiSkillHoldUntil = 0,

    -- Wall Combo Tree State
    CachedTreePart = nil,
    CachedTreeOrigCF = nil,
    CachedTreeOrigCollide = true,
    CachedTreeOrigAnchored = true,
    WallComboActiveUntil = 0,
    TreeIsCurrentlyMoved = false,

    -- Movement / Visual State
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

-- // HELPER: CHUẨN HÓA CHUỖI
local function trimString(s)
    if typeof(s) ~= "string" then return "" end
    return string.gsub(s, "^%s*(.-)%s*$", "%1")
end

local function normalizeName(s)
    return string.lower(trimString(s))
end

local function isValidSkillLabelText(txt, slotStr)
    if #txt < 2 or #txt > 45 then return false end
    if txt == slotStr or txt == "[" .. slotStr .. "]" then return false end
    if tonumber(txt) ~= nil then return false end
    local lower = string.lower(txt)
    if string.match(lower, "^%d+%.?%d*s$") then return false end
    if lower == "cooldown" or lower == "ready" or lower == "locked" then return false end
    return true
end

-- // QUÉT TÊN SKILL 1 -> 4 TRÊN HOTBAR / BACKPACK
local function scanHotbarSkills1To4()
    local found = { ["1"] = nil, ["2"] = nil, ["3"] = nil, ["4"] = nil }
    local tools = {}
    local char = LocalPlayer.Character or State.Char
    local backpack = LocalPlayer:FindFirstChildOfClass("Backpack")

    if backpack then
        for _, item in ipairs(backpack:GetChildren()) do
            if item:IsA("Tool") then table.insert(tools, item) end
        end
    end
    if char then
        for _, item in ipairs(char:GetChildren()) do
            if item:IsA("Tool") then table.insert(tools, item) end
        end
    end

    for idx, tool in ipairs(tools) do
        local slotAttr = tool:GetAttribute("Slot") or tool:GetAttribute("Key") or tool:GetAttribute("Index")
        local keyStr = slotAttr and tostring(slotAttr) or tostring(idx)
        if found[keyStr] == nil and (keyStr == "1" or keyStr == "2" or keyStr == "3" or keyStr == "4") then
            found[keyStr] = trimString(tool.Name)
        end
    end

    local pGui = LocalPlayer:FindFirstChildOfClass("PlayerGui")
    if pGui then
        for _, inst in ipairs(pGui:GetDescendants()) do
            local instName = trimString(inst.Name)
            local matchedSlot = string.match(instName, "^[Ss]?[ll]?[oo]?[tt]?([1-4])$") or string.match(instName, "^Move([1-4])$")

            if matchedSlot and (inst:IsA("Frame") or inst:IsA("ImageButton") or inst:IsA("TextButton") or inst:IsA("ImageLabel")) then
                for _, child in ipairs(inst:GetDescendants()) do
                    if child:IsA("TextLabel") or child:IsA("TextButton") then
                        local t = trimString(child.Text)
                        if isValidSkillLabelText(t, matchedSlot) then
                            found[matchedSlot] = found[matchedSlot] or t
                        end
                    end
                end
            end

            if inst:IsA("TextLabel") or inst:IsA("TextButton") then
                local txt = trimString(inst.Text)
                local keyMatch = string.match(txt, "^%[?([1-4])%]?$")
                if keyMatch and inst.Parent then
                    local container = inst.Parent
                    for _, sib in ipairs(container:GetDescendants()) do
                        if (sib:IsA("TextLabel") or sib:IsA("TextButton")) and sib ~= inst then
                            local sTxt = trimString(sib.Text)
                            if isValidSkillLabelText(sTxt, keyMatch) then
                                found[keyMatch] = found[keyMatch] or sTxt
                            end
                        end
                    end
                    if not found[keyMatch] and container.Parent and container.Parent:IsA("GuiObject") then
                        for _, sib in ipairs(container.Parent:GetDescendants()) do
                            if (sib:IsA("TextLabel") or sib:IsA("TextButton")) and sib ~= inst then
                                local sTxt = trimString(sib.Text)
                                if isValidSkillLabelText(sTxt, keyMatch) then
                                    found[keyMatch] = found[keyMatch] or sTxt
                                end
                            end
                        end
                    end
                end
            end
        end
    end

    for k = 1, 4 do
        local sKey = tostring(k)
        if found[sKey] and #found[sKey] > 0 then
            State.DetectedSlotNames[sKey] = found[sKey]
        end
    end

    if State.SlotStatusLabel and State.SlotStatusLabel.Parent then
        State.SlotStatusLabel.Text = string.format(
            "[1]: %s  |  [2]: %s\n[3]: %s  |  [4]: %s",
            State.DetectedSlotNames["1"],
            State.DetectedSlotNames["2"],
            State.DetectedSlotNames["3"],
            State.DetectedSlotNames["4"]
        )
    end

    return State.DetectedSlotNames
end

local function updateCopyButtonCounter()
    if State.CopyBtnRef and State.CopyBtnRef.Parent then
        State.CopyBtnRef.Text = string.format("📋 COPY LOG TÊN SKILL 1->4 (Đã lưu: %d dòng)", #State.SkillHistoryLogs)
    end
end

local function addSkillLogEntry(slotStr, skillName, extraInfo)
    if not Config.ScriptRunning or not Config.SkillLoggerEnabled then return end
    local entry = string.format("[Phím %s] Skill: \"%s\" | %s", tostring(slotStr), tostring(skillName), tostring(extraInfo or ""))
    if State.SkillHistoryLogs[#State.SkillHistoryLogs] == entry then return end
    table.insert(State.SkillHistoryLogs, entry)
    updateCopyButtonCounter()
end

-- // KIỂM TRA NHÂN VẬT CÒN ĐANG TRONG SKILL KHÔNG
local function isCharacterStillInSkill(char)
    if not char then return false end
    for _, child in ipairs(char:GetChildren()) do
        local n = string.lower(child.Name)
        if n == "usingmove" or n == "skill" or n == "casting" or n == "action" or n == "move" or n == "inmove" or n == "attacking" then
            return true
        end
    end
    if char:GetAttribute("UsingMove") == true or char:GetAttribute("InSkill") == true or char:GetAttribute("Attacking") == true then
        return true
    end
    local track = State.CurrentSkillAnimTrack
    if track and track.IsPlaying then
        return true
    end
    return false
end

-- // KIỂM TRA KHỚP KÉO (WELD / MOTOR6D / ALIGNPOSITION) VỚI ĐỐI THỦ
local function resolveModelFromPart(part)
    if not part then return nil end
    local live = Workspace:FindFirstChild("Live")
    if live and part:IsDescendantOf(live) then
        local cur = part
        while cur and cur.Parent ~= live do
            cur = cur.Parent
        end
        if cur and cur:IsA("Model") then return cur end
    end
    return part:FindFirstAncestorOfClass("Model")
end

local function checkGrabJointModel(inst)
    local myChar = LocalPlayer.Character or State.Char
    if not myChar then return nil end

    if inst:IsA("Weld") or inst:IsA("WeldConstraint") or inst:IsA("Motor6D") or inst:IsA("JointInstance") or inst:IsA("RigidConstraint") then
        if inst:IsA("JointInstance") or inst:IsA("WeldConstraint") or inst:IsA("RigidConstraint") then
            if inst.Enabled == false then return nil end
        end
        local p0, p1 = inst.Part0, inst.Part1
        if p0 and p1 then
            if p0:IsDescendantOf(myChar) and not p1:IsDescendantOf(myChar) then
                local enemyModel = resolveModelFromPart(p1)
                if enemyModel and enemyModel ~= myChar and enemyModel:FindFirstChildOfClass("Humanoid") then
                    return enemyModel
                end
            elseif p1:IsDescendantOf(myChar) and not p0:IsDescendantOf(myChar) then
                local enemyModel = resolveModelFromPart(p0)
                if enemyModel and enemyModel ~= myChar and enemyModel:FindFirstChildOfClass("Humanoid") then
                    return enemyModel
                end
            end
        end
    elseif inst:IsA("AlignPosition") then
        local a0, a1 = inst.Attachment0, inst.Attachment1
        if a0 and a1 then
            if a0:IsDescendantOf(myChar) and not a1:IsDescendantOf(myChar) then
                local enemyModel = resolveModelFromPart(a1)
                if enemyModel and enemyModel ~= myChar and enemyModel:FindFirstChildOfClass("Humanoid") then
                    return enemyModel
                end
            elseif a1:IsDescendantOf(myChar) and not a0:IsDescendantOf(myChar) then
                local enemyModel = resolveModelFromPart(a0)
                if enemyModel and enemyModel ~= myChar and enemyModel:FindFirstChildOfClass("Humanoid") then
                    return enemyModel
                end
            end
        end
    elseif inst:IsA("ObjectValue") then
        local lowerName = string.lower(inst.Name)
        if string.find(lowerName, "grab") or string.find(lowerName, "victim") or string.find(lowerName, "target") or string.find(lowerName, "weld") then
            if inst.Value and inst.Value:IsA("Model") and inst.Value ~= myChar then
                return inst.Value
            elseif inst.Value and inst.Value:IsA("BasePart") and not inst.Value:IsDescendantOf(myChar) then
                return resolveModelFromPart(inst.Value)
            elseif inst.Value and inst.Value:IsA("Player") and inst.Value ~= LocalPlayer then
                return inst.Value.Character
            end
        end
    end
    return nil
end

-- // QUÉT DANH SÁCH MỤC TIÊU ĐANG BỊ KHỚP KÉO DÍNH VÀO NGƯỜI MÌNH
local function getAllCurrentlyGrabbedModels()
    local grabbedMap = {}
    local grabbedList = {}
    local myChar = LocalPlayer.Character or State.Char
    if not myChar then return grabbedList, grabbedMap end

    for _, desc in ipairs(myChar:GetDescendants()) do
        local m = checkGrabJointModel(desc)
        if m and not grabbedMap[m] then
            grabbedMap[m] = true
            table.insert(grabbedList, m)
        end
    end

    local liveFolder = Workspace:FindFirstChild("Live")
    if liveFolder then
        for _, enemyModel in ipairs(liveFolder:GetChildren()) do
            if enemyModel ~= myChar and enemyModel.Name ~= LocalPlayer.Name and enemyModel:IsA("Model") then
                local eRoot = enemyModel:FindFirstChild("HumanoidRootPart")
                if eRoot and State.Root and (eRoot.Position - State.Root.Position).Magnitude <= 14 then
                    for _, desc in ipairs(enemyModel:GetDescendants()) do
                        local m = checkGrabJointModel(desc)
                        if m and not grabbedMap[enemyModel] then
                            grabbedMap[enemyModel] = true
                            table.insert(grabbedList, enemyModel)
                        end
                    end
                end
            end
        end
    end

    return grabbedList, grabbedMap
end

-- // LẤY DANH SÁCH ĐỐI THỦ CHO MULTI-TARGET (MINE / PIERCE THE HEAVENS / BLAST AWAY)
local function getMultiTargetCandidates(onlySelectedInDropdown)
    local results = {}
    local myChar = LocalPlayer.Character or State.Char

    for _, plr in ipairs(Players:GetPlayers()) do
        if plr ~= LocalPlayer and plr.Character and plr.Character ~= myChar then
            local allowed = true
            if onlySelectedInDropdown and not Config.MineSelectAll then
                allowed = (Config.SelectedMineTargets[plr.Name] == true)
            end
            if allowed then
                local tRoot = plr.Character:FindFirstChild("HumanoidRootPart")
                local tHum = plr.Character:FindFirstChildOfClass("Humanoid")
                if tRoot and tHum and tHum.Health > 0 then
                    table.insert(results, { Model = plr.Character, Root = tRoot, Hum = tHum, Name = plr.Name })
                end
            end
        end
    end
    return results
end

-- // HÀM DÌM XUỐNG VOID & TỰ BAY VỀ KHI HẾT SKILL
local function dropToVoidAndReturnWhenSkillEnds(customWaitBeforeDrop)
    if not Config.ScriptRunning or State.VoidKillActive or not Config.AutoVoidKill then return end
    local myChar = LocalPlayer.Character or State.Char
    local myRoot = myChar and myChar:FindFirstChild("HumanoidRootPart") or State.Root
    local myHum = myChar and myChar:FindFirstChildOfClass("Humanoid") or State.Hum
    if not myChar or not myRoot or not myHum or myHum.Health <= 0 then return end

    State.VoidKillActive = true
    State.VoidReturnCFrame = State.LastSafeCFrame or myRoot.CFrame

    task.spawn(function()
        if customWaitBeforeDrop and customWaitBeforeDrop > 0 then
            task.wait(customWaitBeforeDrop)
        end

        if not Config.ScriptRunning or not Config.AutoVoidKill or not State.Root or not State.Hum or State.Hum.Health <= 0 then
            State.VoidKillActive = false
            State.VoidDropTargetCF = nil
            return
        end

        local voidHeight = Workspace.FallenPartsDestroyHeight
        if voidHeight ~= voidHeight or voidHeight < -10000 or voidHeight > 500 then
            voidHeight = -500
        end
        local safeVoidY = voidHeight + Config.VoidDepthOffset
        local basePos = State.VoidReturnCFrame.Position
        State.VoidDropTargetCF = CFrame.new(basePos.X, safeVoidY, basePos.Z)

        local dropStartTick = tick()
        local minStayInVoid = 0.42

        while Config.ScriptRunning and Config.AutoVoidKill and State.Root and State.Hum and State.Hum.Health > 0 do
            local elapsed = tick() - dropStartTick
            if elapsed >= Config.VoidMaxHoldTime then
                break
            end

            if State.Root.Anchored then State.Root.Anchored = false end
            State.Root.CFrame = State.VoidDropTargetCF
            State.Root.AssemblyLinearVelocity = Vector3.zero
            State.Root.AssemblyAngularVelocity = Vector3.zero

            if elapsed >= minStayInVoid and not isCharacterStillInSkill(State.Char) then
                break
            end

            RunService.Heartbeat:Wait()
        end

        State.VoidDropTargetCF = nil

        if State.Root and State.VoidReturnCFrame then
            for _ = 1, 10 do
                if State.Root.Anchored then State.Root.Anchored = false end
                State.Root.CFrame = State.VoidReturnCFrame + Vector3.new(0, 3.5, 0)
                State.Root.AssemblyLinearVelocity = Vector3.zero
                State.Root.AssemblyAngularVelocity = Vector3.zero
                RunService.RenderStepped:Wait()
            end
        end

        State.VoidKillActive = false
    end)
end

-- // CƠ CHẾ RIÊNG 1: "MINE" -> DÍNH 1 NGƯỜI LÀ TP CỰC NHANH QUA TẤT CẢ MỤC TIÊU ĐÃ CHỌN RỒI XUỐNG VOID
local function executeMineMultiTargetSequence()
    if State.VoidKillActive or not Config.AutoVoidKill then return end
    State.VoidKillActive = true
    State.VoidReturnCFrame = State.LastSafeCFrame or (State.Root and State.Root.CFrame)

    task.spawn(function()
        local startWait = tick()
        local firstGrabbed = nil

        while (tick() - startWait) < 2.2 and Config.ScriptRunning and Config.AutoVoidKill do
            local list = getAllCurrentlyGrabbedModels()
            if #list >= 1 then
                firstGrabbed = list[1]
                break
            end
            RunService.Heartbeat:Wait()
        end

        if firstGrabbed and State.Root then
            local targets = getMultiTargetCandidates(true)
            for _, t in ipairs(targets) do
                if t.Model ~= firstGrabbed and t.Root and t.Hum and t.Hum.Health > 0 then
                    for _ = 1, 2 do
                        if State.Root then
                            State.Root.CFrame = t.Root.CFrame
                            State.Root.AssemblyLinearVelocity = Vector3.zero
                        end
                        RunService.RenderStepped:Wait()
                    end
                end
            end
        end

        State.VoidKillActive = false
        dropToVoidAndReturnWhenSkillEnds(0.02)
    end)
end

-- // CƠ CHẾ RIÊNG 2: "PIERCE THE HEAVENS" -> KHI DÍNH 1 NGƯỜI MỚI TP GOM TỐI ĐA 3 NGƯỜI RỒI XUỐNG VOID
local function executePierceTheHeavensSequence()
    if State.VoidKillActive or not Config.AutoVoidKill then return end
    State.VoidKillActive = true
    State.VoidReturnCFrame = State.LastSafeCFrame or (State.Root and State.Root.CFrame)

    task.spawn(function()
        local startWait = tick()
        local firstGrabbed = nil

        while (tick() - startWait) < 3.2 and Config.ScriptRunning and Config.AutoVoidKill do
            local list = getAllCurrentlyGrabbedModels()
            if #list >= 1 then
                firstGrabbed = list[1]
                break
            end
            RunService.Heartbeat:Wait()
        end

        if firstGrabbed and State.Root then
            local _, grabbedMap = getAllCurrentlyGrabbedModels()
            local count = 1
            local targets = getMultiTargetCandidates(true)

            for _, t in ipairs(targets) do
                if count >= 3 then break end
                if not grabbedMap[t.Model] and t.Root and t.Hum and t.Hum.Health > 0 then
                    local sweepStart = tick()
                    while (tick() - sweepStart) < 0.14 and State.Root and t.Root do
                        State.Root.CFrame = t.Root.CFrame
                        State.Root.AssemblyLinearVelocity = Vector3.zero
                        RunService.Heartbeat:Wait()
                        local _, nowMap = getAllCurrentlyGrabbedModels()
                        if nowMap[t.Model] then
                            grabbedMap[t.Model] = true
                            break
                        end
                    end
                    count = count + 1
                end
            end
        end

        State.VoidKillActive = false
        dropToVoidAndReturnWhenSkillEnds(0.02)
    end)
end

-- // CƠ CHẾ RIÊNG 3: "BLAST AWAY" -> LOOP BẮT LIÊN TỤC QUA NHỮNG NGƯỜI CHƯA BỊ BẮT, AI BẮT RỒI THÌ BỎ QUA
local function executeBlastAwayLoopSequence()
    if State.VoidKillActive or not Config.AutoVoidKill then return end
    State.VoidKillActive = true
    State.VoidReturnCFrame = State.LastSafeCFrame or (State.Root and State.Root.CFrame)
    State.AlreadyGrabbedInSession = {}

    task.spawn(function()
        local loopStart = tick()
        while (tick() - loopStart) < 0.85 and Config.ScriptRunning and Config.AutoVoidKill and State.Root do
            local _, currentGrabbedMap = getAllCurrentlyGrabbedModels()
            for m, _ in pairs(currentGrabbedMap) do
                State.AlreadyGrabbedInSession[m] = true
            end

            local targets = getMultiTargetCandidates(true)
            local touchedAny = false

            for _, t in ipairs(targets) do
                if not State.AlreadyGrabbedInSession[t.Model] and t.Root and t.Hum and t.Hum.Health > 0 then
                    touchedAny = true
                    State.Root.CFrame = t.Root.CFrame
                    State.Root.AssemblyLinearVelocity = Vector3.zero
                    RunService.Heartbeat:Wait()

                    local _, updatedMap = getAllCurrentlyGrabbedModels()
                    if updatedMap[t.Model] then
                        State.AlreadyGrabbedInSession[t.Model] = true
                    end
                end
            end

            if not touchedAny then
                break
            end
            RunService.Heartbeat:Wait()
        end

        State.VoidKillActive = false
        dropToVoidAndReturnWhenSkillEnds(0.02)
    end)
end

-- // PHÂN LOẠI & XỬ LÝ TỪNG SKILL TRONG DANH SÁCH
local function handleSkillCastForVoidKill(rawSkillName)
    if not Config.AutoVoidKill or not rawSkillName then return end
    local clean = normalizeName(rawSkillName)
    if #clean == 0 then return end

    if string.find(clean, "phantom shot", 1, true) then
        local now = tick()
        if State.PhantomShotStage == 1 and (now - State.PhantomShotFirstTick) <= 4.5 then
            State.PhantomShotStage = 0
            addSkillLogEntry(State.LastKeyPressed or "?", rawSkillName, "Phantom Shot LẦN 2 -> Bay xuống Void!")
            dropToVoidAndReturnWhenSkillEnds(Config.VoidStartupDelay)
        else
            State.PhantomShotStage = 1
            State.PhantomShotFirstTick = now
            addSkillLogEntry(State.LastKeyPressed or "?", rawSkillName, "Phantom Shot LẦN 1 (Chờ lần 2)")
        end
        return
    end

    if string.find(clean, "sub zero", 1, true) then
        local hum = State.Hum
        local isAir = (not hum)
            or (hum.FloorMaterial == Enum.Material.Air)
            or UserInputService:IsKeyDown(Enum.KeyCode.Space)
            or (hum:GetState() == Enum.HumanoidStateType.Jumping)
            or (hum:GetState() == Enum.HumanoidStateType.Freefall)

        if isAir then
            addSkillLogEntry(State.LastKeyPressed or "?", rawSkillName, "Sub Zero AIR -> Bỏ qua")
            return
        else
            addSkillLogEntry(State.LastKeyPressed or "?", rawSkillName, "Sub Zero GROUND -> Bay xuống Void!")
            dropToVoidAndReturnWhenSkillEnds(Config.VoidStartupDelay)
            return
        end
    end

    if clean == "mine" or string.find(clean, "mine", 1, true) then
        addSkillLogEntry(State.LastKeyPressed or "?", rawSkillName, "MINE -> Multi-Target Chain TP!")
        executeMineMultiTargetSequence()
        return
    end

    if string.find(clean, "pierce the heavens", 1, true) then
        addSkillLogEntry(State.LastKeyPressed or "?", rawSkillName, "Pierce The Heavens -> Gom tối đa 3!")
        executePierceTheHeavensSequence()
        return
    end

    if string.find(clean, "blast away", 1, true) then
        addSkillLogEntry(State.LastKeyPressed or "?", rawSkillName, "BLAST AWAY -> Loop chạm gom mục tiêu!")
        executeBlastAwayLoopSequence()
        return
    end

    for _, grabSkill in ipairs(StandardGrabSkills) do
        if string.find(clean, grabSkill, 1, true) then
            addSkillLogEntry(State.LastKeyPressed or "?", rawSkillName, "Matched Grab Skill -> Bay xuống Void!")
            dropToVoidAndReturnWhenSkillEnds(Config.VoidStartupDelay)
            return
        end
    end
end

-- // ANTI-SKILL ENGINE (TẠO BẢN ẢO ẢNH MỜ TẠI CHỖ + ĐƯA NHÂN VẬT GỐC BAY RA XA)
local function createGhostCloneAt(cframePos)
    if State.AntiSkillGhostModel then
        pcall(function() State.AntiSkillGhostModel:Destroy() end)
        State.AntiSkillGhostModel = nil
    end

    local myChar = LocalPlayer.Character or State.Char
    local myRoot = myChar and myChar:FindFirstChild("HumanoidRootPart")
    if not myChar or not myRoot then return nil end

    local ghost = Instance.new("Model")
    ghost.Name = "NovaAntiSkillIllusion"

    local ghostRoot = nil
    for _, part in ipairs(myChar:GetChildren()) do
        if part:IsA("BasePart") then
            local cp = Instance.new("Part")
            cp.Name = part.Name
            cp.Size = part.Size
            cp.Color = Color3.fromRGB(90, 195, 255)
            cp.Material = Enum.Material.ForceField
            cp.Transparency = (part.Name == "HumanoidRootPart") and 1 or 0.45
            cp.Anchored = true
            cp.CanCollide = false
            cp.CFrame = cframePos * (myRoot.CFrame:ToObjectSpace(part.CFrame))
            cp.Parent = ghost
            if part.Name == "HumanoidRootPart" then
                ghostRoot = cp
            end
        end
    end

    ghost.PrimaryPart = ghostRoot
    ghost.Parent = Workspace
    State.AntiSkillGhostModel = ghost
    return ghostRoot
end

local function removeGhostCloneAndRestoreCamera()
    if State.AntiSkillGhostModel then
        pcall(function() State.AntiSkillGhostModel:Destroy() end)
        State.AntiSkillGhostModel = nil
    end
    if State.Hum then
        Camera.CameraSubject = State.Hum
    end
end

local function isEnemyUsingSkillNearby()
    local myChar = LocalPlayer.Character or State.Char
    local myRoot = State.Root
    if not myChar or not myRoot then return false end

    local refPos = State.AntiSkillEvading and (State.AntiSkillAnchorCF and State.AntiSkillAnchorCF.Position or myRoot.Position) or myRoot.Position
    local range = Config.AntiSkillDetectRange

    local function checkEnemyModel(eModel)
        local eRoot = eModel:FindFirstChild("HumanoidRootPart")
        local eHum = eModel:FindFirstChildOfClass("Humanoid")
        if not eRoot or not eHum or eHum.Health <= 0 then return false end
        if (eRoot.Position - refPos).Magnitude > range then return false end

        if isCharacterStillInSkill(eModel) then
            return true
        end

        local animator = eHum:FindFirstChildOfClass("Animator")
        if animator then
            for _, track in ipairs(animator:GetPlayingAnimationTracks()) do
                if track.IsPlaying and (
                    track.Priority == Enum.AnimationPriority.Action
                    or track.Priority == Enum.AnimationPriority.Action2
                    or track.Priority == Enum.AnimationPriority.Action3
                    or track.Priority == Enum.AnimationPriority.Action4
                ) then
                    return true
                end
            end
        end
        return false
    end

    local liveFolder = Workspace:FindFirstChild("Live")
    if liveFolder then
        for _, m in ipairs(liveFolder:GetChildren()) do
            if m ~= myChar and m.Name ~= LocalPlayer.Name and m:IsA("Model") then
                if checkEnemyModel(m) then return true end
            end
        end
    end

    for _, plr in ipairs(Players:GetPlayers()) do
        if plr ~= LocalPlayer and plr.Character then
            if checkEnemyModel(plr.Character) then return true end
        end
    end

    return false
end

local function updateAntiSkillSystem()
    if not Config.ScriptRunning or not Config.AntiSkillEnabled or State.VoidKillActive then
        if State.AntiSkillEvading then
            State.AntiSkillEvading = false
            removeGhostCloneAndRestoreCamera()
            if State.Root and State.AntiSkillAnchorCF then
                State.Root.CFrame = State.AntiSkillAnchorCF
                State.Root.AssemblyLinearVelocity = Vector3.zero
            end
            State.AntiSkillAnchorCF = nil
        end
        return
    end

    local root = State.Root
    local hum = State.Hum
    if not root or not hum or hum.Health <= 0 then return end

    local enemyCasting = isEnemyUsingSkillNearby()
    if enemyCasting then
        State.AntiSkillHoldUntil = tick() + 0.32
    end

    if tick() < State.AntiSkillHoldUntil then
        if not State.AntiSkillEvading then
            State.AntiSkillEvading = true
            State.AntiSkillAnchorCF = root.CFrame
            local ghostRoot = createGhostCloneAt(State.AntiSkillAnchorCF)
            if ghostRoot then
                Camera.CameraSubject = ghostRoot
            end
        end

        -- Nhân vật gốc bay ra xa, tách rời khỏi bản Ảo Ảnh và không bị AutoTarget kéo về
        root.CFrame = State.AntiSkillAnchorCF + Config.AntiSkillSafeOffset
        root.AssemblyLinearVelocity = Vector3.zero
        root.AssemblyAngularVelocity = Vector3.zero
    elseif State.AntiSkillEvading then
        State.AntiSkillEvading = false
        removeGhostCloneAndRestoreCamera()
        if State.AntiSkillAnchorCF then
            root.CFrame = State.AntiSkillAnchorCF
            root.AssemblyLinearVelocity = Vector3.zero
            State.AntiSkillAnchorCF = nil
        end
    end
end

-- // WALL COMBO ENGINE (TỰ ĐỘNG QUÉT OBJECT CÂY THẬT TRONG MAP + KÉO TỚI TRƯỚC MẶT)
local function restoreMapTreePart()
    if State.CachedTreePart and State.CachedTreePart.Parent and State.CachedTreeOrigCF then
        pcall(function()
            State.CachedTreePart.CFrame = State.CachedTreeOrigCF
            State.CachedTreePart.CanCollide = State.CachedTreeOrigCollide
            State.CachedTreePart.Anchored = State.CachedTreeOrigAnchored
            State.CachedTreePart.LocalTransparencyModifier = 0
        end)
    end
    State.TreeIsCurrentlyMoved = false
end

local function updateTreeStatusUI()
    if State.TreeStatusLabel and State.TreeStatusLabel.Parent then
        if State.CachedTreePart and State.CachedTreePart.Parent then
            State.TreeStatusLabel.Text = "🌳 Cây đang dùng: " .. State.CachedTreePart:GetFullName()
            State.TreeStatusLabel.TextColor3 = Color3.fromRGB(115, 235, 155)
        else
            State.TreeStatusLabel.Text = "🌳 Cây đang dùng: Chưa tìm thấy (Hãy bấm nút Quét Cây bên dưới)"
            State.TreeStatusLabel.TextColor3 = Color3.fromRGB(255, 175, 105)
        end
    end
end

local function lockTreeCandidate(part)
    if not part or not part:IsA("BasePart") then return nil end
    restoreMapTreePart()
    State.CachedTreePart = part
    State.CachedTreeOrigCF = part.CFrame
    State.CachedTreeOrigCollide = part.CanCollide
    State.CachedTreeOrigAnchored = part.Anchored
    updateTreeStatusUI()
    return part
end

local function scanAndFindRealMapTree(preferNearestToPlayer)
    if not preferNearestToPlayer and State.CachedTreePart and State.CachedTreePart.Parent then
        return State.CachedTreePart
    end

    local myChar = LocalPlayer.Character or State.Char
    local myRoot = State.Root
    local refPos = myRoot and myRoot.Position or Vector3.zero
    local live = Workspace:FindFirstChild("Live")

    local bestPart = nil
    local bestScore = math.huge

    for _, inst in ipairs(Workspace:GetDescendants()) do
        if inst:IsA("BasePart")
            and inst.CanCollide
            and inst.Name ~= "Terrain"
            and inst.Name ~= "CameraOcclusionPart"
            and (not myChar or not inst:IsDescendantOf(myChar))
            and (not live or not inst:IsDescendantOf(live)) then

            -- Loại trừ nền đất khổng lồ (Baseplate)
            if inst.Size.X < 85 and inst.Size.Z < 85 and inst.Size.Y >= 3.2 and inst.Size.Y <= 110 then
                local fullPath = string.lower(inst:GetFullName())
                local isTreeNamed = (
                    string.find(fullPath, "tree", 1, true)
                    or string.find(fullPath, "trunk", 1, true)
                    or string.find(fullPath, "wood", 1, true)
                    or string.find(fullPath, "pine", 1, true)
                    or string.find(fullPath, "foliage", 1, true)
                    or inst.Material == Enum.Material.Wood
                    or inst.Material == Enum.Material.WoodPlanks
                )

                if isTreeNamed or preferNearestToPlayer then
                    local dist = (inst.Position - refPos).Magnitude
                    -- Ưu tiên tuyệt đối những vật thể có tên/chất liệu là Cây (Tree/Trunk/Wood)
                    local score = isTreeNamed and dist or (dist + 5000)
                    if score < bestScore then
                        bestScore = score
                        bestPart = inst
                    end
                end
            end
        end
    end

    if bestPart then
        return lockTreeCandidate(bestPart)
    end
    updateTreeStatusUI()
    return nil
end

local function getClosestEnemyInFrontForWallCombo()
    local myChar = LocalPlayer.Character or State.Char
    local myRoot = State.Root
    if not myChar or not myRoot then return nil end

    local bestRoot = nil
    local shortest = 9.5

    local function checkModel(m)
        local eRoot = m:FindFirstChild("HumanoidRootPart")
        local eHum = m:FindFirstChildOfClass("Humanoid")
        if eRoot and eHum and eHum.Health > 0 then
            local d = (eRoot.Position - myRoot.Position).Magnitude
            if d < shortest then
                shortest = d
                bestRoot = eRoot
            end
        end
    end

    local liveFolder = Workspace:FindFirstChild("Live")
    if liveFolder then
        for _, m in ipairs(liveFolder:GetChildren()) do
            if m ~= myChar and m.Name ~= LocalPlayer.Name and m:IsA("Model") then
                checkModel(m)
            end
        end
    end

    for _, plr in ipairs(Players:GetPlayers()) do
        if plr ~= LocalPlayer and plr.Character then
            checkModel(plr.Character)
        end
    end

    return bestRoot
end

local function updateWallComboSystem()
    if not Config.ScriptRunning or not Config.WallComboEnabled or State.VoidKillActive or State.AntiSkillEvading then
        if State.TreeIsCurrentlyMoved then
            restoreMapTreePart()
        end
        return
    end

    local root = State.Root
    if not root then return end

    local shouldPlaceTree = (Config.WallComboTriggerMode == "HoldAlwaysInFront") or (tick() < State.WallComboActiveUntil)
    local treePart = scanAndFindRealMapTree(false)
    if not treePart then return end

    if shouldPlaceTree then
        State.TreeIsCurrentlyMoved = true
        pcall(function()
            treePart.Anchored = true
            treePart.CanCollide = true
            treePart.LocalTransparencyModifier = 0.65

            -- Nếu có địch đang đứng sát trước mặt, ép Cây ngay sát sau lưng địch để Raycast xuyên qua địch trúng Cây 100%
            local enemyRoot = getClosestEnemyInFrontForWallCombo()
            local dist = Config.WallComboDistance
            if enemyRoot then
                local enemyDist = (enemyRoot.Position - root.Position).Magnitude
                dist = math.clamp(enemyDist + 1.25, 3.2, 7.5)
            end

            treePart.CFrame = root.CFrame * CFrame.new(0, 0, -dist)
        end)
    elseif State.TreeIsCurrentlyMoved then
        restoreMapTreePart()
    end
end

-- // FULL ANTI-STUN ENGINE
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

    if root.Anchored and not isCharacterStillInSkill(char) then root.Anchored = false end
    for _, part in ipairs(char:GetChildren()) do
        if part:IsA("BasePart") and part.Anchored and not isCharacterStillInSkill(char) then
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
    if hum.WalkSpeed < targetWS then hum.WalkSpeed = targetWS end
    local targetJP = Config.JumpBoostEnabled and Config.JumpPower or 50
    if hum.UseJumpPower and hum.JumpPower < targetJP then hum.JumpPower = targetJP end

    for _, child in ipairs(char:GetChildren()) do cleanStunInstance(child) end
    for _, child in ipairs(root:GetChildren()) do cleanStunInstance(child) end

    for attrName, attrVal in pairs(char:GetAttributes()) do
        if isStunName(attrName) and attrVal == true then char:SetAttribute(attrName, false) end
    end
    for attrName, attrVal in pairs(hum:GetAttributes()) do
        if isStunName(attrName) and attrVal == true then hum:SetAttribute(attrName, false) end
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

    task.delay(0.6, function()
        if Config.ScriptRunning then
            scanHotbarSkills1To4()
            scanAndFindRealMapTree(false)
        end
    end)

    task.spawn(function()
        local animator = State.Hum:WaitForChild("Animator", 5)
        if animator and Config.ScriptRunning then
            State.Animator = animator
            table.insert(State.CharConnections, animator.AnimationPlayed:Connect(function(track)
                pcall(function()
                    if (tick() - State.LastSkillCastTick) <= 1.5 and State.LastKeyPressed then
                        State.CurrentSkillAnimTrack = track
                        local animId = track.Animation and track.Animation.AnimationId or "nil"
                        addSkillLogEntry(
                            State.LastKeyPressed,
                            State.LastSkillName,
                            string.format("AnimID=%s | Duration=%.2fs", tostring(animId), track.Length or 0)
                        )
                    end
                end)
            end))
        end
    end)

    table.insert(State.CharConnections, char.DescendantAdded:Connect(function(inst)
        if not Config.ScriptRunning then return end

        if inst:IsA("Tool") then
            local slotKey = State.LastKeyPressed or "?"
            State.LastSkillName = inst.Name
            State.LastSkillCastTick = tick()
            addSkillLogEntry(slotKey, inst.Name, "Equipped Skill Tool")
            handleSkillCastForVoidKill(inst.Name)
        end

        if Config.AntiStunEnabled then
            cleanStunInstance(inst)
        end

        if Config.AutoVoidKill and not State.VoidKillActive then
            task.defer(function()
                local victim = checkGrabJointModel(inst)
                if victim then
                    local cleanLast = normalizeName(State.LastSkillName)
                    if string.find(cleanLast, "sub zero", 1, true) and State.Hum and State.Hum.FloorMaterial == Enum.Material.Air then
                        return
                    end
                    dropToVoidAndReturnWhenSkillEnds(0.04)
                end
            end)
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

-- // 3. FLUENT ACRYLIC MAIN WINDOW (NOVA HUB v22)
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
SubTitle.Size = UDim2.new(0, 290, 1, 0)
SubTitle.Position = UDim2.new(0, 134, 0, 0)
SubTitle.BackgroundTransparency = 1
SubTitle.Text = "Heroes Battlegrounds v22 (Tree Scanner + AntiSkill)"
SubTitle.TextColor3 = Color3.fromRGB(155, 165, 180)
SubTitle.Font = Enum.Font.Gotham
SubTitle.TextSize = 11
SubTitle.TextXAlignment = Enum.TextXAlignment.Left
SubTitle.Parent = TopBar

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
    Config.AutoVoidKill = false
    Config.AntiVoidEnabled = false
    Config.AntiSkillEnabled = false
    Config.WallComboEnabled = false
    Config.AntiStunEnabled = false
    Config.AimbotActive = false
    Config.ESPEnabled = false

    pcall(removeGhostCloneAndRestoreCamera)
    pcall(restoreMapTreePart)
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
SectionHeader.Text = "AntiSkill & Wall"
SectionHeader.TextColor3 = Color3.fromRGB(245, 247, 252)
SectionHeader.Font = Enum.Font.GothamBold
SectionHeader.TextSize = 20
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
    Label.TextSize = 12
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

-- // MULTI-SELECT DROPDOWN BUILDER (CHO CHIÊU "MINE" & MULTI-GRAB)
local function addMultiSelectDropdown(parent, label, getOptionsFunc)
    local isOpen = false

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
    TitleLbl.TextSize = 12
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
    ValueLbl.Text = "All Players (Default)"
    ValueLbl.TextColor3 = Color3.fromRGB(115, 215, 255)
    ValueLbl.Font = Enum.Font.GothamMedium
    ValueLbl.TextSize = 11
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

    local function updateSummaryText()
        local picked = {}
        for k, v in pairs(Config.SelectedMineTargets) do
            if v then table.insert(picked, k) end
        end
        if #picked == 0 then
            Config.MineSelectAll = true
            ValueLbl.Text = "All Players (Auto)"
        else
            Config.MineSelectAll = false
            ValueLbl.Text = string.format("Đã chọn %d: %s", #picked, table.concat(picked, ", "))
        end
    end

    local function rebuildMultiItems()
        for _, child in ipairs(ListFrame:GetChildren()) do
            if child:IsA("TextButton") then child:Destroy() end
        end

        local names = getOptionsFunc()
        for _, pName in ipairs(names) do
            if pName ~= "None" then
                local isChecked = (Config.SelectedMineTargets[pName] == true)
                local ItemBtn = Instance.new("TextButton")
                ItemBtn.Size = UDim2.new(1, 0, 0, 24)
                ItemBtn.BackgroundColor3 = isChecked and Color3.fromRGB(40, 95, 155) or Color3.fromRGB(30, 32, 38)
                ItemBtn.BackgroundTransparency = isChecked and 0.1 or 0.4
                ItemBtn.Text = (isChecked and " [✓] " or " [ ] ") .. tostring(pName)
                ItemBtn.TextColor3 = isChecked and Color3.fromRGB(255, 255, 255) or Color3.fromRGB(185, 190, 205)
                ItemBtn.Font = isChecked and Enum.Font.GothamBold or Enum.Font.Gotham
                ItemBtn.TextSize = 12
                ItemBtn.TextXAlignment = Enum.TextXAlignment.Left
                ItemBtn.AutoButtonColor = false
                ItemBtn.Parent = ListFrame
                Instance.new("UICorner", ItemBtn).CornerRadius = UDim.new(0, 4)

                ItemBtn.MouseButton1Click:Connect(function()
                    Config.SelectedMineTargets[pName] = not Config.SelectedMineTargets[pName]
                    updateSummaryText()
                    rebuildMultiItems()
                end)
            end
        end
    end

    local function setOpen(openState)
        isOpen = openState
        rebuildMultiItems()
        local listHeight = 110
        ListFrame.Size = UDim2.new(1, -20, 0, listHeight)
        local targetHeight = isOpen and (54 + listHeight) or 44

        TweenService:Create(Container, TweenInfo.new(0.18, Enum.EasingStyle.Quad, Enum.EasingDirection.Out), {
            Size = UDim2.new(1, 0, 0, targetHeight)
        }):Play()
        Chevron.Text = isOpen and "⌃" or "⌄"
    end

    HeaderBtn.MouseButton1Click:Connect(function() setOpen(not isOpen) end)
    return { Refresh = rebuildMultiItems }
end

-- // STANDARD SINGLE DROPDOWN BUILDER
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
    TitleLbl.TextSize = 12
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

local function addButton(parent, text, bgColor, callback)
    local Btn = Instance.new("TextButton")
    Btn.Size = UDim2.new(1, 0, 0, 38)
    Btn.BackgroundColor3 = bgColor or Color3.fromRGB(45, 95, 165)
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

-- // CREATE SIDEBAR TABS (Đặt AntiSkill & Wall lên đầu để bạn tiện test ngay)
local TabCombat = createTab("AntiSkill & Wall", "🛡")
local TabVoid   = createTab("Void Kill & Skills", "🌀")
local TabTarget = createTab("AutoFarm", "◇")
local TabMove   = createTab("LocalPlayer", "👤")
local TabVisual = createTab("Settings", "⚙")

local function getPlayerNames()
    local list = {}
    for _, p in ipairs(Players:GetPlayers()) do
        if p ~= LocalPlayer then table.insert(list, p.Name) end
    end
    if #list == 0 then table.insert(list, "None") end
    return list
end

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

-- // 1. POPULATE ANTI-SKILL & WALL COMBO TAB
addFeatureToggle(TabCombat, "AntiSkill", "Anti-Skill (Tạo Ảo Ảnh Mờ + Nhân Vật Gốc Bay Ra Xa)", "ASKILL", false, function(v)
    Config.AntiSkillEnabled = v
    if not v then
        updateAntiSkillSystem()
    end
end)

addSlider(TabCombat, "Khoảng cách phát hiện địch dùng Skill (Studs)", 12, 65, 34, function(v)
    Config.AntiSkillDetectRange = v
end)

local TreeInfoCard = Instance.new("Frame")
TreeInfoCard.Size = UDim2.new(1, 0, 0, 38)
TreeInfoCard.BackgroundColor3 = Color3.fromRGB(28, 32, 42)
TreeInfoCard.BackgroundTransparency = 0.15
TreeInfoCard.BorderSizePixel = 0
TreeInfoCard.Parent = TabCombat
Instance.new("UICorner", TreeInfoCard).CornerRadius = UDim.new(0, 6)

State.TreeStatusLabel = Instance.new("TextLabel")
State.TreeStatusLabel.Size = UDim2.new(1, -20, 1, -6)
State.TreeStatusLabel.Position = UDim2.new(0, 10, 0, 3)
State.TreeStatusLabel.BackgroundTransparency = 1
State.TreeStatusLabel.Text = "🌳 Cây đang dùng: Đang tự động quét..."
State.TreeStatusLabel.TextColor3 = Color3.fromRGB(165, 225, 255)
State.TreeStatusLabel.Font = Enum.Font.GothamSemibold
State.TreeStatusLabel.TextSize = 11
State.TreeStatusLabel.TextXAlignment = Enum.TextXAlignment.Left
State.TreeStatusLabel.TextTruncate = Enum.TextTruncate.AtEnd
State.TreeStatusLabel.Parent = TreeInfoCard

addFeatureToggle(TabCombat, "WallCombo", "Wall Combo (Kéo Cây Thật Trong Map Tới Trước Mặt)", "WALLC", false, function(v)
    Config.WallComboEnabled = v
    if v then
        scanAndFindRealMapTree(false)
    else
        restoreMapTreePart()
    end
end)

addButton(TabCombat, "🌳 QUÉT & COPY TÊN OBJECT CÂY GẦN BẠN NHẤT", Color3.fromRGB(40, 130, 95), function(btn)
    local tree = scanAndFindRealMapTree(true)
    if tree then
        local info = string.format(
            "FullName: %s | Class: %s | Size: %s | Material: %s",
            tree:GetFullName(),
            tree.ClassName,
            tostring(tree.Size),
            tostring(tree.Material.Name)
        )
        pcall(function()
            if setclipboard then setclipboard(info)
            elseif toclipboard then toclipboard(info) end
        end)
        btn.Text = "✅ ĐÃ KHÓA CÂY & COPY ĐƯỜNG DẪN: " .. tree.Name
    else
        btn.Text = "⚠️ Không tìm thấy Cây nào quanh đây!"
    end
    task.delay(2.2, function()
        if btn and btn.Parent then
            btn.Text = "🌳 QUÉT & COPY TÊN OBJECT CÂY GẦN BẠN NHẤT"
        end
    end)
end)

addDropdown(TabCombat, "Chế độ kích hoạt Cây Wall Combo", {"AutoOnM1AndG", "HoldAlwaysInFront"}, 1, function(mode)
    Config.WallComboTriggerMode = mode
    if not Config.WallComboEnabled or mode == "AutoOnM1AndG" then
        restoreMapTreePart()
    end
end)

addSlider(TabCombat, "Khoảng cách đặt Cây trước mặt (Studs)", 2.5, 8.0, 4.5, function(v)
    Config.WallComboDistance = v
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

-- // 2. POPULATE VOID KILL & SKILLS TAB
addFeatureToggle(TabVoid, "AntiVoid", "Anti-Void (Luôn Bật Sẵn Khi Execute)", "AVOID", true, function(v)
    Config.AntiVoidEnabled = v
end)

addFeatureToggle(TabVoid, "AutoVoidKill", "Auto Void Kill (34+ Grab Skills + Special Modes)", "VOIDK", true, function(v)
    Config.AutoVoidKill = v
    if not v then
        State.VoidKillActive = false
        State.VoidDropTargetCF = nil
    end
end)

local MineMultiDropdown = addMultiSelectDropdown(TabVoid, "Chọn nhiều mục tiêu (MINE / BLAST AWAY / Pierce)", getPlayerNames)

addSlider(TabVoid, "Delay chờ Skill tóm trước khi xuống Void (s)", 0.05, 0.80, 0.18, function(v)
    Config.VoidStartupDelay = v
end)

addSlider(TabVoid, "Thời gian tối đa giữ dưới Void (s)", 0.50, 3.50, 1.75, function(v)
    Config.VoidMaxHoldTime = v
end)

local SlotPreviewCard = Instance.new("Frame")
SlotPreviewCard.Size = UDim2.new(1, 0, 0, 48)
SlotPreviewCard.BackgroundColor3 = Color3.fromRGB(28, 32, 42)
SlotPreviewCard.BackgroundTransparency = 0.15
SlotPreviewCard.BorderSizePixel = 0
SlotPreviewCard.Parent = TabVoid
Instance.new("UICorner", SlotPreviewCard).CornerRadius = UDim.new(0, 6)

State.SlotStatusLabel = Instance.new("TextLabel")
State.SlotStatusLabel.Size = UDim2.new(1, -20, 1, -8)
State.SlotStatusLabel.Position = UDim2.new(0, 10, 0, 4)
State.SlotStatusLabel.BackgroundTransparency = 1
State.SlotStatusLabel.Text = "[1]: Chưa quét  |  [2]: Chưa quét\n[3]: Chưa quét  |  [4]: Chưa quét"
State.SlotStatusLabel.TextColor3 = Color3.fromRGB(165, 225, 255)
State.SlotStatusLabel.Font = Enum.Font.GothamSemibold
State.SlotStatusLabel.TextSize = 11
State.SlotStatusLabel.TextXAlignment = Enum.TextXAlignment.Left
State.SlotStatusLabel.Parent = SlotPreviewCard

State.CopyBtnRef = addButton(TabVoid, "📋 COPY LOG TÊN SKILL 1->4 (Đã lưu: 0 dòng)", Color3.fromRGB(35, 140, 95), function(btn)
    local slots = scanHotbarSkills1To4()
    local report = "=== NOVA HUB v22 - SKILL 1->4 LOG REPORT ===\n"
    report = report .. string.format(
        "Hotbar: [1]=%s | [2]=%s | [3]=%s | [4]=%s\n",
        tostring(slots["1"]), tostring(slots["2"]), tostring(slots["3"]), tostring(slots["4"])
    )
    report = report .. "--------------------------------------------\n"
    report = report .. (#State.SkillHistoryLogs > 0 and table.concat(State.SkillHistoryLogs, "\n") or "(Chưa có log)")

    local copied = false
    pcall(function()
        if setclipboard then setclipboard(report); copied = true
        elseif toclipboard then toclipboard(report); copied = true end
    end)

    if copied then
        btn.Text = "✅ ĐÃ COPY LOG VÀO CLIPBOARD!"
    else
        btn.Text = "⚠️ Đã in Log ra F9 Console"
        print(report)
    end
    task.delay(2, function()
        if btn and btn.Parent then updateCopyButtonCounter() end
    end)
end)

-- // 3. POPULATE AUTOFARM / AUTOTARGET TAB
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

addButton(TabVisual, "Refresh Player Lists (AutoFarm & MINE)", nil, function()
    PlayerDropdown.Refresh(getPlayerNames())
    MineMultiDropdown.Refresh()
end)

addButton(TabVisual, "Unload & Remove Script (Same as × Button)", Color3.fromRGB(145, 45, 50), function()
    unloadEntireScript()
end)

-- // KHỞI TẠO MẶC ĐỊNH: ANTI-VOID LUÔN BẬT
Config.AntiVoidEnabled = true
Config.AutoVoidKill = true
Config.UIInitialized = true
task.defer(function()
    scanHotbarSkills1To4()
    scanAndFindRealMapTree(false)
end)

table.insert(State.Connections, Players.PlayerAdded:Connect(function()
    task.wait(0.2)
    if Config.ScriptRunning then
        PlayerDropdown.Refresh(getPlayerNames())
        MineMultiDropdown.Refresh()
    end
end))

table.insert(State.Connections, Players.PlayerRemoving:Connect(function(leavingPlr)
    if not Config.ScriptRunning then return end
    Config.SelectedMineTargets[leavingPlr.Name] = nil
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
    MineMultiDropdown.Refresh()
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

-- // STEPPED LOOP: ÉP CỨNG VỊ TRÍ VOID KILL / ANTI-SKILL TRƯỚC PHYSICS STEP
table.insert(State.Connections, RunService.Stepped:Connect(function()
    if not Config.ScriptRunning then return end
    if State.VoidKillActive and State.VoidDropTargetCF and State.Root then
        if State.Root.Anchored then State.Root.Anchored = false end
        State.Root.CFrame = State.VoidDropTargetCF
        State.Root.AssemblyLinearVelocity = Vector3.zero
        State.Root.AssemblyAngularVelocity = Vector3.zero
    elseif State.AntiSkillEvading and State.AntiSkillAnchorCF and State.Root then
        State.Root.CFrame = State.AntiSkillAnchorCF + Config.AntiSkillSafeOffset
        State.Root.AssemblyLinearVelocity = Vector3.zero
        State.Root.AssemblyAngularVelocity = Vector3.zero
    end
end))

-- // RENDERSTEPPED LOOP
table.insert(State.Connections, RunService.RenderStepped:Connect(function(dt)
    if not Config.ScriptRunning then return end
    local char = State.Char
    local root = State.Root
    local hum = State.Hum

    -- 1. Ưu tiên cao nhất: Anti-Skill & Void Kill (Hoàn toàn độc lập, không bị AutoTarget ghi đè)
    updateAntiSkillSystem()

    if State.VoidKillActive and State.VoidDropTargetCF and root then
        root.CFrame = State.VoidDropTargetCF
        root.AssemblyLinearVelocity = Vector3.zero
        root.AssemblyAngularVelocity = Vector3.zero
    end

    -- 2. Wall Combo Tree Spoofer
    updateWallComboSystem()

    if Config.AntiStunEnabled and char and root and hum then
        enforceOldFullAntiStun(char, root, hum)
    end

    if Config.InvisibleEnabled then
        for i = 1, #State.InvisData.HiddenParts do
            local p = State.InvisData.HiddenParts[i]
            if p then p.CanCollide = false end
        end
    end

    -- 3. AutoTarget chỉ chạy khi KHÔNG đang né Anti-Skill và KHÔNG đang dìm Void Kill
    if Config.AutoTargetEnabled and root and hum and not State.VoidKillActive and not State.AntiSkillEvading then
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

-- // HEARTBEAT LOOP
table.insert(State.Connections, RunService.Heartbeat:Connect(function(dt)
    if not Config.ScriptRunning then return end
    local char = State.Char
    local root = State.Root
    local hum = State.Hum

    if root and hum and hum.Health > 0 then
        local voidY = Workspace.FallenPartsDestroyHeight
        if voidY ~= voidY or voidY < -10000 or voidY > 500 then voidY = -500 end

        if not State.VoidKillActive and not State.AntiSkillEvading then
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

        if Config.AntiStunEnabled and char then
            enforceOldFullAntiStun(char, root, hum)
        elseif Config.SpeedEnabled then
            hum.WalkSpeed = Config.WalkSpeed
        end

        if Config.JumpBoostEnabled then
            hum.UseJumpPower = true
            hum.JumpPower = Config.JumpPower
        end

        if Config.InfJumpEnabled and not Config.FlyEnabled and not Config.AutoTargetEnabled and not State.VoidKillActive and not State.AntiSkillEvading then
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

        if Config.FlyEnabled and not Config.AutoTargetEnabled and not State.VoidKillActive and not State.AntiSkillEvading then
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

-- // INPUT TRIGGERS: SKILL 1->4 + WALL COMBO TRIGGER ON M1/G
local KeyMap1To4 = {
    [Enum.KeyCode.One]   = "1",
    [Enum.KeyCode.Two]   = "2",
    [Enum.KeyCode.Three] = "3",
    [Enum.KeyCode.Four]  = "4",
}

table.insert(State.Connections, UserInputService.JumpRequest:Connect(function()
    triggerUndetectedInfJump()
end))

table.insert(State.Connections, UserInputService.InputBegan:Connect(function(input, gpe)
    if not Config.ScriptRunning then return end
    if not gpe and input.KeyCode == Enum.KeyCode.LeftAlt then
        toggleMenu()
    end

    -- Khi đánh thường M1 hoặc bấm G, giữ Cây thật trước mặt 0.70s để kích hoạt Wall Combo
    if not gpe and Config.WallComboEnabled then
        if input.UserInputType == Enum.UserInputType.MouseButton1 or input.KeyCode == Enum.KeyCode.G then
            State.WallComboActiveUntil = tick() + 0.70
        end
    end

    local slotStr = KeyMap1To4[input.KeyCode]
    if not gpe and slotStr then
        State.LastKeyPressed = slotStr
        State.LastSkillCastTick = tick()
        local slots = scanHotbarSkills1To4()
        local skillName = slots[slotStr] or ("Skill_" .. slotStr)
        State.LastSkillName = skillName
        addSkillLogEntry(slotStr, skillName, "Key Pressed")
        handleSkillCastForVoidKill(skillName)
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
