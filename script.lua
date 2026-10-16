-- Context: Luau (Roblox Client Executor - Heroes Battlegrounds Edition v26 Stealth)
-- Root Causes of "crash: modded client detected (Error Code: 267)" Fixed:
--   1. NEVER modify Workspace.FallenPartsDestroyHeight (HBG client integrity watcher checks GetPropertyChangedSignal("FallenPartsDestroyHeight") and instant-kicks with "crash: modded client detected").
--   2. NEVER parent custom Parts/Models (NovaInfiniteVoidFloor, NovaMovableGhostDecoy, CameraOcclusionPart) directly into Workspace where Workspace.DescendantAdded scans them; all visual/collision proxies now use randomized GUID names inside Workspace.CurrentCamera with Archivable = false.
--   3. NEVER insert NoCollisionConstraint or Highlight into LocalPlayer.Character or enemy characters (Character.DescendantAdded anti-cheat check); Wall Combo now uses part.CanCollide toggling and CFrame offset outside your hitbox.
--   4. GUI is isolated inside gethui() or randomized ScreenGui name with RobloxGui / PlayerGui fallback.

local Players = game:GetService("Players")
local RunService = game:GetService("RunService")
local UserInputService = game:GetService("UserInputService")
local TweenService = game:GetService("TweenService")
local Workspace = game:GetService("Workspace")
local CoreGui = game:GetService("CoreGui")
local TeleportService = game:GetService("TeleportService")
local HttpService = game:GetService("HttpService")

local LocalPlayer = Players.LocalPlayer
local Camera = Workspace.CurrentCamera

local function randomToken()
    local chars = "abcdefghijklmnopqrstuvwxyzABCDEFGHIJKLMNOPQRSTUVWXYZ"
    local out = {}
    for i = 1, 10 do
        local idx = math.random(1, #chars)
        out[i] = string.sub(chars, idx, idx)
    end
    return table.concat(out)
end

local Config = {
    ScriptRunning = true,
    UIInitialized = false,

    -- Background Anti-Void
    AntiVoidEnabled = true,

    -- Deep Void & Void Kill (Safe Depth above FallenPartsDestroyHeight so we never touch FallenPartsDestroyHeight!)
    DeepVoidActive = false,
    VoidKillDepth = 445,
    AutoVoidKill = false,
    VoidMaxHoldTime = 1.85,

    MineSelectedTargets = {},

    KnownGrabSkillNames = {
        "Quintuple Smash", "Shadow Whip", "Lightning Crush", "Whiplash",
        "Blackout Clutch", "Azure Grab", "Ember Assault", "PEAKING SCORCH",
        "Infernal Assault", "Glacial Cinder", "Hell Assault", "Phantom Shot",
        "Cluster Spark", "Sub Zero", "FREEZEBURN WAVE", "BLAZING SOUL",
        "Explosion Combo", "Blast Cataput", "Blast Catapult", "Eruption Dive",
        "MINE", "Pierce The Heavens", "BLAST AWAY", "Recipro Assault",
        "Deteriorate", "Scatter", "Turbo Release", "Jet Storm",
        "Renovation", "Stone Weaponry", "Calamity", "Disfigruation",
        "Disfiguration", "Twin Talons", "Crimson Heaven", "Plume",
        "Razor Blitz", "Assasin's Eclipse", "Assassin's Eclipse",
    },

    -- Combat & Auto Features
    AutoSkillEnabled = false,
    AutoSkillDelay = 0.35,
    AutoUltimateEnabled = false,
    AutoUltimateDelay = 0.80,

    AntiSkillEnabled = false,
    AntiSkillRange = 16,

    WallComboEnabled = false,
    WallComboMode = "TreeBehindEnemy",
    WallBehindEnemyOffset = 3.6,
    WallComboKey = Enum.KeyCode.V,
    ObjectESPEnabled = false,
    ObjectESPRange = 45,

    AntiStunEnabled = false,
    AimbotWidgetOpen = false,
    AimbotActive = false,
    AimPart = "Head",
    SelectedPlayer = nil,
    AutoTargetEnabled = false,
    TargetFreeMove = false,
    TargetMode = "Behind",
    OrbitSpeed = 15,
    TargetRange = 5.5,

    -- Movement
    FlyEnabled = false,
    FlyMode = "FloorPad",
    FlySpeed = 65,
    InfJumpEnabled = false,
    InfJumpMode = "FlyPadStep",
    InvisibleEnabled = false,
    InvisMode = "RootJointBreak",
    SpeedEnabled = false,
    WalkSpeed = 50,
    JumpBoostEnabled = false,
    JumpPower = 100,

    -- Visuals & Server
    ESPEnabled = false,
    CustomJobId = "",
}

local State = {
    UIToken = randomToken(),
    PadToken = randomToken(),
    FloorToken = randomToken(),
    DecoyToken = randomToken(),

    Char = nil,
    Root = nil,
    Hum = nil,
    Animator = nil,
    CharConnections = {},

    DetectedSlotNames = {
        ["1"] = "Unscanned",
        ["2"] = "Unscanned",
        ["3"] = "Unscanned",
        ["4"] = "Unscanned",
    },
    LastKeyPressed = nil,
    LastSkillName = "None",
    LastSkillCastTick = 0,
    CurrentSkillAnimTrack = nil,
    SlotStatusLabel = nil,

    PhantomShotStage = 0,
    PhantomShotLastTick = 0,
    ActiveSpecialSkill = nil,
    GrabbedThisCast = {},
    GrabWatchWindowUntil = 0,

    LastSafeCFrame = nil,
    VoidKillActive = false,
    VoidDropTargetCF = nil,
    VoidReturnCFrame = nil,

    InfiniteVoidPlatform = nil,
    DeepVoidStandCF = nil,
    PreDeepVoidCFrame = nil,

    AntiSkillEvading = false,
    DecoyModel = nil,
    DecoyCameraProxy = nil,
    DecoyCFrame = nil,

    CachedTreeWoods = {},
    ActiveWallTree = nil,
    SavedTrunkData = nil,
    WallComboPulseRunning = false,
    M1ClickCount = 0,
    LastM1ClickTick = 0,

    ObjectESPItems = {},
    LastObjectESPRefresh = 0,

    LastAutoSkillTick = 0,
    AutoSkillIndex = 1,
    LastAutoUltTick = 0,

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

-- Safe Y calculation that NEVER modifies Workspace.FallenPartsDestroyHeight
local function getSafeVoidFloorY()
    local destroyY = Workspace.FallenPartsDestroyHeight
    if destroyY ~= destroyY or destroyY < -10000 or destroyY > 500 then
        destroyY = -500
    end
    local desiredY = -math.abs(Config.VoidKillDepth)
    -- Clamp at least 22 studs above FallenPartsDestroyHeight so you never die and never need to edit FallenPartsDestroyHeight
    return math.max(desiredY, destroyY + 22)
end

local function getKillZoneVoidY()
    local destroyY = Workspace.FallenPartsDestroyHeight
    if destroyY ~= destroyY or destroyY < -10000 or destroyY > 500 then
        destroyY = -500
    end
    return destroyY + 14
end

local function findNearestValidPlayer(maxRange)
    local myRoot = State.Root
    local refPos = myRoot and myRoot.Position or Camera.CFrame.Position
    local closestPlayer = nil
    local shortestDist = maxRange or math.huge

    for _, plr in ipairs(Players:GetPlayers()) do
        if plr ~= LocalPlayer and plr.Character then
            local tRoot = plr.Character:FindFirstChild("HumanoidRootPart")
            local tHum = plr.Character:FindFirstChildOfClass("Humanoid")
            if tRoot and tHum and tHum.Health > 0 then
                local dist = (tRoot.Position - refPos).Magnitude
                if dist <= shortestDist then
                    shortestDist = dist
                    closestPlayer = plr
                end
            end
        end
    end
    return closestPlayer, shortestDist
end

local function findNearestEnemyRoot(maxRange)
    local myChar = LocalPlayer.Character or State.Char
    local myRoot = State.Root
    if not myChar or not myRoot then return nil, nil end

    local bestModel, bestRoot = nil, nil
    local shortest = maxRange or 18

    local live = Workspace:FindFirstChild("Live")
    local list = live and live:GetChildren() or {}
    for _, m in ipairs(list) do
        if m ~= myChar and m:IsA("Model") then
            local r = m:FindFirstChild("HumanoidRootPart")
            local h = m:FindFirstChildOfClass("Humanoid")
            if r and h and h.Health > 0 then
                local d = (r.Position - myRoot.Position).Magnitude
                if d <= shortest then
                    shortest = d
                    bestModel = m
                    bestRoot = r
                end
            end
        end
    end

    if not bestRoot then
        local plr = findNearestValidPlayer(shortest)
        if plr and plr.Character then
            bestModel = plr.Character
            bestRoot = plr.Character:FindFirstChild("HumanoidRootPart")
        end
    end

    return bestModel, bestRoot
end

-- // SCAN TREE OBJECTS FOR WALL COMBO (ZERO CHARACTER INJECTION)
local function scanRealTreeWoods()
    local woods = {}
    local mapFolder = Workspace:FindFirstChild("Map")
    local destroyable = mapFolder and mapFolder:FindFirstChild("DestroyableParts")
    local treesFolder = destroyable and destroyable:FindFirstChild("Trees")

    if treesFolder then
        for _, treeModel in ipairs(treesFolder:GetChildren()) do
            local woodPart = treeModel:FindFirstChild("Wood")
            if woodPart and woodPart:IsA("BasePart") then
                table.insert(woods, woodPart)
            else
                for _, desc in ipairs(treeModel:GetDescendants()) do
                    if desc:IsA("BasePart") and (desc.Name == "Wood" or desc.Material == Enum.Material.Wood) then
                        table.insert(woods, desc)
                    end
                end
            end
        end
    end

    if #woods == 0 then
        for _, inst in ipairs(Workspace:GetDescendants()) do
            if inst:IsA("BasePart") and (inst.Name == "Wood" or inst.Material == Enum.Material.Wood) and inst.CanCollide then
                table.insert(woods, inst)
            end
        end
    end

    State.CachedTreeWoods = woods
    return woods
end

local function restoreActiveWallTree()
    local part = State.ActiveWallTree
    local saved = State.SavedTrunkData
    if part and part.Parent and saved then
        pcall(function()
            part.CFrame = saved.CFrame
            part.Anchored = saved.Anchored
            part.CanCollide = saved.CanCollide
            part.LocalTransparencyModifier = 0
            part.AssemblyLinearVelocity = Vector3.zero
            part.AssemblyAngularVelocity = Vector3.zero
        end)
    end
    State.ActiveWallTree = nil
    State.SavedTrunkData = nil
    State.WallComboPulseRunning = false
end

local function triggerWallComboBehindEnemy(duration)
    local myChar = LocalPlayer.Character or State.Char
    local myRoot = State.Root
    if not myChar or not myRoot then return end

    if #State.CachedTreeWoods == 0 then
        scanRealTreeWoods()
    end

    local holdTime = duration or 0.75

    if Config.WallComboMode == "SnapToRealTree" then
        local nearestWood, shortest = nil, math.huge
        for _, w in ipairs(State.CachedTreeWoods) do
            if w and w.Parent then
                local d = (w.Position - myRoot.Position).Magnitude
                if d < shortest then
                    shortest = d
                    nearestWood = w
                end
            end
        end
        if nearestWood and shortest <= 120 then
            local dirToTree = Vector3.new(nearestWood.Position.X - myRoot.Position.X, 0, nearestWood.Position.Z - myRoot.Position.Z)
            if dirToTree.Magnitude > 0.1 then
                dirToTree = dirToTree.Unit
                local standPos = Vector3.new(nearestWood.Position.X, myRoot.Position.Y, nearestWood.Position.Z) - (dirToTree * 5.0)
                myRoot.CFrame = CFrame.lookAt(standPos, Vector3.new(nearestWood.Position.X, myRoot.Position.Y, nearestWood.Position.Z))
                myRoot.AssemblyLinearVelocity = Vector3.zero
            end
        end
        return
    end

    if State.WallComboPulseRunning then return end
    local chosenWood = nil
    local shortestDist = math.huge
    for _, w in ipairs(State.CachedTreeWoods) do
        if w and w.Parent then
            local d = (w.Position - myRoot.Position).Magnitude
            if d < shortestDist then
                shortestDist = d
                chosenWood = w
            end
        end
    end
    if not chosenWood then return end

    State.WallComboPulseRunning = true
    State.ActiveWallTree = chosenWood
    State.SavedTrunkData = {
        CFrame = chosenWood.CFrame,
        Anchored = chosenWood.Anchored,
        CanCollide = chosenWood.CanCollide,
    }

    task.spawn(function()
        pcall(function()
            chosenWood.Anchored = true
            chosenWood.CanCollide = true
            chosenWood.CanQuery = true
            chosenWood.LocalTransparencyModifier = 0.45
        end)

        local startTick = tick()
        while (tick() - startTick) < holdTime and Config.ScriptRunning and State.Root do
            local _, curEnemyRoot = findNearestEnemyRoot(16)
            local wallCF

            if curEnemyRoot then
                local flatMe = Vector3.new(State.Root.Position.X, curEnemyRoot.Position.Y, State.Root.Position.Z)
                local dirMeToEnemy = (curEnemyRoot.Position - flatMe)
                if dirMeToEnemy.Magnitude > 0.1 then
                    dirMeToEnemy = dirMeToEnemy.Unit
                else
                    dirMeToEnemy = State.Root.CFrame.LookVector
                end
                -- Keep at least 3.6 studs behind enemy so it never overlaps LocalPlayer
                local behindEnemyPos = curEnemyRoot.Position + (dirMeToEnemy * math.max(Config.WallBehindEnemyOffset, 3.2))
                wallCF = CFrame.lookAt(behindEnemyPos, curEnemyRoot.Position) * CFrame.Angles(0, 0, math.rad(90))
            else
                wallCF = (State.Root.CFrame * CFrame.new(0, 0, -5.0)) * CFrame.Angles(0, 0, math.rad(90))
            end

            pcall(function()
                chosenWood.CFrame = wallCF
                chosenWood.AssemblyLinearVelocity = Vector3.zero
                chosenWood.AssemblyAngularVelocity = Vector3.zero
            end)

            RunService.Heartbeat:Wait()
        end

        restoreActiveWallTree()
    end)
end

-- // STEALTH INFINITE VOID PLATFORM (PARENTED TO CAMERA, NEVER WORKSPACE)
local function ensureInfiniteVoidPlatform()
    local targetY = getSafeVoidFloorY()
    if State.InfiniteVoidPlatform and State.InfiniteVoidPlatform.Parent then
        return State.InfiniteVoidPlatform
    end

    local plat = Instance.new("Part")
    plat.Name = State.FloorToken
    plat.Archivable = false
    plat.Size = Vector3.new(512, 4, 512)
    plat.Anchored = true
    plat.CanCollide = true
    plat.Transparency = 0.45
    plat.Color = Color3.fromRGB(45, 165, 255)
    plat.CFrame = CFrame.new(0, targetY - 2, 0)
    plat.Parent = Camera

    State.InfiniteVoidPlatform = plat
    return plat
end

local function teleportToDeepVoid()
    local myRoot = State.Root
    if not myRoot then return end

    Config.DeepVoidActive = true
    local targetY = getSafeVoidFloorY()

    if myRoot.Position.Y > -80 then
        State.PreDeepVoidCFrame = myRoot.CFrame
    end

    local plat = ensureInfiniteVoidPlatform()
    local targetPos = Vector3.new(myRoot.Position.X, targetY + 3.5, myRoot.Position.Z)
    plat.CFrame = CFrame.new(targetPos.X, targetY - 2, targetPos.Z)
    State.DeepVoidStandCF = CFrame.new(targetPos)

    task.spawn(function()
        for _ = 1, 18 do
            if not Config.DeepVoidActive or not State.Root then break end
            State.Root.CFrame = State.DeepVoidStandCF
            State.Root.AssemblyLinearVelocity = Vector3.zero
            RunService.Heartbeat:Wait()
        end
    end)
end

local function teleportBackFromDeepVoid()
    Config.DeepVoidActive = false
    local myRoot = State.Root
    if myRoot then
        local returnCF = State.PreDeepVoidCFrame or State.LastSafeCFrame or CFrame.new(0, 65, 0)
        for _ = 1, 10 do
            if State.Root then
                State.Root.CFrame = returnCF + Vector3.new(0, 4, 0)
                State.Root.AssemblyLinearVelocity = Vector3.zero
            end
            RunService.RenderStepped:Wait()
        end
    end
    if State.InfiniteVoidPlatform then
        pcall(function() State.InfiniteVoidPlatform:Destroy() end)
        State.InfiniteVoidPlatform = nil
    end
end

-- // HOTBAR SKILL SCANNER
local function trimString(s)
    if typeof(s) ~= "string" then return "" end
    return string.gsub(s, "^%s*(.-)%s*$", "%1")
end

local function isMatchedGrabSkillName(skillName)
    if typeof(skillName) ~= "string" or #skillName == 0 then return false end
    local lower = string.lower(skillName)
    for _, targetName in ipairs(Config.KnownGrabSkillNames) do
        if string.find(lower, string.lower(targetName), 1, true) then
            return true
        end
    end
    return false
end

local function isValidSkillLabelText(txt, slotStr)
    if #txt < 2 or #txt > 45 then return false end
    if txt == slotStr or txt == "[" .. slotStr .. "]" then return false end
    if tonumber(txt) ~= nil then return false end
    local lower = string.lower(txt)
    if string.match(lower, "^%d+%.?%d*s$") then return false end
    if lower == "cooldown" or lower == "ready" or lower == "locked" or lower == "ult" or lower == "awakening" then
        return false
    end
    return true
end

local ScreenGui

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
        local bottomLabels = {}
        local vpY = Camera and Camera.ViewportSize.Y or 800

        for _, inst in ipairs(pGui:GetDescendants()) do
            if not ScreenGui or not inst:IsDescendantOf(ScreenGui) then
                local instName = trimString(inst.Name)
                local matchedSlot = string.match(instName, "^[Ss]?[ll]?[oo]?[tt]?([1-4])$") or string.match(instName, "^Move([1-4])$") or string.match(instName, "^Skill([1-4])$")

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

                if (inst:IsA("TextLabel") or inst:IsA("TextButton")) and inst.Visible then
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
                    elseif isMatchedGrabSkillName(txt) or (inst.AbsolutePosition.Y > vpY * 0.68 and isValidSkillLabelText(txt, "")) then
                        table.insert(bottomLabels, {
                            Text = txt,
                            X = inst.AbsolutePosition.X,
                        })
                    end
                end
            end
        end

        if not (found["1"] and found["2"] and found["3"] and found["4"]) and #bottomLabels > 0 then
            table.sort(bottomLabels, function(a, b) return a.X < b.X end)
            local uniqueLabels = {}
            for _, item in ipairs(bottomLabels) do
                if #uniqueLabels == 0 or uniqueLabels[#uniqueLabels].Text ~= item.Text then
                    table.insert(uniqueLabels, item)
                end
            end
            for i = 1, math.min(4, #uniqueLabels) do
                local k = tostring(i)
                if not found[k] then
                    found[k] = uniqueLabels[i].Text
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
            "Slot 1: %s  |  Slot 2: %s\nSlot 3: %s  |  Slot 4: %s",
            State.DetectedSlotNames["1"],
            State.DetectedSlotNames["2"],
            State.DetectedSlotNames["3"],
            State.DetectedSlotNames["4"]
        )
    end

    return State.DetectedSlotNames
end

local function isCharacterStillInSkill(char)
    if not char then return false end
    for _, child in ipairs(char:GetChildren()) do
        local n = string.lower(child.Name)
        if n == "usingmove" or n == "skill" or n == "casting" or n == "action" or n == "move" or n == "inmove" then
            return true
        end
    end
    if char:GetAttribute("UsingMove") == true or char:GetAttribute("InSkill") == true then
        return true
    end
    local track = State.CurrentSkillAnimTrack
    if track and track.IsPlaying then
        return true
    end
    return false
end

-- // STRICT PHYSICAL GRAB DETECTION
local function resolveModelFromPart(part)
    if not part then return nil end
    local live = Workspace:FindFirstChild("Live")
    if live and part:IsDescendantOf(live) then
        local cur = part
        while cur and cur.Parent ~= live do
            cur = cur.Parent
        end
        if cur and cur:IsA("Model") then
            return cur
        end
    end
    return part:FindFirstAncestorOfClass("Model")
end

local function checkStrictGrabJoint(inst)
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
    elseif inst:IsA("AlignPosition") or inst:IsA("AlignOrientation") then
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
        if string.find(lowerName, "grab") or string.find(lowerName, "victim") or string.find(lowerName, "weld") then
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

local function getConfirmedCarriedEnemies()
    local myChar = LocalPlayer.Character or State.Char
    local myRoot = State.Root
    local grabbedMap = {}
    local grabbedList = {}
    if not myChar or not myRoot then return grabbedList, grabbedMap end

    for _, desc in ipairs(myChar:GetDescendants()) do
        local m = checkStrictGrabJoint(desc)
        if m and not grabbedMap[m] then
            grabbedMap[m] = true
            table.insert(grabbedList, m)
        end
    end

    local liveFolder = Workspace:FindFirstChild("Live")
    local candidates = liveFolder and liveFolder:GetChildren() or {}
    for _, enemyModel in ipairs(candidates) do
        if enemyModel ~= myChar and enemyModel:IsA("Model") and not grabbedMap[enemyModel] then
            local eRoot = enemyModel:FindFirstChild("HumanoidRootPart")
            local eHum = enemyModel:FindFirstChildOfClass("Humanoid")
            if eRoot and eHum and eHum.Health > 0 and (eRoot.Position - myRoot.Position).Magnitude <= 12 then
                for _, desc in ipairs(enemyModel:GetDescendants()) do
                    if checkStrictGrabJoint(desc) then
                        grabbedMap[enemyModel] = true
                        table.insert(grabbedList, enemyModel)
                        break
                    end
                end

                if not grabbedMap[enemyModel] and tick() <= State.GrabWatchWindowUntil then
                    local hasGrabTag = (enemyModel:FindFirstChild("Grabbed") ~= nil)
                        or (enemyModel:GetAttribute("Grabbed") == true)
                        or (eRoot:FindFirstChildOfClass("AlignPosition") ~= nil)
                        or (eRoot:FindFirstChildOfClass("WeldConstraint") ~= nil)
                    if hasGrabTag and (eRoot.Position - myRoot.Position).Magnitude <= 6.5 then
                        grabbedMap[enemyModel] = true
                        table.insert(grabbedList, enemyModel)
                    end
                end
            end
        end
    end

    return grabbedList, grabbedMap
end

-- // UNDETECTED VOID KILL EXECUTION (NEVER TOUCHES FallenPartsDestroyHeight)
local function executeVoidKillTrip()
    if not Config.ScriptRunning or State.VoidKillActive or not Config.AutoVoidKill then return end
    local myChar = LocalPlayer.Character or State.Char
    local myRoot = myChar and myChar:FindFirstChild("HumanoidRootPart") or State.Root
    local myHum = myChar and myChar:FindFirstChildOfClass("Humanoid") or State.Hum
    if not myChar or not myRoot or not myHum or myHum.Health <= 0 then return end

    State.VoidKillActive = true
    State.VoidReturnCFrame = State.LastSafeCFrame or myRoot.CFrame

    task.spawn(function()
        -- Hover 14 studs above FallenPartsDestroyHeight while pitching -90deg so enemy crosses the kill plane without modifying Workspace properties
        local targetDepthY = getKillZoneVoidY()
        local basePos = State.VoidReturnCFrame.Position
        local startPos = myRoot.Position

        for step = 1, 4 do
            if State.Root then
                local alpha = step / 4
                local curY = startPos.Y + (targetDepthY - startPos.Y) * alpha
                State.VoidDropTargetCF = CFrame.new(basePos.X, curY, basePos.Z) * CFrame.Angles(math.rad(-90), 0, 0)
                State.Root.CFrame = State.VoidDropTargetCF
                State.Root.AssemblyLinearVelocity = Vector3.zero
            end
            RunService.Heartbeat:Wait()
        end

        State.VoidDropTargetCF = CFrame.new(basePos.X, targetDepthY, basePos.Z) * CFrame.Angles(math.rad(-90), 0, 0)

        local dropStartTick = tick()
        local minStayInVoid = 0.50

        while Config.ScriptRunning and Config.AutoVoidKill and State.Root and State.Hum and State.Hum.Health > 0 do
            local elapsed = tick() - dropStartTick
            if elapsed >= Config.VoidMaxHoldTime then
                break
            end

            if State.Root.Anchored then
                State.Root.Anchored = false
            end
            State.Root.CFrame = State.VoidDropTargetCF
            State.Root.AssemblyLinearVelocity = Vector3.zero
            State.Root.AssemblyAngularVelocity = Vector3.zero

            local carriedList = getConfirmedCarriedEnemies()
            if elapsed >= minStayInVoid and (#carriedList == 0 and not isCharacterStillInSkill(State.Char)) then
                break
            end

            RunService.Heartbeat:Wait()
        end

        State.VoidDropTargetCF = nil

        if State.Root and State.VoidReturnCFrame then
            for _ = 1, 10 do
                if State.Root.Anchored then
                    State.Root.Anchored = false
                end
                State.Root.CFrame = State.VoidReturnCFrame + Vector3.new(0, 3.5, 0)
                State.Root.AssemblyLinearVelocity = Vector3.zero
                State.Root.AssemblyAngularVelocity = Vector3.zero
                RunService.RenderStepped:Wait()
            end
        end

        State.ActiveSpecialSkill = nil
        State.VoidKillActive = false
    end)
end

-- // SPECIAL SKILL SEQUENCES: MINE / PIERCE THE HEAVENS / BLAST AWAY
local function runMineMultiTargetSequence()
    if State.VoidKillActive then return end
    State.ActiveSpecialSkill = "MINE"
    State.VoidReturnCFrame = State.LastSafeCFrame or (State.Root and State.Root.CFrame)

    task.spawn(function()
        local startWait = tick()
        local firstGrabbed = nil

        while (tick() - startWait) < 2.2 and Config.ScriptRunning and Config.AutoVoidKill and not State.VoidKillActive do
            local list = getConfirmedCarriedEnemies()
            if #list > 0 then
                firstGrabbed = list[1]
                break
            end
            RunService.Heartbeat:Wait()
        end

        if not firstGrabbed or not State.Root then
            State.ActiveSpecialSkill = nil
            return
        end

        for targetName, isSelected in pairs(Config.MineSelectedTargets) do
            if isSelected and Config.ScriptRunning and Config.AutoVoidKill and State.Root then
                local tPlr = Players:FindFirstChild(targetName)
                local tChar = tPlr and tPlr.Character
                local tRoot = tChar and tChar:FindFirstChild("HumanoidRootPart")
                local tHum = tChar and tChar:FindFirstChildOfClass("Humanoid")
                if tChar and tChar ~= firstGrabbed and tRoot and tHum and tHum.Health > 0 then
                    for _ = 1, 3 do
                        if State.Root then
                            State.Root.CFrame = tRoot.CFrame * CFrame.new(0, 0, -1.2)
                            State.Root.AssemblyLinearVelocity = Vector3.zero
                        end
                        RunService.Heartbeat:Wait()
                    end
                end
            end
        end

        executeVoidKillTrip()
    end)
end

local function runPierceTheHeavensSequence()
    if State.VoidKillActive then return end
    State.ActiveSpecialSkill = "Pierce The Heavens"
    State.VoidReturnCFrame = State.LastSafeCFrame or (State.Root and State.Root.CFrame)

    task.spawn(function()
        local startWait = tick()
        local grabbedList, grabbedMap = {}, {}

        while (tick() - startWait) < 3.6 and Config.ScriptRunning and Config.AutoVoidKill and not State.VoidKillActive do
            grabbedList, grabbedMap = getConfirmedCarriedEnemies()
            if #grabbedList >= 1 then
                break
            end
            RunService.Heartbeat:Wait()
        end

        if #grabbedList == 0 or not State.Root then
            State.ActiveSpecialSkill = nil
            return
        end

        local candidates = {}
        for _, plr in ipairs(Players:GetPlayers()) do
            if plr ~= LocalPlayer and plr.Character and not grabbedMap[plr.Character] then
                local eRoot = plr.Character:FindFirstChild("HumanoidRootPart")
                local eHum = plr.Character:FindFirstChildOfClass("Humanoid")
                if eRoot and eHum and eHum.Health > 0 then
                    table.insert(candidates, { Model = plr.Character, Root = eRoot, Dist = (eRoot.Position - State.Root.Position).Magnitude })
                end
            end
        end
        table.sort(candidates, function(a, b) return a.Dist < b.Dist end)

        for _, cand in ipairs(candidates) do
            local curList, curMap = getConfirmedCarriedEnemies()
            if #curList >= 3 then break end
            if not curMap[cand.Model] and cand.Root and cand.Root.Parent then
                local sweepStart = tick()
                while (tick() - sweepStart) < 0.16 and Config.ScriptRunning and Config.AutoVoidKill and State.Root do
                    State.Root.CFrame = cand.Root.CFrame * CFrame.new(0, 0, -1.0)
                    State.Root.AssemblyLinearVelocity = Vector3.zero
                    local _, checkMap = getConfirmedCarriedEnemies()
                    if checkMap[cand.Model] then break end
                    RunService.Heartbeat:Wait()
                end
            end
        end

        executeVoidKillTrip()
    end)
end

local function runBlastAwayLoopSequence()
    if State.VoidKillActive then return end
    State.ActiveSpecialSkill = "BLAST AWAY"
    State.GrabbedThisCast = {}
    State.VoidReturnCFrame = State.LastSafeCFrame or (State.Root and State.Root.CFrame)

    task.spawn(function()
        local loopStart = tick()
        while (tick() - loopStart) < 0.85 and Config.ScriptRunning and Config.AutoVoidKill and State.Root and State.Hum and State.Hum.Health > 0 do
            local _, grabbedMap = getConfirmedCarriedEnemies()
            for m, _ in pairs(grabbedMap) do
                State.GrabbedThisCast[m] = true
            end

            local nextTargetRoot = nil
            local shortest = math.huge
            for _, plr in ipairs(Players:GetPlayers()) do
                if plr ~= LocalPlayer and plr.Character and not State.GrabbedThisCast[plr.Character] then
                    local eRoot = plr.Character:FindFirstChild("HumanoidRootPart")
                    local eHum = plr.Character:FindFirstChildOfClass("Humanoid")
                    if eRoot and eHum and eHum.Health > 0 then
                        local d = (eRoot.Position - State.Root.Position).Magnitude
                        if d < shortest and d <= 120 then
                            shortest = d
                            nextTargetRoot = eRoot
                        end
                    end
                end
            end

            if nextTargetRoot then
                State.Root.CFrame = nextTargetRoot.CFrame * CFrame.new(0, 0, -0.8)
                State.Root.AssemblyLinearVelocity = Vector3.zero
            else
                break
            end

            RunService.Heartbeat:Wait()
        end

        local finalGrabbed = getConfirmedCarriedEnemies()
        if #finalGrabbed > 0 then
            executeVoidKillTrip()
        else
            State.ActiveSpecialSkill = nil
        end
    end)
end

local KeyMap1To4 = {
    [Enum.KeyCode.One]   = "1",
    [Enum.KeyCode.Two]   = "2",
    [Enum.KeyCode.Three] = "3",
    [Enum.KeyCode.Four]  = "4",
}

local function onSkillSlotTriggered(slotStr)
    State.LastKeyPressed = slotStr
    State.LastSkillCastTick = tick()

    local slots = scanHotbarSkills1To4()
    local skillName = slots[slotStr] or ("Skill_" .. slotStr)
    State.LastSkillName = skillName
    local lowerSkill = string.lower(skillName)

    if not Config.AutoVoidKill or State.VoidKillActive then return end

    local isKnownGrab = isMatchedGrabSkillName(skillName)
    if not isKnownGrab then
        State.GrabWatchWindowUntil = 0
        return
    end

    if string.find(lowerSkill, "sub zero", 1, true) then
        local hum = State.Hum
        local isAirborne = UserInputService:IsKeyDown(Enum.KeyCode.Space)
            or (hum and (hum.FloorMaterial == Enum.Material.Air or hum:GetState() == Enum.HumanoidStateType.Freefall or hum:GetState() == Enum.HumanoidStateType.Jumping))
        if isAirborne then
            State.GrabWatchWindowUntil = 0
            return
        end
    end

    if string.find(lowerSkill, "phantom shot", 1, true) then
        local now = tick()
        if State.PhantomShotStage == 1 and (now - State.PhantomShotLastTick) <= 6.5 then
            State.PhantomShotStage = 0
        else
            State.PhantomShotStage = 1
            State.PhantomShotLastTick = now
            State.GrabWatchWindowUntil = 0
            return
        end
    end

    State.GrabWatchWindowUntil = tick() + 2.2

    if lowerSkill == "mine" or string.find(lowerSkill, "^mine$") then
        runMineMultiTargetSequence()
        return
    end

    if string.find(lowerSkill, "pierce the heavens", 1, true) then
        runPierceTheHeavensSequence()
        return
    end

    if string.find(lowerSkill, "blast away", 1, true) then
        runBlastAwayLoopSequence()
        return
    end

    task.spawn(function()
        local waitStart = tick()
        while (tick() - waitStart) < 2.2 and Config.ScriptRunning and Config.AutoVoidKill and not State.VoidKillActive do
            local carried = getConfirmedCarriedEnemies()
            if #carried > 0 then
                executeVoidKillTrip()
                return
            end
            RunService.Heartbeat:Wait()
        end
    end)
end

-- // STEALTH ANTI-SKILL (PARENTED TO CAMERA, NEVER WORKSPACE)
local function isEnemyActuallyCastingSkillNearMe(enemyChar, enemyRoot, myPosition)
    if not enemyChar or not enemyRoot then return false end
    local dist = (enemyRoot.Position - myPosition).Magnitude
    if dist > Config.AntiSkillRange then return false end

    local dirToMe = (myPosition - enemyRoot.Position)
    local isAimingAtMe = (dist <= 9.5) or (dirToMe.Magnitude > 0.1 and enemyRoot.CFrame.LookVector:Dot(dirToMe.Unit) >= 0.25)
    if not isAimingAtMe then return false end

    if enemyChar:GetAttribute("UsingMove") == true or enemyChar:GetAttribute("InSkill") == true or enemyChar:GetAttribute("Skill") == true then
        return true
    end

    for _, child in ipairs(enemyChar:GetChildren()) do
        local n = string.lower(child.Name)
        if n == "usingmove" or n == "skill" or n == "casting" or n == "inmove" or n == "heavy" or n == "nojump" then
            return true
        end
        if child:IsA("Tool") then
            return true
        end
    end

    for _, desc in ipairs(enemyRoot:GetChildren()) do
        if desc:IsA("BodyVelocity") or desc:IsA("BodyPosition") or desc:IsA("LinearVelocity") or desc:IsA("BodyGyro") or desc:IsA("AlignPosition") then
            local dn = string.lower(desc.Name)
            if not string.find(dn, "knockback") and not string.find(dn, "stun") then
                return true
            end
        end
    end

    return false
end

local function detectNearbyEnemySkillThreat()
    local refPos = State.AntiSkillEvading and (State.DecoyCFrame and State.DecoyCFrame.Position) or (State.Root and State.Root.Position)
    if not refPos then return false end

    for _, plr in ipairs(Players:GetPlayers()) do
        if plr ~= LocalPlayer and plr.Character then
            local eRoot = plr.Character:FindFirstChild("HumanoidRootPart")
            local eHum = plr.Character:FindFirstChildOfClass("Humanoid")
            if eRoot and eHum and eHum.Health > 0 then
                if isEnemyActuallyCastingSkillNearMe(plr.Character, eRoot, refPos) then
                    return true
                end
            end
        end
    end
    return false
end

local function spawnMovableGhostDecoy(startCF)
    if State.DecoyModel then
        pcall(function() State.DecoyModel:Destroy() end)
        State.DecoyModel = nil
    end
    if State.DecoyCameraProxy then
        pcall(function() State.DecoyCameraProxy:Destroy() end)
        State.DecoyCameraProxy = nil
    end

    local myChar = LocalPlayer.Character or State.Char
    if not myChar then return end

    State.DecoyCFrame = startCF
    ensureInfiniteVoidPlatform()

    local prevArch = myChar.Archivable
    myChar.Archivable = true
    local clone = myChar:Clone()
    myChar.Archivable = prevArch

    if clone then
        clone.Name = State.DecoyToken
        clone.Archivable = false
        for _, desc in ipairs(clone:GetDescendants()) do
            if desc:IsA("LocalScript") or desc:IsA("Script") or desc:IsA("RemoteEvent") or desc:IsA("RemoteFunction") or desc:IsA("BodyMover") or desc:IsA("Humanoid") then
                desc:Destroy()
            elseif desc:IsA("BasePart") then
                desc.Anchored = true
                desc.CanCollide = false
                if desc.Name == "HumanoidRootPart" then
                    desc.Transparency = 1
                else
                    desc.Transparency = 0.55
                    desc.Color = Color3.fromRGB(110, 205, 255)
                end
            elseif desc:IsA("Decal") then
                desc.Transparency = 0.55
            end
        end
        local dRoot = clone:FindFirstChild("HumanoidRootPart")
        if dRoot then
            clone.PrimaryPart = dRoot
            clone:PivotTo(startCF)
        end

        clone.Parent = Camera
        State.DecoyModel = clone
    end

    local camProxy = Instance.new("Part")
    camProxy.Name = State.DecoyToken .. "_Cam"
    camProxy.Archivable = false
    camProxy.Size = Vector3.new(1, 1, 1)
    camProxy.Transparency = 1
    camProxy.Anchored = true
    camProxy.CanCollide = false
    camProxy.CFrame = startCF + Vector3.new(0, 1.5, 0)
    camProxy.Parent = Camera
    State.DecoyCameraProxy = camProxy

    Camera.CameraSubject = camProxy
end

local function stopMovableGhostDecoy()
    local returnCF = State.DecoyCFrame
    if State.DecoyModel then
        pcall(function() State.DecoyModel:Destroy() end)
        State.DecoyModel = nil
    end
    if State.DecoyCameraProxy then
        pcall(function() State.DecoyCameraProxy:Destroy() end)
        State.DecoyCameraProxy = nil
    end
    if State.Hum then
        Camera.CameraSubject = State.Hum
    end
    if State.Root and returnCF and not Config.DeepVoidActive then
        for _ = 1, 5 do
            State.Root.CFrame = returnCF
            State.Root.AssemblyLinearVelocity = Vector3.zero
            RunService.RenderStepped:Wait()
        end
    end
    if not Config.DeepVoidActive and State.InfiniteVoidPlatform then
        pcall(function() State.InfiniteVoidPlatform:Destroy() end)
        State.InfiniteVoidPlatform = nil
    end
    State.DecoyCFrame = nil
end

-- // MAP OBJECT ESP (BILLBOARD ONLY, NO SELECTIONBOX ADORNEE TRIGGERS)
local function clearObjectESP()
    for _, item in pairs(State.ObjectESPItems) do
        pcall(function() if item.Billboard then item.Billboard:Destroy() end end)
    end
    State.ObjectESPItems = {}
end

local function updateObjectESP()
    if not Config.ScriptRunning or not Config.ObjectESPEnabled then return end
    local now = tick()
    if (now - State.LastObjectESPRefresh) < 0.40 then return end
    State.LastObjectESPRefresh = now

    local myRoot = State.Root
    if not myRoot then return end
    local myChar = LocalPlayer.Character or State.Char
    local liveFolder = Workspace:FindFirstChild("Live")

    local seen = {}
    for _, inst in ipairs(Workspace:GetDescendants()) do
        if inst:IsA("BasePart") and inst ~= Workspace.Terrain and inst.Name ~= "Baseplate" and not inst:IsDescendantOf(Camera) then
            if (not myChar or not inst:IsDescendantOf(myChar)) and (not liveFolder or not inst:IsDescendantOf(liveFolder)) then
                local dist = (inst.Position - myRoot.Position).Magnitude
                if dist <= Config.ObjectESPRange and inst.Size.Magnitude >= 3.5 and inst.Size.Magnitude <= 120 then
                    seen[inst] = true
                    if not State.ObjectESPItems[inst] then
                        local bb = Instance.new("BillboardGui")
                        bb.Size = UDim2.new(0, 220, 0, 48)
                        bb.AlwaysOnTop = true
                        bb.Adornee = inst
                        bb.Parent = ScreenGui

                        local lbl = Instance.new("TextLabel", bb)
                        lbl.Size = UDim2.new(1, 0, 1, 0)
                        lbl.BackgroundTransparency = 1
                        lbl.TextColor3 = Color3.fromRGB(130, 255, 155)
                        lbl.TextStrokeTransparency = 0
                        lbl.Font = Enum.Font.GothamBold
                        lbl.TextSize = 10

                        State.ObjectESPItems[inst] = { Billboard = bb, Label = lbl }
                    end

                    local pName = inst.Parent and inst.Parent.Name or "Workspace"
                    State.ObjectESPItems[inst].Label.Text = string.format(
                        "%s.%s\nSize: %.1f, %.1f, %.1f | Mat: %s [%dm]",
                        pName,
                        inst.Name,
                        inst.Size.X, inst.Size.Y, inst.Size.Z,
                        inst.Material.Name,
                        math.floor(dist)
                    )
                end
            end
        end
    end

    for part, data in pairs(State.ObjectESPItems) do
        if not seen[part] or not part.Parent then
            pcall(function() data.Billboard:Destroy() end)
            State.ObjectESPItems[part] = nil
        end
    end
end

local function copyNearestMapObjectInfo(btn)
    local myRoot = State.Root
    if not myRoot then return end
    local myChar = LocalPlayer.Character or State.Char
    local liveFolder = Workspace:FindFirstChild("Live")

    local candidates = {}
    for _, inst in ipairs(Workspace:GetDescendants()) do
        if inst:IsA("BasePart") and inst ~= Workspace.Terrain and not inst:IsDescendantOf(Camera) then
            if (not myChar or not inst:IsDescendantOf(myChar)) and (not liveFolder or not inst:IsDescendantOf(liveFolder)) then
                local dist = (inst.Position - myRoot.Position).Magnitude
                if dist <= 45 and inst.Size.Magnitude <= 140 then
                    table.insert(candidates, { Part = inst, Dist = dist })
                end
            end
        end
    end

    table.sort(candidates, function(a, b) return a.Dist < b.Dist end)
    local lines = { "=== NEAREST MAP OBJECTS ===" }
    for i = 1, math.min(8, #candidates) do
        local p = candidates[i].Part
        table.insert(lines, string.format(
            "%d. FullName: %s | Class: %s | Size: %.2f, %.2f, %.2f | Material: %s | Dist: %.1fm",
            i, p:GetFullName(), p.ClassName, p.Size.X, p.Size.Y, p.Size.Z, p.Material.Name, candidates[i].Dist
        ))
    end
    local report = table.concat(lines, "\n")
    pcall(function()
        if setclipboard then setclipboard(report) elseif toclipboard then toclipboard(report) end
    end)
    if btn then
        btn.Text = "Copied Nearest Objects"
        task.delay(2, function()
            if btn and btn.Parent then btn.Text = "Copy Nearest Object Info" end
        end)
    end
end

-- // SERVER HOP FUNCTIONS
local function rejoinCurrentServer()
    TeleportService:TeleportToPlaceInstance(game.PlaceId, game.JobId, LocalPlayer)
end

local function joinRandomSmoothServer(btn)
    if btn then btn.Text = "Searching Smooth Server..." end
    task.spawn(function()
        local url = string.format("https://games.roblox.com/v1/games/%d/servers/Public?sortOrder=Asc&limit=100", game.PlaceId)
        local ok, res = pcall(function()
            return HttpService:JSONDecode(game:HttpGet(url))
        end)

        if ok and res and res.data then
            local bestServers = {}
            for _, srv in ipairs(res.data) do
                if type(srv) == "table" and srv.id ~= game.JobId and srv.playing and srv.maxPlayers and srv.playing < (srv.maxPlayers - 2) and srv.playing >= 2 then
                    table.insert(bestServers, srv)
                end
            end

            table.sort(bestServers, function(a, b)
                local pingA = tonumber(a.ping) or 999
                local pingB = tonumber(b.ping) or 999
                if pingA ~= pingB then
                    return pingA < pingB
                end
                return (a.playing or 99) < (b.playing or 99)
            end)

            if #bestServers > 0 then
                local pick = bestServers[math.random(1, math.min(5, #bestServers))]
                if btn then btn.Text = "Joining Smooth Server..." end
                TeleportService:TeleportToPlaceInstance(game.PlaceId, pick.id, LocalPlayer)
                return
            end
        end

        if btn then
            btn.Text = "No Server Found"
            task.delay(2, function()
                if btn and btn.Parent then btn.Text = "Random Smooth Server" end
            end)
        end
    end)
end

local function joinServerByJobId(btn)
    local job = trimString(Config.CustomJobId)
    if #job > 8 then
        TeleportService:TeleportToPlaceInstance(game.PlaceId, job, LocalPlayer)
    elseif btn then
        btn.Text = "Invalid Job ID"
        task.delay(1.8, function()
            if btn and btn.Parent then btn.Text = "Join Job ID" end
        end)
    end
end

-- // ANTI-STUN ENGINE
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
        if not State.VoidKillActive and isStunName(inst.Name) then
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
end

local function scanProximityGrab()
    if not Config.ScriptRunning or not Config.AutoVoidKill or State.VoidKillActive then return end
    if State.ActiveSpecialSkill ~= nil then return end

    if string.find(string.lower(State.LastSkillName or ""), "phantom shot", 1, true) and State.PhantomShotStage == 1 then
        return
    end

    local carriedList = getConfirmedCarriedEnemies()
    if #carriedList > 0 then
        State.GrabWatchWindowUntil = 0
        executeVoidKillTrip()
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
                    end
                end)
            end))
        end
    end)

    table.insert(State.CharConnections, char.DescendantAdded:Connect(function(inst)
        if not Config.ScriptRunning then return end

        if inst:IsA("Tool") then
            State.LastSkillName = inst.Name
            State.LastSkillCastTick = tick()
        end

        if Config.AntiStunEnabled then
            cleanStunInstance(inst)
        end

        if Config.AutoVoidKill and not State.VoidKillActive and State.ActiveSpecialSkill == nil then
            task.defer(function()
                if string.find(string.lower(State.LastSkillName or ""), "phantom shot", 1, true) and State.PhantomShotStage == 1 then
                    return
                end
                local victim = checkStrictGrabJoint(inst)
                if victim then
                    executeVoidKillTrip()
                end
            end)
        end
    end))
end

if LocalPlayer.Character then
    task.spawn(bindCharacter, LocalPlayer.Character)
end
table.insert(State.Connections, LocalPlayer.CharacterAdded:Connect(bindCharacter))

-- // STEALTH GUI PARENTING (AVOIDS COREGUI CHILD SCANS)
local function getGuiParent()
    local okHui, hui = pcall(function()
        return gethui and gethui()
    end)
    if okHui and hui then return hui end
    return LocalPlayer:WaitForChild("PlayerGui")
end

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

local function ensureFlyPad()
    if State.FlyPad and State.FlyPad.Parent then return State.FlyPad end
    local pad = Instance.new("Part")
    pad.Name = State.PadToken
    pad.Archivable = false
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

-- // UI ROOT (RANDOMIZED NAME + ARCHIVABLE FALSE)
ScreenGui = Instance.new("ScreenGui")
ScreenGui.Name = State.UIToken
ScreenGui.Archivable = false
ScreenGui.ResetOnSpawn = false
ScreenGui.IgnoreGuiInset = true
ScreenGui.ZIndexBehavior = Enum.ZIndexBehavior.Sibling
ScreenGui.Parent = getGuiParent()

-- // EXTERNAL DROPDOWN POPUP
local DropdownPopup = Instance.new("Frame")
DropdownPopup.Name = "ExtPopup"
DropdownPopup.Size = UDim2.new(0, 235, 0, 290)
DropdownPopup.Position = UDim2.new(0.5, 290, 0.5, -145)
DropdownPopup.BackgroundColor3 = Color3.fromRGB(18, 20, 25)
DropdownPopup.BackgroundTransparency = 0.05
DropdownPopup.BorderSizePixel = 0
DropdownPopup.Visible = false
DropdownPopup.Active = true
DropdownPopup.ZIndex = 50
DropdownPopup.Parent = ScreenGui
Instance.new("UICorner", DropdownPopup).CornerRadius = UDim.new(0, 8)

local DropPopStroke = Instance.new("UIStroke", DropdownPopup)
DropPopStroke.Color = Color3.fromRGB(70, 175, 255)
DropPopStroke.Thickness = 1.3

local DropPopHeader = Instance.new("Frame")
DropPopHeader.Size = UDim2.new(1, 0, 0, 34)
DropPopHeader.BackgroundTransparency = 1
DropPopHeader.Active = true
DropPopHeader.ZIndex = 51
DropPopHeader.Parent = DropdownPopup

local DropPopTitle = Instance.new("TextLabel")
DropPopTitle.Size = UDim2.new(1, -40, 1, 0)
DropPopTitle.Position = UDim2.new(0, 12, 0, 0)
DropPopTitle.BackgroundTransparency = 1
DropPopTitle.Text = "Select Option"
DropPopTitle.TextColor3 = Color3.fromRGB(240, 245, 255)
DropPopTitle.Font = Enum.Font.GothamBold
DropPopTitle.TextSize = 12
DropPopTitle.TextXAlignment = Enum.TextXAlignment.Left
DropPopTitle.TextTruncate = Enum.TextTruncate.AtEnd
DropPopTitle.ZIndex = 52
DropPopTitle.Parent = DropPopHeader

local DropPopClose = Instance.new("TextButton")
DropPopClose.Size = UDim2.new(0, 28, 0, 26)
DropPopClose.Position = UDim2.new(1, -32, 0, 4)
DropPopClose.BackgroundColor3 = Color3.fromRGB(145, 45, 50)
DropPopClose.Text = "X"
DropPopClose.TextColor3 = Color3.fromRGB(255, 255, 255)
DropPopClose.Font = Enum.Font.GothamBold
DropPopClose.TextSize = 13
DropPopClose.AutoButtonColor = false
DropPopClose.ZIndex = 52
DropPopClose.Parent = DropPopHeader
Instance.new("UICorner", DropPopClose).CornerRadius = UDim.new(0, 6)

local DropPopScroll = Instance.new("ScrollingFrame")
DropPopScroll.Size = UDim2.new(1, -16, 1, -44)
DropPopScroll.Position = UDim2.new(0, 8, 0, 36)
DropPopScroll.BackgroundColor3 = Color3.fromRGB(24, 26, 32)
DropPopScroll.BackgroundTransparency = 0.2
DropPopScroll.BorderSizePixel = 0
DropPopScroll.ScrollBarThickness = 3
DropPopScroll.ScrollBarImageColor3 = Color3.fromRGB(70, 175, 255)
DropPopScroll.CanvasSize = UDim2.new(0, 0, 0, 0)
DropPopScroll.AutomaticCanvasSize = Enum.AutomaticSize.Y
DropPopScroll.ZIndex = 51
DropPopScroll.Parent = DropdownPopup
Instance.new("UICorner", DropPopScroll).CornerRadius = UDim.new(0, 6)

local DropPopPad = Instance.new("UIPadding", DropPopScroll)
DropPopPad.PaddingTop = UDim.new(0, 6)
DropPopPad.PaddingBottom = UDim.new(0, 6)
DropPopPad.PaddingLeft = UDim.new(0, 6)
DropPopPad.PaddingRight = UDim.new(0, 6)

local DropPopLayout = Instance.new("UIListLayout", DropPopScroll)
DropPopLayout.Padding = UDim.new(0, 4)
DropPopLayout.SortOrder = Enum.SortOrder.LayoutOrder

makeDraggable(DropPopHeader, DropdownPopup, nil)

local activePopupOwner = nil
DropPopClose.MouseButton1Click:Connect(function()
    DropdownPopup.Visible = false
    activePopupOwner = nil
end)

-- // FLOATING ICON
local AppIcon = Instance.new("TextButton")
AppIcon.Name = "FloatingIcon"
AppIcon.Size = UDim2.new(0, 42, 0, 42)
AppIcon.Position = UDim2.new(0, 20, 0.45, 0)
AppIcon.BackgroundColor3 = Color3.fromRGB(0, 0, 0)
AppIcon.Text = "N"
AppIcon.TextColor3 = Color3.fromRGB(255, 255, 255)
AppIcon.Font = Enum.Font.GothamBlack
AppIcon.TextSize = 22
AppIcon.AutoButtonColor = false
AppIcon.Parent = ScreenGui
Instance.new("UICorner", AppIcon).CornerRadius = UDim.new(0, 10)

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

-- // AIMBOT POPUP
local AimbotPopup = Instance.new("Frame")
AimbotPopup.Name = "AimbotPopup"
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
            AimTargetLabel.Text = "No Target Found"
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

-- // MAIN WINDOW
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
SubTitle.Text = "Heroes Battlegrounds v26 Stealth"
SubTitle.TextColor3 = Color3.fromRGB(155, 165, 180)
SubTitle.Font = Enum.Font.Gotham
SubTitle.TextSize = 12
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
    if not MainFrame.Visible then
        DropdownPopup.Visible = false
    end
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
    Config.DeepVoidActive = false
    Config.AntiStunEnabled = false
    Config.AntiSkillEnabled = false
    Config.WallComboEnabled = false
    Config.ObjectESPEnabled = false
    Config.AutoSkillEnabled = false
    Config.AutoUltimateEnabled = false
    Config.AimbotActive = false
    Config.ESPEnabled = false

    pcall(stopMovableGhostDecoy)
    pcall(restoreActiveWallTree)
    pcall(clearObjectESP)
    pcall(cleanupInvisible)
    pcall(clearFlyPad)
    if State.InfiniteVoidPlatform then
        pcall(function() State.InfiniteVoidPlatform:Destroy() end)
        State.InfiniteVoidPlatform = nil
    end

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
SectionHeader.Text = "Void Kill"
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

local function addDropdown(parent, label, options, defaultIndex, callback)
    local selectedValue = options[defaultIndex or 1] or "None"
    local currentOptions = options
    local ownerId = tostring({})

    local Container = Instance.new("Frame")
    Container.Size = UDim2.new(1, 0, 0, 44)
    Container.BackgroundColor3 = Color3.fromRGB(32, 34, 40)
    Container.BackgroundTransparency = 0.25
    Container.BorderSizePixel = 0
    Container.Parent = parent
    Instance.new("UICorner", Container).CornerRadius = UDim.new(0, 6)

    local CardStroke = Instance.new("UIStroke", Container)
    CardStroke.Color = Color3.fromRGB(52, 56, 66)
    CardStroke.Transparency = 0.4
    CardStroke.Thickness = 1

    local HeaderBtn = Instance.new("TextButton")
    HeaderBtn.Size = UDim2.new(1, 0, 1, 0)
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
    BoxStroke.Color = Color3.fromRGB(65, 145, 225)
    BoxStroke.Thickness = 1

    local ValueLbl = Instance.new("TextLabel")
    ValueLbl.Size = UDim2.new(1, -28, 1, 0)
    ValueLbl.Position = UDim2.new(0, 10, 0, 0)
    ValueLbl.BackgroundTransparency = 1
    ValueLbl.Text = tostring(selectedValue)
    ValueLbl.TextColor3 = Color3.fromRGB(215, 220, 230)
    ValueLbl.Font = Enum.Font.GothamMedium
    ValueLbl.TextSize = 11
    ValueLbl.TextXAlignment = Enum.TextXAlignment.Left
    ValueLbl.TextTruncate = Enum.TextTruncate.AtEnd
    ValueLbl.Parent = SelectBox

    local Chevron = Instance.new("TextLabel")
    Chevron.Size = UDim2.new(0, 20, 1, 0)
    Chevron.Position = UDim2.new(1, -22, 0, 0)
    Chevron.BackgroundTransparency = 1
    Chevron.Text = "↗"
    Chevron.TextColor3 = Color3.fromRGB(110, 195, 255)
    Chevron.Font = Enum.Font.GothamBold
    Chevron.TextSize = 13
    Chevron.Parent = SelectBox

    local function renderExternalPopup()
        for _, child in ipairs(DropPopScroll:GetChildren()) do
            if child:IsA("TextButton") then child:Destroy() end
        end
        DropPopTitle.Text = label

        for _, opt in ipairs(currentOptions) do
            local isSelected = (opt == selectedValue)
            local ItemBtn = Instance.new("TextButton")
            ItemBtn.Size = UDim2.new(1, 0, 0, 28)
            ItemBtn.BackgroundColor3 = isSelected and Color3.fromRGB(45, 115, 195) or Color3.fromRGB(32, 35, 42)
            ItemBtn.BackgroundTransparency = isSelected and 0.05 or 0.25
            ItemBtn.Text = (isSelected and "  ●  " or "  ○  ") .. tostring(opt)
            ItemBtn.TextColor3 = isSelected and Color3.fromRGB(255, 255, 255) or Color3.fromRGB(195, 205, 220)
            ItemBtn.Font = isSelected and Enum.Font.GothamBold or Enum.Font.GothamMedium
            ItemBtn.TextSize = 12
            ItemBtn.TextXAlignment = Enum.TextXAlignment.Left
            ItemBtn.AutoButtonColor = false
            ItemBtn.ZIndex = 53
            ItemBtn.Parent = DropPopScroll
            Instance.new("UICorner", ItemBtn).CornerRadius = UDim.new(0, 5)

            ItemBtn.MouseButton1Click:Connect(function()
                selectedValue = opt
                ValueLbl.Text = tostring(selectedValue)
                callback(selectedValue)
                renderExternalPopup()
            end)
        end
    end

    HeaderBtn.MouseButton1Click:Connect(function()
        if DropdownPopup.Visible and activePopupOwner == ownerId then
            DropdownPopup.Visible = false
            activePopupOwner = nil
        else
            activePopupOwner = ownerId
            renderExternalPopup()
            DropdownPopup.Visible = true
        end
    end)

    return {
        Refresh = function(newOptions)
            currentOptions = newOptions
            if not table.find(currentOptions, selectedValue) then
                selectedValue = currentOptions[1] or "None"
                ValueLbl.Text = tostring(selectedValue)
                callback(selectedValue)
            end
            if DropdownPopup.Visible and activePopupOwner == ownerId then
                renderExternalPopup()
            end
        end
    }
end

local function addMultiDropdown(parent, label, options, callback)
    local selectedMap = {}
    local currentOptions = options
    local ownerId = tostring({})

    local Container = Instance.new("Frame")
    Container.Size = UDim2.new(1, 0, 0, 44)
    Container.BackgroundColor3 = Color3.fromRGB(32, 34, 40)
    Container.BackgroundTransparency = 0.25
    Container.BorderSizePixel = 0
    Container.Parent = parent
    Instance.new("UICorner", Container).CornerRadius = UDim.new(0, 6)

    local CardStroke = Instance.new("UIStroke", Container)
    CardStroke.Color = Color3.fromRGB(52, 56, 66)
    CardStroke.Transparency = 0.4
    CardStroke.Thickness = 1

    local HeaderBtn = Instance.new("TextButton")
    HeaderBtn.Size = UDim2.new(1, 0, 1, 0)
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
    BoxStroke.Color = Color3.fromRGB(65, 145, 225)
    BoxStroke.Thickness = 1

    local ValueLbl = Instance.new("TextLabel")
    ValueLbl.Size = UDim2.new(1, -28, 1, 0)
    ValueLbl.Position = UDim2.new(0, 10, 0, 0)
    ValueLbl.BackgroundTransparency = 1
    ValueLbl.Text = "None Selected"
    ValueLbl.TextColor3 = Color3.fromRGB(215, 220, 230)
    ValueLbl.Font = Enum.Font.GothamMedium
    ValueLbl.TextSize = 11
    ValueLbl.TextXAlignment = Enum.TextXAlignment.Left
    ValueLbl.TextTruncate = Enum.TextTruncate.AtEnd
    ValueLbl.Parent = SelectBox

    local Chevron = Instance.new("TextLabel")
    Chevron.Size = UDim2.new(0, 20, 1, 0)
    Chevron.Position = UDim2.new(1, -22, 0, 0)
    Chevron.BackgroundTransparency = 1
    Chevron.Text = "↗"
    Chevron.TextColor3 = Color3.fromRGB(110, 195, 255)
    Chevron.Font = Enum.Font.GothamBold
    Chevron.TextSize = 13
    Chevron.Parent = SelectBox

    local function updateSummaryText()
        local names = {}
        for k, v in pairs(selectedMap) do
            if v then table.insert(names, k) end
        end
        if #names == 0 then
            ValueLbl.Text = "None Selected"
        else
            ValueLbl.Text = table.concat(names, ", ")
        end
    end

    local function renderExternalMultiPopup()
        for _, child in ipairs(DropPopScroll:GetChildren()) do
            if child:IsA("TextButton") then child:Destroy() end
        end
        DropPopTitle.Text = label

        for _, opt in ipairs(currentOptions) do
            if opt ~= "None" then
                local isSelected = (selectedMap[opt] == true)
                local ItemBtn = Instance.new("TextButton")
                ItemBtn.Size = UDim2.new(1, 0, 0, 28)
                ItemBtn.BackgroundColor3 = isSelected and Color3.fromRGB(40, 125, 195) or Color3.fromRGB(32, 35, 42)
                ItemBtn.BackgroundTransparency = isSelected and 0.05 or 0.25
                ItemBtn.Text = (isSelected and "  ●  " or "  ○  ") .. tostring(opt)
                ItemBtn.TextColor3 = isSelected and Color3.fromRGB(255, 255, 255) or Color3.fromRGB(195, 205, 220)
                ItemBtn.Font = isSelected and Enum.Font.GothamBold or Enum.Font.GothamMedium
                ItemBtn.TextSize = 12
                ItemBtn.TextXAlignment = Enum.TextXAlignment.Left
                ItemBtn.AutoButtonColor = false
                ItemBtn.ZIndex = 53
                ItemBtn.Parent = DropPopScroll
                Instance.new("UICorner", ItemBtn).CornerRadius = UDim.new(0, 5)

                ItemBtn.MouseButton1Click:Connect(function()
                    selectedMap[opt] = not selectedMap[opt]
                    updateSummaryText()
                    callback(selectedMap)
                    renderExternalMultiPopup()
                end)
            end
        end
    end

    HeaderBtn.MouseButton1Click:Connect(function()
        if DropdownPopup.Visible and activePopupOwner == ownerId then
            DropdownPopup.Visible = false
            activePopupOwner = nil
        else
            activePopupOwner = ownerId
            renderExternalMultiPopup()
            DropdownPopup.Visible = true
        end
    end)

    return {
        Refresh = function(newOptions)
            currentOptions = newOptions
            local validSet = {}
            for _, o in ipairs(newOptions) do validSet[o] = true end
            for k, _ in pairs(selectedMap) do
                if not validSet[k] then selectedMap[k] = nil end
            end
            updateSummaryText()
            callback(selectedMap)
            if DropdownPopup.Visible and activePopupOwner == ownerId then
                renderExternalMultiPopup()
            end
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

local function addDualButtons(parent, textLeft, colorLeft, cbLeft, textRight, colorRight, cbRight)
    local Row = Instance.new("Frame")
    Row.Size = UDim2.new(1, 0, 0, 38)
    Row.BackgroundTransparency = 1
    Row.Parent = parent

    local BtnL = Instance.new("TextButton")
    BtnL.Size = UDim2.new(0.485, 0, 1, 0)
    BtnL.Position = UDim2.new(0, 0, 0, 0)
    BtnL.BackgroundColor3 = colorLeft or Color3.fromRGB(45, 115, 195)
    BtnL.BackgroundTransparency = 0.1
    BtnL.Text = textLeft
    BtnL.TextColor3 = Color3.fromRGB(255, 255, 255)
    BtnL.Font = Enum.Font.GothamBold
    BtnL.TextSize = 12
    BtnL.Parent = Row
    Instance.new("UICorner", BtnL).CornerRadius = UDim.new(0, 6)

    local StrokeL = Instance.new("UIStroke", BtnL)
    StrokeL.Color = Color3.fromRGB(85, 175, 255)
    StrokeL.Transparency = 0.2
    StrokeL.Thickness = 1.2

    local BtnR = Instance.new("TextButton")
    BtnR.Size = UDim2.new(0.485, 0, 1, 0)
    BtnR.Position = UDim2.new(0.515, 0, 0, 0)
    BtnR.BackgroundColor3 = colorRight or Color3.fromRGB(55, 65, 85)
    BtnR.BackgroundTransparency = 0.1
    BtnR.Text = textRight
    BtnR.TextColor3 = Color3.fromRGB(255, 255, 255)
    BtnR.Font = Enum.Font.GothamBold
    BtnR.TextSize = 12
    BtnR.Parent = Row
    Instance.new("UICorner", BtnR).CornerRadius = UDim.new(0, 6)

    local StrokeR = Instance.new("UIStroke", BtnR)
    StrokeR.Color = Color3.fromRGB(110, 130, 165)
    StrokeR.Transparency = 0.2
    StrokeR.Thickness = 1.2

    BtnL.MouseButton1Click:Connect(function() cbLeft(BtnL) end)
    BtnR.MouseButton1Click:Connect(function() cbRight(BtnR) end)
end

local function addTextInput(parent, label, placeholder, callback)
    local Card = Instance.new("Frame")
    Card.Size = UDim2.new(1, 0, 0, 44)
    Card.BackgroundColor3 = Color3.fromRGB(32, 34, 40)
    Card.BackgroundTransparency = 0.25
    Card.BorderSizePixel = 0
    Card.Parent = parent
    Instance.new("UICorner", Card).CornerRadius = UDim.new(0, 6)

    local CardStroke = Instance.new("UIStroke", Card)
    CardStroke.Color = Color3.fromRGB(52, 56, 66)
    CardStroke.Transparency = 0.4
    CardStroke.Thickness = 1

    local TitleLbl = Instance.new("TextLabel")
    TitleLbl.Size = UDim2.new(0.42, -14, 1, 0)
    TitleLbl.Position = UDim2.new(0, 14, 0, 0)
    TitleLbl.BackgroundTransparency = 1
    TitleLbl.Text = label
    TitleLbl.TextColor3 = Color3.fromRGB(230, 234, 242)
    TitleLbl.Font = Enum.Font.GothamMedium
    TitleLbl.TextSize = 12
    TitleLbl.TextXAlignment = Enum.TextXAlignment.Left
    TitleLbl.Parent = Card

    local Box = Instance.new("TextBox")
    Box.Size = UDim2.new(0.55, -14, 0, 28)
    Box.Position = UDim2.new(0.45, 0, 0.5, -14)
    Box.BackgroundColor3 = Color3.fromRGB(22, 24, 30)
    Box.Text = ""
    Box.PlaceholderText = placeholder or ""
    Box.TextColor3 = Color3.fromRGB(240, 245, 255)
    Box.PlaceholderColor3 = Color3.fromRGB(120, 130, 145)
    Box.Font = Enum.Font.GothamMedium
    Box.TextSize = 11
    Box.ClearTextOnFocus = false
    Box.Parent = Card
    Instance.new("UICorner", Box).CornerRadius = UDim.new(0, 5)

    local BoxStroke = Instance.new("UIStroke", Box)
    BoxStroke.Color = Color3.fromRGB(65, 145, 225)
    BoxStroke.Thickness = 1

    Box:GetPropertyChangedSignal("Text"):Connect(function()
        callback(Box.Text)
    end)
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
local TabVoid   = createTab("Void Kill", "🌀")
local TabCombat = createTab("Combat", "⚔")
local TabTarget = createTab("AutoFarm", "◇")
local TabMove   = createTab("LocalPlayer", "👤")
local TabServer = createTab("Server", "🌐")
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
        seat.Archivable = false
        seat.Size = Vector3.new(1, 1, 1)
        seat.Transparency = 1
        seat.CanCollide = false
        seat.Name = State.PadToken .. "_S"
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

-- // 1. POPULATE VOID KILL TAB
local SlotPreviewCard = Instance.new("Frame")
SlotPreviewCard.Size = UDim2.new(1, 0, 0, 48)
SlotPreviewCard.BackgroundColor3 = Color3.fromRGB(28, 32, 42)
SlotPreviewCard.BackgroundTransparency = 0.15
SlotPreviewCard.BorderSizePixel = 0
SlotPreviewCard.Parent = TabVoid
Instance.new("UICorner", SlotPreviewCard).CornerRadius = UDim.new(0, 6)

local SlotPreviewStroke = Instance.new("UIStroke", SlotPreviewCard)
SlotPreviewStroke.Color = Color3.fromRGB(65, 165, 245)
SlotPreviewStroke.Transparency = 0.35
SlotPreviewStroke.Thickness = 1

State.SlotStatusLabel = Instance.new("TextLabel")
State.SlotStatusLabel.Size = UDim2.new(1, -20, 1, -8)
State.SlotStatusLabel.Position = UDim2.new(0, 10, 0, 4)
State.SlotStatusLabel.BackgroundTransparency = 1
State.SlotStatusLabel.Text = "Slot 1: Unscanned  |  Slot 2: Unscanned\nSlot 3: Unscanned  |  Slot 4: Unscanned"
State.SlotStatusLabel.TextColor3 = Color3.fromRGB(165, 225, 255)
State.SlotStatusLabel.Font = Enum.Font.GothamSemibold
State.SlotStatusLabel.TextSize = 11
State.SlotStatusLabel.TextXAlignment = Enum.TextXAlignment.Left
State.SlotStatusLabel.Parent = SlotPreviewCard

addDualButtons(
    TabVoid,
    "Teleport Void", Color3.fromRGB(45, 115, 195), function() teleportToDeepVoid() end,
    "Teleport Back", Color3.fromRGB(55, 135, 95), function() teleportBackFromDeepVoid() end
)

addFeatureToggle(TabVoid, "AutoVoidKill", "Auto Void Kill", "VOIDK", false, function(v)
    Config.AutoVoidKill = v
    if not v then
        State.VoidKillActive = false
        State.VoidDropTargetCF = nil
        State.ActiveSpecialSkill = nil
    else
        scanHotbarSkills1To4()
    end
end)

local MineMultiDropdown = addMultiDropdown(TabVoid, "Mine Multi Targets", currentTargetList, function(selectedMap)
    Config.MineSelectedTargets = selectedMap
end)

addSlider(TabVoid, "Void Hold Duration", 0.50, 3.50, 1.85, function(v)
    Config.VoidMaxHoldTime = v
end)

-- // 2. POPULATE COMBAT TAB
addFeatureToggle(TabCombat, "WallCombo", "Auto Wall Combo", "WALLC", false, function(v)
    Config.WallComboEnabled = v
    if v then
        scanRealTreeWoods()
    else
        restoreActiveWallTree()
    end
end)

addDropdown(TabCombat, "Wall Combo Mode", {"TreeBehindEnemy", "SnapToRealTree"}, 1, function(mode)
    Config.WallComboMode = mode
    restoreActiveWallTree()
end)

addButton(TabCombat, "Trigger Wall Combo Now", Color3.fromRGB(45, 130, 85), function()
    triggerWallComboBehindEnemy(0.80)
end)

addFeatureToggle(TabCombat, "ObjectESP", "Tree And Map Object ESP", "OBJESP", false, function(v)
    Config.ObjectESPEnabled = v
    if not v then
        clearObjectESP()
    end
end)

addButton(TabCombat, "Copy Nearest Object Info", Color3.fromRGB(55, 105, 165), function(btn)
    copyNearestMapObjectInfo(btn)
end)

addFeatureToggle(TabCombat, "AutoSkill", "Auto Skill", "ASKL", false, function(v)
    Config.AutoSkillEnabled = v
end)

addFeatureToggle(TabCombat, "AutoUltimate", "Auto Ultimate", "AULT", false, function(v)
    Config.AutoUltimateEnabled = v
end)

addFeatureToggle(TabCombat, "AntiSkill", "Anti Skill", "ANTIS", false, function(v)
    Config.AntiSkillEnabled = v
    if not v and State.AntiSkillEvading then
        State.AntiSkillEvading = false
        stopMovableGhostDecoy()
    end
end)

addSlider(TabCombat, "Anti Skill Range", 8, 35, 16, function(v)
    Config.AntiSkillRange = v
end)

addFeatureToggle(TabCombat, "AntiStun", "Anti Stun", "ASTUN", false, function(v)
    Config.AntiStunEnabled = v
    if v and State.Char and State.Root and State.Hum then
        enforceOldFullAntiStun(State.Char, State.Root, State.Hum)
    end
end)

addFeatureToggle(TabCombat, "AimbotPopup", "Aimbot Widget", "AIM", false, function(v)
    Config.AimbotWidgetOpen = v
    AimbotPopup.Visible = v
    if not v then setAimbotActiveState(false) end
end)

addDropdown(TabCombat, "Aimbot Part", {"Head", "HumanoidRootPart"}, 1, function(part)
    Config.AimPart = part
end)

-- // 3. POPULATE AUTOFARM TAB
addFeatureToggle(TabTarget, "AutoTarget", "AutoFarm Player", "TAR", false, function(v)
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

local PlayerDropdown = addDropdown(TabTarget, "Select Target Player", currentTargetList, 1, function(selected)
    Config.SelectedPlayer = selected
    State.FreeMoveOffset = Vector3.zero
end)

addDropdown(TabTarget, "Target Position Mode", {"Behind", "Orbit", "Random", "Below", "Upper", "Front"}, 1, function(mode)
    Config.TargetMode = mode
    State.FreeMoveOffset = Vector3.zero
end)

addSlider(TabTarget, "Orbit Speed", 1, 60, 15, function(v)
    Config.OrbitSpeed = v
end)

addSlider(TabTarget, "Target Range", 1, 200, 5.5, function(v)
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

-- // 4. POPULATE LOCALPLAYER TAB
addFeatureToggle(TabMove, "Fly", "Loop Fly", "FLY", false, function(v)
    Config.FlyEnabled = v
    if not v then
        clearFlyPad()
        if State.Root then State.Root.AssemblyLinearVelocity = Vector3.zero end
    end
end)

addDropdown(TabMove, "Fly Mode", {"FloorPad", "LoopPulse"}, 1, function(opt)
    Config.FlyMode = opt
end)

addSlider(TabMove, "Fly Speed", 10, 500, 65, function(v)
    Config.FlySpeed = v
end)

addFeatureToggle(TabMove, "InfJump", "Infinite Jump", "INFJ", false, function(v)
    Config.InfJumpEnabled = v
    if not v then
        State.InfJumpArcActive = false
        if not Config.FlyEnabled and not Config.AutoTargetEnabled then
            clearFlyPad()
        end
    end
end)

addDropdown(TabMove, "Infinite Jump Mode", {"FlyPadStep", "ParabolicCFrame", "MicroBounce"}, 1, function(opt)
    Config.InfJumpMode = opt
end)

addFeatureToggle(TabMove, "Invisible", "Invisible", "INVIS", false, function(v)
    Config.InvisibleEnabled = v
    toggleInvisible(v)
end)

addDropdown(TabMove, "Invisible Mode", {"RootJointBreak", "UndergroundC0", "SeatDesync"}, 1, function(opt)
    Config.InvisMode = opt
    if Config.InvisibleEnabled then toggleInvisible(true) end
end)

addFeatureToggle(TabMove, "Speed", "WalkSpeed Boost", "SPD", false, function(v)
    Config.SpeedEnabled = v
    if not v and State.Hum then State.Hum.WalkSpeed = 16 end
end)

addSlider(TabMove, "WalkSpeed", 16, 500, 50, function(v)
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

-- // 5. POPULATE SERVER TAB
addButton(TabServer, "Rejoin Server", Color3.fromRGB(45, 110, 185), function()
    rejoinCurrentServer()
end)

addButton(TabServer, "Random Smooth Server", Color3.fromRGB(40, 140, 95), function(btn)
    joinRandomSmoothServer(btn)
end)

addTextInput(TabServer, "Server Job ID", "Paste Job ID Here", function(txt)
    Config.CustomJobId = txt
end)

addButton(TabServer, "Join Job ID", Color3.fromRGB(65, 95, 165), function(btn)
    joinServerByJobId(btn)
end)

-- // 6. POPULATE SETTINGS TAB
addFeatureToggle(TabVisual, "ESP", "Player ESP", "ESP", false, function(v)
    Config.ESPEnabled = v
    if not v then
        for _, obj in pairs(State.ESPObjects) do
            if obj.Billboard then obj.Billboard:Destroy() end
        end
        State.ESPObjects = {}
    end
end)

addButton(TabVisual, "Refresh Player Lists", nil, function()
    local updated = getPlayerNames()
    PlayerDropdown.Refresh(updated)
    MineMultiDropdown.Refresh(updated)
end)

addButton(TabVisual, "Unload Script", Color3.fromRGB(145, 45, 50), function()
    unloadEntireScript()
end)

Config.AntiVoidEnabled = true
Config.AutoVoidKill = false
Config.UIInitialized = true
task.defer(scanHotbarSkills1To4)
task.defer(scanRealTreeWoods)

table.insert(State.Connections, Players.PlayerAdded:Connect(function()
    task.wait(0.2)
    if Config.ScriptRunning then
        local updated = getPlayerNames()
        PlayerDropdown.Refresh(updated)
        MineMultiDropdown.Refresh(updated)
    end
end))

table.insert(State.Connections, Players.PlayerRemoving:Connect(function(leavingPlr)
    if not Config.ScriptRunning then return end
    if State.LockedAimbotPlayer == leavingPlr then
        setAimbotActiveState(false)
    end
    if State.ESPObjects[leavingPlr] then
        pcall(function() State.ESPObjects[leavingPlr].Billboard:Destroy() end)
        State.ESPObjects[leavingPlr] = nil
    end
    task.wait(0.2)
    local updated = getPlayerNames()
    PlayerDropdown.Refresh(updated)
    MineMultiDropdown.Refresh(updated)
end))

-- // STEALTH ESP (BILLBOARD ONLY, NO HIGHLIGHT INSTANCE ON CHARACTERS)
local function updateESP()
    if not Config.ScriptRunning or not Config.ESPEnabled then return end
    local now = tick()
    if now - State.LastESPRefresh < 0.15 then return end
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
                        pcall(function() State.ESPObjects[plr].Billboard:Destroy() end)
                    end

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

                    State.ESPObjects[plr] = {Char = char, Billboard = bb, Label = txt}
                end

                local dist = myRoot and math.floor((myRoot.Position - root.Position).Magnitude) or 0
                State.ESPObjects[plr].Label.Text = string.format("%s [%d HP]\n[%dm]", plr.Name, math.floor(hum.Health), dist)
            elseif State.ESPObjects[plr] then
                pcall(function() State.ESPObjects[plr].Billboard:Destroy() end)
                State.ESPObjects[plr] = nil
            end
        end
    end
end

local function getPlanarMoveVector(hum)
    local moveDir = Vector3.zero
    local camCF = Camera.CFrame
    local flatLook = Vector3.new(camCF.LookVector.X, 0, camCF.LookVector.Z)
    local flatRight = Vector3.new(camCF.RightVector.X, 0, camCF.RightVector.Z)
    if flatLook.Magnitude > 0.01 then flatLook = flatLook.Unit end
    if flatRight.Magnitude > 0.01 then flatRight = flatRight.Unit end

    if UserInputService:IsKeyDown(Enum.KeyCode.W) then moveDir = moveDir + flatLook end
    if UserInputService:IsKeyDown(Enum.KeyCode.S) then moveDir = moveDir - flatLook end
    if UserInputService:IsKeyDown(Enum.KeyCode.D) then moveDir = moveDir + flatRight end
    if UserInputService:IsKeyDown(Enum.KeyCode.A) then moveDir = moveDir - flatRight end

    if moveDir.Magnitude == 0 and hum and hum.MoveDirection.Magnitude > 0 then
        moveDir = Vector3.new(hum.MoveDirection.X, 0, hum.MoveDirection.Z)
    end
    if moveDir.Magnitude > 0 then return moveDir.Unit end
    return Vector3.zero
end

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

-- // STEPPED LOOP
table.insert(State.Connections, RunService.Stepped:Connect(function()
    if not Config.ScriptRunning then return end
    local targetY = getSafeVoidFloorY()

    if State.VoidKillActive and State.VoidDropTargetCF and State.Root then
        if State.Root.Anchored then State.Root.Anchored = false end
        State.Root.CFrame = State.VoidDropTargetCF
        State.Root.AssemblyLinearVelocity = Vector3.zero
        State.Root.AssemblyAngularVelocity = Vector3.zero
    elseif State.AntiSkillEvading and State.DecoyCFrame and State.Root then
        local plat = ensureInfiniteVoidPlatform()
        local voidPos = Vector3.new(State.DecoyCFrame.Position.X, targetY + 3.5, State.DecoyCFrame.Position.Z)
        plat.CFrame = CFrame.new(voidPos.X, targetY - 2, voidPos.Z)
        State.Root.CFrame = CFrame.new(voidPos) * State.DecoyCFrame.Rotation
        State.Root.AssemblyLinearVelocity = Vector3.zero
    elseif Config.DeepVoidActive and State.Root then
        local plat = ensureInfiniteVoidPlatform()
        plat.CFrame = CFrame.new(State.Root.Position.X, targetY - 2, State.Root.Position.Z)
        if State.Root.Position.Y > (targetY + 45) or State.Root.Position.Y < (targetY - 12) then
            State.Root.CFrame = CFrame.new(State.Root.Position.X, targetY + 3.5, State.Root.Position.Z) * State.Root.CFrame.Rotation
            State.Root.AssemblyLinearVelocity = Vector3.zero
        end
    end
end))

-- // RENDERSTEPPED LOOP
table.insert(State.Connections, RunService.RenderStepped:Connect(function(dt)
    if not Config.ScriptRunning then return end
    local char = State.Char
    local root = State.Root
    local hum = State.Hum
    local targetY = getSafeVoidFloorY()

    if State.VoidKillActive and State.VoidDropTargetCF and root then
        root.CFrame = State.VoidDropTargetCF
        root.AssemblyLinearVelocity = Vector3.zero
        root.AssemblyAngularVelocity = Vector3.zero
    elseif State.AntiSkillEvading and State.DecoyCFrame and root and hum then
        local moveVec = getPlanarMoveVector(hum)
        local spd = Config.SpeedEnabled and Config.WalkSpeed or 22
        local newPos = State.DecoyCFrame.Position + (moveVec * spd * dt)

        local lookDir = moveVec.Magnitude > 0.05 and moveVec or Vector3.new(Camera.CFrame.LookVector.X, 0, Camera.CFrame.LookVector.Z)
        if lookDir.Magnitude > 0.01 then
            State.DecoyCFrame = CFrame.lookAt(newPos, newPos + lookDir.Unit)
        else
            State.DecoyCFrame = CFrame.new(newPos) * State.DecoyCFrame.Rotation
        end

        if State.DecoyModel and State.DecoyModel.PrimaryPart then
            State.DecoyModel:PivotTo(State.DecoyCFrame)
        end
        if State.DecoyCameraProxy then
            State.DecoyCameraProxy.CFrame = State.DecoyCFrame + Vector3.new(0, 1.5, 0)
            if Camera.CameraSubject ~= State.DecoyCameraProxy then
                Camera.CameraSubject = State.DecoyCameraProxy
            end
        end

        local voidPos = Vector3.new(State.DecoyCFrame.Position.X, targetY + 3.5, State.DecoyCFrame.Position.Z)
        root.CFrame = CFrame.new(voidPos) * State.DecoyCFrame.Rotation
        root.AssemblyLinearVelocity = Vector3.zero
    end

    if Config.AntiStunEnabled and char and root and hum then
        enforceOldFullAntiStun(char, root, hum)
    end

    if Config.InvisibleEnabled then
        for i = 1, #State.InvisData.HiddenParts do
            local p = State.InvisData.HiddenParts[i]
            if p then p.CanCollide = false end
        end
    end

    if Config.AutoTargetEnabled and root and hum and not State.VoidKillActive and not State.AntiSkillEvading and not Config.DeepVoidActive and State.ActiveSpecialSkill == nil then
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
    local targetY = getSafeVoidFloorY()

    if root and hum and hum.Health > 0 then
        local voidY = Workspace.FallenPartsDestroyHeight
        if voidY ~= voidY or voidY < -10000 or voidY > 500 then voidY = -500 end

        -- Stealth Auto Skill (activates Backpack/Character tools directly without VirtualInputManager detection)
        if Config.AutoSkillEnabled and not State.VoidKillActive and not State.AntiSkillEvading and not UserInputService:GetFocusedTextBox() then
            local now = tick()
            if (now - State.LastAutoSkillTick) >= Config.AutoSkillDelay then
                State.LastAutoSkillTick = now
                local idx = State.AutoSkillIndex
                State.AutoSkillIndex = (idx % 4) + 1
                local backpack = LocalPlayer:FindFirstChildOfClass("Backpack")
                local slotName = State.DetectedSlotNames[tostring(idx)]
                if backpack and slotName and slotName ~= "Unscanned" then
                    local tool = backpack:FindFirstChild(slotName)
                    if tool and tool:IsA("Tool") then
                        pcall(function() hum:EquipTool(tool) end)
                        pcall(function() tool:Activate() end)
                    end
                end
                onSkillSlotTriggered(tostring(idx))
            end
        end

        if Config.AutoUltimateEnabled and not State.VoidKillActive and not UserInputService:GetFocusedTextBox() then
            local now = tick()
            if (now - State.LastAutoUltTick) >= Config.AutoUltimateDelay then
                State.LastAutoUltTick = now
                pcall(function()
                    local main = char and char:FindFirstChild("Main")
                    local rem = main and main:FindFirstChild("RemoteEvent")
                    if rem then
                        rem:FireServer("Awakening")
                    end
                end)
            end
        end

        if Config.AntiSkillEnabled and not State.VoidKillActive then
            local dangerNear = detectNearbyEnemySkillThreat()
            if dangerNear and not State.AntiSkillEvading then
                State.AntiSkillEvading = true
                spawnMovableGhostDecoy(root.CFrame)
                local voidPos = Vector3.new(State.DecoyCFrame.Position.X, targetY + 3.5, State.DecoyCFrame.Position.Z)
                root.CFrame = CFrame.new(voidPos) * State.DecoyCFrame.Rotation
                root.AssemblyLinearVelocity = Vector3.zero
            elseif not dangerNear and State.AntiSkillEvading then
                State.AntiSkillEvading = false
                stopMovableGhostDecoy()
            end
        elseif State.AntiSkillEvading then
            State.AntiSkillEvading = false
            stopMovableGhostDecoy()
        end

        if not State.VoidKillActive and not State.AntiSkillEvading and not Config.DeepVoidActive then
            if hum.FloorMaterial ~= Enum.Material.Air and root.Position.Y > -50 then
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

        if Config.AutoVoidKill and not State.VoidKillActive and not State.AntiSkillEvading then
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
    updateObjectESP()
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

    local slotStr = KeyMap1To4[input.KeyCode]
    if not gpe and slotStr then
        onSkillSlotTriggered(slotStr)
    end

    if not gpe and Config.WallComboEnabled then
        if input.UserInputType == Enum.UserInputType.MouseButton1 or input.UserInputType == Enum.UserInputType.Touch then
            local now = tick()
            if (now - State.LastM1ClickTick) > 1.35 then
                State.M1ClickCount = 1
            else
                State.M1ClickCount = State.M1ClickCount + 1
            end
            State.LastM1ClickTick = now

            if State.M1ClickCount >= 3 then
                if State.M1ClickCount >= 4 then
                    State.M1ClickCount = 0
                end
                local _, eRoot = findNearestEnemyRoot(16)
                if eRoot then
                    triggerWallComboBehindEnemy(0.75)
                end
            end
        elseif input.KeyCode == Enum.KeyCode.Q then
            local _, eRoot = findNearestEnemyRoot(16)
            if eRoot then
                triggerWallComboBehindEnemy(0.75)
            end
        end
    end

    if not gpe and input.KeyCode == Config.WallComboKey then
        triggerWallComboBehindEnemy(0.85)
    end

    if not gpe and input.KeyCode == Enum.KeyCode.Space and Config.InfJumpEnabled then
        triggerUndetectedInfJump()
    end
end))
