-- Context: Luau (Roblox Client Executor - Heroes Battlegrounds Edition v39)
-- Updates in v39:
--   1. Unified Multi-Target Grab Engine: MINE, Pierce The Heavens, and BLAST AWAY now share a single dropdown selection pool!
--   2. "ALL" Selector Option: Instantly selects all players in the server for multi-target sweeps.
--   3. Fixed Multi-Target Teleportation: Iterates through checked targets with proper yield timing so character cleanly visits every selected player before executing the Void/Far/High drop.
--   4. High Place altitude set to Y = 1800: Vector3.new(35.79, 1800.00, -207.31).
--   5. Ultra-Far distance increased to 1 Billion (1B) - 10 Billion (10B) studs.

local cloneref = cloneref or function(obj) return obj end

local Players = cloneref(game:GetService("Players"))
local RunService = cloneref(game:GetService("RunService"))
local UserInputService = cloneref(game:GetService("UserInputService"))
local TweenService = cloneref(game:GetService("TweenService"))
local Workspace = cloneref(game:GetService("Workspace"))
local CoreGui = cloneref(game:GetService("CoreGui"))
local TeleportService = cloneref(game:GetService("TeleportService"))
local HttpService = cloneref(game:GetService("HttpService"))

local LocalPlayer = Players.LocalPlayer
local Camera = Workspace.CurrentCamera

local function randomToken()
    local chars = "abcdefghijklmnopqrstuvwxyzABCDEFGHIJKLMNOPQRSTUVWXYZ"
    local out = {}
    for i = 1, 12 do
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

    -- Void Kill & Deep Void
    VoidKillPlaneY = -500,
    VoidFarHorizontalDist = 2900,
    VoidSafeMarginAboveDeath = 2.2,
    DeepVoidActive = false,

    -- Grab-Carry Modes
    AutoVoidKill = false,
    AutoHighPlaceCarry = false,
    AutoUltraFarCarry = false,

    HighPlaceTargetPos = Vector3.new(35.79, 1800.00, -207.31),
    UltraFarDistanceBillions = 1, -- 1B to 10B studs
    VoidMaxHoldTime = 1.45,

    -- Unified Multi-Target Grab State
    MultiTargetSelectedMap = {},
    MultiTargetSelectAll = false,

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
    AutoSkillDelay = 0.45,
    AutoUltimateEnabled = false,
    AutoUltimateDelay = 0.80,

    AntiSkillEnabled = false,
    AntiSkillRange = 16,

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

    -- Movement (Max 500, Default WalkSpeed = 55, FlySpeed = 75)
    FlyEnabled = false,
    FlyMode = "InvisibleGroundPad",
    FlySpeed = 75,
    InfJumpEnabled = false,
    InfJumpMode = "FlyPadStep",
    InvisibleEnabled = false,
    InvisMode = "RootJointBreak",
    SpeedEnabled = false,
    WalkSpeed = 55,
    JumpBoostEnabled = false,
    JumpPower = 100,

    -- Visuals & Server
    ESPEnabled = false,
    CustomJobId = "",
}

local State = {
    UIToken = randomToken(),
    WhiteFloorToken = randomToken(),
    GroundPadToken = randomToken(),

    Char = nil,
    Root = nil,
    Hum = nil,
    Animator = nil,
    OrigRootJointC0 = nil,
    OrigRootJointC1 = nil,
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
    CoordStatusLabel = nil,

    WhiteVoidPlatform = nil,
    InvisibleGroundPad = nil,
    FlyAltitudeY = nil,
    DeepVoidStandCF = nil,
    PreDeepVoidCFrame = nil,

    PhantomShotStage = 0,
    PhantomShotLastTick = 0,
    ActiveSpecialSkill = nil,
    GrabbedThisCast = {},
    GrabWatchWindowUntil = 0,

    LastSafeCFrame = nil,
    VoidKillActive = false,
    VoidDropTargetCF = nil,
    VoidReturnCFrame = nil,

    AntiSkillEvading = false,
    DecoyCFrame = nil,

    LastAutoSkillTick = 0,
    AutoSkillIndex = 1,
    LastAutoUltTick = 0,

    InfJumpArcActive = false,
    InfJumpArcTimer = 0,
    LastJumpTime = 0,
    OrbitAngle = 0,
    FreeMoveOffset = Vector3.zero,
    LockedAimbotPlayer = nil,
    InvisData = { SavedC0 = nil, HiddenParts = {} },
    ESPObjects = {},
    LastESPRefresh = 0,
    ToggleRegistry = {},
    PinnedButtons = {},
    Connections = {},
}

-- // ==========================================================================
-- // EXACT R6 / R15 FOOT BOTTOM OFFSET & SOLID ZERO-DROP GROUND PAD
-- // ==========================================================================
local function getExactFootBottomOffset(char, root, hum)
    if not root or not hum then return 3.0 end
    if hum.RigType == Enum.HumanoidRigType.R6 then
        local leftLeg = char and char:FindFirstChild("Left Leg")
        local rightLeg = char and char:FindFirstChild("Right Leg")
        local legHeight = (leftLeg and leftLeg:IsA("BasePart") and leftLeg.Size.Y)
            or (rightLeg and rightLeg:IsA("BasePart") and rightLeg.Size.Y)
            or 2.0
        return (root.Size.Y * 0.5) + legHeight
    else
        local hip = (hum.HipHeight > 0.1) and hum.HipHeight or 2.0
        return (root.Size.Y * 0.5) + hip
    end
end

local function ensureInvisibleGroundPad()
    if State.InvisibleGroundPad and State.InvisibleGroundPad.Parent then
        return State.InvisibleGroundPad
    end
    local pad = Instance.new("Part")
    pad.Name = State.GroundPadToken
    pad.Archivable = false
    pad.Size = Vector3.new(36, 4, 36)
    pad.Anchored = true
    pad.CanCollide = true
    pad.Transparency = 1
    pad.Material = Enum.Material.Plastic
    pad.CustomPhysicalProperties = PhysicalProperties.new(10, 1, 0, 1, 1)
    pad.CFrame = CFrame.new(0, 99999, 0)
    pad.Parent = Workspace.Terrain
    State.InvisibleGroundPad = pad
    return pad
end

local function destroyInvisibleGroundPad()
    if State.InvisibleGroundPad then
        pcall(function() State.InvisibleGroundPad:Destroy() end)
        State.InvisibleGroundPad = nil
    end
end

local function updateGroundPadUnderCharacter(char, root, hum, lockedRootY)
    if not root or not hum then return end
    local pad = ensureInvisibleGroundPad()
    local footBottomDist = getExactFootBottomOffset(char, root, hum)
    local padTopY = lockedRootY - footBottomDist + 0.03
    local padCenterY = padTopY - (pad.Size.Y * 0.5)
    pad.CFrame = CFrame.new(root.Position.X, padCenterY, root.Position.Z)
    pad.AssemblyLinearVelocity = Vector3.zero
end

local function syncFlyAltitudeToCFrame(newCF)
    if not newCF then return end
    State.FlyAltitudeY = newCF.Position.Y
    if Config.FlyEnabled and State.Root and State.Hum then
        updateGroundPadUnderCharacter(State.Char, State.Root, State.Hum, State.FlyAltitudeY)
    end
end

-- // ==========================================================================
-- // FIXED Y = -500 VOID PLANE & 2,000-STUD WHITE PLATFORM
-- // ==========================================================================
local function getVoidKillPlaneY()
    local destroyY = Workspace.FallenPartsDestroyHeight
    if destroyY ~= destroyY or destroyY < -10000 or destroyY > 500 then
        destroyY = -500
    end
    Config.VoidKillPlaneY = destroyY
    return destroyY
end

local function getPlayerSafeVoidKillHoverY()
    return getVoidKillPlaneY() + Config.VoidSafeMarginAboveDeath
end

local function ensureWhiteVoidPlatform(surfaceCenterPos)
    if State.WhiteVoidPlatform and State.WhiteVoidPlatform.Parent then
        State.WhiteVoidPlatform.CFrame = CFrame.new(surfaceCenterPos.X, surfaceCenterPos.Y - 3, surfaceCenterPos.Z)
        return State.WhiteVoidPlatform
    end

    local plat = Instance.new("Part")
    plat.Name = State.WhiteFloorToken
    plat.Archivable = false
    plat.Size = Vector3.new(600, 6, 600)
    plat.Anchored = true
    plat.CanCollide = true
    plat.Material = Enum.Material.SmoothPlastic
    plat.Color = Color3.fromRGB(255, 255, 255)
    plat.Transparency = 0
    plat.CFrame = CFrame.new(surfaceCenterPos.X, surfaceCenterPos.Y - 3, surfaceCenterPos.Z)
    plat.Parent = Workspace.Terrain

    State.WhiteVoidPlatform = plat
    return plat
end

local function destroyWhiteVoidPlatform()
    if State.WhiteVoidPlatform then
        pcall(function() State.WhiteVoidPlatform:Destroy() end)
        State.WhiteVoidPlatform = nil
    end
end

local function getRootMotor(char)
    if not char then return nil end
    local lowerTorso = char:FindFirstChild("LowerTorso")
    if lowerTorso and lowerTorso:FindFirstChild("Root") then
        return lowerTorso.Root
    end
    local hrp = char:FindFirstChild("HumanoidRootPart")
    if hrp and hrp:FindFirstChild("RootJoint") then
        return hrp.RootJoint
    end
    local torso = char:FindFirstChild("Torso")
    if torso and torso:FindFirstChild("RootJoint") then
        return torso.RootJoint
    end
    return nil
end

local function forceFullCharacterAndCameraResync(targetCF)
    local char = LocalPlayer.Character or State.Char
    local root = (char and char:FindFirstChild("HumanoidRootPart")) or State.Root
    local hum = (char and char:FindFirstChildOfClass("Humanoid")) or State.Hum
    if not char or not root or not targetCF then return end

    pcall(function()
        local motor = getRootMotor(char)
        if motor and not Config.InvisibleEnabled then
            if State.OrigRootJointC0 then motor.C0 = State.OrigRootJointC0 end
            if State.OrigRootJointC1 then motor.C1 = State.OrigRootJointC1 end
            motor.Transform = CFrame.identity
        end

        for _, desc in ipairs(char:GetDescendants()) do
            if desc:IsA("Weld") or desc:IsA("WeldConstraint") or desc:IsA("RigidConstraint") or desc:IsA("AlignPosition") or desc:IsA("AlignOrientation") then
                local p0 = (desc:IsA("AlignPosition") or desc:IsA("AlignOrientation")) and desc.Attachment0 or desc.Part0
                local p1 = (desc:IsA("AlignPosition") or desc:IsA("AlignOrientation")) and desc.Attachment1 or desc.Part1
                if (p0 and not p0:IsDescendantOf(char)) or (p1 and not p1:IsDescendantOf(char)) then
                    if desc:IsA("WeldConstraint") or desc:IsA("RigidConstraint") or desc:IsA("AlignPosition") or desc:IsA("AlignOrientation") then
                        desc.Enabled = false
                    end
                    desc:Destroy()
                end
            end
        end

        local pos = targetCF.Position
        local _, yaw, _ = targetCF:ToEulerAnglesYXZ()
        local uprightCF = CFrame.new(pos) * CFrame.Angles(0, yaw, 0)

        if root.Anchored then root.Anchored = false end
        char:PivotTo(uprightCF)
        root.CFrame = uprightCF
        root.AssemblyLinearVelocity = Vector3.zero
        root.AssemblyAngularVelocity = Vector3.zero

        syncFlyAltitudeToCFrame(uprightCF)

        for _, part in ipairs(char:GetDescendants()) do
            if part:IsA("BasePart") then
                part.AssemblyLinearVelocity = Vector3.zero
                part.AssemblyAngularVelocity = Vector3.zero
            end
        end

        if hum then
            if hum.PlatformStand then hum.PlatformStand = false end
            if hum.Sit then hum.Sit = false end
            hum:ChangeState(Enum.HumanoidStateType.GettingUp)
            hum:ChangeState(Enum.HumanoidStateType.Running)

            Camera = Workspace.CurrentCamera
            if Camera then
                Camera.CameraType = Enum.CameraType.Custom
                Camera.CameraSubject = hum
                if (Camera.CFrame.Position - uprightCF.Position).Magnitude > 150 then
                    Camera.CFrame = CFrame.lookAt(uprightCF.Position + Vector3.new(0, 6, 12), uprightCF.Position + Vector3.new(0, 1.5, 0))
                end
            end
        end
    end)
end

local function teleportToDeepVoid()
    local myRoot = State.Root
    if not myRoot then return end

    if not Config.DeepVoidActive and myRoot.Position.Y > -100 and myRoot.Position.Magnitude < 1400 then
        State.PreDeepVoidCFrame = myRoot.CFrame
    end

    Config.DeepVoidActive = true

    local voidKillY = getVoidKillPlaneY()
    local platformSurfaceY = math.max(-2000, voidKillY + 50)
    local platformCenter = Vector3.new(2000, platformSurfaceY, 2000)

    ensureWhiteVoidPlatform(platformCenter)
    local standCF = CFrame.new(platformCenter.X, platformSurfaceY + 3.5, platformCenter.Z)
    State.DeepVoidStandCF = standCF
    syncFlyAltitudeToCFrame(standCF)

    task.spawn(function()
        for _ = 1, 14 do
            if not Config.DeepVoidActive or not State.Root then break end
            ensureWhiteVoidPlatform(platformCenter)
            forceFullCharacterAndCameraResync(standCF)
            RunService.Heartbeat:Wait()
        end
    end)
end

local function teleportBackFromDeepVoid()
    Config.DeepVoidActive = false
    State.DeepVoidStandCF = nil
    destroyWhiteVoidPlatform()

    local returnCF = State.PreDeepVoidCFrame or State.LastSafeCFrame or CFrame.new(0, 65, 0)
    task.spawn(function()
        for _ = 1, 12 do
            forceFullCharacterAndCameraResync(returnCF + Vector3.new(0, 4, 0))
            RunService.RenderStepped:Wait()
        end
    end)
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

function isCharacterStillInSkill(char)
    if not char then return false end
    if char:GetAttribute("ComboStun") == true or char:GetAttribute("UsingMove") == true or char:GetAttribute("InSkill") == true then
        return true
    end
    for _, child in ipairs(char:GetChildren()) do
        local n = string.lower(child.Name)
        if n == "usingmove" or n == "skill" or n == "casting" or n == "action" or n == "move" or n == "inmove" then
            return true
        end
    end
    local track = State.CurrentSkillAnimTrack
    if track and track.IsPlaying then
        return true
    end
    return false
end

local function isAnyGrabCarryModeActive()
    return Config.AutoVoidKill or Config.AutoHighPlaceCarry or Config.AutoUltraFarCarry
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

-- // ==========================================================================
-- // UNIFIED MULTI-TARGET GRAB & CARRY ENGINE (SUPPORTS ALL 3 SKILLS + ALL TOGGLE + TELEPORT ITERATION)
-- // ==========================================================================
local function executeUnifiedMultiTargetGrabTrip()
    if not Config.ScriptRunning or State.VoidKillActive or not isAnyGrabCarryModeActive() then return end
    local myChar = LocalPlayer.Character or State.Char
    local myRoot = myChar and myChar:FindFirstChild("HumanoidRootPart") or State.Root
    local myHum = myChar and myChar:FindFirstChildOfClass("Humanoid") or State.Hum
    if not myChar or not myRoot or not myHum or myHum.Health <= 0 then return end

    State.VoidKillActive = true
    if State.LastSafeCFrame and State.LastSafeCFrame.Position.Y > -20 and State.LastSafeCFrame.Position.Magnitude < 2000 then
        State.VoidReturnCFrame = State.LastSafeCFrame
    elseif myRoot.Position.Y > -20 and myRoot.Position.Magnitude < 2000 then
        State.VoidReturnCFrame = myRoot.CFrame
    else
        State.VoidReturnCFrame = CFrame.new(0, 55, 0)
    end

    task.spawn(function()
        -- 1. Determine Target Destination based on active mode
        local targetCFs = {}

        if Config.AutoHighPlaceCarry then
            table.insert(targetCFs, CFrame.new(Config.HighPlaceTargetPos))
        elseif Config.AutoUltraFarCarry then
            local billDist = math.clamp(Config.UltraFarDistanceBillions or 1, 1, 10) * 1000000000
            local originPos = State.VoidReturnCFrame.Position
            local flatDir = Vector3.new(originPos.X, 0, originPos.Z)
            flatDir = (flatDir.Magnitude < 1) and Vector3.new(0.7071, 0, 0.7071) or flatDir.Unit
            local farPos = Vector3.new(flatDir.X * billDist, 1800, flatDir.Z * billDist)
            table.insert(targetCFs, CFrame.new(farPos))
        else
            -- Auto Void Kill (Y = -500)
            local voidDamageY = getVoidKillPlaneY()
            local safeHoverY = getPlayerSafeVoidKillHoverY()
            local originPos = State.VoidReturnCFrame.Position
            local flatDir = Vector3.new(originPos.X, 0, originPos.Z)
            flatDir = (flatDir.Magnitude < 1) and Vector3.new(1, 0, 0) or flatDir.Unit
            local voidXZ = Vector3.new(originPos.X, 0, originPos.Z) + (flatDir * (Config.VoidFarHorizontalDist or 2900))
            table.insert(targetCFs, CFrame.new(voidXZ.X, safeHoverY, voidXZ.Z) * CFrame.Angles(math.rad(-90), 0, 0))
        end

        -- 2. Gather Multi-Target Characters (checked in MultiTargetSelectedMap or ALL)
        local destinationCF = targetCFs[1]
        local dropStartTick = tick()
        local minHold = 0.35

        while Config.ScriptRunning and isAnyGrabCarryModeActive() and State.Root and State.Hum and State.Hum.Health > 0 do
            local elapsed = tick() - dropStartTick
            if elapsed >= Config.VoidMaxHoldTime then
                break
            end

            -- If "ALL" or specific players are ticked in MultiTargetSelectedMap, teleport to each selected player's root position first!
            local visitedAnyTarget = false
            for _, plr in ipairs(Players:GetPlayers()) do
                if plr ~= LocalPlayer and plr.Character then
                    local pName = plr.Name
                    local isSelected = Config.MultiTargetSelectAll or Config.MultiTargetSelectedMap[pName]
                    if isSelected then
                        local pRoot = plr.Character:FindFirstChild("HumanoidRootPart")
                        local pHum = plr.Character:FindFirstChildOfClass("Humanoid")
                        if pRoot and pHum and pHum.Health > 0 then
                            visitedAnyTarget = true
                            if State.Root then
                                State.Root.CFrame = pRoot.CFrame * CFrame.new(0, 0, -1.0)
                                State.Root.AssemblyLinearVelocity = Vector3.zero
                            end
                            RunService.Heartbeat:Wait()
                        end
                    end
                end
            end

            -- Then deliver to the final destination (Void / High Place / Ultra-Far)
            if State.Root then
                if Config.AutoVoidKill then
                    local voidDamageY = getVoidKillPlaneY()
                    local microDip = math.sin(elapsed * 40) * 0.55
                    local clampedY = math.max(voidDamageY + 1.4, destinationCF.Position.Y + microDip)
                    State.Root.CFrame = CFrame.new(destinationCF.Position.X, clampedY, destinationCF.Position.Z) * destinationCF.Rotation
                else
                    State.Root.CFrame = destinationCF
                end
                State.Root.AssemblyLinearVelocity = Vector3.zero
                State.Root.AssemblyAngularVelocity = Vector3.zero
            end

            local carriedList = getConfirmedCarriedEnemies()
            local allDone = (#carriedList == 0 and not isCharacterStillInSkill(State.Char))
            if elapsed >= minHold and (allDone or not visitedAnyTarget) then
                break
            end

            RunService.Heartbeat:Wait()
        end

        State.VoidDropTargetCF = nil

        local returnCF = (State.VoidReturnCFrame or CFrame.new(0, 55, 0)) + Vector3.new(0, 3.5, 0)
        for _ = 1, 16 do
            forceFullCharacterAndCameraResync(returnCF)
            RunService.RenderStepped:Wait()
        end

        State.ActiveSpecialSkill = nil
        State.VoidKillActive = false
    end)
end

-- // UNIFIED SKILL TRIGGERS FOR MINE / PIERCE / BLAST AWAY
local function runUnifiedMultiTargetSequence(skillLabel)
    if State.VoidKillActive then return end
    State.ActiveSpecialSkill = skillLabel or "MULTI_GRAB"
    State.VoidReturnCFrame = State.LastSafeCFrame or (State.Root and State.Root.CFrame)
    executeUnifiedMultiTargetGrabTrip()
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

    if not isAnyGrabCarryModeActive() or State.VoidKillActive then return end

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

    -- Any supported grab skill (Mine, Pierce The Heavens, Blast Away, Quintuple Smash, etc.) triggers the unified multi-target handler!
    runUnifiedMultiTargetSequence(skillName)
end

-- // ZERO-INSTANCE ANTI-SKILL EVASION
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
    State.DecoyCFrame = startCF
end

local function stopMovableGhostDecoy()
    local returnCF = State.DecoyCFrame
    if returnCF and not Config.DeepVoidActive then
        for _ = 1, 8 do
            forceFullCharacterAndCameraResync(returnCF)
            RunService.RenderStepped:Wait()
        end
    end
    State.DecoyCFrame = nil
end

-- // PUBLIC SERVER HOP FUNCTIONS (LOWEST PING & LOWEST PLAYERS)
local function rejoinCurrentServer()
    TeleportService:TeleportToPlaceInstance(game.PlaceId, game.JobId, LocalPlayer)
end

local function joinBestPublicServerByMode(mode, btn, defaultText)
    if btn then btn.Text = "Scanning Public Servers..." end
    task.spawn(function()
        local sortOrder = (mode == "LowestPlayers") and "Asc" or "Desc"
        local url = string.format("https://games.roblox.com/v1/games/%d/servers/Public?sortOrder=%s&limit=100", game.PlaceId, sortOrder)
        local ok, res = pcall(function()
            return HttpService:JSONDecode(game:HttpGet(url))
        end)

        if ok and res and type(res.data) == "table" then
            local candidates = {}
            for _, srv in ipairs(res.data) do
                if type(srv) == "table"
                    and type(srv.id) == "string"
                    and srv.id ~= game.JobId
                    and tonumber(srv.playing)
                    and tonumber(srv.maxPlayers)
                    and srv.playing >= 1
                    and srv.playing < (srv.maxPlayers - 1) then
                    table.insert(candidates, srv)
                end
            end

            if mode == "LowestPing" then
                table.sort(candidates, function(a, b)
                    local pA = tonumber(a.ping) or 9999
                    local pB = tonumber(b.ping) or 9999
                    if pA ~= pB then
                        return pA < pB
                    end
                    return (tonumber(a.playing) or 99) < (tonumber(b.playing) or 99)
                end)
            elseif mode == "LowestPlayers" then
                table.sort(candidates, function(a, b)
                    local plA = tonumber(a.playing) or 99
                    local plB = tonumber(b.playing) or 99
                    if plA ~= plB then
                        return plA < plB
                    end
                    return (tonumber(a.ping) or 9999) < (tonumber(b.ping) or 9999)
                end)
            end

            if #candidates > 0 then
                local chosen = candidates[1]
                if btn then
                    btn.Text = string.format("Joining (%d Plrs | %dms)...", chosen.playing or 0, chosen.ping or 0)
                end
                TeleportService:TeleportToPlaceInstance(game.PlaceId, chosen.id, LocalPlayer)
                return
            end
        end

        if btn then
            btn.Text = "No Matching Public Server Found"
            task.delay(2, function()
                if btn and btn.Parent then btn.Text = defaultText end
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

-- // REAL ANTI-STUN ENGINE
local HitstunAnimKeywords = {
    "stun", "hit", "hurt", "stagger", "ragdoll", "knock", "down", "slam", "grabbed", "freeze", "paralyz"
}

local function isCharCurrentlyStunned(char, hum)
    if not char or not hum then return false end
    if char:GetAttribute("ComboStun") == true and char:GetAttribute("IFrame") == true then
        return false
    end
    local stunAttr = char:GetAttribute("Stun")
    if typeof(stunAttr) == "number" and stunAttr > 0 then
        return true
    end
    if hum.WalkSpeed < 14 or hum.PlatformStand or hum.Sit then
        return true
    end
    local st = hum:GetState()
    if st == Enum.HumanoidStateType.Ragdoll
        or st == Enum.HumanoidStateType.FallingDown
        or st == Enum.HumanoidStateType.Physics
        or st == Enum.HumanoidStateType.PlatformStanding then
        return true
    end
    if char:GetAttribute("Stunned") == true
        or char:GetAttribute("Ragdoll") == true
        or char:GetAttribute("Hitstun") == true
        or char:GetAttribute("NoMove") == true then
        return true
    end
    for _, child in ipairs(char:GetChildren()) do
        local n = string.lower(child.Name)
        if string.find(n, "stun", 1, true)
            or string.find(n, "ragdoll", 1, true)
            or string.find(n, "nojump", 1, true)
            or string.find(n, "nospeed", 1, true)
            or string.find(n, "slow", 1, true)
            or string.find(n, "knockback", 1, true)
            or string.find(n, "cantmove", 1, true)
            or string.find(n, "freeze", 1, true) then
            return true
        end
    end
    return false
end

local function enforceRealAntiStun(char, root, hum, dt)
    if not char or not root or not hum then return end
    if char:GetAttribute("ComboStun") == true and char:GetAttribute("IFrame") == true then
        return
    end

    if not isCharacterStillInSkill(char) then
        if root.Anchored then root.Anchored = false end
        for _, p in ipairs(char:GetChildren()) do
            if p:IsA("BasePart") and p.Anchored then
                p.Anchored = false
            end
        end
    end

    if hum.PlatformStand then hum.PlatformStand = false end
    if hum.Sit then hum.Sit = false end
    hum.AutoRotate = true

    local curState = hum:GetState()
    if curState == Enum.HumanoidStateType.Ragdoll
        or curState == Enum.HumanoidStateType.FallingDown
        or curState == Enum.HumanoidStateType.Physics
        or curState == Enum.HumanoidStateType.PlatformStanding then
        pcall(function()
            hum:ChangeState(Enum.HumanoidStateType.Running)
        end)
    end

    local animator = State.Animator or hum:FindFirstChildOfClass("Animator")
    if animator then
        for _, track in ipairs(animator:GetPlayingAnimationTracks()) do
            if track ~= State.CurrentSkillAnimTrack then
                local tName = string.lower(track.Name or "")
                for i = 1, #HitstunAnimKeywords do
                    if string.find(tName, HitstunAnimKeywords[i], 1, true) then
                        pcall(function() track:Stop(0) end)
                        break
                    end
                end
            end
        end
    end

    local stunned = isCharCurrentlyStunned(char, hum)
    if stunned and not isCharacterStillInSkill(char) then
        local inputVec = getPlanarMoveVector(hum)
        local targetSpd = Config.SpeedEnabled and Config.WalkSpeed or 22
        local curVel = root.AssemblyLinearVelocity

        if inputVec.Magnitude > 0 then
            root.AssemblyLinearVelocity = Vector3.new(inputVec.X * targetSpd, math.clamp(curVel.Y, -35, 35), inputVec.Z * targetSpd)
            if dt and dt > 0 then
                root.CFrame = root.CFrame + (inputVec * targetSpd * dt * 0.45)
            end
            local camLook = Vector3.new(Camera.CFrame.LookVector.X, 0, Camera.CFrame.LookVector.Z)
            if camLook.Magnitude > 0.1 then
                root.CFrame = CFrame.lookAt(root.Position, root.Position + camLook.Unit)
            end
        else
            root.AssemblyLinearVelocity = Vector3.new(0, math.clamp(curVel.Y, -45, 25), 0)
            root.AssemblyAngularVelocity = Vector3.zero
        end
    end
end

local function scanProximityGrab()
    if not Config.ScriptRunning or not isAnyGrabCarryModeActive() or State.VoidKillActive then return end
    if State.ActiveSpecialSkill ~= nil then return end

    if string.find(string.lower(State.LastSkillName or ""), "phantom shot", 1, true) and State.PhantomShotStage == 1 then
        return
    end

    local carriedList = getConfirmedCarriedEnemies()
    if #carriedList > 0 then
        State.GrabWatchWindowUntil = 0
        executeUnifiedMultiTargetGrabTrip()
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

    task.defer(function()
        local motor = getRootMotor(char)
        if motor then
            State.OrigRootJointC0 = motor.C0
            State.OrigRootJointC1 = motor.C1
        end
        if State.Root then
            State.FlyAltitudeY = State.Root.Position.Y
        end
    end)

    task.delay(0.8, function()
        if Config.ScriptRunning and isAnyGrabCarryModeActive() then
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

        if isAnyGrabCarryModeActive() and not State.VoidKillActive and State.ActiveSpecialSkill == nil then
            task.defer(function()
                if string.find(string.lower(State.LastSkillName or ""), "phantom shot", 1, true) and State.PhantomShotStage == 1 then
                    return
                end
                local victim = checkStrictGrabJoint(inst)
                if victim then
                    executeUnifiedMultiTargetGrabTrip()
                end
            end)
        end
    end))
end

if LocalPlayer.Character then
    task.spawn(bindCharacter, LocalPlayer.Character)
end
table.insert(State.Connections, LocalPlayer.CharacterAdded:Connect(bindCharacter))

-- // STEALTH GUI PARENTING
local function getGuiParent()
    local okHui, hui = pcall(function()
        return gethui and gethui()
    end)
    if okHui and hui then return hui end

    local okCore, cGui = pcall(function()
        return CoreGui
    end)
    if okCore and cGui then return cGui end

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

local function cleanupInvisible()
    local char = State.Char
    if char then
        local motor = getRootMotor(char)
        if motor and State.InvisData.SavedC0 then
            motor.C0 = State.InvisData.SavedC0
            State.InvisData.SavedC0 = nil
        end
        for _, v in ipairs(State.InvisData.HiddenParts) do
            if v and v.Parent then
                v.LocalTransparencyModifier = 0
            end
        end
    end
    State.InvisData.HiddenParts = {}
end

-- // UI ROOT
ScreenGui = Instance.new("ScreenGui")
ScreenGui.Name = State.UIToken
ScreenGui.Archivable = false
ScreenGui.ResetOnSpawn = false
ScreenGui.IgnoreGuiInset = true
ScreenGui.ZIndexBehavior = Enum.ZIndexBehavior.Sibling
pcall(function()
    if syn and syn.protect_gui then
        syn.protect_gui(ScreenGui)
    end
end)
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
SubTitle.Text = "Heroes Battlegrounds v39 UnifiedMultiTarget"
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
    Config.AutoHighPlaceCarry = false
    Config.AutoUltraFarCarry = false
    Config.AntiVoidEnabled = false
    Config.DeepVoidActive = false
    Config.AntiStunEnabled = false
    Config.AntiSkillEnabled = false
    Config.AutoSkillEnabled = false
    Config.AutoUltimateEnabled = false
    Config.AimbotActive = false
    Config.ESPEnabled = false

    pcall(stopMovableGhostDecoy)
    pcall(destroyWhiteVoidPlatform)
    pcall(destroyInvisibleGroundPad)
    pcall(cleanupInvisible)

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

    local function setFeatureState(newState, skipCallback)
        if not Config.UIInitialized then return end
        state = (newState == true)
        syncVisuals()
        if not skipCallback then
            callback(state)
        end
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

local function addUnifiedMultiTargetDropdown(parent, label, options, callback)
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
        if Config.MultiTargetSelectAll then
            ValueLbl.Text = "[ALL PLAYERS]"
        else
            local names = {}
            for k, v in pairs(Config.MultiTargetSelectedMap) do
                if v then table.insert(names, k) end
            end
            if #names == 0 then
                ValueLbl.Text = "None Selected"
            else
                ValueLbl.Text = table.concat(names, ", ")
            end
        end
    end

    local function renderExternalMultiPopup()
        for _, child in ipairs(DropPopScroll:GetChildren()) do
            if child:IsA("TextButton") then child:Destroy() end
        end
        DropPopTitle.Text = label

        -- Render "ALL" Button First
        local allSelected = Config.MultiTargetSelectAll
        local AllBtn = Instance.new("TextButton")
        AllBtn.Size = UDim2.new(1, 0, 0, 28)
        AllBtn.BackgroundColor3 = allSelected and Color3.fromRGB(195, 85, 45) or Color3.fromRGB(32, 35, 42)
        AllBtn.BackgroundTransparency = allSelected and 0.05 or 0.25
        AllBtn.Text = (allSelected and "  ● [ALL]  " or "  ○ [ALL]  ") .. "Select All Players"
        AllBtn.TextColor3 = allSelected and Color3.fromRGB(255, 255, 255) or Color3.fromRGB(255, 215, 115)
        AllBtn.Font = allSelected and Enum.Font.GothamBold or Enum.Font.GothamMedium
        AllBtn.TextSize = 12
        AllBtn.TextXAlignment = Enum.TextXAlignment.Left
        AllBtn.AutoButtonColor = false
        AllBtn.ZIndex = 53
        AllBtn.Parent = DropPopScroll
        Instance.new("UICorner", AllBtn).CornerRadius = UDim.new(0, 5)

        AllBtn.MouseButton1Click:Connect(function()
            Config.MultiTargetSelectAll = not Config.MultiTargetSelectAll
            updateSummaryText()
            callback(Config.MultiTargetSelectedMap, Config.MultiTargetSelectAll)
            renderExternalMultiPopup()
        end)

        -- Render Individual Players
        for _, opt in ipairs(currentOptions) do
            if opt ~= "None" then
                local isSelected = (Config.MultiTargetSelectedMap[opt] == true) and not Config.MultiTargetSelectAll
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
                    Config.MultiTargetSelectAll = false
                    Config.MultiTargetSelectedMap[opt] = not Config.MultiTargetSelectedMap[opt]
                    updateSummaryText()
                    callback(Config.MultiTargetSelectedMap, Config.MultiTargetSelectAll)
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
            for k, _ in pairs(Config.MultiTargetSelectedMap) do
                if not validSet[k] then Config.MultiTargetSelectedMap[k] = nil end
            end
            updateSummaryText()
            callback(Config.MultiTargetSelectedMap, Config.MultiTargetSelectAll)
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

    local motor = getRootMotor(char)
    if motor then
        State.InvisData.SavedC0 = motor.C0
        if Config.InvisMode == "UndergroundC0" then
            motor.C0 = motor.C0 * CFrame.new(0, -14, 0)
        else
            motor.C0 = motor.C0 * CFrame.new(0, 600, 0)
        end
    end
    for _, v in ipairs(State.InvisData.HiddenParts) do
        v.LocalTransparencyModifier = 0.65
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

-- // ==========================================================================
-- // 1. POPULATE VOID KILL TAB
-- // ==========================================================================
addDualButtons(
    TabVoid,
    "TP Void (2k White Floor)", Color3.fromRGB(45, 115, 195), function() teleportToDeepVoid() end,
    "TP Back (Full Resync)", Color3.fromRGB(55, 135, 95), function() teleportBackFromDeepVoid() end
)

addFeatureToggle(TabVoid, "AutoVoidKill", "1. Auto Void Kill (Drop Enemy Below Y = -500)", "VOIDK", false, function(v)
    Config.AutoVoidKill = v
    if v then
        if Config.AutoHighPlaceCarry and State.ToggleRegistry["AutoHighPlaceCarry"] then
            Config.AutoHighPlaceCarry = false
            State.ToggleRegistry["AutoHighPlaceCarry"](false, true)
        end
        if Config.AutoUltraFarCarry and State.ToggleRegistry["AutoUltraFarCarry"] then
            Config.AutoUltraFarCarry = false
            State.ToggleRegistry["AutoUltraFarCarry"](false, true)
        end
        scanHotbarSkills1To4()
    elseif not isAnyGrabCarryModeActive() then
        State.VoidKillActive = false
        State.VoidDropTargetCF = nil
        State.ActiveSpecialSkill = nil
    end
end)

addFeatureToggle(TabVoid, "AutoHighPlaceCarry", "2. Auto Carry High Place (35.79, 1800.00, -207.31)", "HIGHC", false, function(v)
    Config.AutoHighPlaceCarry = v
    if v then
        if Config.AutoVoidKill and State.ToggleRegistry["AutoVoidKill"] then
            Config.AutoVoidKill = false
            State.ToggleRegistry["AutoVoidKill"](false, true)
        end
        if Config.AutoUltraFarCarry and State.ToggleRegistry["AutoUltraFarCarry"] then
            Config.AutoUltraFarCarry = false
            State.ToggleRegistry["AutoUltraFarCarry"](false, true)
        end
        scanHotbarSkills1To4()
    elseif not isAnyGrabCarryModeActive() then
        State.VoidKillActive = false
        State.VoidDropTargetCF = nil
        State.ActiveSpecialSkill = nil
    end
end)

addFeatureToggle(TabVoid, "AutoUltraFarCarry", "3. Auto Carry Ultra-Far (1B - 10B Studs)", "FARC", false, function(v)
    Config.AutoUltraFarCarry = v
    if v then
        if Config.AutoVoidKill and State.ToggleRegistry["AutoVoidKill"] then
            Config.AutoVoidKill = false
            State.ToggleRegistry["AutoVoidKill"](false, true)
        end
        if Config.AutoHighPlaceCarry and State.ToggleRegistry["AutoHighPlaceCarry"] then
            Config.AutoHighPlaceCarry = false
            State.ToggleRegistry["AutoHighPlaceCarry"](false, true)
        end
        scanHotbarSkills1To4()
    elseif not isAnyGrabCarryModeActive() then
        State.VoidKillActive = false
        State.VoidDropTargetCF = nil
        State.ActiveSpecialSkill = nil
    end
end)

addSlider(TabVoid, "Ultra-Far Distance (Billion Studs)", 1, 10, 1, function(v)
    Config.UltraFarDistanceBillions = v
end)

local UnifiedMultiTargetDropdown = addUnifiedMultiTargetDropdown(TabVoid, "Multi-Target Grab (Select Players or ALL)", currentTargetList, function(selectedMap, selectAll)
    Config.MultiTargetSelectedMap = selectedMap
    Config.MultiTargetSelectAll = selectAll
end)

addSlider(TabVoid, "Carry / Void Hold Duration", 0.35, 3.00, 1.45, function(v)
    Config.VoidMaxHoldTime = v
end)

-- // 2. POPULATE COMBAT TAB
addFeatureToggle(TabCombat, "AutoSkill", "Auto Skill (1 - 4)", "ASKL", false, function(v)
    Config.AutoSkillEnabled = v
    if v then scanHotbarSkills1To4() end
end)

addFeatureToggle(TabCombat, "AutoUltimate", "Auto Ultimate (Awakening)", "AULT", false, function(v)
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

addFeatureToggle(TabCombat, "AntiStun", "Real Anti Stun (Stop Hurt1-4 + Anti-Knockback)", "ASTUN", false, function(v)
    Config.AntiStunEnabled = v
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
        syncFlyAltitudeToCFrame(State.Root.CFrame)
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

local function executeInstantTeleportToSelectedPlayer()
    local targetPlr = Players:FindFirstChild(Config.SelectedPlayer or "")
    local myRoot = State.Root
    local tRoot = targetPlr and targetPlr.Character and targetPlr.Character:FindFirstChild("HumanoidRootPart")
    if myRoot and tRoot then
        local destCF = tRoot.CFrame * CFrame.new(0, 0, 3)
        syncFlyAltitudeToCFrame(destCF)
        task.spawn(function()
            for _ = 1, 4 do
                if State.Root and tRoot and tRoot.Parent then
                    local liveDest = tRoot.CFrame * CFrame.new(0, 0, 3)
                    syncFlyAltitudeToCFrame(liveDest)
                    State.Root.CFrame = liveDest
                    State.Root.AssemblyLinearVelocity = Vector3.zero
                end
                RunService.Heartbeat:Wait()
            end
        end)
    end
end

addButton(TabTarget, "Instant Teleport To Selected Player", Color3.fromRGB(45, 130, 205), function()
    executeInstantTeleportToSelectedPlayer()
end)

addFeatureToggle(TabTarget, "TeleportPlayer", "Pin-able Instant Teleport To Player", "TP", false, function(v)
    if v then
        executeInstantTeleportToSelectedPlayer()
        task.delay(0.15, function()
            if State.ToggleRegistry["TeleportPlayer"] then
                State.ToggleRegistry["TeleportPlayer"](false, true)
            end
        end)
    end
end)

-- // 4. POPULATE LOCALPLAYER TAB
addFeatureToggle(TabMove, "Fly", "Fly (Zero-Drop Invisible Ground Pad)", "FLY", false, function(v)
    Config.FlyEnabled = v
    if v and State.Root then
        State.FlyAltitudeY = State.Root.Position.Y
        updateGroundPadUnderCharacter(State.Char, State.Root, State.Hum, State.FlyAltitudeY)
        State.Root.AssemblyLinearVelocity = Vector3.zero
    else
        State.FlyAltitudeY = nil
        destroyInvisibleGroundPad()
        if State.Root then
            State.Root.AssemblyLinearVelocity = Vector3.zero
        end
    end
end)

addDropdown(TabMove, "Fly Mode", {"InvisibleGroundPad", "LoopFly"}, 1, function(opt)
    Config.FlyMode = opt
    if State.Root then
        State.FlyAltitudeY = State.Root.Position.Y
        updateGroundPadUnderCharacter(State.Char, State.Root, State.Hum, State.FlyAltitudeY)
    end
end)

addSlider(TabMove, "Fly Speed", 10, 500, 75, function(v)
    Config.FlySpeed = v
end)

addFeatureToggle(TabMove, "InfJump", "Infinite Jump", "INFJ", false, function(v)
    Config.InfJumpEnabled = v
    if not v then
        State.InfJumpArcActive = false
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
end)

addSlider(TabMove, "WalkSpeed", 16, 500, 55, function(v)
    Config.WalkSpeed = v
end)

addFeatureToggle(TabMove, "JumpBoost", "JumpPower Boost", "JMP", false, function(v)
    Config.JumpBoostEnabled = v
end)

addSlider(TabMove, "JumpPower", 50, 350, 100, function(v)
    Config.JumpPower = v
end)

-- // 5. POPULATE SERVER TAB
addButton(TabServer, "Rejoin Current Server", Color3.fromRGB(45, 110, 185), function()
    rejoinCurrentServer()
end)

addButton(TabServer, "Join Lowest Ping Server (Public)", Color3.fromRGB(40, 145, 95), function(btn)
    joinBestPublicServerByMode("LowestPing", btn, "Join Lowest Ping Server (Public)")
end)

addButton(TabServer, "Join Lowest Player Server (Public)", Color3.fromRGB(55, 125, 175), function(btn)
    joinBestPublicServerByMode("LowestPlayers", btn, "Join Lowest Player Server (Public)")
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
    UnifiedMultiTargetDropdown.Refresh(updated)
end)

addButton(TabVisual, "Unload Script", Color3.fromRGB(145, 45, 50), function()
    unloadEntireScript()
end)

Config.AntiVoidEnabled = true
Config.AutoVoidKill = false
Config.AutoHighPlaceCarry = false
Config.AutoUltraFarCarry = false
Config.UIInitialized = true

table.insert(State.Connections, Players.PlayerAdded:Connect(function()
    task.wait(0.2)
    if Config.ScriptRunning then
        local updated = getPlayerNames()
        PlayerDropdown.Refresh(updated)
        UnifiedMultiTargetDropdown.Refresh(updated)
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
    UnifiedMultiTargetDropdown.Refresh(updated)
end))

-- // STEALTH ESP
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
table.insert(State.Connections, RunService.Stepped:Connect(function(_, dt)
    if not Config.ScriptRunning then return end
    local voidDamageY = getVoidKillPlaneY()

    if State.VoidKillActive and State.VoidDropTargetCF and State.Root then
        if (Config.AutoHighPlaceCarry or Config.AutoUltraFarCarry) and not Config.AutoVoidKill then
            State.Root.CFrame = State.VoidDropTargetCF
        else
            local pos = State.VoidDropTargetCF.Position
            local safeY = math.max(pos.Y, voidDamageY + 1.4)
            State.Root.CFrame = CFrame.new(pos.X, safeY, pos.Z) * State.VoidDropTargetCF.Rotation
        end
        State.Root.AssemblyLinearVelocity = Vector3.zero
        State.Root.AssemblyAngularVelocity = Vector3.zero
    elseif State.AntiSkillEvading and State.DecoyCFrame and State.Root then
        local safeY = voidDamageY + 35
        local voidPos = Vector3.new(State.DecoyCFrame.Position.X, safeY, State.DecoyCFrame.Position.Z)
        State.Root.CFrame = CFrame.new(voidPos) * State.DecoyCFrame.Rotation
        State.Root.AssemblyLinearVelocity = Vector3.zero
    elseif Config.DeepVoidActive and State.Root and State.DeepVoidStandCF then
        local surfaceY = State.DeepVoidStandCF.Position.Y - 3.5
        ensureWhiteVoidPlatform(Vector3.new(State.Root.Position.X, surfaceY, State.Root.Position.Z))
        if State.Root.Position.Y < (surfaceY + 2.5) then
            State.Root.CFrame = CFrame.new(State.Root.Position.X, surfaceY + 3.2, State.Root.Position.Z) * State.Root.CFrame.Rotation
            State.Root.AssemblyLinearVelocity = Vector3.new(State.Root.AssemblyLinearVelocity.X, 0, State.Root.AssemblyLinearVelocity.Z)
        end
    elseif Config.FlyEnabled and not Config.AutoTargetEnabled and State.Root and State.Hum then
        if not State.FlyAltitudeY then
            State.FlyAltitudeY = State.Root.Position.Y
        end
        updateGroundPadUnderCharacter(State.Char, State.Root, State.Hum, State.FlyAltitudeY)
        local curVel = State.Root.AssemblyLinearVelocity
        if curVel.Y < 0 then
            State.Root.AssemblyLinearVelocity = Vector3.new(curVel.X, 0, curVel.Z)
        end
    end

    if Config.AntiStunEnabled and State.Char and State.Root and State.Hum then
        enforceRealAntiStun(State.Char, State.Root, State.Hum, dt)
    end
end))

-- // RENDERSTEPPED LOOP
table.insert(State.Connections, RunService.RenderStepped:Connect(function(dt)
    if not Config.ScriptRunning then return end
    local char = State.Char
    local root = State.Root
    local hum = State.Hum
    local voidDamageY = getVoidKillPlaneY()

    if State.VoidKillActive and State.VoidDropTargetCF and root then
        if (Config.AutoHighPlaceCarry or Config.AutoUltraFarCarry) and not Config.AutoVoidKill then
            root.CFrame = State.VoidDropTargetCF
        else
            local pos = State.VoidDropTargetCF.Position
            local safeY = math.max(pos.Y, voidDamageY + 1.4)
            root.CFrame = CFrame.new(pos.X, safeY, pos.Z) * State.VoidDropTargetCF.Rotation
        end
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

        local voidPos = Vector3.new(State.DecoyCFrame.Position.X, voidDamageY + 35, State.DecoyCFrame.Position.Z)
        root.CFrame = CFrame.new(voidPos) * State.DecoyCFrame.Rotation
        root.AssemblyLinearVelocity = Vector3.zero
    end

    if Config.AntiStunEnabled and char and root and hum then
        enforceRealAntiStun(char, root, hum, dt)
    end

    if Config.AutoTargetEnabled and root and hum and not State.VoidKillActive and not State.AntiSkillEvading and not Config.DeepVoidActive and State.ActiveSpecialSkill == nil then
        local targetPlr = Players:FindFirstChild(Config.SelectedPlayer or "")
        local tRoot = targetPlr and targetPlr.Character and targetPlr.Character:FindFirstChild("HumanoidRootPart")

        if tRoot then
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
            local lookCF = CFrame.lookAt(finalPos, targetPos)
            root.CFrame = lookCF
            root.AssemblyLinearVelocity = Vector3.zero
            root.AssemblyAngularVelocity = Vector3.zero
            syncFlyAltitudeToCFrame(lookCF)
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
    local voidDamageY = getVoidKillPlaneY()

    if root and hum and hum.Health > 0 then
        if Config.AutoSkillEnabled and not State.VoidKillActive and not State.AntiSkillEvading and not isCharacterStillInSkill(char) and not UserInputService:GetFocusedTextBox() then
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

        if Config.AutoUltimateEnabled and not State.VoidKillActive and not isCharacterStillInSkill(char) and not UserInputService:GetFocusedTextBox() then
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
                local voidPos = Vector3.new(State.DecoyCFrame.Position.X, voidDamageY + 35, State.DecoyCFrame.Position.Z)
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

        -- Anti-Void Protection
        if State.VoidKillActive and Config.AutoVoidKill then
            if root.Position.Y <= (voidDamageY + 1.2) then
                root.CFrame = CFrame.new(root.Position.X, voidDamageY + 2.2, root.Position.Z) * root.CFrame.Rotation
                root.AssemblyLinearVelocity = Vector3.zero
            end
        elseif not State.VoidKillActive and not State.AntiSkillEvading and not Config.DeepVoidActive then
            if hum.FloorMaterial ~= Enum.Material.Air and root.Position.Y > -30 and root.Position.Magnitude < 1200 and not Config.FlyEnabled then
                State.LastSafeCFrame = root.CFrame
            end

            if Config.AntiVoidEnabled and root.Position.Y < (voidDamageY + 55) then
                local safeCF = (State.LastSafeCFrame and State.LastSafeCFrame.Position.Y > -20) and (State.LastSafeCFrame + Vector3.new(0, 5, 0)) or CFrame.new(0, 60, 0)
                forceFullCharacterAndCameraResync(safeCF)
            end
        end

        if isAnyGrabCarryModeActive() and not State.VoidKillActive and not State.AntiSkillEvading then
            scanProximityGrab()
        end

        -- Speed Boost
        if Config.SpeedEnabled and hum.MoveDirection.Magnitude > 0 and not Config.FlyEnabled and not Config.AutoTargetEnabled and not isCharacterStillInSkill(char) then
            local extraSpeed = math.max(0, Config.WalkSpeed - 16)
            if extraSpeed > 0 then
                root.CFrame = root.CFrame + (hum.MoveDirection * math.min(extraSpeed, 95) * dt)
            end
        end

        -- Infinite Jump
        if Config.InfJumpEnabled and not Config.FlyEnabled and not Config.AutoTargetEnabled and not State.VoidKillActive and not State.AntiSkillEvading then
            local elapsed = tick() - State.InfJumpArcTimer
            if State.InfJumpArcActive and elapsed < 0.22 then
                local liftSpeed = Config.JumpBoostEnabled and (Config.JumpPower * 0.55) or 32
                if Config.InfJumpMode == "FlyPadStep" or Config.InfJumpMode == "ParabolicCFrame" then
                    local decay = math.clamp(1 - (elapsed / 0.22), 0.15, 1)
                    root.CFrame = root.CFrame + Vector3.new(0, liftSpeed * decay * dt, 0)
                    root.AssemblyLinearVelocity = Vector3.new(root.AssemblyLinearVelocity.X, 0.5, root.AssemblyLinearVelocity.Z)
                elseif Config.InfJumpMode == "MicroBounce" then
                    if elapsed < 0.05 then
                        root.AssemblyLinearVelocity = Vector3.new(root.AssemblyLinearVelocity.X, liftSpeed * 1.35, root.AssemblyLinearVelocity.Z)
                    end
                end
            else
                State.InfJumpArcActive = false
            end
        end

        -- FLY
        if Config.FlyEnabled and not Config.AutoTargetEnabled and not State.VoidKillActive and not State.AntiSkillEvading then
            local moveDir = getFlightDirection(hum)
            local spd = Config.FlySpeed or 75

            if not State.FlyAltitudeY then
                State.FlyAltitudeY = root.Position.Y
            end

            if math.abs(moveDir.Y) > 0.01 then
                State.FlyAltitudeY = State.FlyAltitudeY + (moveDir.Y * spd * dt)
            end

            updateGroundPadUnderCharacter(char, root, hum, State.FlyAltitudeY)

            if Config.FlyMode == "InvisibleGroundPad" then
                if moveDir.Magnitude > 0 then
                    root.AssemblyLinearVelocity = Vector3.new(moveDir.X * spd, moveDir.Y * spd, moveDir.Z * spd)
                else
                    root.AssemblyLinearVelocity = Vector3.new(0, 0, 0)
                end

                if math.abs(root.Position.Y - State.FlyAltitudeY) > 0.04 then
                    root.CFrame = CFrame.new(root.Position.X, State.FlyAltitudeY, root.Position.Z) * root.CFrame.Rotation
                end
            elseif Config.FlyMode == "LoopFly" then
                if moveDir.Magnitude > 0 then
                    local stepXZ = Vector3.new(moveDir.X, 0, moveDir.Z) * math.min(spd, 85) * dt
                    root.CFrame = CFrame.new(root.Position.X + stepXZ.X, State.FlyAltitudeY, root.Position.Z + stepXZ.Z) * root.CFrame.Rotation
                    root.AssemblyLinearVelocity = Vector3.new(moveDir.X * 16, 0, moveDir.Z * 16)
                else
                    root.CFrame = CFrame.new(root.Position.X, State.FlyAltitudeY, root.Position.Z) * root.CFrame.Rotation
                    root.AssemblyLinearVelocity = Vector3.zero
                end
            end
        elseif not Config.FlyEnabled and State.InvisibleGroundPad then
            destroyInvisibleGroundPad()
        end
    end

    updateESP()
end))

-- // INPUT TRIGGERS
table.insert(State.Connections, UserInputService.JumpRequest:Connect(function()
    if Config.JumpBoostEnabled and State.Root and State.Hum and State.Hum.FloorMaterial ~= Enum.Material.Air then
        local vel = State.Root.AssemblyLinearVelocity
        State.Root.AssemblyLinearVelocity = Vector3.new(vel.X, Config.JumpPower, vel.Z)
    end
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

    if not gpe and input.KeyCode == Enum.KeyCode.Space and Config.InfJumpEnabled then
        triggerUndetectedInfJump()
    end
end))
