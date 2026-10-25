--[[
    AXIOM / DARK UI SHELL
    Standalone Roblox LocalScript. All feature controls are visual-only.
    No targeting, movement, remote calls, exploit hooks, or game-feature logic is connected.
    Profile save/load keeps snapshots in memory for this running session only.
]]

local Players = game:GetService("Players")
local UserInputService = game:GetService("UserInputService")
local TweenService = game:GetService("TweenService")
local Workspace = game:GetService("Workspace")

local LocalPlayer = Players.LocalPlayer
local PlayerGui = LocalPlayer:WaitForChild("PlayerGui")

-- Clean up the last execution so reinjecting the script does not stack input listeners.
local previousCleanup = rawget(_G, "__AxiomDarkUIShellCleanup")
if type(previousCleanup) == "function" then pcall(previousCleanup) end
local managedConnections = {}
local function connectManaged(signal, callback)
    local connection = signal:Connect(callback)
    table.insert(managedConnections, connection)
    return connection
end
local function cleanupManaged()
    for _, connection in ipairs(managedConnections) do
        pcall(function() connection:Disconnect() end)
    end
    table.clear(managedConnections)
end
_G.__AxiomDarkUIShellCleanup = cleanupManaged

local oldGui = PlayerGui:FindFirstChild("AxiomDarkUIShell")
if oldGui then oldGui:Destroy() end

local COLORS = {
    Background = Color3.fromRGB(18, 18, 22),
    Surface = Color3.fromRGB(20, 20, 23),
    Surface2 = Color3.fromRGB(28, 28, 32),
    Surface3 = Color3.fromRGB(38, 38, 43),
    Border = Color3.fromRGB(48, 48, 54),
    Primary = Color3.fromRGB(240, 240, 245),
    Secondary = Color3.fromRGB(140, 140, 150),
    Muted = Color3.fromRGB(92, 92, 102),
    Track = Color3.fromRGB(49, 49, 55),
    White = Color3.fromRGB(255, 255, 255),
    Black = Color3.fromRGB(26, 26, 31),
    Good = Color3.fromRGB(205, 205, 215),
}

local function newInstance(className, props, parent)
    local obj = Instance.new(className)
    for key, value in pairs(props or {}) do
        obj[key] = value
    end
    obj.Parent = parent
    return obj
end

local function addCorner(obj, radius)
    return newInstance("UICorner", { CornerRadius = UDim.new(0, radius or 8) }, obj)
end

local function addStroke(obj, color, transparency, thickness)
    return newInstance("UIStroke", {
        Color = color or COLORS.Border,
        Transparency = transparency or 0,
        Thickness = thickness or 1,
    }, obj)
end

local function makeLabel(parent, text, size, position, textSize, color, alignment)
    return newInstance("TextLabel", {
        BackgroundTransparency = 1,
        Size = size,
        Position = position,
        Text = text or "",
        TextColor3 = color or COLORS.Primary,
        Font = Enum.Font.Gotham,
        TextSize = textSize or 12,
        TextXAlignment = alignment or Enum.TextXAlignment.Left,
        TextYAlignment = Enum.TextYAlignment.Center,
        BorderSizePixel = 0,
        RichText = false,
        ZIndex = (parent and parent:IsA("GuiObject") and parent.ZIndex or 1) + 1,
    }, parent)
end

local function makeButton(parent, text, size, position)
    local button = newInstance("TextButton", {
        AutoButtonColor = false,
        BackgroundColor3 = COLORS.Surface2,
        BorderSizePixel = 0,
        Size = size,
        Position = position,
        Text = text or "",
        TextColor3 = COLORS.Primary,
        Font = Enum.Font.Gotham,
        TextSize = 12,
        ZIndex = (parent and parent:IsA("GuiObject") and parent.ZIndex or 1) + 1,
    }, parent)
    addCorner(button, 7)
    return button
end

local pages = {
    {
        name = "Combat", icon = "⌖",
        tabs = { "All", "Aimbot", "Anti-Aim", "Triggerbot", "Ragebot", "Feedback" },
        sections = {
            { title = "Main", side = 1, items = {
                { type="toggle", label="Enable aimbot", key="combat_aimbot", tab="Aimbot", default=false },
                { type="slider", label="Field of view", key="combat_fov_radius", tab="Aimbot", min=10, max=180, step=1, default=90, suffix="°" },
                { type="slider", label="Smoothness", key="combat_smoothness", tab="Aimbot", min=0, max=100, step=1, default=35, suffix="%" },
                { type="dropdown", label="Target part", key="combat_target_part", tab="Aimbot", options={"Head","Upper Torso","HumanoidRootPart","Closest Part"}, default="Head" },
                { type="toggle", label="Wallbang", key="combat_wallbang", tab="Aimbot", default=false },
            }},
            { title = "Targeting", side = 1, items = {
                { type="dropdown", label="Priority", key="combat_priority", tab="Ragebot", options={"Closest","Lowest Health","Highest Threat","Cursor Distance"}, default="Closest" },
                { type="slider", label="Max distance", key="combat_max_distance", tab="Ragebot", min=25, max=1000, step=25, default=400, suffix=" studs" },
                { type="toggle", label="Team check", key="combat_team_check", tab="Aimbot", default=true },
                { type="toggle", label="Visibility check", key="combat_visibility_check", tab="Aimbot", default=true },
                { type="dropdown", label="Evasion", key="combat_evasion", tab="Ragebot", options={"Off","Low","Balanced","Aggressive"}, default="Off" },
            }},
            { title = "Misc", side = 2, items = {
                { type="toggle", label="Triggerbot", key="combat_triggerbot", tab="Triggerbot", default=false },
                { type="slider", label="Trigger delay", key="combat_trigger_delay", tab="Triggerbot", min=0, max=300, step=5, default=50, suffix=" ms" },
                { type="toggle", label="Hit sounds", key="combat_hit_sounds", tab="Feedback", default=true },
                { type="toggle", label="Hit chams", key="combat_hit_chams", tab="Feedback", default=false },
                { type="dropdown", label="Hit sound", key="combat_hit_sound", tab="Feedback", options={"Default","Beep","Click","Metallic","Soft"}, default="Default" },
            }},
            { title = "Extra", side = 2, items = {
                { type="toggle", label="Silent aim", key="combat_silent_aim", tab="Aimbot", default=false },
                { type="slider", label="Hit chance", key="combat_hit_chance", tab="Aimbot", min=0, max=100, step=1, default=100, suffix="%" },
                { type="dropdown", label="Prediction", key="combat_prediction", tab="Aimbot", options={"Off","Linear","Adaptive","Custom"}, default="Linear" },
                { type="toggle", label="Ragebot", key="combat_ragebot", tab="Ragebot", default=false },
                { type="slider", label="Pitch", key="combat_pitch", tab="Anti-Aim", min=-180, max=180, step=1, default=0, suffix="°" },
                { type="slider", label="Yaw", key="combat_yaw", tab="Anti-Aim", min=-180, max=180, step=1, default=0, suffix="°" },
                { type="toggle", label="Spinbot", key="combat_spinbot", tab="Anti-Aim", default=false },
                { type="toggle", label="Desync", key="combat_desync", tab="Anti-Aim", default=false },
            }},
        },
    },
    {
        name = "Movement", icon = "↕",
        tabs = { "All", "Main", "Void Spam", "CFrame Speed", "Orbit" },
        sections = {
            { title = "Main", side = 1, items = {
                { type="toggle", label="Noclip", key="move_noclip", tab="Main", default=false },
                { type="toggle", label="Fly", key="move_fly", tab="Main", default=false },
                { type="slider", label="Fly Speed", key="move_fly_speed", tab="Main", min=1, max=150, step=1, default=35 },
                { type="slider", label="Sprint Modifier", key="move_sprint_modifier", tab="Main", min=1, max=5, step=0.1, default=1.5, suffix="x" },
                { type="slider", label="Slide Modifier", key="move_slide_modifier", tab="Main", min=1, max=5, step=0.1, default=1.5, suffix="x" },
            }},
            { title = "Void Spam", side = 2, items = {
                { type="toggle", label="Void Spam", key="move_void_spam", tab="Void Spam", default=false },
                { type="toggle", label="Quantum Mode", key="move_void_quantum", tab="Void Spam", default=false },
                { type="toggle", label="Teleport Mode", key="move_void_teleport", tab="Void Spam", default=false },
                { type="dropdown", label="Pattern", key="move_void_pattern", tab="Void Spam", options={"Random","Spiral","Wave","Bounce","Chaos"}, default="Random" },
                { type="slider", label="Pattern Rate", key="move_void_rate", tab="Void Spam", min=1, max=60, step=1, default=15, suffix=" Hz" },
            }},
            { title = "CFrame Speed", side = 1, items = {
                { type="toggle", label="CFrame Speed", key="move_cframe_speed", tab="CFrame Speed", default=false },
                { type="slider", label="Drift", key="move_cframe_drift", tab="CFrame Speed", min=0, max=100, step=1, default=10 },
                { type="slider", label="Chaos", key="move_cframe_chaos", tab="CFrame Speed", min=0, max=100, step=1, default=0, suffix="%" },
            }},
            { title = "Orbit", side = 2, items = {
                { type="toggle", label="Orbit", key="move_orbit", tab="Orbit", default=false },
                { type="slider", label="Orbit Radius", key="move_orbit_radius", tab="Orbit", min=1, max=100, step=1, default=8 },
                { type="slider", label="Orbit Speed", key="move_orbit_speed", tab="Orbit", min=1, max=360, step=1, default=90, suffix="°/s" },
                { type="slider", label="Orbit Height", key="move_orbit_height", tab="Orbit", min=-30, max=30, step=1, default=0 },
            }},
        },
    },
    {
        name = "Visuals", icon = "◉",
        tabs = { "All", "Player ESP", "Chams", "Lighting", "Crosshair" },
        sections = {
            { title = "Player ESP", side = 1, items = {
                { type="toggle", label="Player ESP", key="visual_esp", tab="Player ESP", default=false },
                { type="toggle", label="Box", key="visual_esp_box", tab="Player ESP", default=true },
                { type="toggle", label="Name", key="visual_esp_name", tab="Player ESP", default=true },
                { type="toggle", label="Health Bar", key="visual_esp_health", tab="Player ESP", default=true },
                { type="toggle", label="Distance", key="visual_esp_distance", tab="Player ESP", default=true },
                { type="toggle", label="Skeleton", key="visual_esp_skeleton", tab="Player ESP", default=false },
            }},
            { title = "Chams", side = 2, items = {
                { type="toggle", label="Chams", key="visual_chams", tab="Chams", default=false },
                { type="toggle", label="Character Chams", key="visual_character_chams", tab="Chams", default=true },
                { type="toggle", label="Viewmodel Chams", key="visual_viewmodel_chams", tab="Chams", default=false },
                { type="dropdown", label="Chams Style", key="visual_chams_style", tab="Chams", options={"Flat","Outline","Glow","Metallic"}, default="Flat" },
            }},
            { title = "Lighting", side = 1, items = {
                { type="toggle", label="Fullbright", key="visual_fullbright", tab="Lighting", default=false },
                { type="dropdown", label="Lighting Override", key="visual_lighting", tab="Lighting", options={"Default","Bright","Night","Flat","Soft"}, default="Default" },
                { type="slider", label="Brightness", key="visual_brightness", tab="Lighting", min=0, max=5, step=0.1, default=1, suffix="x" },
                { type="slider", label="Contrast", key="visual_contrast", tab="Lighting", min=0, max=2, step=0.05, default=1, suffix="x" },
            }},
            { title = "Crosshair", side = 2, items = {
                { type="toggle", label="Custom Crosshair", key="visual_crosshair", tab="Crosshair", default=false },
                { type="dropdown", label="Crosshair Shape", key="visual_crosshair_shape", tab="Crosshair", options={"Cross","Dot","Circle","Plus","T"}, default="Cross" },
                { type="slider", label="Crosshair Size", key="visual_crosshair_size", tab="Crosshair", min=2, max=40, step=1, default=8, suffix=" px" },
                { type="slider", label="Crosshair Gap", key="visual_crosshair_gap", tab="Crosshair", min=0, max=20, step=1, default=4, suffix=" px" },
                { type="slider", label="Crosshair Thickness", key="visual_crosshair_thickness", tab="Crosshair", min=1, max=8, step=1, default=2, suffix=" px" },
            }},
        },
    },
    {
        name = "Utility / Misc", icon = "⚙",
        tabs = { "All", "Automation", "Targeting", "Network", "Configs" },
        sections = {
            { title = "Automation", side = 1, items = {
                { type="toggle", label="Auto-Queue", key="misc_auto_queue", tab="Automation", default=false },
                { type="toggle", label="Auto-Loadout", key="misc_auto_loadout", tab="Automation", default=false },
                { type="dropdown", label="Loadout Preset", key="misc_loadout_preset", tab="Automation", options={"Default","Rifle","Shotgun","Balanced","Custom"}, default="Default" },
            }},
            { title = "Targeting", side = 2, items = {
                { type="toggle", label="Teleport to Target", key="misc_teleport_target", tab="Targeting", default=false },
                { type="toggle", label="Predictive", key="misc_predictive", tab="Targeting", default=false },
                { type="dropdown", label="Adaptive Mode", key="misc_adaptive_mode", tab="Targeting", options={"Off","Conservative","Balanced","Responsive"}, default="Off" },
                { type="toggle", label="Anti-Bait", key="misc_anti_bait", tab="Targeting", default=false },
                { type="dropdown", label="Evasion Profile", key="misc_anti_bait_evasion", tab="Targeting", options={"Off","Low","Medium","High"}, default="Off" },
            }},
            { title = "Network", side = 1, items = {
                { type="toggle", label="Desync", key="misc_desync", tab="Network", default=false },
                { type="slider", label="Velocity Amount", key="misc_velocity", tab="Network", min=0, max=100, step=1, default=0 },
                { type="dropdown", label="Position Mode", key="misc_position_mode", tab="Network", options={"Default","Velocity Preview","Position Preview"}, default="Default" },
            }},
            { title = "Configs", side = 2, items = {
                { type="input", label="Profile Name", key="misc_profile_name", tab="Configs", default="default" },
                { type="action", label="Save Config", action="save", tab="Configs" },
                { type="action", label="Load Config", action="load", tab="Configs" },
                { type="action", label="Reset UI Values", action="reset", tab="Configs" },
                { type="note", label="Profiles stay in memory until this UI closes.", tab="Configs" },
            }},
        },
    },
}

local settings = {}
local defaults = {}
for _, page in ipairs(pages) do
    for _, section in ipairs(page.sections) do
        for _, item in ipairs(section.items) do
            if item.key then
                settings[item.key] = item.default
                defaults[item.key] = item.default
            end
        end
    end
end

local profiles = {}
settings.__menu = true
defaults.__menu = true
local activePage = pages[1]
local activeTab = "All"
local searchQuery = ""
local valueUpdaters = {}
local keybindRows = {}
local activeDropdownCloser = nil
local activeSlider = nil
local draggingWindow = false
local dragInput = nil
local dragStart = nil
local windowStart = nil

local gui = newInstance("ScreenGui", {
    Name = "AxiomDarkUIShell",
    ResetOnSpawn = false,
    IgnoreGuiInset = true,
    ZIndexBehavior = Enum.ZIndexBehavior.Sibling,
    DisplayOrder = 75,
}, PlayerGui)
gui.Destroying:Connect(function()
    cleanupManaged()
    if rawget(_G, "__AxiomDarkUIShellCleanup") == cleanupManaged then
        _G.__AxiomDarkUIShellCleanup = nil
    end
end)

local camera = Workspace.CurrentCamera
local viewport = camera and camera.ViewportSize or Vector2.new(1328, 720)
local uiScale = math.clamp(math.min(viewport.X / 1328, viewport.Y / 720), 0.55, 1.45)
local windowWidth = 860
local windowHeight = 605

local main = newInstance("Frame", {
    Name = "MainWindow",
    AnchorPoint = Vector2.new(0.5, 0.5),
    Position = UDim2.new(0, 837 * uiScale, 0, 382 * uiScale),
    Size = UDim2.fromOffset(windowWidth, windowHeight),
    BackgroundColor3 = COLORS.Background,
    BorderSizePixel = 0,
    ClipsDescendants = true,
    ZIndex = 1,
}, gui)
addCorner(main, 8)
addStroke(main, Color3.fromRGB(7, 7, 10), 0.12, 1)
local mainScale = newInstance("UIScale", { Scale = uiScale }, main)

local sidebar = newInstance("Frame", {
    Name = "Sidebar",
    Size = UDim2.new(0, 60, 1, 0),
    BackgroundColor3 = Color3.fromRGB(15, 15, 19),
    BorderSizePixel = 0,
    ZIndex = 2,
}, main)
newInstance("Frame", {
    Size = UDim2.new(0, 1, 1, 0),
    Position = UDim2.new(1, -1, 0, 0),
    BackgroundColor3 = COLORS.Border,
    BackgroundTransparency = 0.35,
    BorderSizePixel = 0,
    ZIndex = 3,
}, sidebar)

local brandMark = makeLabel(sidebar, "A", UDim2.new(1, 0, 0, 42), UDim2.new(0, 0, 0, 13), 20, COLORS.Primary, Enum.TextXAlignment.Center)
brandMark.Font = Enum.Font.GothamBold
brandMark.Visible = false

local sidebarButtons = {}
local iconsArea = newInstance("Frame", {
    BackgroundTransparency = 1,
    Position = UDim2.new(0, 0, 0, 12),
    Size = UDim2.new(1, 0, 0, 260),
    ZIndex = 3,
}, sidebar)
newInstance("UIListLayout", {
    Padding = UDim.new(0, 9),
    HorizontalAlignment = Enum.HorizontalAlignment.Center,
    SortOrder = Enum.SortOrder.LayoutOrder,
}, iconsArea)

local topArea = newInstance("Frame", {
    Name = "TopArea",
    Position = UDim2.new(0, 60, 0, 0),
    Size = UDim2.new(1, -60, 0, 66),
    BackgroundColor3 = COLORS.Background,
    BorderSizePixel = 0,
    ZIndex = 2,
}, main)
newInstance("Frame", {
    Position = UDim2.new(0, 0, 1, -1),
    Size = UDim2.new(1, 0, 0, 1),
    BackgroundColor3 = COLORS.Border,
    BackgroundTransparency = 0.3,
    BorderSizePixel = 0,
    ZIndex = 3,
}, topArea)

local titleLabel = makeLabel(topArea, "AXIOM  /  INTERFACE", UDim2.new(1, -32, 0, 18), UDim2.new(0, 16, 0, 7), 10, COLORS.Secondary)
titleLabel.Font = Enum.Font.GothamBold
local subtitleLabel = makeLabel(topArea, "CONFIGURATION SHELL", UDim2.new(1, -32, 0, 13), UDim2.new(0, 16, 0, 21), 9, COLORS.Muted)
titleLabel.Visible = false
subtitleLabel.Visible = false

local tabScroll = newInstance("ScrollingFrame", {
    Name = "Tabs",
    Position = UDim2.new(0, 12, 0, 16),
    Size = UDim2.new(1, -250, 0, 34),
    BackgroundTransparency = 1,
    BorderSizePixel = 0,
    CanvasSize = UDim2.new(0, 0, 0, 0),
    ScrollBarThickness = 2,
    ScrollBarImageColor3 = COLORS.Muted,
    ScrollingDirection = Enum.ScrollingDirection.X,
    AutomaticCanvasSize = Enum.AutomaticSize.X,
    ZIndex = 4,
}, topArea)
local tabList = newInstance("UIListLayout", {
    FillDirection = Enum.FillDirection.Horizontal,
    Padding = UDim.new(0, 6),
    SortOrder = Enum.SortOrder.LayoutOrder,
    VerticalAlignment = Enum.VerticalAlignment.Center,
}, tabScroll)

local searchBoxFrame = newInstance("Frame", {
    Name = "SearchBox",
    AnchorPoint = Vector2.new(1, 0),
    Position = UDim2.new(1, -14, 0, 16),
    Size = UDim2.new(0, 220, 0, 32),
    BackgroundColor3 = COLORS.Surface2,
    BorderSizePixel = 0,
    ZIndex = 4,
}, topArea)
addCorner(searchBoxFrame, 7)
addStroke(searchBoxFrame, COLORS.Border, 0.25, 1)
makeLabel(searchBoxFrame, "⌕", UDim2.new(0, 24, 1, 0), UDim2.new(0, 6, 0, 0), 18, COLORS.Secondary, Enum.TextXAlignment.Center)
local searchBox = newInstance("TextBox", {
    Name = "SearchInput",
    Position = UDim2.new(0, 32, 0, 0),
    Size = UDim2.new(1, -40, 1, 0),
    BackgroundTransparency = 1,
    ClearTextOnFocus = false,
    Text = "",
    PlaceholderText = "Search features...",
    PlaceholderColor3 = COLORS.Secondary,
    TextColor3 = COLORS.Primary,
    Font = Enum.Font.Gotham,
    TextSize = 11,
    TextXAlignment = Enum.TextXAlignment.Left,
    BorderSizePixel = 0,
    ZIndex = 5,
}, searchBoxFrame)

local content = newInstance("Frame", {
    Name = "Content",
    Position = UDim2.new(0, 60, 0, 66),
    Size = UDim2.new(1, -60, 1, -96),
    BackgroundTransparency = 1,
    BorderSizePixel = 0,
    ZIndex = 2,
}, main)

local footer = newInstance("Frame", {
    Name = "Footer",
    Position = UDim2.new(0, 60, 1, -30),
    Size = UDim2.new(1, -60, 0, 30),
    BackgroundColor3 = Color3.fromRGB(14, 14, 17),
    BorderSizePixel = 0,
    ZIndex = 3,
}, main)
newInstance("Frame", {
    Position = UDim2.new(0, 0, 0, 0),
    Size = UDim2.new(1, 0, 0, 1),
    BackgroundColor3 = COLORS.Border,
    BackgroundTransparency = 0.35,
    BorderSizePixel = 0,
    ZIndex = 4,
}, footer)
makeLabel(footer, "AXIOM", UDim2.new(0, 120, 1, 0), UDim2.new(0, 14, 0, 0), 10, COLORS.Primary).Font = Enum.Font.GothamBold
makeLabel(footer, "UI ONLY  •  SESSION PROFILE", UDim2.new(0.5, 0, 1, 0), UDim2.new(0.5, -110, 0, 0), 9, COLORS.Secondary, Enum.TextXAlignment.Center)
makeLabel(footer, "LOCAL", UDim2.new(0, 70, 1, 0), UDim2.new(1, -82, 0, 0), 9, COLORS.Secondary, Enum.TextXAlignment.Right)

local function makeColumn(name, position)
    local scroller = newInstance("ScrollingFrame", {
        Name = name,
        Position = position,
        Size = UDim2.new(0.5, -15, 1, -16),
        BackgroundTransparency = 1,
        BorderSizePixel = 0,
        ScrollBarThickness = 3,
        ScrollBarImageColor3 = COLORS.Muted,
        CanvasSize = UDim2.new(0, 0, 0, 0),
        ScrollingDirection = Enum.ScrollingDirection.Y,
        AutomaticCanvasSize = Enum.AutomaticSize.None,
        ClipsDescendants = true,
        ZIndex = 2,
    }, content)
    local layout = newInstance("UIListLayout", {
        Padding = UDim.new(0, 10),
        SortOrder = Enum.SortOrder.LayoutOrder,
    }, scroller)
    newInstance("UIPadding", {
        PaddingTop = UDim.new(0, 10),
        PaddingBottom = UDim.new(0, 12),
        PaddingLeft = UDim.new(0, 10),
        PaddingRight = UDim.new(0, 6),
    }, scroller)
    layout:GetPropertyChangedSignal("AbsoluteContentSize"):Connect(function()
        scroller.CanvasSize = UDim2.new(0, 0, 0, layout.AbsoluteContentSize.Y + 20)
    end)
    return scroller
end

local leftColumn = makeColumn("LeftSections", UDim2.new(0, 0, 0, 0))
local rightColumn = makeColumn("RightSections", UDim2.new(0.5, 5, 0, 0))

-- Floating watermark HUD
local watermark = newInstance("Frame", {
    Name = "Watermark",
    Active = true,
    AnchorPoint = Vector2.new(0.5, 0),
    Position = UDim2.new(0.347, 0, 0, 10),
    Size = UDim2.fromOffset(428, 44),
    BackgroundColor3 = Color3.fromRGB(23, 23, 28),
    BorderSizePixel = 0,
    ZIndex = 30,
}, gui)
addCorner(watermark, 16)
addStroke(watermark, COLORS.Border, 0.15, 1)
newInstance("UIScale", { Scale = uiScale }, watermark)
local markTile = newInstance("Frame", {
    Position = UDim2.new(0, 12, 0.5, -10),
    Size = UDim2.fromOffset(20, 20),
    BackgroundColor3 = COLORS.White,
    BorderSizePixel = 0,
    ZIndex = 31,
}, watermark)
addCorner(markTile, 5)
makeLabel(markTile, "A", UDim2.fromScale(1, 1), UDim2.new(), 11, COLORS.Black, Enum.TextXAlignment.Center).Font = Enum.Font.GothamBold
local watermarkText = makeLabel(watermark, "AXIOM   •   UI SHELL   •   VISUAL ONLY", UDim2.new(1, -50, 1, 0), UDim2.new(0, 42, 0, 0), 10, COLORS.Primary)
watermarkText.Font = Enum.Font.GothamBold

-- Floating keybind/status list
local keyPanel = newInstance("Frame", {
    Name = "KeybindList",
    Position = UDim2.new(0, 22, 0.11, 0),
    Size = UDim2.fromOffset(368, 405),
    BackgroundColor3 = COLORS.Background,
    BorderSizePixel = 0,
    ZIndex = 20,
}, gui)
addCorner(keyPanel, 8)
addStroke(keyPanel, COLORS.Border, 0.2, 1)
newInstance("UIScale", { Scale = uiScale }, keyPanel)
local keyHeader = newInstance("Frame", {
    Size = UDim2.new(1, 0, 0, 34),
    Active = true,
    BackgroundColor3 = COLORS.Surface,
    BorderSizePixel = 0,
    ZIndex = 21,
}, keyPanel)
addCorner(keyHeader, 8)
newInstance("Frame", {
    Position = UDim2.new(0, 0, 1, -8),
    Size = UDim2.new(1, 0, 0, 8),
    BackgroundColor3 = COLORS.Surface,
    BorderSizePixel = 0,
    ZIndex = 21,
}, keyHeader)
local keyDot = newInstance("Frame", {
    Position = UDim2.new(0, 12, 0.5, -4),
    Size = UDim2.fromOffset(8, 8),
    BackgroundColor3 = COLORS.White,
    BorderSizePixel = 0,
    ZIndex = 22,
}, keyHeader)
addCorner(keyDot, 4)
makeLabel(keyHeader, "Keybind list", UDim2.new(1, -100, 1, 0), UDim2.new(0, 27, 0, 0), 12, COLORS.Primary).Font = Enum.Font.GothamBold
makeLabel(keyHeader, "LIVE", UDim2.new(0, 38, 1, 0), UDim2.new(1, -46, 0, 0), 8, COLORS.Secondary, Enum.TextXAlignment.Right)
local keyColumnHead = newInstance("Frame", {
    Position = UDim2.new(0, 10, 0, 40),
    Size = UDim2.new(1, -20, 0, 22),
    BackgroundTransparency = 1,
    BorderSizePixel = 0,
    ZIndex = 21,
}, keyPanel)
makeLabel(keyColumnHead, "Function", UDim2.new(0.51, 0, 1, 0), UDim2.new(0, 5, 0, 0), 10, COLORS.Secondary)
makeLabel(keyColumnHead, "Hotkey", UDim2.new(0.22, 0, 1, 0), UDim2.new(0.55, 0, 0, 0), 10, COLORS.Secondary, Enum.TextXAlignment.Center)
makeLabel(keyColumnHead, "Status", UDim2.new(0.23, 0, 1, 0), UDim2.new(0.77, 0, 0, 0), 10, COLORS.Secondary, Enum.TextXAlignment.Right)
newInstance("Frame", {
    Position = UDim2.new(0, 10, 0, 62),
    Size = UDim2.new(1, -20, 0, 1),
    BackgroundColor3 = COLORS.Border,
    BackgroundTransparency = 0.45,
    BorderSizePixel = 0,
    ZIndex = 21,
}, keyPanel)
local keyList = newInstance("Frame", {
    Position = UDim2.new(0, 10, 0, 68),
    Size = UDim2.new(1, -20, 1, -76),
    BackgroundTransparency = 1,
    BorderSizePixel = 0,
    ZIndex = 21,
}, keyPanel)
newInstance("UIListLayout", {
    Padding = UDim.new(0, 5),
    SortOrder = Enum.SortOrder.LayoutOrder,
}, keyList)

local keybinds = {
    { label="Enable assist", key="combat_aimbot", hotkey="MB2", mode="Hold" },
    { label="Silent aim", key="combat_silent_aim", hotkey="E", mode="Toggle" },
    { label="Enable aimbot", key="combat_aimbot", hotkey="RShift", mode="Hold" },
    { label="Menu", key="__menu", hotkey="LAlt", mode="Toggle" },
    { label="Fly", key="move_fly", hotkey="F", mode="Toggle" },
    { label="Enable anti-aim", key="combat_desync", hotkey="X", mode="Toggle" },
    { label="Enable ragebot", key="combat_ragebot", hotkey="R", mode="Toggle" },
    { label="Enable triggerbot", key="combat_triggerbot", hotkey="MB2", mode="Hold" },
}
for i, binding in ipairs(keybinds) do
    local row = newInstance("Frame", {
        Size = UDim2.new(1, 0, 0, 30),
        BackgroundTransparency = 1,
        LayoutOrder = i,
        ZIndex = 22,
    }, keyList)
    local functionLabel = makeLabel(row, binding.label, UDim2.new(0.51, 0, 1, 0), UDim2.new(0, 5, 0, 0), 10, COLORS.Secondary)
    local hotkeyLabel = makeLabel(row, binding.hotkey, UDim2.new(0.22, 0, 1, 0), UDim2.new(0.55, 0, 0, 0), 10, COLORS.Primary, Enum.TextXAlignment.Center)
    local status = makeLabel(row, binding.mode, UDim2.new(0.23, 0, 1, 0), UDim2.new(0.77, 0, 0, 0), 10, COLORS.Muted, Enum.TextXAlignment.Right)
    keybindRows[binding.key] = keybindRows[binding.key] or {}
    table.insert(keybindRows[binding.key], { status = status, label = functionLabel, hotkey = hotkeyLabel, mode = binding.mode })
end

-- Keep the three floating/main surfaces scaled when the viewport changes (e.g. rotation).
local watermarkScale = watermark:FindFirstChildOfClass("UIScale")
local keyPanelScale = keyPanel:FindFirstChildOfClass("UIScale")
local function refreshScale()
    local currentCamera = Workspace.CurrentCamera
    if not currentCamera then return end
    local size = currentCamera.ViewportSize
    local scale = math.clamp(math.min(size.X / 1328, size.Y / 720), 0.55, 1.45)
    mainScale.Scale = scale
    main.Position = UDim2.new(0, 837 * scale, 0, 382 * scale)
    if watermarkScale then watermarkScale.Scale = scale end
    if keyPanelScale then keyPanelScale.Scale = scale end
end
if camera then
    connectManaged(camera:GetPropertyChangedSignal("ViewportSize"), refreshScale)
end

local toast = nil
local function notify(message)
    if toast then toast:Destroy() end
    toast = newInstance("Frame", {
        AnchorPoint = Vector2.new(1, 0),
        Position = UDim2.new(1, -18, 0, 54),
        Size = UDim2.fromOffset(235, 38),
        BackgroundColor3 = COLORS.Surface2,
        BorderSizePixel = 0,
        ZIndex = 100,
    }, gui)
    addCorner(toast, 8)
    addStroke(toast, COLORS.Border, 0.1, 1)
    makeLabel(toast, message, UDim2.new(1, -20, 1, 0), UDim2.new(0, 10, 0, 0), 10, COLORS.Primary)
    task.delay(2.2, function()
        if toast and toast.Parent then
            local current = toast
            TweenService:Create(current, TweenInfo.new(0.2), { BackgroundTransparency = 1 }):Play()
            task.wait(0.22)
            if current.Parent then current:Destroy() end
            if toast == current then toast = nil end
        end
    end)
end

local function updateKeybinds()
    for _, binding in ipairs(keybinds) do
        local rows = keybindRows[binding.key]
        local enabled = settings[binding.key] == true
        if rows then
            for _, row in ipairs(rows) do
                row.status.Text = row.mode
                row.status.TextColor3 = enabled and COLORS.Primary or COLORS.Muted
                row.label.TextColor3 = enabled and COLORS.Primary or COLORS.Secondary
                row.hotkey.TextColor3 = enabled and COLORS.Primary or COLORS.Secondary
            end
        end
    end
end

local function closeDropdown()
    if activeDropdownCloser then
        local close = activeDropdownCloser
        activeDropdownCloser = nil
        pcall(close)
    end
end

local function cloneTable(source)
    local copy = {}
    for k, v in pairs(source) do copy[k] = v end
    return copy
end

local function refreshAllControls()
    for _, updaterList in pairs(valueUpdaters) do
        for _, updater in ipairs(updaterList) do
            pcall(updater)
        end
    end
    updateKeybinds()
end

local function setValue(key, value)
    settings[key] = value
    updateKeybinds()
end

local function getRounded(value, step)
    if not step or step <= 0 then return value end
    return math.floor(value / step + 0.5) * step
end

local function makeToggle(parent, item, y)
    local row = newInstance("Frame", {
        Position = UDim2.new(0, 12, 0, y),
        Size = UDim2.new(1, -24, 0, 38),
        BackgroundTransparency = 1,
        ZIndex = 5,
    }, parent)
    makeLabel(row, item.label, UDim2.new(1, -68, 1, 0), UDim2.new(0, 0, 0, 0), 11, COLORS.Primary)
    local track = newInstance("TextButton", {
        Name = "ToggleTrack",
        AutoButtonColor = false,
        AnchorPoint = Vector2.new(1, 0.5),
        Position = UDim2.new(1, 0, 0.5, 0),
        Size = UDim2.fromOffset(40, 22),
        BackgroundColor3 = COLORS.Track,
        BorderSizePixel = 0,
        Text = "",
        ZIndex = 6,
    }, row)
    addCorner(track, 11)
    local knob = newInstance("Frame", {
        Position = UDim2.new(0, 3, 0.5, -7),
        Size = UDim2.fromOffset(14, 14),
        BackgroundColor3 = COLORS.Primary,
        BorderSizePixel = 0,
        ZIndex = 7,
    }, track)
    addCorner(knob, 7)
    local knobCenter = newInstance("Frame", {
        AnchorPoint = Vector2.new(0.5, 0.5),
        Position = UDim2.new(0.5, 0, 0.5, 0),
        Size = UDim2.fromOffset(4, 4),
        BackgroundColor3 = COLORS.Surface3,
        BackgroundTransparency = 1,
        BorderSizePixel = 0,
        ZIndex = 8,
    }, knob)
    addCorner(knobCenter, 2)
    local function update()
        local on = settings[item.key] == true
        track.BackgroundColor3 = on and COLORS.White or COLORS.Track
        knob.BackgroundColor3 = on and COLORS.Black or COLORS.Primary
        knob.Position = on and UDim2.new(1, -17, 0.5, -7) or UDim2.new(0, 3, 0.5, -7)
        knobCenter.BackgroundTransparency = on and 0 or 1
    end
    track.Activated:Connect(function()
        setValue(item.key, not settings[item.key])
        update()
    end)
    valueUpdaters[item.key] = valueUpdaters[item.key] or {}
    table.insert(valueUpdaters[item.key], update)
    update()
    return 42
end

local function makeSlider(parent, item, y)
    local row = newInstance("Frame", {
        Position = UDim2.new(0, 12, 0, y),
        Size = UDim2.new(1, -24, 0, 56),
        BackgroundTransparency = 1,
        ZIndex = 5,
    }, parent)
    makeLabel(row, item.label, UDim2.new(1, -78, 0, 19), UDim2.new(0, 0, 0, 0), 11, COLORS.Primary)
    local valueLabel = makeLabel(row, "", UDim2.new(0, 78, 0, 19), UDim2.new(1, -78, 0, 0), 10, COLORS.Secondary, Enum.TextXAlignment.Right)
    local track = newInstance("TextButton", {
        AutoButtonColor = false,
        Position = UDim2.new(0, 0, 0, 34),
        Size = UDim2.new(1, 0, 0, 5),
        BackgroundColor3 = COLORS.Track,
        BorderSizePixel = 0,
        Text = "",
        ZIndex = 6,
    }, row)
    addCorner(track, 3)
    local fill = newInstance("Frame", {
        Size = UDim2.new(0, 0, 1, 0),
        BackgroundColor3 = COLORS.White,
        BorderSizePixel = 0,
        ZIndex = 7,
    }, track)
    addCorner(fill, 3)
    local thumb = newInstance("Frame", {
        AnchorPoint = Vector2.new(0.5, 0.5),
        Position = UDim2.new(0, 0, 0.5, 0),
        Size = UDim2.fromOffset(14, 14),
        BackgroundColor3 = COLORS.White,
        BorderSizePixel = 0,
        ZIndex = 8,
    }, track)
    addCorner(thumb, 7)
    addStroke(thumb, COLORS.Surface3, 0.05, 2)
    local thumbCenter = newInstance("Frame", {
        AnchorPoint = Vector2.new(0.5, 0.5),
        Position = UDim2.new(0.5, 0, 0.5, 0),
        Size = UDim2.fromOffset(4, 4),
        BackgroundColor3 = COLORS.Black,
        BorderSizePixel = 0,
        ZIndex = 9,
    }, thumb)
    addCorner(thumbCenter, 2)

    local function setFromX(x)
        local width = math.max(track.AbsoluteSize.X, 1)
        local alpha = math.clamp((x - track.AbsolutePosition.X) / width, 0, 1)
        local raw = item.min + (item.max - item.min) * alpha
        local step = item.step or 1
        local value = item.min + getRounded((raw - item.min) / step, 1) * step
        value = math.clamp(value, item.min, item.max)
        setValue(item.key, value)
        local fraction = (value - item.min) / math.max(item.max - item.min, 0.0001)
        fill.Size = UDim2.new(fraction, 0, 1, 0)
        thumb.Position = UDim2.new(fraction, 0, 0.5, 0)
        local display = (math.abs(value - math.floor(value)) < 0.0001) and tostring(math.floor(value)) or string.format("%.2f", value):gsub("0+$", ""):gsub("%.$", "")
        valueLabel.Text = display .. (item.suffix or "")
    end
    local function update()
        local value = tonumber(settings[item.key]) or item.min
        local fraction = math.clamp((value - item.min) / math.max(item.max - item.min, 0.0001), 0, 1)
        fill.Size = UDim2.new(fraction, 0, 1, 0)
        thumb.Position = UDim2.new(fraction, 0, 0.5, 0)
        local display = (math.abs(value - math.floor(value)) < 0.0001) and tostring(math.floor(value)) or string.format("%.2f", value):gsub("0+$", ""):gsub("%.$", "")
        valueLabel.Text = display .. (item.suffix or "")
    end
    track.InputBegan:Connect(function(input)
        if input.UserInputType == Enum.UserInputType.MouseButton1 or input.UserInputType == Enum.UserInputType.Touch then
            activeSlider = { updateAt = function(position) setFromX(position.X) } 
            setFromX(input.Position.X)
        end
    end)
    valueUpdaters[item.key] = valueUpdaters[item.key] or {}
    table.insert(valueUpdaters[item.key], update)
    update()
    return 58
end

local function makeDropdown(parent, item, y)
    local row = newInstance("Frame", {
        Position = UDim2.new(0, 12, 0, y),
        Size = UDim2.new(1, -24, 0, 60),
        BackgroundTransparency = 1,
        ZIndex = 5,
    }, parent)
    makeLabel(row, item.label, UDim2.new(1, 0, 0, 19), UDim2.new(0, 0, 0, 0), 11, COLORS.Primary)
    local button = newInstance("TextButton", {
        AutoButtonColor = false,
        Position = UDim2.new(0, 0, 0, 24),
        Size = UDim2.new(1, 0, 0, 31),
        BackgroundColor3 = COLORS.Surface2,
        BorderSizePixel = 0,
        Text = "",
        ZIndex = 6,
    }, row)
    addCorner(button, 6)
    addStroke(button, COLORS.Border, 0.2, 1)
    local selectedText = makeLabel(button, "", UDim2.new(1, -34, 1, 0), UDim2.new(0, 10, 0, 0), 10, COLORS.Secondary)
    local arrow = makeLabel(button, "⌄", UDim2.new(0, 22, 1, 0), UDim2.new(1, -27, 0, -1), 15, COLORS.Secondary, Enum.TextXAlignment.Center)

    local function update()
        selectedText.Text = tostring(settings[item.key] or item.default or "Select")
    end
    local function openOptions()
        closeDropdown()
        local overlay = newInstance("TextButton", {
            Name = "DropdownOverlay",
            Size = UDim2.fromScale(1, 1),
            BackgroundTransparency = 1,
            Text = "",
            AutoButtonColor = false,
            ZIndex = 90,
        }, gui)
        local popupHeight = math.min(#item.options * 29 + 8, 160)
        local popupWidth = math.max(button.AbsoluteSize.X, 150)
        local pos = button.AbsolutePosition
        local screen = camera and camera.ViewportSize or Vector2.new(1280, 720)
        local x = math.clamp(pos.X, 6, math.max(6, screen.X - popupWidth - 6))
        local yPos = pos.Y + button.AbsoluteSize.Y + 4
        if yPos + popupHeight > screen.Y - 8 then yPos = math.max(6, pos.Y - popupHeight - 4) end
        local popup = newInstance("Frame", {
            Name = "DropdownPopup",
            Position = UDim2.fromOffset(x, yPos),
            Size = UDim2.fromOffset(popupWidth, popupHeight),
            BackgroundColor3 = COLORS.Surface,
            BorderSizePixel = 0,
            ClipsDescendants = true,
            ZIndex = 100,
        }, gui)
        addCorner(popup, 7)
        addStroke(popup, COLORS.Border, 0.05, 1)
        local optionScroll = newInstance("ScrollingFrame", {
            Position = UDim2.new(0, 4, 0, 4),
            Size = UDim2.new(1, -8, 1, -8),
            BackgroundTransparency = 1,
            BorderSizePixel = 0,
            ScrollBarThickness = 2,
            ScrollBarImageColor3 = COLORS.Muted,
            CanvasSize = UDim2.new(0, 0, 0, #item.options * 29),
            ScrollingDirection = Enum.ScrollingDirection.Y,
            ZIndex = 101,
        }, popup)
        newInstance("UIListLayout", { Padding = UDim.new(0, 2), SortOrder = Enum.SortOrder.LayoutOrder }, optionScroll)
        for index, option in ipairs(item.options) do
            local optionButton = makeButton(optionScroll, option, UDim2.new(1, -2, 0, 27), UDim2.new(0, 0, 0, 0))
            optionButton.LayoutOrder = index
            optionButton.TextXAlignment = Enum.TextXAlignment.Left
            optionButton.TextSize = 10
            optionButton.TextColor3 = option == settings[item.key] and COLORS.Primary or COLORS.Secondary
            optionButton.BackgroundColor3 = option == settings[item.key] and COLORS.Surface3 or COLORS.Surface
            optionButton.ZIndex = 102
            local pad = newInstance("UIPadding", { PaddingLeft = UDim.new(0, 9) }, optionButton)
            optionButton.Activated:Connect(function()
                setValue(item.key, option)
                update()
                closeDropdown()
            end)
        end
        local function close()
            arrow.Text = "⌄"
            if overlay.Parent then overlay:Destroy() end
            if popup.Parent then popup:Destroy() end
        end
        overlay.Activated:Connect(function() closeDropdown() end)
        activeDropdownCloser = close
        arrow.Text = "⌃"
    end
    button.Activated:Connect(function()
        if activeDropdownCloser then closeDropdown() else openOptions() end
    end)
    valueUpdaters[item.key] = valueUpdaters[item.key] or {}
    table.insert(valueUpdaters[item.key], update)
    update()
    return 64
end

local function makeInput(parent, item, y)
    local row = newInstance("Frame", {
        Position = UDim2.new(0, 12, 0, y),
        Size = UDim2.new(1, -24, 0, 58),
        BackgroundTransparency = 1,
        ZIndex = 5,
    }, parent)
    makeLabel(row, item.label, UDim2.new(1, 0, 0, 18), UDim2.new(0, 0, 0, 0), 11, COLORS.Primary)
    local box = newInstance("TextBox", {
        Position = UDim2.new(0, 0, 0, 24),
        Size = UDim2.new(1, 0, 0, 30),
        BackgroundColor3 = COLORS.Surface2,
        BorderSizePixel = 0,
        ClearTextOnFocus = false,
        Text = tostring(settings[item.key] or ""),
        PlaceholderText = "Enter profile name",
        PlaceholderColor3 = COLORS.Secondary,
        TextColor3 = COLORS.Primary,
        Font = Enum.Font.Gotham,
        TextSize = 10,
        TextXAlignment = Enum.TextXAlignment.Left,
        ZIndex = 6,
    }, row)
    addCorner(box, 6)
    addStroke(box, COLORS.Border, 0.25, 1)
    newInstance("UIPadding", { PaddingLeft = UDim.new(0, 9), PaddingRight = UDim.new(0, 7) }, box)
    box.FocusLost:Connect(function()
        setValue(item.key, box.Text)
    end)
    local function update()
        if not box:IsFocused() then box.Text = tostring(settings[item.key] or "") end
    end
    valueUpdaters[item.key] = valueUpdaters[item.key] or {}
    table.insert(valueUpdaters[item.key], update)
    return 62
end

local function performAction(action)
    if action == "save" then
        local name = tostring(settings.misc_profile_name or "default"):match("^%s*(.-)%s*$")
        if name == "" then notify("Enter a profile name first") return end
        profiles[name] = cloneTable(settings)
        notify("Saved UI profile: " .. name)
    elseif action == "load" then
        local name = tostring(settings.misc_profile_name or "default"):match("^%s*(.-)%s*$")
        if profiles[name] then
            settings = cloneTable(profiles[name])
            refreshAllControls()
            notify("Loaded UI profile: " .. name)
        else
            notify("No in-session profile named " .. name)
        end
    elseif action == "reset" then
        settings = cloneTable(defaults)
        refreshAllControls()
        notify("UI values reset")
    end
end

local function makeAction(parent, item, y)
    local row = newInstance("Frame", {
        Position = UDim2.new(0, 12, 0, y),
        Size = UDim2.new(1, -24, 0, 40),
        BackgroundTransparency = 1,
        ZIndex = 5,
    }, parent)
    local button = makeButton(row, item.label, UDim2.new(1, 0, 0, 32), UDim2.new(0, 0, 0, 2))
    button.BackgroundColor3 = COLORS.Surface3
    button.TextSize = 10
    button.Activated:Connect(function() performAction(item.action) end)
    return 44
end

local function makeNote(parent, item, y)
    local row = newInstance("Frame", {
        Position = UDim2.new(0, 12, 0, y),
        Size = UDim2.new(1, -24, 0, 32),
        BackgroundTransparency = 1,
        ZIndex = 5,
    }, parent)
    makeLabel(row, item.label, UDim2.new(1, 0, 1, 0), UDim2.new(0, 0, 0, 0), 9, COLORS.Secondary)
    return 35
end

local function clearColumn(column)
    for _, child in ipairs(column:GetChildren()) do
        if child:IsA("Frame") or child:IsA("TextLabel") then child:Destroy() end
    end
end

local function createSectionCard(column, section, items, order)
    local estimatedHeight = 42
    for _, item in ipairs(items) do
        if item.type == "toggle" then estimatedHeight += 42
        elseif item.type == "slider" then estimatedHeight += 58
        elseif item.type == "dropdown" then estimatedHeight += 64
        elseif item.type == "input" then estimatedHeight += 62
        elseif item.type == "action" then estimatedHeight += 44
        elseif item.type == "note" then estimatedHeight += 35 end
    end
    local card = newInstance("Frame", {
        Name = section.title:gsub("%W", "") .. "Section",
        Size = UDim2.new(1, -2, 0, estimatedHeight + 5),
        BackgroundColor3 = COLORS.Surface,
        BorderSizePixel = 0,
        LayoutOrder = order,
        ZIndex = 3,
    }, column)
    addCorner(card, 8)
    addStroke(card, COLORS.Border, 0.33, 1)
    local headerBand = newInstance("Frame", {
        Position = UDim2.new(0, 0, 0, 0),
        Size = UDim2.new(1, 0, 0, 36),
        BackgroundColor3 = COLORS.Surface2,
        BorderSizePixel = 0,
        ZIndex = 4,
    }, card)
    addCorner(headerBand, 8)
    newInstance("Frame", {
        Position = UDim2.new(0, 0, 1, -8),
        Size = UDim2.new(1, 0, 0, 8),
        BackgroundColor3 = COLORS.Surface2,
        BorderSizePixel = 0,
        ZIndex = 4,
    }, headerBand)
    local iconMap = { Main="⊙", Misc="▱", Targeting="◎", Extra="☆", ["Player ESP"]="◉", Chams="◇", Lighting="☼", Crosshair="＋", Automation="⌁", Network="⌘", Configs="▣", ["Void Spam"]="⌁", Orbit="◌", ["CFrame Speed"]="↗" }
    makeLabel(card, iconMap[section.title] or "◇", UDim2.new(0, 19, 0, 25), UDim2.new(0, 11, 0, 6), 13, COLORS.Primary, Enum.TextXAlignment.Center)
    local heading = makeLabel(card, section.title, UDim2.new(1, -48, 0, 25), UDim2.new(0, 34, 0, 7), 12, COLORS.Primary)
    heading.Font = Enum.Font.GothamBold
    local separator = newInstance("Frame", {
        Position = UDim2.new(0, 12, 0, 35),
        Size = UDim2.new(1, -24, 0, 1),
        BackgroundColor3 = COLORS.Border,
        BackgroundTransparency = 0.35,
        BorderSizePixel = 0,
        ZIndex = 4,
    }, card)
    local y = 40
    for _, item in ipairs(items) do
        if item.type == "toggle" then y += makeToggle(card, item, y)
        elseif item.type == "slider" then y += makeSlider(card, item, y)
        elseif item.type == "dropdown" then y += makeDropdown(card, item, y)
        elseif item.type == "input" then y += makeInput(card, item, y)
        elseif item.type == "action" then y += makeAction(card, item, y)
        elseif item.type == "note" then y += makeNote(card, item, y) end
    end
end

local function isItemVisible(section, item)
    if activeTab ~= "All" and item.tab ~= activeTab then return false end
    if searchQuery ~= "" then
        local haystack = (section.title .. " " .. item.label):lower()
        if not string.find(haystack, searchQuery, 1, true) then return false end
    end
    return true
end

local function renderPage()
    closeDropdown()
    clearColumn(leftColumn)
    clearColumn(rightColumn)
    valueUpdaters = {}
    for side = 1, 2 do
        local column = side == 1 and leftColumn or rightColumn
        local sequence = 0
        for _, section in ipairs(activePage.sections) do
            if section.side == side then
                local shown = {}
                for _, item in ipairs(section.items) do
                    if isItemVisible(section, item) then table.insert(shown, item) end
                end
                if #shown > 0 then
                    sequence += 1
                    createSectionCard(column, section, shown, sequence)
                end
            end
        end
        if sequence == 0 then
            local empty = makeLabel(column, "No matching features", UDim2.new(1, -20, 0, 36), UDim2.new(0, 10, 0, 10), 11, COLORS.Secondary, Enum.TextXAlignment.Center)
            empty.Name = "EmptyState"
        end
    end
    refreshAllControls()
    task.defer(function()
        leftColumn.CanvasPosition = Vector2.new(0, 0)
        rightColumn.CanvasPosition = Vector2.new(0, 0)
    end)
end

local function rebuildTabs()
    for _, child in ipairs(tabScroll:GetChildren()) do
        if child:IsA("TextButton") then child:Destroy() end
    end
    for index, tabName in ipairs(activePage.tabs) do
        local tabButton = makeButton(tabScroll, tabName, UDim2.fromOffset(math.max(58, #tabName * 7 + 19), 28), UDim2.new())
        tabButton.LayoutOrder = index
        tabButton.TextSize = 10
        tabButton.BackgroundColor3 = tabName == activeTab and COLORS.White or COLORS.Surface
        tabButton.TextColor3 = tabName == activeTab and COLORS.Black or COLORS.Secondary
        tabButton.Font = tabName == activeTab and Enum.Font.GothamBold or Enum.Font.Gotham
        if tabName == activeTab then addStroke(tabButton, COLORS.Border, 0.15, 1) end
        tabButton.Activated:Connect(function()
            activeTab = tabName
            rebuildTabs()
            renderPage()
        end)
    end
end

local function setPage(page)
    activePage = page
    activeTab = "All"
    subtitleLabel.Text = string.upper(page.name) .. "  /  CONFIGURATION"
    for _, entry in ipairs(sidebarButtons) do
        entry.accent.Visible = entry.page == page
        entry.button.BackgroundColor3 = entry.page == page and COLORS.White or COLORS.Background
        entry.button.TextColor3 = entry.page == page and COLORS.Black or COLORS.Secondary
    end
    rebuildTabs()
    renderPage()
end

for index, page in ipairs(pages) do
    local button = newInstance("TextButton", {
        Name = page.name:gsub("%W", "") .. "Navigation",
        AutoButtonColor = false,
        Size = UDim2.fromOffset(42, 42),
        BackgroundColor3 = page == activePage and COLORS.White or COLORS.Background,
        BorderSizePixel = 0,
        Text = page.icon,
        TextColor3 = page == activePage and COLORS.Black or COLORS.Secondary,
        Font = Enum.Font.Gotham,
        TextSize = 20,
        LayoutOrder = index,
        ZIndex = 4,
    }, iconsArea)
    addCorner(button, 8)
    local accent = newInstance("Frame", {
        Position = UDim2.new(0, -5, 0.5, -10),
        Size = UDim2.fromOffset(3, 20),
        BackgroundColor3 = COLORS.White,
        BorderSizePixel = 0,
        Visible = page == activePage,
        ZIndex = 5,
    }, button)
    addCorner(accent, 2)
    button.Activated:Connect(function() setPage(page) end)
    table.insert(sidebarButtons, { page = page, button = button, accent = accent })
end

searchBox:GetPropertyChangedSignal("Text"):Connect(function()
    searchQuery = searchBox.Text:lower():match("^%s*(.-)%s*$") or ""
    renderPage()
end)

-- Window drag: the title strip is the drag handle.
local dragBar = newInstance("TextButton", {
    Name = "DragBar",
    Position = UDim2.new(0, 60, 0, 0),
    Size = UDim2.new(1, -60, 0, 14),
    BackgroundTransparency = 1,
    Text = "",
    AutoButtonColor = false,
    ZIndex = 10,
}, main)
-- The narrow top edge is the drag handle; it stays clear of the tab buttons.
dragBar.Size = UDim2.new(1, -60, 0, 14)
dragBar.BackgroundTransparency = 1
dragBar.Activated:Connect(function() end)
dragBar.InputBegan:Connect(function(input)
    if input.UserInputType == Enum.UserInputType.MouseButton1 or input.UserInputType == Enum.UserInputType.Touch then
        draggingWindow = true
        dragStart = input.Position
        windowStart = main.Position
        dragInput = input
    end
end)
connectManaged(UserInputService.InputChanged, function(input)
    if activeSlider and (input.UserInputType == Enum.UserInputType.MouseMovement or input.UserInputType == Enum.UserInputType.Touch) then
        activeSlider.updateAt(input.Position)
    end
    if draggingWindow and (input.UserInputType == Enum.UserInputType.MouseMovement or input.UserInputType == Enum.UserInputType.Touch) then
        local delta = input.Position - dragStart
        main.Position = UDim2.new(windowStart.X.Scale, windowStart.X.Offset + delta.X, windowStart.Y.Scale, windowStart.Y.Offset + delta.Y)
    end
end)
connectManaged(UserInputService.InputEnded, function(input)
    if input.UserInputType == Enum.UserInputType.MouseButton1 or input.UserInputType == Enum.UserInputType.Touch then
        draggingWindow = false
        dragInput = nil
        activeSlider = nil
    end
end)

-- Hotkeys only flip their matching UI values. They do not invoke game behavior.
local hotkeyToSetting = {
    [Enum.KeyCode.E] = "combat_silent_aim",
    [Enum.KeyCode.R] = "combat_ragebot",
    [Enum.KeyCode.X] = "combat_desync",
    [Enum.KeyCode.F] = "move_fly",
    [Enum.KeyCode.Q] = "combat_aimbot",
    [Enum.KeyCode.B] = "combat_triggerbot",
    [Enum.KeyCode.V] = "visual_esp",
}
connectManaged(UserInputService.InputBegan, function(input, gameProcessed)
    if gameProcessed or UserInputService:GetFocusedTextBox() then return end
    local key = hotkeyToSetting[input.KeyCode]
    if key then
        setValue(key, not settings[key])
        for _, updaters in pairs(valueUpdaters) do
            for _, update in ipairs(updaters) do pcall(update) end
        end
    end
    if input.KeyCode == Enum.KeyCode.LeftAlt or input.KeyCode == Enum.KeyCode.RightShift then
        main.Visible = not main.Visible
        settings.__menu = main.Visible
        updateKeybinds()
    end
end)

-- Make the top watermark and keybind panel independently draggable too.
local function makePanelDraggable(panel, handle)
    local moveConnection
    handle.InputBegan:Connect(function(input)
        if input.UserInputType ~= Enum.UserInputType.MouseButton1 and input.UserInputType ~= Enum.UserInputType.Touch then return end
        local origin = input.Position
        local original = panel.Position
        local moveConn, endConn
        moveConn = connectManaged(UserInputService.InputChanged, function(changed)
            if changed.UserInputType == Enum.UserInputType.MouseMovement or changed.UserInputType == Enum.UserInputType.Touch then
                local delta = changed.Position - origin
                panel.Position = UDim2.new(original.X.Scale, original.X.Offset + delta.X, original.Y.Scale, original.Y.Offset + delta.Y)
            end
        end)
        endConn = connectManaged(UserInputService.InputEnded, function(ended)
            if ended.UserInputType == Enum.UserInputType.MouseButton1 or ended.UserInputType == Enum.UserInputType.Touch then
                moveConn:Disconnect()
                endConn:Disconnect()
            end
        end)
    end)
end
makePanelDraggable(watermark, watermark)
makePanelDraggable(keyPanel, keyHeader)

-- Close dropdowns and refresh the little live status panel when the UI first appears.
updateKeybinds()
rebuildTabs()
renderPage()

-- Tiny keyboard hint in the bottom of the sidebar.
local shortcut = makeLabel(sidebar, "RSHIFT\nHIDE", UDim2.new(1, -6, 0, 30), UDim2.new(0, 3, 1, -40), 8, COLORS.Muted, Enum.TextXAlignment.Center)
shortcut.TextYAlignment = Enum.TextYAlignment.Center

notify("UI loaded · visual controls only")
