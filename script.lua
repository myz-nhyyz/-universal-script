-- Context: Luau (Roblox Client Executor Environment - Synapse/Wave/Solara/Fluxus compatible)
-- Architecture: Single-file immediate/retained hybrid ScreenGui + RunService.Heartbeat / RenderStepped loops.

local Players = game:GetService("Players")
local RunService = game:GetService("RunService")
local UserInputService = game:GetService("UserInputService")
local Workspace = game:GetService("Workspace")
local CoreGui = game:GetService("CoreGui")

local LocalPlayer = Players.LocalPlayer
local Camera = Workspace.CurrentCamera
local Mouse = LocalPlayer:GetMouse()

-- // CONFIGURATION & STATE
local Config = {
    -- Movement
    FlyEnabled = false,
    FlyMode = "FloorPad", -- "FloorPad" | "LoopPulse"
    FlySpeed = 60,
    SpeedEnabled = false,
    WalkSpeed = 50,
    JumpBoostEnabled = false,
    JumpPower = 100,
    InfJumpEnabled = false,
    InvisibleEnabled = false,

    -- Combat / Target
    AimlockEnabled = false,
    AimPart = "Head",
    SelectedPlayer = nil,
    AutoTargetEnabled = false,
    TargetMode = "Behind", -- "Orbit" | "Behind" | "Below" | "Upper" | "Front"
    OrbitSpeed = 15,
    TargetRange = 8,

    -- Visuals
    ESPEnabled = false,
}

local State = {
    FlyPad = nil,
    OrbitAngle = 0,
    InvisClone = nil,
    OriginalCFrame = nil,
    ESPObjects = {},
    Connections = {},
}

-- // SAFE GUI PARENTING
local function getGuiParent()
    local success, res = pcall(function()
        return (gethui and gethui()) or CoreGui
    end)
    if success and res then return res end
    return LocalPlayer:WaitForChild("PlayerGui")
end

-- // CLEANUP PREVIOUS INSTANCE
local oldGui = getGuiParent():FindFirstChild("OllieBenchUI")
if oldGui then oldGui:Destroy() end

-- // UI BUILDER (Draggable, Tabbed, Sliders, Dropdowns)
local ScreenGui = Instance.new("ScreenGui")
ScreenGui.Name = "OllieBenchUI"
ScreenGui.ResetOnSpawn = false
ScreenGui.ZIndexBehavior = Enum.ZIndexBehavior.Sibling
ScreenGui.Parent = getGuiParent()

local MainFrame = Instance.new("Frame")
MainFrame.Size = UDim2.new(0, 480, 0, 380)
MainFrame.Position = UDim2.new(0.5, -240, 0.5, -190)
MainFrame.BackgroundColor3 = Color3.fromRGB(18, 18, 22)
MainFrame.BorderSizePixel = 0
MainFrame.Active = true
MainFrame.Draggable = true
MainFrame.Parent = ScreenGui

local UICorner = Instance.new("UICorner", MainFrame)
UICorner.CornerRadius = UDim.new(0, 6)

local UIStroke = Instance.new("UIStroke", MainFrame)
UIStroke.Color = Color3.fromRGB(60, 60, 75)
UIStroke.Thickness = 1

local TopBar = Instance.new("Frame")
TopBar.Size = UDim2.new(1, 0, 0, 32)
TopBar.BackgroundColor3 = Color3.fromRGB(26, 26, 32)
TopBar.BorderSizePixel = 0
TopBar.Parent = MainFrame
Instance.new("UICorner", TopBar).CornerRadius = UDim.new(0, 6)

local TitleLabel = Instance.new("TextLabel")
TitleLabel.Size = UDim2.new(1, -20, 1, 0)
TitleLabel.Position = UDim2.new(0, 10, 0, 0)
TitleLabel.BackgroundTransparency = 1
TitleLabel.Text = "OLLIE BENCH // MULTI-SUITE [INSERT TO HIDE]"
TitleLabel.TextColor3 = Color3.fromRGB(220, 220, 230)
TitleLabel.Font = Enum.Font.Code
TitleLabel.TextSize = 13
TitleLabel.TextXAlignment = Enum.TextXAlignment.Left
TitleLabel.Parent = TopBar

local TabHolder = Instance.new("Frame")
TabHolder.Size = UDim2.new(0, 110, 1, -42)
TabHolder.Position = UDim2.new(0, 6, 0, 36)
TabHolder.BackgroundColor3 = Color3.fromRGB(22, 22, 28)
TabHolder.BorderSizePixel = 0
TabHolder.Parent = MainFrame
Instance.new("UICorner", TabHolder).CornerRadius = UDim.new(0, 4)

local TabListLayout = Instance.new("UIListLayout", TabHolder)
TabListLayout.Padding = UDim.new(0, 4)
TabListLayout.SortOrder = Enum.SortOrder.LayoutOrder

local ContentHolder = Instance.new("Frame")
ContentHolder.Size = UDim2.new(1, -128, 1, -42)
ContentHolder.Position = UDim2.new(0, 122, 0, 36)
ContentHolder.BackgroundColor3 = Color3.fromRGB(22, 22, 28)
ContentHolder.BorderSizePixel = 0
ContentHolder.Parent = MainFrame
Instance.new("UICorner", ContentHolder).CornerRadius = UDim.new(0, 4)

local Pages = {}
local function createTab(name)
    local TabBtn = Instance.new("TextButton")
    TabBtn.Size = UDim2.new(1, 0, 0, 32)
    TabBtn.BackgroundColor3 = Color3.fromRGB(30, 30, 38)
    TabBtn.BorderSizePixel = 0
    TabBtn.Text = name
    TabBtn.TextColor3 = Color3.fromRGB(180, 180, 195)
    TabBtn.Font = Enum.Font.Code
    TabBtn.TextSize = 13
    TabBtn.Parent = TabHolder
    Instance.new("UICorner", TabBtn).CornerRadius = UDim.new(0, 4)

    local Page = Instance.new("ScrollingFrame")
    Page.Size = UDim2.new(1, -12, 1, -12)
    Page.Position = UDim2.new(0, 6, 0, 6)
    Page.BackgroundTransparency = 1
    Page.ScrollBarThickness = 2
    Page.Visible = false
    Page.CanvasSize = UDim2.new(0, 0, 0, 0)
    Page.AutomaticCanvasSize = Enum.AutomaticSize.Y
    Page.Parent = ContentHolder

    local Layout = Instance.new("UIListLayout", Page)
    Layout.Padding = UDim.new(0, 6)
    Layout.SortOrder = Enum.SortOrder.LayoutOrder

    TabBtn.MouseButton1Click:Connect(function()
        for _, p in pairs(Pages) do p.Visible = false end
        Page.Visible = true
    end)

    table.insert(Pages, Page)
    if #Pages == 1 then Page.Visible = true end
    return Page
end

local function addToggle(parent, text, default, callback)
    local Btn = Instance.new("TextButton")
    Btn.Size = UDim2.new(1, 0, 0, 28)
    Btn.BackgroundColor3 = default and Color3.fromRGB(45, 95, 65) or Color3.fromRGB(32, 32, 40)
    Btn.Text = "  " .. text .. ": " .. (default and "ON" or "OFF")
    Btn.TextColor3 = Color3.fromRGB(230, 230, 240)
    Btn.Font = Enum.Font.Code
    Btn.TextSize = 12
    Btn.TextXAlignment = Enum.TextXAlignment.Left
    Btn.Parent = parent
    Instance.new("UICorner", Btn).CornerRadius = UDim.new(0, 4)

    local state = default
    Btn.MouseButton1Click:Connect(function()
        state = not state
        Btn.BackgroundColor3 = state and Color3.fromRGB(45, 95, 65) or Color3.fromRGB(32, 32, 40)
        Btn.Text = "  " .. text .. ": " .. (state and "ON" or "OFF")
        callback(state)
    end)
end

local function addButton(parent, text, callback)
    local Btn = Instance.new("TextButton")
    Btn.Size = UDim2.new(1, 0, 0, 28)
    Btn.BackgroundColor3 = Color3.fromRGB(45, 50, 75)
    Btn.Text = text
    Btn.TextColor3 = Color3.fromRGB(240, 240, 255)
    Btn.Font = Enum.Font.Code
    Btn.TextSize = 12
    Btn.Parent = parent
    Instance.new("UICorner", Btn).CornerRadius = UDim.new(0, 4)
    Btn.MouseButton1Click:Connect(callback)
    return Btn
end

local function addCycle(parent, label, options, defaultIndex, callback)
    local idx = defaultIndex or 1
    local Btn = Instance.new("TextButton")
    Btn.Size = UDim2.new(1, 0, 0, 28)
    Btn.BackgroundColor3 = Color3.fromRGB(38, 38, 48)
    Btn.Text = "  " .. label .. ": < " .. tostring(options[idx]) .. " >"
    Btn.TextColor3 = Color3.fromRGB(220, 200, 120)
    Btn.Font = Enum.Font.Code
    Btn.TextSize = 12
    Btn.TextXAlignment = Enum.TextXAlignment.Left
    Btn.Parent = parent
    Instance.new("UICorner", Btn).CornerRadius = UDim.new(0, 4)

    Btn.MouseButton1Click:Connect(function()
        idx = idx + 1
        if idx > #options then idx = 1 end
        Btn.Text = "  " .. label .. ": < " .. tostring(options[idx]) .. " >"
        callback(options[idx])
    end)
    return Btn
end

local function addSlider(parent, label, minVal, maxVal, defaultVal, callback)
    local Holder = Instance.new("Frame")
    Holder.Size = UDim2.new(1, 0, 0, 42)
    Holder.BackgroundColor3 = Color3.fromRGB(30, 30, 38)
    Holder.Parent = parent
    Instance.new("UICorner", Holder).CornerRadius = UDim.new(0, 4)

    local TextLbl = Instance.new("TextLabel")
    TextLbl.Size = UDim2.new(1, -12, 0, 20)
    TextLbl.Position = UDim2.new(0, 6, 0, 2)
    TextLbl.BackgroundTransparency = 1
    TextLbl.Text = label .. ": " .. tostring(defaultVal)
    TextLbl.TextColor3 = Color3.fromRGB(220, 220, 230)
    TextLbl.Font = Enum.Font.Code
    TextLbl.TextSize = 12
    TextLbl.TextXAlignment = Enum.TextXAlignment.Left
    TextLbl.Parent = Holder

    local BarBg = Instance.new("Frame")
    BarBg.Size = UDim2.new(1, -16, 0, 8)
    BarBg.Position = UDim2.new(0, 8, 0, 26)
    BarBg.BackgroundColor3 = Color3.fromRGB(16, 16, 20)
    BarBg.Parent = Holder
    Instance.new("UICorner", BarBg).CornerRadius = UDim.new(0, 4)

    local BarFill = Instance.new("Frame")
    local initPct = math.clamp((defaultVal - minVal) / (maxVal - minVal), 0, 1)
    BarFill.Size = UDim2.new(initPct, 0, 1, 0)
    BarFill.BackgroundColor3 = Color3.fromRGB(80, 140, 210)
    BarFill.Parent = BarBg
    Instance.new("UICorner", BarFill).CornerRadius = UDim.new(0, 4)

    local dragging = false
    local function updateSlide(input)
        local rel = math.clamp((input.Position.X - BarBg.AbsolutePosition.X) / BarBg.AbsoluteSize.X, 0, 1)
        BarFill.Size = UDim2.new(rel, 0, 1, 0)
        local val = math.floor((minVal + (maxVal - minVal) * rel) * 10) / 10
        TextLbl.Text = label .. ": " .. tostring(val)
        callback(val)
    end

    BarBg.InputBegan:Connect(function(input)
        if input.UserInputType == Enum.UserInputType.MouseButton1 then
            dragging = true
            updateSlide(input)
        end
    end)
    UserInputService.InputEnded:Connect(function(input)
        if input.UserInputType == Enum.UserInputType.MouseButton1 then
            dragging = false
        end
    end)
    UserInputService.InputChanged:Connect(function(input)
        if dragging and input.UserInputType == Enum.UserInputType.MouseMovement then
            updateSlide(input)
        end
    end)
end

-- // CREATE TABS
local TabMove = createTab("Movement")
local TabTarget = createTab("Auto Target")
local TabCombat = createTab("Aim & ESP")

-- // HELPERS FOR CHARACTER
local function getChar(plr)
    plr = plr or LocalPlayer
    return plr and plr.Character
end

local function getRoot(plr)
    local char = getChar(plr)
    return char and char:FindFirstChild("HumanoidRootPart")
end

local function getHum(plr)
    local char = getChar(plr)
    return char and char:FindFirstChildOfClass("Humanoid")
end

-- // 1. ANTI-RAGDOLL LOOPFLY IMPLEMENTATION
-- Creates a physical invisible part welded/snapped directly under the player's feet every frame
-- Forces Humanoid State away from Freefall/Ragdoll so server/client scripts think player is standing on ground.
local function ensureFlyPad()
    if State.FlyPad and State.FlyPad.Parent then return State.FlyPad end
    local pad = Instance.new("Part")
    pad.Name = "TerrainChunk_01"
    pad.Size = Vector3.new(6, 1, 6)
    pad.Transparency = 1
    pad.Anchored = true
    pad.CanCollide = true
    pad.Parent = Workspace
    State.FlyPad = pad
    return pad
end

local function clearFlyPad()
    if State.FlyPad then
        State.FlyPad:Destroy()
        State.FlyPad = nil
    end
end

-- // 2. INVISIBLE IMPLEMENTATION (Seat / Root Desync Method)
local function toggleInvisible(enable)
    local char = getChar()
    local root = getRoot()
    if not char or not root then return end

    if enable then
        State.OriginalCFrame = root.CFrame
        char.Archivable = true
        local clone = char:Clone()
        clone.Name = LocalPlayer.Name .. "_Ghost"
        for _, v in ipairs(clone:GetDescendants()) do
            if v:IsA("BasePart") then
                v.Transparency = (v.Name == "HumanoidRootPart") and 1 or 0.5
            end
        end
        clone.Parent = Workspace
        clone.HumanoidRootPart.CFrame = State.OriginalCFrame

        -- Send real character far below void height limit or safe zone while controlling proxy
        root.CFrame = State.OriginalCFrame * CFrame.new(0, 100000, 0)
        task.wait(0.1)
        local seat = Instance.new("Seat")
        seat.Size = Vector3.new(1, 1, 1)
        seat.Transparency = 1
        seat.CanCollide = false
        seat.Name = "InvisProxy"
        seat.Parent = Workspace
        seat.CFrame = State.OriginalCFrame

        local weld = Instance.new("Weld")
        weld.Part0 = seat
        weld.Part1 = root
        weld.Parent = seat

        clone:Destroy()
        root.CFrame = State.OriginalCFrame
        for _, v in ipairs(char:GetDescendants()) do
            if v:IsA("BasePart") and v.Name ~= "HumanoidRootPart" then
                v.LocalTransparencyModifier = 0.6
            end
        end
        State.InvisClone = seat
    else
        if State.InvisClone then
            State.InvisClone:Destroy()
            State.InvisClone = nil
        end
        for _, v in ipairs(char:GetDescendants()) do
            if v:IsA("BasePart") then
                v.LocalTransparencyModifier = 0
            end
        end
    end
end

-- // 3. POPULATE MOVEMENT TAB
addToggle(TabMove, "LoopFly (Anti-Ragdoll)", false, function(v)
    Config.FlyEnabled = v
    if not v then
        clearFlyPad()
        local root = getRoot()
        if root then
            root.AssemblyLinearVelocity = Vector3.zero
        end
    end
end)

addCycle(TabMove, "Fly Bypass Mode", {"FloorPad", "LoopPulse"}, 1, function(opt)
    Config.FlyMode = opt
end)

addSlider(TabMove, "Fly Speed", 10, 300, 60, function(v)
    Config.FlySpeed = v
end)

addToggle(TabMove, "Speed Boost", false, function(v)
    Config.SpeedEnabled = v
    if not v and getHum() then getHum().WalkSpeed = 16 end
end)

addSlider(TabMove, "WalkSpeed", 16, 250, 50, function(v)
    Config.WalkSpeed = v
end)

addToggle(TabMove, "Jump Boost", false, function(v)
    Config.JumpBoostEnabled = v
    if not v and getHum() then
        getHum().UseJumpPower = true
        getHum().JumpPower = 50
    end
end)

addSlider(TabMove, "JumpPower", 50, 350, 100, function(v)
    Config.JumpPower = v
end)

addToggle(TabMove, "Infinite Jump", false, function(v)
    Config.InfJumpEnabled = v
end)

addToggle(TabMove, "Invisible (Desync)", false, function(v)
    Config.InvisibleEnabled = v
    toggleInvisible(v)
end)

-- // 4. POPULATE AUTO TARGET & TELEPORT TAB
local PlayerCycleBtn
local function getPlayerNames()
    local list = {}
    for _, p in ipairs(Players:GetPlayers()) do
        if p ~= LocalPlayer then
            table.insert(list, p.Name)
        end
    end
    if #list == 0 then table.insert(list, "None") end
    return list
end

local currentTargetList = getPlayerNames()
Config.SelectedPlayer = currentTargetList[1]

PlayerCycleBtn = addCycle(TabTarget, "Select Target", currentTargetList, 1, function(selected)
    Config.SelectedPlayer = selected
end)

addButton(TabTarget, "Refresh Player List", function()
    currentTargetList = getPlayerNames()
    Config.SelectedPlayer = currentTargetList[1]
    PlayerCycleBtn.Text = "  Select Target: < " .. tostring(Config.SelectedPlayer) .. " >"
end)

addButton(TabTarget, "Instant Teleport To Target", function()
    local targetPlr = Players:FindFirstChild(Config.SelectedPlayer or "")
    local myRoot = getRoot()
    local tRoot = getRoot(targetPlr)
    if myRoot and tRoot then
        myRoot.CFrame = tRoot.CFrame * CFrame.new(0, 0, 3)
        myRoot.AssemblyLinearVelocity = Vector3.zero
    end
end)

addToggle(TabTarget, "Auto Target (Zero-Delay Lock)", false, function(v)
    Config.AutoTargetEnabled = v
    if not v then
        local myRoot = getRoot()
        if myRoot then myRoot.AssemblyLinearVelocity = Vector3.zero end
    end
end)

addCycle(TabTarget, "Target Position", {"Behind", "Orbit", "Below", "Upper", "Front"}, 1, function(mode)
    Config.TargetMode = mode
end)

addSlider(TabTarget, "Orbit Speed", 1, 60, 15, function(v)
    Config.OrbitSpeed = v
end)

addSlider(TabTarget, "Target Range (Distance)", 1, 40, 8, function(v)
    Config.TargetRange = v
end)

-- // 5. POPULATE AIM & ESP TAB
addToggle(TabCombat, "Camera Aimlock (Nearest to Cursor)", false, function(v)
    Config.AimlockEnabled = v
end)

addCycle(TabCombat, "Aim Part", {"Head", "HumanoidRootPart"}, 1, function(part)
    Config.AimPart = part
end)

addToggle(TabCombat, "Player ESP (Highlight + Info)", false, function(v)
    Config.ESPEnabled = v
    if not v then
        for _, obj in pairs(State.ESPObjects) do
            if obj.Highlight then obj.Highlight:Destroy() end
            if obj.Billboard then obj.Billboard:Destroy() end
        end
        State.ESPObjects = {}
    end
end)

-- // ESP MANAGER
local function updateESP()
    if not Config.ESPEnabled then return end
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
                    hl.FillColor = Color3.fromRGB(255, 60, 60)
                    hl.OutlineColor = Color3.fromRGB(255, 255, 255)
                    hl.FillTransparency = 0.5
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
                    txt.TextColor3 = Color3.fromRGB(255, 230, 80)
                    txt.TextStrokeTransparency = 0
                    txt.Font = Enum.Font.Code
                    txt.TextSize = 12

                    State.ESPObjects[plr] = {Char = char, Highlight = hl, Billboard = bb, Label = txt}
                end

                local myRoot = getRoot()
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

-- // NEAREST PLAYER FOR AIMLOCK
local function getClosestPlayerToCursor()
    local closest = nil
    local shortestDist = math.huge
    local mousePos = UserInputService:GetMouseLocation()

    for _, plr in ipairs(Players:GetPlayers()) do
        if plr ~= LocalPlayer and plr.Character then
            local part = plr.Character:FindFirstChild(Config.AimPart)
            local hum = plr.Character:FindFirstChildOfClass("Humanoid")
            if part and hum and hum.Health > 0 then
                local screenPos, onScreen = Camera:WorldToViewportPoint(part.Position)
                if onScreen then
                    local dist = (Vector2.new(screenPos.X, screenPos.Y) - mousePos).Magnitude
                    if dist < shortestDist then
                        shortestDist = dist
                        closest = part
                    end
                end
            end
        end
    end
    return closest
end

-- // ZERO-DELAY CORE LOOPS (RenderStepped + Heartbeat)
table.insert(State.Connections, RunService.RenderStepped:Connect(function(dt)
    local char = getChar()
    local root = getRoot()
    local hum = getHum()

    -- 1. ZERO-DELAY AUTO TARGET (Overrides everything for instant sticking)
    if Config.AutoTargetEnabled and root and hum then
        local targetPlr = Players:FindFirstChild(Config.SelectedPlayer or "")
        local tRoot = getRoot(targetPlr)

        if tRoot then
            -- Disable ragdoll states on self while sticking
            hum:SetStateEnabled(Enum.HumanoidStateType.Ragdoll, false)
            hum:SetStateEnabled(Enum.HumanoidStateType.FallingDown, false)

            local r = Config.TargetRange
            local targetPos = tRoot.Position
            local targetCF = tRoot.CFrame
            local finalCFrame

            if Config.TargetMode == "Orbit" then
                State.OrbitAngle = (State.OrbitAngle + dt * Config.OrbitSpeed) % (math.pi * 2)
                local offset = Vector3.new(math.cos(State.OrbitAngle) * r, 0, math.sin(State.OrbitAngle) * r)
                finalCFrame = CFrame.lookAt(targetPos + offset, targetPos)
            elseif Config.TargetMode == "Behind" then
                local pos = (targetCF * CFrame.new(0, 0, r)).Position
                finalCFrame = CFrame.lookAt(pos, targetPos)
            elseif Config.TargetMode == "Front" then
                local pos = (targetCF * CFrame.new(0, 0, -r)).Position
                finalCFrame = CFrame.lookAt(pos, targetPos)
            elseif Config.TargetMode == "Below" then
                local pos = targetPos - Vector3.new(0, r, 0)
                finalCFrame = CFrame.lookAt(pos, targetPos)
            elseif Config.TargetMode == "Upper" then
                local pos = targetPos + Vector3.new(0, r, 0)
                finalCFrame = CFrame.lookAt(pos, targetPos)
            end

            -- Direct CFrame write + zero velocity so physics never lags behind target
            root.CFrame = finalCFrame
            root.AssemblyLinearVelocity = Vector3.zero
            root.AssemblyAngularVelocity = Vector3.zero

            -- Keep floor pad under feet even during AutoTarget to prevent server air-time ragdoll
            local pad = ensureFlyPad()
            pad.CFrame = CFrame.new(root.Position - Vector3.new(0, (hum.HipHeight + (root.Size.Y / 2) + 0.5), 0))
        end
    end

    -- 2. CAMERA AIMLOCK
    if Config.AimlockEnabled then
        local aimPart = getClosestPlayerToCursor()
        if aimPart then
            Camera.CFrame = CFrame.lookAt(Camera.CFrame.Position, aimPart.Position)
        end
    end
end))

table.insert(State.Connections, RunService.Heartbeat:Connect(function(dt)
    local char = getChar()
    local root = getRoot()
    local hum = getHum()

    if root and hum then
        -- Speed & Jump Boost
        if Config.SpeedEnabled then
            hum.WalkSpeed = Config.WalkSpeed
        end
        if Config.JumpBoostEnabled then
            hum.UseJumpPower = true
            hum.JumpPower = Config.JumpPower
        end

        -- LoopFly with Anti-Ragdoll FloorPad / Pulse
        if Config.FlyEnabled and not Config.AutoTargetEnabled then
            hum:SetStateEnabled(Enum.HumanoidStateType.Ragdoll, false)
            hum:SetStateEnabled(Enum.HumanoidStateType.FallingDown, false)

            local moveDir = Vector3.zero
            local camCF = Camera.CFrame
            if UserInputService:IsKeyDown(Enum.KeyCode.W) then moveDir = moveDir + camCF.LookVector end
            if UserInputService:IsKeyDown(Enum.KeyCode.S) then moveDir = moveDir - camCF.LookVector end
            if UserInputService:IsKeyDown(Enum.KeyCode.D) then moveDir = moveDir + camCF.RightVector end
            if UserInputService:IsKeyDown(Enum.KeyCode.A) then moveDir = moveDir - camCF.RightVector end
            if UserInputService:IsKeyDown(Enum.KeyCode.Space) then moveDir = moveDir + Vector3.new(0, 1, 0) end
            if UserInputService:IsKeyDown(Enum.KeyCode.LeftControl) then moveDir = moveDir - Vector3.new(0, 1, 0) end

            if moveDir.Magnitude > 0 then
                moveDir = moveDir.Unit
            end

            if Config.FlyMode == "FloorPad" then
                -- Moves CFrame cleanly while locking a physical collideable block underneath feet
                root.CFrame = root.CFrame + (moveDir * Config.FlySpeed * dt)
                root.AssemblyLinearVelocity = Vector3.new(0, 0.1, 0)
                local pad = ensureFlyPad()
                local footOffset = hum.HipHeight + (root.Size.Y / 2) + (pad.Size.Y / 2) - 0.05
                pad.CFrame = CFrame.new(root.Position - Vector3.new(0, footOffset, 0))
                hum:ChangeState(Enum.HumanoidStateType.Running)
            elseif Config.FlyMode == "LoopPulse" then
                -- Alternates grounded state and velocity pulses + micro-pad touch every tick
                local pad = ensureFlyPad()
                local footOffset = hum.HipHeight + (root.Size.Y / 2) + (pad.Size.Y / 2)
                pad.CFrame = CFrame.new(root.Position - Vector3.new(0, footOffset, 0))
                root.AssemblyLinearVelocity = (moveDir * Config.FlySpeed) + Vector3.new(0, 2.5, 0)
                hum:ChangeState(Enum.HumanoidStateType.Landed)
            end
        elseif not Config.FlyEnabled and not Config.AutoTargetEnabled then
            clearFlyPad()
        end
    end

    updateESP()
end))

-- // INFINITE JUMP & MENU TOGGLE
table.insert(State.Connections, UserInputService.JumpRequest:Connect(function()
    if Config.InfJumpEnabled then
        local hum = getHum()
        if hum then
            hum:ChangeState(Enum.HumanoidStateType.Jumping)
        end
    end
end))

table.insert(State.Connections, UserInputService.InputBegan:Connect(function(input, gpe)
    if not gpe and input.KeyCode == Enum.KeyCode.Insert then
        MainFrame.Visible = not MainFrame.Visible
    end
end))
