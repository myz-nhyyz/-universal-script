-- Context: Luau (Roblox Client Executor - Mobile & PC Cross-Platform)
-- Architecture: Fluent Acrylic Dark UI (Pill Switches, Left Indicator Sidebar, Window Controls)
--               + Anti-Kick Namecall Hook + Floor-Step Parabolic InfJump (Zero-State/Zero-Instance Detection).

local Players = game:GetService("Players")
local RunService = game:GetService("RunService")
local UserInputService = game:GetService("UserInputService")
local TweenService = game:GetService("TweenService")
local Workspace = game:GetService("Workspace")
local CoreGui = game:GetService("CoreGui")

local LocalPlayer = Players.LocalPlayer
local Camera = Workspace.CurrentCamera

-- // 0. ANTI-KICK & ANTI-TELEPORT/STATE DETECTION GUARD (Metatable Hook)
-- Blocks local anti-cheat scripts from calling LocalPlayer:Kick() or firing ban remotes on state checks
pcall(function()
    if hookmetamethod and getnamecallmethod and checkcaller then
        local oldNamecall
        oldNamecall = hookmetamethod(game, "__namecall", function(self, ...)
            local method = getnamecallmethod()
            if not checkcaller() then
                if (method == "Kick" or method == "kick") and self == LocalPlayer then
                    return nil
                end
            end
            return oldNamecall(self, ...)
        end)
    end
end)

-- // CONFIGURATION & STATE
local Config = {
    -- Movement & Protection
    FlyEnabled = false,
    FlyMode = "FloorPad", -- "FloorPad" | "LoopPulse"
    FlySpeed = 60,
    InfJumpEnabled = false,
    InfJumpMode = "FlyPadStep", -- "FlyPadStep" (Same bypass as Fly) | "ParabolicCFrame" (Zero-Velocity/Zero-Part) | "MicroBounce"
    SpeedEnabled = false,
    WalkSpeed = 50,
    JumpBoostEnabled = false,
    JumpPower = 100,
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
    TargetFreeMove = true,
    TargetMode = "Behind", -- "Behind" | "Orbit" | "Random" | "Below" | "Upper" | "Front"
    OrbitSpeed = 15,
    TargetRange = 8,

    -- Visuals
    ESPEnabled = false,
}

local State = {
    FlyPad = nil,
    InfJumpArcActive = false,
    InfJumpArcTimer = 0,
    LastJumpTime = 0,
    OrbitAngle = 0,
    FreeMoveOffset = Vector3.zero,
    LockedAimbotPlayer = nil,
    InvisData = {
        Seat = nil,
        SavedC0 = nil,
    },
    ESPObjects = {},
    ToggleRegistry = {},
    PinnedButtons = {},
    Connections = {},
}

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

local oldGui = getGuiParent():FindFirstChild("OllieFluentUI")
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
ScreenGui.Name = "OllieFluentUI"
ScreenGui.ResetOnSpawn = false
ScreenGui.IgnoreGuiInset = true
ScreenGui.ZIndexBehavior = Enum.ZIndexBehavior.Sibling
ScreenGui.Parent = getGuiParent()

-- // 1. FLOATING MINI APP ICON (38x38 px)
local AppIcon = Instance.new("TextButton")
AppIcon.Name = "FloatingAppIcon"
AppIcon.Size = UDim2.new(0, 38, 0, 38)
AppIcon.Position = UDim2.new(0, 20, 0.45, 0)
AppIcon.BackgroundColor3 = Color3.fromRGB(20, 22, 26)
AppIcon.BackgroundTransparency = 0.1
AppIcon.Text = "O"
AppIcon.TextColor3 = Color3.fromRGB(70, 175, 255)
AppIcon.Font = Enum.Font.GothamBold
AppIcon.TextSize = 16
AppIcon.AutoButtonColor = false
AppIcon.Parent = ScreenGui
Instance.new("UICorner", AppIcon).CornerRadius = UDim.new(0, 10)

local IconStroke = Instance.new("UIStroke", AppIcon)
IconStroke.Color = Color3.fromRGB(65, 165, 255)
IconStroke.Thickness = 1.5

local StatusDot = Instance.new("Frame")
StatusDot.Size = UDim2.new(0, 8, 0, 8)
StatusDot.Position = UDim2.new(1, -9, 0, 2)
StatusDot.BackgroundColor3 = Color3.fromRGB(65, 225, 120)
StatusDot.BorderSizePixel = 0
StatusDot.Parent = AppIcon
Instance.new("UICorner", StatusDot).CornerRadius = UDim.new(1, 0)

-- // 2. DEDICATED AIMBOT POP-UP MINI WINDOW (Sticky Single-Target Lock)
local AimbotPopup = Instance.new("Frame")
AimbotPopup.Name = "AimbotStickyPopup"
AimbotPopup.Size = UDim2.new(0, 155, 0, 58)
AimbotPopup.Position = UDim2.new(0.82, -75, 0.35, 0)
AimbotPopup.BackgroundColor3 = Color3.fromRGB(20, 22, 26)
AimbotPopup.BackgroundTransparency = 0.12
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

-- // 3. FLUENT ACRYLIC MAIN WINDOW (Matches Uploaded Reference Image)
local MainFrame = Instance.new("Frame")
MainFrame.Size = UDim2.new(0, 560, 0, 360)
MainFrame.Position = UDim2.new(0.5, -280, 0.5, -180)
MainFrame.BackgroundColor3 = Color3.fromRGB(20, 21, 25)
MainFrame.BackgroundTransparency = 0.08 -- Translucent Acrylic Dark Glass
MainFrame.BorderSizePixel = 0
MainFrame.Active = true
MainFrame.Parent = ScreenGui
Instance.new("UICorner", MainFrame).CornerRadius = UDim.new(0, 8)

local MainStroke = Instance.new("UIStroke", MainFrame)
MainStroke.Color = Color3.fromRGB(58, 62, 72)
MainStroke.Transparency = 0.3
MainStroke.Thickness = 1

-- Top Window Bar
local TopBar = Instance.new("Frame")
TopBar.Size = UDim2.new(1, 0, 0, 38)
TopBar.BackgroundTransparency = 1
TopBar.Active = true
TopBar.Parent = MainFrame

local HubTitle = Instance.new("TextLabel")
HubTitle.Size = UDim2.new(0, 75, 1, 0)
HubTitle.Position = UDim2.new(0, 16, 0, 0)
HubTitle.BackgroundTransparency = 1
HubTitle.Text = "Ollie Hub"
HubTitle.TextColor3 = Color3.fromRGB(240, 244, 250)
HubTitle.Font = Enum.Font.GothamBold
HubTitle.TextSize = 13
HubTitle.TextXAlignment = Enum.TextXAlignment.Left
HubTitle.Parent = TopBar

local GreenBadge = Instance.new("TextLabel")
GreenBadge.Size = UDim2.new(0, 18, 0, 18)
GreenBadge.Position = UDim2.new(0, 86, 0.5, -9)
GreenBadge.BackgroundColor3 = Color3.fromRGB(45, 195, 100)
GreenBadge.Text = "⚡"
GreenBadge.TextColor3 = Color3.fromRGB(255, 255, 255)
GreenBadge.Font = Enum.Font.GothamBold
GreenBadge.TextSize = 10
GreenBadge.Parent = TopBar
Instance.new("UICorner", GreenBadge).CornerRadius = UDim.new(1, 0)

local SubTitle = Instance.new("TextLabel")
SubTitle.Size = UDim2.new(0, 200, 1, 0)
SubTitle.Position = UDim2.new(0, 110, 0, 0)
SubTitle.BackgroundTransparency = 1
SubTitle.Text = "Universal Multi-Suite"
SubTitle.TextColor3 = Color3.fromRGB(155, 165, 180)
SubTitle.Font = Enum.Font.Gotham
SubTitle.TextSize = 12
SubTitle.TextXAlignment = Enum.TextXAlignment.Left
SubTitle.Parent = TopBar

-- Top-Right Window Controls (—  □  ×)
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
ExitBtn.TextColor3 = Color3.fromRGB(185, 190, 200)
ExitBtn.Font = Enum.Font.Gotham
ExitBtn.TextSize = 18
ExitBtn.Parent = TopBar

local isCompact = false
local function toggleMenu()
    MainFrame.Visible = not MainFrame.Visible
    StatusDot.BackgroundColor3 = MainFrame.Visible and Color3.fromRGB(65, 225, 120) or Color3.fromRGB(230, 75, 75)
end

MinBtn.MouseButton1Click:Connect(toggleMenu)
ExitBtn.MouseButton1Click:Connect(toggleMenu)
MaxBtn.MouseButton1Click:Connect(function()
    isCompact = not isCompact
    TweenService:Create(MainFrame, TweenInfo.new(0.2, Enum.EasingStyle.Quad, Enum.EasingDirection.Out), {
        Size = isCompact and UDim2.new(0, 480, 0, 310) or UDim2.new(0, 560, 0, 360)
    }):Play()
end)

makeDraggable(TopBar, MainFrame, nil)
makeDraggable(AppIcon, AppIcon, toggleMenu)

-- Left Sidebar Navigation
local Sidebar = Instance.new("Frame")
Sidebar.Size = UDim2.new(0, 150, 1, -48)
Sidebar.Position = UDim2.new(0, 10, 0, 42)
Sidebar.BackgroundTransparency = 1
Sidebar.Parent = MainFrame

local SidebarLayout = Instance.new("UIListLayout", Sidebar)
SidebarLayout.Padding = UDim.new(0, 4)
SidebarLayout.SortOrder = Enum.SortOrder.LayoutOrder

-- Right Content Area (With Large Section Title Header like "AutoFarm" in Screenshot)
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

local Pages = {}
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

    -- Left Cyan Indicator Pill (Matches Reference Image)
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
    table.insert(Pages, Page)

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

    -- Subtle Pin Shortcut Button
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

    -- Fluent Pill Toggle Switch (Right Side)
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
            floatBtn.BackgroundColor3 = state and Color3.fromRGB(45, 145, 225) or Color3.fromRGB(22, 24, 30)
            floatBtn.Text = shortName .. "\n" .. (state and "ON" or "OFF")
        end
    end

    local function setFeatureState(newState)
        state = newState
        syncVisuals()
        callback(state)
    end

    SwitchTrack.MouseButton1Click:Connect(function()
        setFeatureState(not state)
    end)
    ClickZone.MouseButton1Click:Connect(function()
        setFeatureState(not state)
    end)

    PinBtn.MouseButton1Click:Connect(function()
        if State.PinnedButtons[id] then
            State.PinnedButtons[id]:Destroy()
            State.PinnedButtons[id] = nil
            PinBtn.BackgroundColor3 = Color3.fromRGB(40, 43, 52)
            PinBtn.Text = "PIN"
            PinBtn.TextColor3 = Color3.fromRGB(150, 165, 190)
        else
            pinCount = (pinCount % 6) + 1
            local FloatBtn = Instance.new("TextButton")
            FloatBtn.Name = "Pin_" .. id
            FloatBtn.Size = UDim2.new(0, 50, 0, 36)
            FloatBtn.Position = UDim2.new(0, 68, 0.25, pinCount * 42)
            FloatBtn.BackgroundColor3 = state and Color3.fromRGB(45, 145, 225) or Color3.fromRGB(22, 24, 30)
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

-- // FLUENT CARD DROPDOWN BUILDER (Matches "Select a player to autofarm [ v ]" in Reference Image)
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

    -- Right Selector Box inside the Row
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
            if child:IsA("TextButton") then
                child:Destroy()
            end
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
        end
    }
end

local function addButton(parent, text, callback)
    local Btn = Instance.new("TextButton")
    Btn.Size = UDim2.new(1, 0, 0, 36)
    Btn.BackgroundColor3 = Color3.fromRGB(36, 40, 48)
    Btn.BackgroundTransparency = 0.2
    Btn.Text = text
    Btn.TextColor3 = Color3.fromRGB(235, 240, 250)
    Btn.Font = Enum.Font.GothamSemibold
    Btn.TextSize = 12
    Btn.Parent = parent
    Instance.new("UICorner", Btn).CornerRadius = UDim.new(0, 6)

    local Stroke = Instance.new("UIStroke", Btn)
    Stroke.Color = Color3.fromRGB(60, 66, 78)
    Stroke.Transparency = 0.4
    Stroke.Thickness = 1

    Btn.MouseButton1Click:Connect(callback)
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

-- // CREATE SIDEBAR TABS (Matching Screenshot Layout: Combat, AutoTarget, LocalPlayer, Visuals)
local TabCombat = createTab("Combat", "⚔")
local TabTarget = createTab("AutoTarget", "◇")
local TabMove   = createTab("LocalPlayer", "👤")
local TabVisual = createTab("Settings & ESP", "⚙")

-- // SHARED CAMERA/TERRAIN FLOOR PAD (Used by BOTH LoopFly & FlyPadStep InfJump)
-- Parenting to Workspace.CurrentCamera hides the part from Workspace.DescendantAdded anti-cheat scanners
-- while still keeping physical collision active for the LocalPlayer!
local function ensureFlyPad()
    if State.FlyPad and State.FlyPad.Parent then return State.FlyPad end
    local pad = Instance.new("Part")
    pad.Name = "CameraOcclusionPart"
    pad.Size = Vector3.new(6.5, 1.2, 6.5)
    pad.Transparency = 1
    pad.Anchored = true
    pad.CanCollide = true
    pad.Parent = Camera -- Hidden inside Camera container so Workspace anti-cheat checks never detect it
    State.FlyPad = pad
    return pad
end

local function clearFlyPad()
    if State.FlyPad then
        State.FlyPad:Destroy()
        State.FlyPad = nil
    end
end

-- // UNDETECTED INFINITE JUMP BYPASS (Uses exact same Ground-Pad physics as Fly + Zero-State CFrame Arc)
-- Why previous InfJump got kicked/anti'd:
--   1. Calling Humanoid:ChangeState(Jumping) in mid-air triggers server/client StateChanged anti-cheats.
--   2. Parenting parts into Workspace triggers Workspace.DescendantAdded checks.
--   3. Huge instant Y velocity spikes trigger anti-velocity checks.
-- How this fixes it:
--   * "FlyPadStep": Locks the invisible Camera-parented FloorPad right under your feet for 0.14s while you hold/press Jump.
--     The Roblox engine naturally sees you standing on solid ground (`FloorMaterial ~= Air`), so your normal jump works natively
--     with ZERO `ChangeState` calls and ZERO ragdoll!
--   * "ParabolicCFrame": Smoothly glides your CFrame along a natural jump arc over 0.22s while keeping Y velocity near 0.
local function triggerUndetectedInfJump()
    if not Config.InfJumpEnabled then return end
    local now = tick()
    if now - State.LastJumpTime < 0.14 then return end
    State.LastJumpTime = now

    local root = getRoot()
    local hum = getHum()
    if not root or not hum or hum.Health <= 0 then return end

    -- Prevent air-time ragdoll timers without calling forbidden ChangeState(Jumping)
    hum:SetStateEnabled(Enum.HumanoidStateType.Ragdoll, false)
    hum:SetStateEnabled(Enum.HumanoidStateType.FallingDown, false)

    State.InfJumpArcActive = true
    State.InfJumpArcTimer = now
end

-- // FULL ANTI-STUN ENGINE
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

    if root.Anchored then root.Anchored = false end
    for _, part in ipairs(char:GetChildren()) do
        if part:IsA("BasePart") and part.Anchored then
            part.Anchored = false
        end
    end

    hum.PlatformStand = false
    hum.Sit = false
    hum.AutoRotate = true
    hum:SetStateEnabled(Enum.HumanoidStateType.Ragdoll, false)
    hum:SetStateEnabled(Enum.HumanoidStateType.FallingDown, false)
    hum:SetStateEnabled(Enum.HumanoidStateType.Physics, false)
    hum:SetStateEnabled(Enum.HumanoidStateType.Jumping, true)

    local targetWS = Config.SpeedEnabled and Config.WalkSpeed or 16
    if hum.WalkSpeed < targetWS then
        hum.WalkSpeed = targetWS
    end

    for _, inst in ipairs(char:GetDescendants()) do
        if inst:IsA("BodyVelocity") or inst:IsA("BodyPosition") or inst:IsA("BodyAngularVelocity")
            or inst:IsA("BodyGyro") or inst:IsA("LinearVelocity") or inst:IsA("VectorForce") then
            if inst.Name ~= "OllieMover" then
                inst:Destroy()
            end
        elseif (inst:IsA("BoolValue") or inst:IsA("StringValue") or inst:IsA("NumberValue") or inst:IsA("IntValue") or inst:IsA("Folder"))
            and isStunName(inst.Name) then
            inst:Destroy()
        end
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
        seat.Parent = Camera
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

-- // POPULATE COMBAT TAB
addFeatureToggle(TabCombat, "AimbotPopup", "Aimbot (Open Sticky Pop-Up)", "AIM", false, function(v)
    Config.AimbotWidgetOpen = v
    AimbotPopup.Visible = v
    if not v then
        setAimbotActiveState(false)
    end
end)

addDropdown(TabCombat, "Aimbot Target Part", {"Head", "HumanoidRootPart"}, 1, function(part)
    Config.AimPart = part
end)

addFeatureToggle(TabCombat, "AntiStun", "Anti-Stun (Full Immunity)", "ASTUN", false, function(v)
    Config.AntiStunEnabled = v
end)

-- // POPULATE AUTOTARGET TAB
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

addFeatureToggle(TabTarget, "AutoTarget", "Auto Target Player", "TAR", false, function(v)
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

addFeatureToggle(TabTarget, "TeleportPlayer", "Instant Teleport To Player", "TP", false, function(v)
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

local PlayerDropdown = addDropdown(TabTarget, "Select a player to target", currentTargetList, 1, function(selected)
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

addSlider(TabTarget, "Target Range (Distance)", 1, 40, 8, function(v)
    Config.TargetRange = v
end)

addButton(TabTarget, "Refresh Player List", function()
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

-- // POPULATE LOCALPLAYER (MOVEMENT) TAB
addFeatureToggle(TabMove, "Fly", "LoopFly (Anti-Ragdoll Pad)", "FLY", false, function(v)
    Config.FlyEnabled = v
    if not v then
        clearFlyPad()
        local root = getRoot()
        if root then root.AssemblyLinearVelocity = Vector3.zero end
    end
end)

addDropdown(TabMove, "Select Fly Bypass Mode", {"FloorPad", "LoopPulse"}, 1, function(opt)
    Config.FlyMode = opt
end)

addSlider(TabMove, "Fly Speed", 10, 300, 60, function(v)
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
    if Config.InvisibleEnabled then
        toggleInvisible(true)
    end
end)

addFeatureToggle(TabMove, "Speed", "WalkSpeed Boost", "SPD", false, function(v)
    Config.SpeedEnabled = v
    if not v and getHum() then getHum().WalkSpeed = 16 end
end)

addSlider(TabMove, "WalkSpeed", 16, 250, 50, function(v)
    Config.WalkSpeed = v
end)

addFeatureToggle(TabMove, "JumpBoost", "JumpPower Boost", "JMP", false, function(v)
    Config.JumpBoostEnabled = v
    if not v and getHum() then
        getHum().UseJumpPower = true
        getHum().JumpPower = 50
    end
end)

addSlider(TabMove, "JumpPower", 50, 350, 100, function(v)
    Config.JumpPower = v
end)

-- // POPULATE SETTINGS & ESP TAB
addFeatureToggle(TabVisual, "ESP", "Player ESP (Highlight + Info)", "ESP", false, function(v)
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

    -- 0. ANTI-STUN ENFORCEMENT
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

    -- 1. ZERO-DELAY AUTO TARGET
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
                local theta = math.random() * math.pi * 2
                local phi = math.acos(2 * math.random() - 1)
                local randRadius = math.max(1.5, r * (0.45 + 0.55 * math.random()))
                local chaosOffset = Vector3.new(
                    randRadius * math.sin(phi) * math.cos(theta),
                    randRadius * math.cos(phi) * 0.75,
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

    -- 2. STICKY SINGLE-TARGET AIMBOT
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

        -- // UNDETECTED FLYPAD-STEP INFINITE JUMP LOOP
        -- Uses the exact same FloorPad mechanism as LoopFly so the game thinks you stepped on a block!
        if Config.InfJumpEnabled and not Config.FlyEnabled and not Config.AutoTargetEnabled then
            hum:SetStateEnabled(Enum.HumanoidStateType.Ragdoll, false)
            hum:SetStateEnabled(Enum.HumanoidStateType.FallingDown, false)

            local elapsed = tick() - State.InfJumpArcTimer
            if State.InfJumpArcActive and elapsed < 0.22 then
                local pad = ensureFlyPad()
                local footOffset = hum.HipHeight + (root.Size.Y / 2) + (pad.Size.Y / 2) - 0.04
                local liftSpeed = Config.JumpBoostEnabled and (Config.JumpPower * 0.45) or 28

                if Config.InfJumpMode == "FlyPadStep" then
                    -- Exactly like LoopFly: moves CFrame up smoothly while keeping solid floor pad glued under feet
                    local decay = math.clamp(1 - (elapsed / 0.22), 0.15, 1)
                    root.CFrame = root.CFrame + Vector3.new(0, liftSpeed * decay * dt, 0)
                    root.AssemblyLinearVelocity = Vector3.new(root.AssemblyLinearVelocity.X, 0.2, root.AssemblyLinearVelocity.Z)
                    pad.CFrame = CFrame.new(root.Position - Vector3.new(0, footOffset, 0))

                elseif Config.InfJumpMode == "ParabolicCFrame" then
                    -- Zero-part, zero-velocity CFrame arc for ultra-strict anti-cheats
                    clearFlyPad()
                    local decay = math.clamp(1 - (elapsed / 0.22), 0.1, 1)
                    root.CFrame = root.CFrame + Vector3.new(0, (liftSpeed * 1.15) * decay * dt, 0)
                    root.AssemblyLinearVelocity = Vector3.new(root.AssemblyLinearVelocity.X, 0, root.AssemblyLinearVelocity.Z)

                elseif Config.InfJumpMode == "MicroBounce" then
                    -- Places solid Camera-parented floor pad right under feet so native Roblox jump physics bounces off it
                    pad.CFrame = CFrame.new(root.Position - Vector3.new(0, footOffset, 0))
                    if elapsed < 0.05 then
                        root.AssemblyLinearVelocity = Vector3.new(root.AssemblyLinearVelocity.X, liftSpeed * 1.4, root.AssemblyLinearVelocity.Z)
                    end
                end
            else
                State.InfJumpArcActive = false
                -- Keep brief floor pad touch every 0.35s while falling to reset server air-time ragdoll counters!
                if hum:GetState() == Enum.HumanoidStateType.Freefall then
                    local pad = ensureFlyPad()
                    local footOffset = hum.HipHeight + (root.Size.Y / 2) + (pad.Size.Y / 2) - 0.02
                    if ( math.floor(tick() * 10) % 4 == 0 ) then
                        pad.CFrame = CFrame.new(root.Position - Vector3.new(0, footOffset, 0))
                    else
                        pad.CFrame = CFrame.new(0, 999999, 0)
                    end
                else
                    clearFlyPad()
                end
            end
        end

        -- // LOOPFLY ENGINE
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

-- // MULTI-HOOK INFINITE JUMP TRIGGERS
table.insert(State.Connections, UserInputService.JumpRequest:Connect(function()
    triggerUndetectedInfJump()
end))

table.insert(State.Connections, UserInputService.InputBegan:Connect(function(input, gpe)
    if not gpe and input.KeyCode == Enum.KeyCode.LeftAlt then
        toggleMenu()
    end
    if not gpe and input.KeyCode == Enum.KeyCode.Space and Config.InfJumpEnabled then
        triggerUndetectedInfJump()
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
                    triggerUndetectedInfJump()
                end
            end)
        end
        task.wait(2)
    end
end)
