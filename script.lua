-- Context: Luau (Roblox Client Executor - Mobile & PC Cross-Platform)
-- Architecture: Chaotic Spherical Random Target + Free-Move Offset Accumulator + Anti-Stun Engine + Sticky Aimbot Pop-Up.

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
    -- Movement & Protection
    FlyEnabled = false,
    FlyMode = "FloorPad", -- "FloorPad" | "LoopPulse"
    FlySpeed = 60,
    SpeedEnabled = false,
    WalkSpeed = 50,
    JumpBoostEnabled = false,
    JumpPower = 100,
    InfJumpEnabled = false,
    InfJumpMode = "HybridPad", -- "HybridPad" | "VelocityBypass" | "CFrameImpulse"
    InvisibleEnabled = false,
    InvisMode = "RootJointBreak", -- "RootJointBreak" | "UndergroundC0" | "SeatDesync"
    AntiStunEnabled = false,

    -- Combat / Target
    TeleportLoopEnabled = false,
    AimbotWidgetOpen = false,
    AimbotActive = false,
    AimPart = "Head",
    SelectedPlayer = nil,
    AutoTargetEnabled = false,
    TargetFreeMove = true, -- Allows WASD / Joystick movement while continuously snapping to target
    TargetMode = "Behind", -- "Behind" | "Orbit" | "Random" | "Below" | "Upper" | "Front"
    OrbitSpeed = 15,
    TargetRange = 8,

    -- Visuals
    ESPEnabled = false,
}

local State = {
    FlyPad = nil,
    JumpPad = nil,
    LastJumpTime = 0,
    OrbitAngle = 0,
    FreeMoveOffset = Vector3.zero, -- Dynamic offset controlled by player movement during AutoTarget
    LockedAimbotPlayer = nil,
    InvisData = {
        Seat = nil,
        FakeClone = nil,
        SavedC0 = nil,
    },
    ESPObjects = {},
    ToggleRegistry = {},
    PinnedButtons = {},
    Connections = {},
}

-- Known Stun / Knockback / Freeze object names used across popular fighting/battlegrounds games
local StunKeywords = {
    "stun", "stuns", "nojump", "nospeed", "slow", "knockback", "ragdoll", "freeze",
    "frozen", "dizz", "paralyz", "combo", "hitstun", "block", "cantmove", "disabled",
    "anchor", "heavy", "slam", "downed"
}

-- // SAFE GUI PARENTING
local function getGuiParent()
    local success, res = pcall(function()
        return (gethui and gethui()) or CoreGui
    end)
    if success and res then return res end
    return LocalPlayer:WaitForChild("PlayerGui")
end

local oldGui = getGuiParent():FindFirstChild("OllieBenchUI")
if oldGui then oldGui:Destroy() end

-- // DRAG ENGINE (Distinguishes Drag vs Tap for Mobile & PC)
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

-- // CHARACTER HELPERS
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

-- // FIND NEAREST PLAYER (For Sticky Aimbot Pop-Up)
local function findNearestValidPlayer()
    local myRoot = getRoot()
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

-- // UI ROOT
local ScreenGui = Instance.new("ScreenGui")
ScreenGui.Name = "OllieBenchUI"
ScreenGui.ResetOnSpawn = false
ScreenGui.IgnoreGuiInset = true
ScreenGui.ZIndexBehavior = Enum.ZIndexBehavior.Sibling
ScreenGui.Parent = getGuiParent()

-- // 1. FLOATING MINI APP ICON (40x40 px)
local AppIcon = Instance.new("TextButton")
AppIcon.Name = "FloatingAppIcon"
AppIcon.Size = UDim2.new(0, 40, 0, 40)
AppIcon.Position = UDim2.new(0, 20, 0.45, 0)
AppIcon.BackgroundColor3 = Color3.fromRGB(18, 19, 26)
AppIcon.Text = "O"
AppIcon.TextColor3 = Color3.fromRGB(100, 180, 255)
AppIcon.Font = Enum.Font.GothamBold
AppIcon.TextSize = 16
AppIcon.AutoButtonColor = false
AppIcon.Parent = ScreenGui
Instance.new("UICorner", AppIcon).CornerRadius = UDim.new(0, 10)

local IconStroke = Instance.new("UIStroke", AppIcon)
IconStroke.Color = Color3.fromRGB(85, 145, 235)
IconStroke.Thickness = 1.6

local StatusDot = Instance.new("Frame")
StatusDot.Size = UDim2.new(0, 8, 0, 8)
StatusDot.Position = UDim2.new(1, -9, 0, 2)
StatusDot.BackgroundColor3 = Color3.fromRGB(65, 220, 115)
StatusDot.BorderSizePixel = 0
StatusDot.Parent = AppIcon
Instance.new("UICorner", StatusDot).CornerRadius = UDim.new(1, 0)

-- // 2. DEDICATED AIMBOT POP-UP MINI WINDOW (Sticky Single-Target Lock)
local AimbotPopup = Instance.new("Frame")
AimbotPopup.Name = "AimbotStickyPopup"
AimbotPopup.Size = UDim2.new(0, 150, 0, 56)
AimbotPopup.Position = UDim2.new(0.8, -75, 0.35, 0)
AimbotPopup.BackgroundColor3 = Color3.fromRGB(18, 20, 28)
AimbotPopup.BorderSizePixel = 0
AimbotPopup.Visible = false
AimbotPopup.Active = true
AimbotPopup.Parent = ScreenGui
Instance.new("UICorner", AimbotPopup).CornerRadius = UDim.new(0, 8)

local AimPopupStroke = Instance.new("UIStroke", AimbotPopup)
AimPopupStroke.Color = Color3.fromRGB(70, 80, 115)
AimPopupStroke.Thickness = 1.5

local AimPopBtn = Instance.new("TextButton")
AimPopBtn.Size = UDim2.new(1, -12, 0, 28)
AimPopBtn.Position = UDim2.new(0, 6, 0, 6)
AimPopBtn.BackgroundColor3 = Color3.fromRGB(34, 38, 52)
AimPopBtn.Text = "Aimbot: OFF"
AimPopBtn.TextColor3 = Color3.fromRGB(240, 245, 255)
AimPopBtn.Font = Enum.Font.GothamBold
AimPopBtn.TextSize = 12
AimPopBtn.AutoButtonColor = false
AimPopBtn.Parent = AimbotPopup
Instance.new("UICorner", AimPopBtn).CornerRadius = UDim.new(0, 6)

local AimTargetLabel = Instance.new("TextLabel")
AimTargetLabel.Size = UDim2.new(1, -12, 0, 16)
AimTargetLabel.Position = UDim2.new(0, 6, 0, 36)
AimTargetLabel.BackgroundTransparency = 1
AimTargetLabel.Text = "Target: None"
AimTargetLabel.TextColor3 = Color3.fromRGB(160, 175, 205)
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
            AimPopBtn.BackgroundColor3 = Color3.fromRGB(40, 125, 75)
            AimPopupStroke.Color = Color3.fromRGB(75, 210, 120)
            AimTargetLabel.Text = "Locked: " .. State.LockedAimbotPlayer.Name
            AimTargetLabel.TextColor3 = Color3.fromRGB(110, 235, 145)
        else
            Config.AimbotActive = false
            AimPopBtn.Text = "Aimbot: OFF"
            AimPopBtn.BackgroundColor3 = Color3.fromRGB(120, 45, 45)
            AimPopupStroke.Color = Color3.fromRGB(200, 75, 75)
            AimTargetLabel.Text = "No Target Found!"
            AimTargetLabel.TextColor3 = Color3.fromRGB(255, 120, 120)
        end
    else
        State.LockedAimbotPlayer = nil
        AimPopBtn.Text = "Aimbot: OFF"
        AimPopBtn.BackgroundColor3 = Color3.fromRGB(34, 38, 52)
        AimPopupStroke.Color = Color3.fromRGB(70, 80, 115)
        AimTargetLabel.Text = "Target: None"
        AimTargetLabel.TextColor3 = Color3.fromRGB(160, 175, 205)
    end
end

makeDraggable(AimbotPopup, AimbotPopup, nil)
makeDraggable(AimPopBtn, AimbotPopup, function()
    setAimbotActiveState(not Config.AimbotActive)
end)

-- // 3. MAIN WINDOW
local MainFrame = Instance.new("Frame")
MainFrame.Size = UDim2.new(0, 475, 0, 350)
MainFrame.Position = UDim2.new(0.5, -237, 0.5, -175)
MainFrame.BackgroundColor3 = Color3.fromRGB(16, 17, 22)
MainFrame.BorderSizePixel = 0
MainFrame.Active = true
MainFrame.Parent = ScreenGui
Instance.new("UICorner", MainFrame).CornerRadius = UDim.new(0, 8)

local MainStroke = Instance.new("UIStroke", MainFrame)
MainStroke.Color = Color3.fromRGB(55, 60, 80)
MainStroke.Thickness = 1.2

local TopBar = Instance.new("Frame")
TopBar.Size = UDim2.new(1, 0, 0, 32)
TopBar.BackgroundColor3 = Color3.fromRGB(22, 24, 32)
TopBar.BorderSizePixel = 0
TopBar.Active = true
TopBar.Parent = MainFrame
Instance.new("UICorner", TopBar).CornerRadius = UDim.new(0, 8)

local TitleLabel = Instance.new("TextLabel")
TitleLabel.Size = UDim2.new(1, -40, 1, 0)
TitleLabel.Position = UDim2.new(0, 12, 0, 0)
TitleLabel.BackgroundTransparency = 1
TitleLabel.Text = "OLLIE BENCH v6 // [LEFT-ALT OR ICON]"
TitleLabel.TextColor3 = Color3.fromRGB(230, 235, 245)
TitleLabel.Font = Enum.Font.GothamBold
TitleLabel.TextSize = 12
TitleLabel.TextXAlignment = Enum.TextXAlignment.Left
TitleLabel.Parent = TopBar

local CloseBtn = Instance.new("TextButton")
CloseBtn.Size = UDim2.new(0, 26, 0, 22)
CloseBtn.Position = UDim2.new(1, -30, 0, 5)
CloseBtn.BackgroundColor3 = Color3.fromRGB(36, 38, 50)
CloseBtn.Text = "—"
CloseBtn.TextColor3 = Color3.fromRGB(220, 220, 230)
CloseBtn.Font = Enum.Font.GothamBold
CloseBtn.TextSize = 12
CloseBtn.Parent = TopBar
Instance.new("UICorner", CloseBtn).CornerRadius = UDim.new(0, 5)

local function toggleMenu()
    MainFrame.Visible = not MainFrame.Visible
    StatusDot.BackgroundColor3 = MainFrame.Visible and Color3.fromRGB(65, 220, 115) or Color3.fromRGB(230, 75, 75)
end

CloseBtn.MouseButton1Click:Connect(toggleMenu)
makeDraggable(TopBar, MainFrame, nil)
makeDraggable(AppIcon, AppIcon, toggleMenu)

local TabHolder = Instance.new("Frame")
TabHolder.Size = UDim2.new(0, 108, 1, -44)
TabHolder.Position = UDim2.new(0, 8, 0, 38)
TabHolder.BackgroundColor3 = Color3.fromRGB(20, 22, 29)
TabHolder.BorderSizePixel = 0
TabHolder.Parent = MainFrame
Instance.new("UICorner", TabHolder).CornerRadius = UDim.new(0, 6)

local TabPadding = Instance.new("UIPadding", TabHolder)
TabPadding.PaddingTop = UDim.new(0, 6)
TabPadding.PaddingLeft = UDim.new(0, 6)
TabPadding.PaddingRight = UDim.new(0, 6)

local TabListLayout = Instance.new("UIListLayout", TabHolder)
TabListLayout.Padding = UDim.new(0, 5)
TabListLayout.SortOrder = Enum.SortOrder.LayoutOrder

local ContentHolder = Instance.new("Frame")
ContentHolder.Size = UDim2.new(1, -130, 1, -44)
ContentHolder.Position = UDim2.new(0, 122, 0, 38)
ContentHolder.BackgroundColor3 = Color3.fromRGB(20, 22, 29)
ContentHolder.BorderSizePixel = 0
ContentHolder.Parent = MainFrame
Instance.new("UICorner", ContentHolder).CornerRadius = UDim.new(0, 6)

local Pages = {}
local TabButtons = {}
local function createTab(name)
    local TabBtn = Instance.new("TextButton")
    TabBtn.Size = UDim2.new(1, 0, 0, 32)
    TabBtn.BackgroundColor3 = Color3.fromRGB(28, 30, 40)
    TabBtn.BorderSizePixel = 0
    TabBtn.Text = name
    TabBtn.TextColor3 = Color3.fromRGB(170, 175, 195)
    TabBtn.Font = Enum.Font.GothamSemibold
    TabBtn.TextSize = 12
    TabBtn.AutoButtonColor = false
    TabBtn.Parent = TabHolder
    Instance.new("UICorner", TabBtn).CornerRadius = UDim.new(0, 5)

    local Page = Instance.new("ScrollingFrame")
    Page.Size = UDim2.new(1, -14, 1, -14)
    Page.Position = UDim2.new(0, 7, 0, 7)
    Page.BackgroundTransparency = 1
    Page.ScrollBarThickness = 3
    Page.ScrollBarImageColor3 = Color3.fromRGB(85, 145, 235)
    Page.Visible = false
    Page.CanvasSize = UDim2.new(0, 0, 0, 0)
    Page.AutomaticCanvasSize = Enum.AutomaticSize.Y
    Page.Parent = ContentHolder

    local Layout = Instance.new("UIListLayout", Page)
    Layout.Padding = UDim.new(0, 7)
    Layout.SortOrder = Enum.SortOrder.LayoutOrder

    local Pad = Instance.new("UIPadding", Page)
    Pad.PaddingBottom = UDim.new(0, 8)
    Pad.PaddingRight = UDim.new(0, 4)

    TabBtn.MouseButton1Click:Connect(function()
        for _, p in pairs(Pages) do p.Visible = false end
        for _, b in pairs(TabButtons) do
            TweenService:Create(b, TweenInfo.new(0.15), {
                BackgroundColor3 = Color3.fromRGB(28, 30, 40),
                TextColor3 = Color3.fromRGB(170, 175, 195)
            }):Play()
        end
        Page.Visible = true
        TweenService:Create(TabBtn, TweenInfo.new(0.15), {
            BackgroundColor3 = Color3.fromRGB(50, 95, 175),
            TextColor3 = Color3.fromRGB(255, 255, 255)
        }):Play()
    end)

    table.insert(Pages, Page)
    table.insert(TabButtons, TabBtn)
    if #Pages == 1 then
        Page.Visible = true
        TabBtn.BackgroundColor3 = Color3.fromRGB(50, 95, 175)
        TabBtn.TextColor3 = Color3.fromRGB(255, 255, 255)
    end
    return Page
end

-- // FEATURE TOGGLE + FLOATING SHORTCUT PIN BUILDER
local pinCount = 0
local function addFeatureToggle(parent, id, label, shortName, defaultState, callback)
    local Row = Instance.new("Frame")
    Row.Size = UDim2.new(1, 0, 0, 32)
    Row.BackgroundTransparency = 1
    Row.Parent = parent

    local MainBtn = Instance.new("TextButton")
    MainBtn.Size = UDim2.new(1, -54, 1, 0)
    MainBtn.BackgroundColor3 = defaultState and Color3.fromRGB(40, 110, 70) or Color3.fromRGB(28, 31, 42)
    MainBtn.Text = "   " .. label .. ":  " .. (defaultState and "ON" or "OFF")
    MainBtn.TextColor3 = Color3.fromRGB(235, 240, 250)
    MainBtn.Font = Enum.Font.GothamSemibold
    MainBtn.TextSize = 12
    MainBtn.TextXAlignment = Enum.TextXAlignment.Left
    MainBtn.AutoButtonColor = false
    MainBtn.Parent = Row
    Instance.new("UICorner", MainBtn).CornerRadius = UDim.new(0, 6)

    local BtnStroke = Instance.new("UIStroke", MainBtn)
    BtnStroke.Color = defaultState and Color3.fromRGB(70, 180, 110) or Color3.fromRGB(45, 50, 68)
    BtnStroke.Thickness = 1

    local PinBtn = Instance.new("TextButton")
    PinBtn.Size = UDim2.new(0, 48, 1, 0)
    PinBtn.Position = UDim2.new(1, -48, 0, 0)
    PinBtn.BackgroundColor3 = Color3.fromRGB(32, 35, 48)
    PinBtn.Text = "PIN"
    PinBtn.TextColor3 = Color3.fromRGB(150, 185, 255)
    PinBtn.Font = Enum.Font.GothamBold
    PinBtn.TextSize = 11
    PinBtn.AutoButtonColor = false
    PinBtn.Parent = Row
    Instance.new("UICorner", PinBtn).CornerRadius = UDim.new(0, 6)

    local state = defaultState

    local function syncVisuals()
        TweenService:Create(MainBtn, TweenInfo.new(0.15), {
            BackgroundColor3 = state and Color3.fromRGB(40, 110, 70) or Color3.fromRGB(28, 31, 42)
        }):Play()
        BtnStroke.Color = state and Color3.fromRGB(70, 180, 110) or Color3.fromRGB(45, 50, 68)
        MainBtn.Text = "   " .. label .. ":  " .. (state and "ON" or "OFF")

        local floatBtn = State.PinnedButtons[id]
        if floatBtn then
            floatBtn.BackgroundColor3 = state and Color3.fromRGB(40, 115, 70) or Color3.fromRGB(22, 24, 34)
            floatBtn.Text = shortName .. "\n" .. (state and "ON" or "OFF")
        end
    end

    local function setFeatureState(newState)
        state = newState
        syncVisuals()
        callback(state)
    end

    MainBtn.MouseButton1Click:Connect(function()
        setFeatureState(not state)
    end)

    PinBtn.MouseButton1Click:Connect(function()
        if State.PinnedButtons[id] then
            State.PinnedButtons[id]:Destroy()
            State.PinnedButtons[id] = nil
            PinBtn.BackgroundColor3 = Color3.fromRGB(32, 35, 48)
            PinBtn.Text = "PIN"
        else
            pinCount = (pinCount % 6) + 1
            local FloatBtn = Instance.new("TextButton")
            FloatBtn.Name = "Pin_" .. id
            FloatBtn.Size = UDim2.new(0, 52, 0, 36)
            FloatBtn.Position = UDim2.new(0, 70, 0.25, pinCount * 42)
            FloatBtn.BackgroundColor3 = state and Color3.fromRGB(40, 115, 70) or Color3.fromRGB(22, 24, 34)
            FloatBtn.Text = shortName .. "\n" .. (state and "ON" or "OFF")
            FloatBtn.TextColor3 = Color3.fromRGB(240, 245, 255)
            FloatBtn.Font = Enum.Font.GothamBold
            FloatBtn.TextSize = 10
            FloatBtn.AutoButtonColor = false
            FloatBtn.Parent = ScreenGui
            Instance.new("UICorner", FloatBtn).CornerRadius = UDim.new(0, 8)

            local fStroke = Instance.new("UIStroke", FloatBtn)
            fStroke.Color = Color3.fromRGB(90, 145, 225)
            fStroke.Thickness = 1.2

            State.PinnedButtons[id] = FloatBtn
            PinBtn.BackgroundColor3 = Color3.fromRGB(65, 95, 160)
            PinBtn.Text = "UNPIN"

            makeDraggable(FloatBtn, FloatBtn, function()
                setFeatureState(not state)
            end)
        end
    end)

    State.ToggleRegistry[id] = setFeatureState
end

-- // SLEEK ANIMATED DROPDOWN BUILDER
local function addDropdown(parent, label, options, defaultIndex, callback)
    local isOpen = false
    local selectedValue = options[defaultIndex or 1] or "None"

    local Container = Instance.new("Frame")
    Container.Size = UDim2.new(1, 0, 0, 34)
    Container.BackgroundColor3 = Color3.fromRGB(26, 29, 39)
    Container.BorderSizePixel = 0
    Container.ClipsDescendants = true
    Container.Parent = parent
    Instance.new("UICorner", Container).CornerRadius = UDim.new(0, 6)

    local DropStroke = Instance.new("UIStroke", Container)
    DropStroke.Color = Color3.fromRGB(52, 58, 82)
    DropStroke.Thickness = 1

    local HeaderBtn = Instance.new("TextButton")
    HeaderBtn.Size = UDim2.new(1, 0, 0, 34)
    HeaderBtn.BackgroundTransparency = 1
    HeaderBtn.Text = ""
    HeaderBtn.AutoButtonColor = false
    HeaderBtn.Parent = Container

    local TitleLbl = Instance.new("TextLabel")
    TitleLbl.Size = UDim2.new(0.52, -10, 1, 0)
    TitleLbl.Position = UDim2.new(0, 12, 0, 0)
    TitleLbl.BackgroundTransparency = 1
    TitleLbl.Text = label
    TitleLbl.TextColor3 = Color3.fromRGB(185, 195, 215)
    TitleLbl.Font = Enum.Font.GothamSemibold
    TitleLbl.TextSize = 12
    TitleLbl.TextXAlignment = Enum.TextXAlignment.Left
    TitleLbl.Parent = HeaderBtn

    local ValueBadge = Instance.new("Frame")
    ValueBadge.Size = UDim2.new(0.45, -28, 0, 22)
    ValueBadge.Position = UDim2.new(0.55, 0, 0.5, -11)
    ValueBadge.BackgroundColor3 = Color3.fromRGB(36, 42, 58)
    ValueBadge.BorderSizePixel = 0
    ValueBadge.Parent = HeaderBtn
    Instance.new("UICorner", ValueBadge).CornerRadius = UDim.new(0, 4)

    local ValueLbl = Instance.new("TextLabel")
    ValueLbl.Size = UDim2.new(1, -8, 1, 0)
    ValueLbl.Position = UDim2.new(0, 4, 0, 0)
    ValueLbl.BackgroundTransparency = 1
    ValueLbl.Text = tostring(selectedValue)
    ValueLbl.TextColor3 = Color3.fromRGB(110, 185, 255)
    ValueLbl.Font = Enum.Font.GothamBold
    ValueLbl.TextSize = 11
    ValueLbl.TextTruncate = Enum.TextTruncate.AtEnd
    ValueLbl.Parent = ValueBadge

    local ArrowLbl = Instance.new("TextLabel")
    ArrowLbl.Size = UDim2.new(0, 20, 0, 20)
    ArrowLbl.Position = UDim2.new(1, -24, 0.5, -10)
    ArrowLbl.BackgroundTransparency = 1
    ArrowLbl.Text = "▼"
    ArrowLbl.TextColor3 = Color3.fromRGB(140, 160, 200)
    ArrowLbl.Font = Enum.Font.GothamBold
    ArrowLbl.TextSize = 10
    ArrowLbl.Parent = HeaderBtn

    local ListFrame = Instance.new("ScrollingFrame")
    ListFrame.Size = UDim2.new(1, -12, 0, 110)
    ListFrame.Position = UDim2.new(0, 6, 0, 38)
    ListFrame.BackgroundColor3 = Color3.fromRGB(18, 20, 27)
    ListFrame.BorderSizePixel = 0
    ListFrame.ScrollBarThickness = 2
    ListFrame.ScrollBarImageColor3 = Color3.fromRGB(100, 170, 255)
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
    ListLayout.Padding = UDim.new(0, 4)
    ListLayout.SortOrder = Enum.SortOrder.LayoutOrder

    local currentOptions = options

    local function setOpen(openState)
        isOpen = openState
        local count = math.clamp(#currentOptions, 1, 4)
        local listHeight = count * 28 + 8
        ListFrame.Size = UDim2.new(1, -12, 0, listHeight)
        local targetHeight = isOpen and (44 + listHeight) or 34

        TweenService:Create(Container, TweenInfo.new(0.18, Enum.EasingStyle.Quad, Enum.EasingDirection.Out), {
            Size = UDim2.new(1, 0, 0, targetHeight)
        }):Play()
        TweenService:Create(DropStroke, TweenInfo.new(0.18), {
            Color = isOpen and Color3.fromRGB(90, 155, 245) or Color3.fromRGB(52, 58, 82)
        }):Play()
        ArrowLbl.Text = isOpen and "▲" or "▼"
    end

    local function rebuildItems(newList)
        currentOptions = newList or currentOptions
        for _, child in ipairs(ListFrame:GetChildren()) do
            if child:IsA("TextButton") then
                child:Destroy()
            end
        end

        for _, opt in ipairs(currentOptions) do
            local isSelected = (opt == selectedValue)
            local ItemBtn = Instance.new("TextButton")
            ItemBtn.Size = UDim2.new(1, 0, 0, 24)
            ItemBtn.BackgroundColor3 = isSelected and Color3.fromRGB(42, 75, 130) or Color3.fromRGB(26, 29, 38)
            ItemBtn.Text = "   " .. tostring(opt)
            ItemBtn.TextColor3 = isSelected and Color3.fromRGB(255, 255, 255) or Color3.fromRGB(190, 195, 210)
            ItemBtn.Font = isSelected and Enum.Font.GothamBold or Enum.Font.Gotham
            ItemBtn.TextSize = 11
            ItemBtn.TextXAlignment = Enum.TextXAlignment.Left
            ItemBtn.AutoButtonColor = false
            ItemBtn.Parent = ListFrame
            Instance.new("UICorner", ItemBtn).CornerRadius = UDim.new(0, 4)

            local AccentBar = Instance.new("Frame")
            AccentBar.Size = UDim2.new(0, 3, 0, 14)
            AccentBar.Position = UDim2.new(0, 3, 0.5, -7)
            AccentBar.BackgroundColor3 = Color3.fromRGB(100, 185, 255)
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

    HeaderBtn.MouseButton1Click:Connect(function()
        setOpen(not isOpen)
    end)

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
        end,
        SetValue = function(val)
            selectedValue = val
            ValueLbl.Text = tostring(val)
            rebuildItems(currentOptions)
            callback(val)
        end
    }
end

local function addButton(parent, text, callback)
    local Btn = Instance.new("TextButton")
    Btn.Size = UDim2.new(1, 0, 0, 30)
    Btn.BackgroundColor3 = Color3.fromRGB(42, 52, 82)
    Btn.Text = text
    Btn.TextColor3 = Color3.fromRGB(240, 245, 255)
    Btn.Font = Enum.Font.GothamSemibold
    Btn.TextSize = 12
    Btn.Parent = parent
    Instance.new("UICorner", Btn).CornerRadius = UDim.new(0, 6)
    Btn.MouseButton1Click:Connect(callback)
    return Btn
end

local function addSlider(parent, label, minVal, maxVal, defaultVal, callback)
    local Holder = Instance.new("Frame")
    Holder.Size = UDim2.new(1, 0, 0, 44)
    Holder.BackgroundColor3 = Color3.fromRGB(26, 29, 39)
    Holder.Active = true
    Holder.Parent = parent
    Instance.new("UICorner", Holder).CornerRadius = UDim.new(0, 6)

    local Stroke = Instance.new("UIStroke", Holder)
    Stroke.Color = Color3.fromRGB(45, 50, 68)
    Stroke.Thickness = 1

    local TextLbl = Instance.new("TextLabel")
    TextLbl.Size = UDim2.new(1, -16, 0, 20)
    TextLbl.Position = UDim2.new(0, 10, 0, 2)
    TextLbl.BackgroundTransparency = 1
    TextLbl.Text = label .. ":  " .. tostring(defaultVal)
    TextLbl.TextColor3 = Color3.fromRGB(220, 225, 240)
    TextLbl.Font = Enum.Font.GothamSemibold
    TextLbl.TextSize = 12
    TextLbl.TextXAlignment = Enum.TextXAlignment.Left
    TextLbl.Parent = Holder

    local BarBg = Instance.new("Frame")
    BarBg.Size = UDim2.new(1, -20, 0, 10)
    BarBg.Position = UDim2.new(0, 10, 0, 26)
    BarBg.BackgroundColor3 = Color3.fromRGB(15, 17, 23)
    BarBg.Active = true
    BarBg.Parent = Holder
    Instance.new("UICorner", BarBg).CornerRadius = UDim.new(0, 5)

    local BarFill = Instance.new("Frame")
    local initPct = math.clamp((defaultVal - minVal) / (maxVal - minVal), 0, 1)
    BarFill.Size = UDim2.new(initPct, 0, 1, 0)
    BarFill.BackgroundColor3 = Color3.fromRGB(85, 150, 235)
    BarFill.Parent = BarBg
    Instance.new("UICorner", BarFill).CornerRadius = UDim.new(0, 5)

    local dragging = false
    local function updateSlide(input)
        local rel = math.clamp((input.Position.X - BarBg.AbsolutePosition.X) / BarBg.AbsoluteSize.X, 0, 1)
        BarFill.Size = UDim2.new(rel, 0, 1, 0)
        local val = math.floor((minVal + (maxVal - minVal) * rel) * 10) / 10
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

-- // CREATE TABS
local TabMove = createTab("Movement")
local TabTarget = createTab("Auto Target")
local TabCombat = createTab("Aim & ESP")

-- // PHYSICAL PAD HELPERS
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

local function spawnMicroJumpPad(root, hum)
    if State.JumpPad then State.JumpPad:Destroy() end
    local pad = Instance.new("Part")
    pad.Name = "Baseplate_Fragment"
    pad.Size = Vector3.new(5, 0.8, 5)
    pad.Transparency = 1
    pad.Anchored = true
    pad.CanCollide = true
    local footOffset = hum.HipHeight + (root.Size.Y / 2) + 0.35
    pad.CFrame = CFrame.new(root.Position - Vector3.new(0, footOffset, 0))
    pad.Parent = Workspace
    State.JumpPad = pad
    task.delay(0.06, function()
        if pad and pad.Parent then pad:Destroy() end
    end)
end

-- // MULTI-BYPASS INFINITE JUMP ENGINE
local function executeBypassJump()
    if not Config.InfJumpEnabled then return end
    local now = tick()
    if now - State.LastJumpTime < 0.15 then return end
    State.LastJumpTime = now

    local root = getRoot()
    local hum = getHum()
    if not root or not hum or hum.Health <= 0 then return end

    local jumpVel = Config.JumpBoostEnabled and Config.JumpPower or 52
    local curVel = root.AssemblyLinearVelocity

    hum:SetStateEnabled(Enum.HumanoidStateType.Jumping, true)
    hum:SetStateEnabled(Enum.HumanoidStateType.Ragdoll, false)

    if Config.InfJumpMode == "HybridPad" then
        spawnMicroJumpPad(root, hum)
        hum:ChangeState(Enum.HumanoidStateType.Landed)
        root.AssemblyLinearVelocity = Vector3.new(curVel.X, jumpVel, curVel.Z)
        hum:ChangeState(Enum.HumanoidStateType.Jumping)
    elseif Config.InfJumpMode == "VelocityBypass" then
        spawnMicroJumpPad(root, hum)
        root.AssemblyLinearVelocity = Vector3.new(curVel.X, jumpVel, curVel.Z)
    elseif Config.InfJumpMode == "CFrameImpulse" then
        root.AssemblyLinearVelocity = Vector3.new(curVel.X, 0, curVel.Z)
        task.spawn(function()
            for i = 1, 6 do
                if root and root.Parent then
                    root.CFrame = root.CFrame + Vector3.new(0, (jumpVel / 180), 0)
                    root.AssemblyLinearVelocity = Vector3.new(root.AssemblyLinearVelocity.X, 2, root.AssemblyLinearVelocity.Z)
                end
                RunService.RenderStepped:Wait()
            end
        end)
    end
end

-- // FULL ANTI-STUN ENGINE (Purges hitstun, ragdoll, freeze, knockback & walkspeed locks)
local function isStunName(str)
    local lower = string.lower(str)
    for _, kw in ipairs(StunKeywords) do
        if string.find(lower, kw, 1, true) then
            return true
        end
    end
    return false
end

local function enforceAntiStun(char, root, hum)
    if not char or not root or not hum then return end

    -- 1. Un-anchor & unlock character parts frozen by stun scripts
    if root.Anchored then root.Anchored = false end
    for _, part in ipairs(char:GetChildren()) do
        if part:IsA("BasePart") and part.Anchored then
            part.Anchored = false
        end
    end

    -- 2. Force Humanoid out of stun/ragdoll/platform states
    hum.PlatformStand = false
    hum.Sit = false
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

    -- 3. Override WalkSpeed & JumpPower reductions caused by hit-stun
    local targetWS = Config.SpeedEnabled and Config.WalkSpeed or 16
    if hum.WalkSpeed < targetWS then
        hum.WalkSpeed = targetWS
    end
    local targetJP = Config.JumpBoostEnabled and Config.JumpPower or 50
    if hum.UseJumpPower and hum.JumpPower < targetJP then
        hum.JumpPower = targetJP
    end

    -- 4. Strip knockback BodyMovers & Stun ValueObjects inside Character/RootPart
    for _, inst in ipairs(char:GetDescendants()) do
        if inst:IsA("BodyVelocity") or inst:IsA("BodyPosition") or inst:IsA("BodyAngularVelocity")
            or inst:IsA("BodyGyro") or inst:IsA("LinearVelocity") or inst:IsA("VectorForce") then
            if inst.Name ~= "OllieMover" then
                inst:Destroy()
            end
        elseif (inst:IsA("BoolValue") or inst:IsA("StringValue") or inst:IsA("NumberValue") or inst:IsA("IntValue") or inst:IsA("Folder") or inst:IsA("Accessory"))
            and isStunName(inst.Name) then
            inst:Destroy()
        end
    end

    -- 5. Reset Stun Attributes placed on Character or Humanoid
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

-- // 3-MODE INVISIBLE ENGINE
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
    local char = getChar()

    if State.InvisData.Seat then
        State.InvisData.Seat:Destroy()
        State.InvisData.Seat = nil
    end
    if State.InvisData.FakeClone then
        State.InvisData.FakeClone:Destroy()
        State.InvisData.FakeClone = nil
    end

    if char then
        local motor = getRootMotor(char)
        if motor and State.InvisData.SavedC0 then
            motor.C0 = State.InvisData.SavedC0
            State.InvisData.SavedC0 = nil
        end
        for _, v in ipairs(char:GetDescendants()) do
            if v:IsA("BasePart") and v.Name ~= "HumanoidRootPart" then
                v.LocalTransparencyModifier = 0
                v.CanCollide = true
            end
        end
    end

    if Camera and char and char:FindFirstChildOfClass("Humanoid") then
        Camera.CameraSubject = char:FindFirstChildOfClass("Humanoid")
    end
end

local function toggleInvisible(enable)
    cleanupInvisible()
    if not enable then return end

    local char = getChar()
    local root = getRoot()
    local hum = getHum()
    if not char or not root or not hum then return end

    if Config.InvisMode == "RootJointBreak" then
        local savedCF = root.CFrame
        local motor = getRootMotor(char)
        if motor then
            State.InvisData.SavedC0 = motor.C0
            motor.C0 = motor.C0 * CFrame.new(0, 600, 0)
        end
        for _, v in ipairs(char:GetDescendants()) do
            if v:IsA("BasePart") and v.Name ~= "HumanoidRootPart" then
                v.LocalTransparencyModifier = 0.65
                v.CanCollide = false
            end
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
        for _, v in ipairs(char:GetDescendants()) do
            if v:IsA("BasePart") and v.Name ~= "HumanoidRootPart" then
                v.CanCollide = false
                v.LocalTransparencyModifier = 0.65
            end
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
        seat.Parent = Workspace
        seat.CFrame = savedCF

        local weld = Instance.new("Weld")
        weld.Part0 = seat
        weld.Part1 = root
        weld.Parent = seat

        root.CFrame = savedCF
        for _, v in ipairs(char:GetDescendants()) do
            if v:IsA("BasePart") and v.Name ~= "HumanoidRootPart" then
                v.LocalTransparencyModifier = 0.6
            end
        end
        State.InvisData.Seat = seat
    end
end

-- // POPULATE MOVEMENT TAB
addFeatureToggle(TabMove, "AntiStun", "Anti-Stun (Immunity)", "ASTUN", false, function(v)
    Config.AntiStunEnabled = v
end)

addFeatureToggle(TabMove, "Fly", "LoopFly (Anti-Ragdoll)", "FLY", false, function(v)
    Config.FlyEnabled = v
    if not v then
        clearFlyPad()
        local root = getRoot()
        if root then root.AssemblyLinearVelocity = Vector3.zero end
    end
end)

addDropdown(TabMove, "Fly Bypass Mode", {"FloorPad", "LoopPulse"}, 1, function(opt)
    Config.FlyMode = opt
end)

addSlider(TabMove, "Fly Speed", 10, 300, 60, function(v)
    Config.FlySpeed = v
end)

addFeatureToggle(TabMove, "InfJump", "Infinite Jump (Bypass)", "INFJ", false, function(v)
    Config.InfJumpEnabled = v
end)

addDropdown(TabMove, "InfJump Mode", {"HybridPad", "VelocityBypass", "CFrameImpulse"}, 1, function(opt)
    Config.InfJumpMode = opt
end)

addFeatureToggle(TabMove, "Invisible", "Invisible (Multi-Bypass)", "INVIS", false, function(v)
    Config.InvisibleEnabled = v
    toggleInvisible(v)
end)

addDropdown(TabMove, "Invisible Mode", {"RootJointBreak", "UndergroundC0", "SeatDesync"}, 1, function(opt)
    Config.InvisMode = opt
    if Config.InvisibleEnabled then
        toggleInvisible(true)
    end
end)

addFeatureToggle(TabMove, "Speed", "Speed Boost", "SPD", false, function(v)
    Config.SpeedEnabled = v
    if not v and getHum() then getHum().WalkSpeed = 16 end
end)

addSlider(TabMove, "WalkSpeed", 16, 250, 50, function(v)
    Config.WalkSpeed = v
end)

addFeatureToggle(TabMove, "JumpBoost", "Jump Boost", "JMP", false, function(v)
    Config.JumpBoostEnabled = v
    if not v and getHum() then
        getHum().UseJumpPower = true
        getHum().JumpPower = 50
    end
end)

addSlider(TabMove, "JumpPower", 50, 350, 100, function(v)
    Config.JumpPower = v
end)

-- // POPULATE AUTO TARGET & TELEPORT TAB
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

local PlayerDropdown = addDropdown(TabTarget, "Target Player", currentTargetList, 1, function(selected)
    Config.SelectedPlayer = selected
    State.FreeMoveOffset = Vector3.zero
end)

addButton(TabTarget, "Refresh Player Dropdown", function()
    PlayerDropdown.Refresh(getPlayerNames())
end)

Players.PlayerAdded:Connect(function()
    task.wait(0.2)
    PlayerDropdown.Refresh(getPlayerNames())
end)

Players.PlayerRemoving:Connect(function(leavingPlr)
    if State.LockedAimbotPlayer == leavingPlr then
        setAimbotActiveState(false)
    end
    task.wait(0.2)
    PlayerDropdown.Refresh(getPlayerNames())
end)

addFeatureToggle(TabTarget, "TeleportPlayer", "Teleport To Target", "TP", false, function(v)
    Config.TeleportLoopEnabled = v
    if v then
        local targetPlr = Players:FindFirstChild(Config.SelectedPlayer or "")
        local myRoot = getRoot()
        local tRoot = getRoot(targetPlr)
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

addFeatureToggle(TabTarget, "AutoTarget", "Auto Target (Zero-Delay)", "TAR", false, function(v)
    Config.AutoTargetEnabled = v
    State.FreeMoveOffset = Vector3.zero
    if not v then
        local myRoot = getRoot()
        if myRoot then myRoot.AssemblyLinearVelocity = Vector3.zero end
    end
end)

addFeatureToggle(TabTarget, "TargetFreeMove", "Free Move While Targeting", "TMOVE", true, function(v)
    Config.TargetFreeMove = v
    if not v then
        State.FreeMoveOffset = Vector3.zero
    end
end)

addDropdown(TabTarget, "Target Mode", {"Behind", "Orbit", "Random", "Below", "Upper", "Front"}, 1, function(mode)
    Config.TargetMode = mode
    State.FreeMoveOffset = Vector3.zero
end)

addSlider(TabTarget, "Orbit / Random Speed", 1, 60, 15, function(v)
    Config.OrbitSpeed = v
end)

addSlider(TabTarget, "Target Range (Distance)", 1, 40, 8, function(v)
    Config.TargetRange = v
end)

-- // POPULATE AIM & ESP TAB
addFeatureToggle(TabCombat, "AimbotPopup", "Aimbot (Open Pop-Up)", "AIM", false, function(v)
    Config.AimbotWidgetOpen = v
    AimbotPopup.Visible = v
    if not v then
        setAimbotActiveState(false)
    end
end)

addDropdown(TabCombat, "Aim Part", {"Head", "HumanoidRootPart"}, 1, function(part)
    Config.AimPart = part
end)

addFeatureToggle(TabCombat, "ESP", "Player ESP (Highlight)", "ESP", false, function(v)
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
                    txt.Font = Enum.Font.GothamBold
                    txt.TextSize = 11

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

-- // HYBRID MOBILE JOYSTICK + PC KEYBOARD FLIGHT VECTOR
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

    if moveDir.Magnitude > 0 then
        return moveDir.Unit
    end
    return Vector3.zero
end

-- // ZERO-DELAY CORE LOOPS (RenderStepped + Heartbeat)
table.insert(State.Connections, RunService.RenderStepped:Connect(function(dt)
    local char = getChar()
    local root = getRoot()
    local hum = getHum()

    -- 0. ANTI-STUN ENFORCEMENT (Runs every render tick so hit-stun never registers)
    if Config.AntiStunEnabled and char and root and hum then
        enforceAntiStun(char, root, hum)
    end

    -- Maintain Noclip on displaced body parts when Invisible is active
    if Config.InvisibleEnabled and char then
        for _, v in ipairs(char:GetDescendants()) do
            if v:IsA("BasePart") and v.Name ~= "HumanoidRootPart" then
                v.CanCollide = false
            end
        end
    end

    -- 1. ZERO-DELAY AUTO TARGET (Supports Random 3D Chaos + Free Movement While Targeting)
    if Config.AutoTargetEnabled and root and hum then
        local targetPlr = Players:FindFirstChild(Config.SelectedPlayer or "")
        local tRoot = getRoot(targetPlr)

        if tRoot then
            hum:SetStateEnabled(Enum.HumanoidStateType.Ragdoll, false)
            hum:SetStateEnabled(Enum.HumanoidStateType.FallingDown, false)

            local r = Config.TargetRange
            local targetPos = tRoot.Position
            local targetCF = tRoot.CFrame
            local basePos

            if Config.TargetMode == "Orbit" then
                State.OrbitAngle = (State.OrbitAngle + dt * Config.OrbitSpeed) % (math.pi * 2)
                local offset = Vector3.new(math.cos(State.OrbitAngle) * r, 0, math.sin(State.OrbitAngle) * r)
                basePos = targetPos + offset

            elseif Config.TargetMode == "Random" then
                -- High-frequency chaotic 3D spherical teleportation strictly bounded by TargetRange
                local theta = math.random() * math.pi * 2
                local phi = math.acos(2 * math.random() - 1)
                local randRadius = math.max(1.5, r * (0.45 + 0.55 * math.random()))
                local chaosOffset = Vector3.new(
                    randRadius * math.sin(phi) * math.cos(theta),
                    randRadius * math.cos(phi) * 0.75, -- Slightly flattened Y so you don't clip too deep underground
                    randRadius * math.sin(phi) * math.sin(theta)
                )
                basePos = targetPos + chaosOffset

            elseif Config.TargetMode == "Behind" then
                basePos = (targetCF * CFrame.new(0, 0, r)).Position
            elseif Config.TargetMode == "Front" then
                basePos = (targetCF * CFrame.new(0, 0, -r)).Position
            elseif Config.TargetMode == "Below" then
                basePos = targetPos - Vector3.new(0, r, 0)
            elseif Config.TargetMode == "Upper" then
                basePos = targetPos + Vector3.new(0, r, 0)
            end

            -- Free Movement While Targeting:
            -- Lets you dodge, weave, and strafe freely around the anchor point while still teleport-following the target
            if Config.TargetFreeMove then
                local moveInput = hum.MoveDirection
                local verticalInput = 0
                if UserInputService:IsKeyDown(Enum.KeyCode.Space) then verticalInput = 1 end
                if UserInputService:IsKeyDown(Enum.KeyCode.LeftControl) then verticalInput = -1 end

                local totalInput = moveInput + Vector3.new(0, verticalInput, 0)
                local moveSpd = Config.SpeedEnabled and Config.WalkSpeed or 26

                if totalInput.Magnitude > 0.05 then
                    State.FreeMoveOffset = State.FreeMoveOffset + (totalInput * moveSpd * dt)
                    -- Clamp offset to 1.5x TargetRange so you can move freely without losing the target lock
                    local maxWeave = math.max(r * 1.5, 6)
                    if State.FreeMoveOffset.Magnitude > maxWeave then
                        State.FreeMoveOffset = State.FreeMoveOffset.Unit * maxWeave
                    end
                else
                    -- Smoothly decay offset back toward the locked anchor when you stop pressing movement keys
                    State.FreeMoveOffset = State.FreeMoveOffset:Lerp(Vector3.zero, math.clamp(dt * 8, 0, 1))
                end
            else
                State.FreeMoveOffset = Vector3.zero
            end

            local finalPos = basePos + State.FreeMoveOffset
            -- Always face directly toward the target's core for instant hit registration
            local finalCFrame = CFrame.lookAt(finalPos, targetPos)

            root.CFrame = finalCFrame
            root.AssemblyLinearVelocity = Vector3.zero
            root.AssemblyAngularVelocity = Vector3.zero

            local pad = ensureFlyPad()
            pad.CFrame = CFrame.new(root.Position - Vector3.new(0, (hum.HipHeight + (root.Size.Y / 2) + 0.5), 0))
        end
    end

    -- 2. STICKY SINGLE-TARGET AIMBOT (Locked via Pop-Up Window)
    if Config.AimbotActive and State.LockedAimbotPlayer then
        local tChar = State.LockedAimbotPlayer.Character
        local aimPart = tChar and (tChar:FindFirstChild(Config.AimPart) or tChar:FindFirstChild("HumanoidRootPart"))
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
        if Config.AntiStunEnabled and char then
            enforceAntiStun(char, root, hum)
        end

        if Config.SpeedEnabled then
            hum.WalkSpeed = Config.WalkSpeed
        end
        if Config.JumpBoostEnabled then
            hum.UseJumpPower = true
            hum.JumpPower = Config.JumpPower
        end
        if Config.InfJumpEnabled then
            hum:SetStateEnabled(Enum.HumanoidStateType.Jumping, true)
        end

        if Config.FlyEnabled and not Config.AutoTargetEnabled then
            hum:SetStateEnabled(Enum.HumanoidStateType.Ragdoll, false)
            hum:SetStateEnabled(Enum.HumanoidStateType.FallingDown, false)

            local moveDir = getFlightDirection(hum)

            if Config.FlyMode == "FloorPad" then
                root.CFrame = root.CFrame + (moveDir * Config.FlySpeed * dt)
                root.AssemblyLinearVelocity = Vector3.new(0, 0.1, 0)
                local pad = ensureFlyPad()
                local footOffset = hum.HipHeight + (root.Size.Y / 2) + (pad.Size.Y / 2) - 0.05
                pad.CFrame = CFrame.new(root.Position - Vector3.new(0, footOffset, 0))
                hum:ChangeState(Enum.HumanoidStateType.Running)
            elseif Config.FlyMode == "LoopPulse" then
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

-- // MULTI-HOOK INFINITE JUMP TRIGGERS
table.insert(State.Connections, UserInputService.JumpRequest:Connect(function()
    executeBypassJump()
end))

table.insert(State.Connections, UserInputService.InputBegan:Connect(function(input, gpe)
    if not gpe and input.KeyCode == Enum.KeyCode.LeftAlt then
        toggleMenu()
    end
    if not gpe and input.KeyCode == Enum.KeyCode.Space and Config.InfJumpEnabled then
        executeBypassJump()
    end
end))

task.spawn(function()
    while ScreenGui and ScreenGui.Parent do
        local pGui = LocalPlayer:FindFirstChildOfClass("PlayerGui")
        local touchGui = pGui and pGui:FindFirstChild("TouchGui")
        local frame = touchGui and touchGui:FindFirstChild("TouchControlFrame")
        local jumpBtn = frame and frame:FindFirstChild("JumpButton")
        if jumpBtn and not jumpBtn:GetAttribute("OllieHooked") then
            jumpBtn:SetAttribute("OllieHooked", true)
            jumpBtn.InputBegan:Connect(function(input)
                if input.UserInputType == Enum.UserInputType.Touch and Config.InfJumpEnabled then
                    executeBypassJump()
                end
            end)
        end
        task.wait(2)
    end
end)
