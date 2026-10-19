--[[
    عمو تشريب Hub - Mobile v21 FINAL-FIX
    =====================================
    - FLING: continuous velocity every frame (guaranteed kill)
    - AUTO-FLING: on from start (server join)
    - TELEPORT: instant to first coin
    - FALL-FIX: HRP collidable + recovery teleport
    - RESET: flings murderer before reset at 50
--]]

local Players = game:GetService("Players")
local RunService = game:GetService("RunService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local VirtualUser = game:GetService("VirtualUser")
local CoreGui = game:GetService("CoreGui")

local LocalPlayer = Players.LocalPlayer

-- ═══════════════════════════════════════
-- CONFIG
-- ═══════════════════════════════════════
local walkSpeed = 27
local FLY_SPEED = 27
local HOVER_HEIGHT = 3

-- ═══════════════════════════════════════
-- STATES
-- ═══════════════════════════════════════
local farmActive = false
local flingActive = true   -- ← شغال افتراضياً (auto-fling)
local antiAFKActive = true
local pendingRespawn = false
local lastResetTime = 0
local ignoreCoins = {}
local hasTeleportedToFirstCoin = false

-- ═══════════════════════════════════════
-- ANTI-AFK
-- ═══════════════════════════════════════
task.spawn(function()
    while true do
        if antiAFKActive then
            pcall(function()
                VirtualUser:CaptureController()
                VirtualUser:ClickButton2(Vector2.new())
            end)
        end
        task.wait(55)
    end
end)

-- ═══════════════════════════════════════
-- MURDERER DETECTION (5 methods)
-- ═══════════════════════════════════════
local function getMurderer()
    -- Method 1: Equipped tool in character
    for _, player in ipairs(Players:GetPlayers()) do
        if player == LocalPlayer then continue end
        local char = player.Character
        if char then
            for _, tool in ipairs(char:GetDescendants()) do
                if tool:IsA("Tool") then
                    local tn = tool.Name:lower()
                    if tn:find("knife") or tn:find("murder") then
                        return player
                    end
                end
            end
        end
    end
    -- Method 2: Backpack
    for _, player in ipairs(Players:GetPlayers()) do
        if player == LocalPlayer then continue end
        local bp = player:FindFirstChild("Backpack")
        if bp then
            for _, tool in ipairs(bp:GetDescendants()) do
                if tool:IsA("Tool") then
                    local tn = tool.Name:lower()
                    if tn:find("knife") or tn:find("murder") then
                        return player
                    end
                end
            end
        end
    end
    -- Method 3: Workspace
    for _, obj in ipairs(workspace:GetDescendants()) do
        if obj:IsA("Tool") then
            local tn = obj.Name:lower()
            if tn:find("knife") or tn:find("murder") then
                local parent = obj.Parent
                if parent then
                    local plr = Players:GetPlayerFromCharacter(parent)
                    if plr and plr ~= LocalPlayer then return plr end
                end
            end
        end
    end
    -- Method 4: Attributes
    for _, player in ipairs(Players:GetPlayers()) do
        if player == LocalPlayer then continue end
        for _, attrName in ipairs({"Role", "role", "GameRole", "Team", "Class"}) do
            local role = player:GetAttribute(attrName)
            if role then
                local r = tostring(role):lower()
                if r:find("murder") or r:find("killer") then
                    return player
                end
            end
        end
    end
    -- Method 5: Team name
    for _, player in ipairs(Players:GetPlayers()) do
        if player == LocalPlayer then continue end
        if player.Team then
            local tn = player.Team.Name:lower()
            if tn:find("murder") or tn:find("killer") then
                return player
            end
        end
    end
    return nil
end

-- ═══════════════════════════════════════
-- FLING (velocity EVERY FRAME - GUARANTEED)
-- ═══════════════════════════════════════
RunService.Heartbeat:Connect(function()
    if not flingActive or pendingRespawn then return end

    local murderer = getMurderer()
    if not murderer then return end

    local char = murderer.Character
    if not char then return end

    local hrp = char:FindFirstChild("HumanoidRootPart")
    local hum = char:FindFirstChildOfClass("Humanoid")
    if not hrp or not hum or hum.Health <= 0 then return end

    -- ═══ CORE FLING ═══
    -- Disable collision
    pcall(function()
        for _, part in ipairs(char:GetDescendants()) do
            if part:IsA("BasePart") then
                part.CanCollide = false
            end
        end
    end)

    -- PlatformStand
    pcall(function() hum.PlatformStand = true end)

    -- Massively apply velocity EVERY FRAME (this is the key)
    pcall(function()
        hrp.AssemblyLinearVelocity = Vector3.new(
            math.random(-500, 500),
            500000 + math.random(0, 100000),
            math.random(-500, 500)
        )
    end)

    -- Also set Velocity (older property)
    pcall(function()
        hrp.Velocity = Vector3.new(0, 500000, 0)
    end)

    -- CFrame to sky (backup)
    pcall(function()
        if hrp.Position.Y < 3000 then
            hrp.CFrame = CFrame.new(hrp.Position.X, 5000, hrp.Position.Z)
        end
    end)
end)

-- ═══════════════════════════════════════
-- HELPERS
-- ═══════════════════════════════════════
local function getHRP()
    local char = LocalPlayer.Character
    return char and char:FindFirstChild("HumanoidRootPart")
end

local function getAllCoins()
    local coins = {}
    for _, map in ipairs(workspace:GetChildren()) do
        if map:FindFirstChild("CoinContainer") then
            for _, coin in ipairs(map.CoinContainer:GetChildren()) do
                if coin:IsA("BasePart") and coin:FindFirstChild("TouchInterest") then
                    if ignoreCoins[coin] ~= true then
                        table.insert(coins, coin)
                    end
                end
            end
        end
    end
    return coins
end

local function getNearestCoin()
    local hrp = getHRP()
    if not hrp then return nil, math.huge end
    local closest, dist = nil, math.huge
    for _, coin in ipairs(getAllCoins()) do
        local d = (hrp.Position - coin.Position).Magnitude
        if d < dist then closest, dist = coin, d end
    end
    return closest, dist
end

local function getCoinCount()
    local mainGui = LocalPlayer.PlayerGui:FindFirstChild("MainGUI")
    if not mainGui then return 0, 0 end
    local gameGui = mainGui:FindFirstChild("Game")
    if not gameGui then return 0, 0 end
    local coinBags = gameGui:FindFirstChild("CoinBags")
    if not coinBags then return 0, 0 end
    for _, bag in ipairs(coinBags:GetDescendants()) do
        if bag:IsA("TextLabel") and bag.Name == "Coins" then
            local cur, mx = bag.Text:match("(%d+)/(%d+)")
            if cur and mx then
                return tonumber(cur), tonumber(mx)
            end
        end
    end
    return 0, 0
end

local function isInRound()
    local mainGui = LocalPlayer.PlayerGui:FindFirstChild("MainGUI")
    if not mainGui then return false end
    local gameGui = mainGui:FindFirstChild("Game")
    if not gameGui then return false end
    local timer = gameGui:FindFirstChild("Timer")
    local earnedXP = gameGui:FindFirstChild("EarnedXP")
    return (timer and timer.Visible) or (earnedXP and earnedXP.Visible)
end

-- ═══════════════════════════════════════
-- RESET
-- ═══════════════════════════════════════
local function doAutoRespawn()
    if pendingRespawn then return end
    if tick() - lastResetTime < 5 then return end
    pendingRespawn = true
    lastResetTime = tick()
    print("[RESET] 50 coins reached - flinging murderer then reset")

    local char = LocalPlayer.Character
    if char then
        local hum = char:FindFirstChildOfClass("Humanoid")
        if hum then
            hum.PlatformStand = false
            hum.WalkSpeed = 16
        end
        for _, part in ipairs(char:GetDescendants()) do
            if part:IsA("BasePart") then part.CanCollide = true end
        end
    end

    -- Fling murderer before reset (extra effort)
    local m = getMurderer()
    if m and m.Character then
        for i = 1, 60 do
            local h = m.Character and m.Character:FindFirstChildOfClass("Humanoid")
            if not h or h.Health <= 0 then break end
            local hrp = m.Character:FindFirstChild("HumanoidRootPart")
            if hrp then
                pcall(function()
                    hrp.AssemblyLinearVelocity = Vector3.new(0, 500000, 0)
                    hrp.CFrame = CFrame.new(hrp.Position.X, 5000 + i * 500, hrp.Position.Z)
                end)
            end
            task.wait(0.05)
        end
    end

    if char then
        local hum = char:FindFirstChildOfClass("Humanoid")
        if hum and hum.Health > 0 then
            pcall(function() hum.Health = 0 end)
        end
    end
    task.wait(3)
    pendingRespawn = false
    ignoreCoins = {}
    hasTeleportedToFirstCoin = false
end

task.spawn(function()
    while true do
        task.wait(0.5)
        if farmActive and not pendingRespawn then
            if isInRound() then
                local cur, mx = getCoinCount()
                if mx and mx >= 40 and cur >= mx then
                    doAutoRespawn()
                end
            end
        end
    end
end)

-- ═══════════════════════════════════════
-- GUI
-- ═══════════════════════════════════════
local ScreenGui = Instance.new("ScreenGui")
ScreenGui.Name = "AmoChereebMobile"
ScreenGui.Parent = CoreGui
ScreenGui.ResetOnSpawn = false

local FloatBtn = Instance.new("TextButton")
FloatBtn.Size = UDim2.new(0, 65, 0, 65)
FloatBtn.Position = UDim2.new(1, -85, 0.45, -32)
FloatBtn.BackgroundColor3 = Color3.fromRGB(15, 15, 15)
FloatBtn.BorderSizePixel = 3
FloatBtn.BorderColor3 = Color3.fromRGB(212, 175, 55)
FloatBtn.Text = "🥷"
FloatBtn.TextSize = 30
FloatBtn.Font = Enum.Font.GothamBold
FloatBtn.TextColor3 = Color3.fromRGB(212, 175, 55)
FloatBtn.AutoButtonColor = false
FloatBtn.Parent = ScreenGui
Instance.new("UICorner", FloatBtn).CornerRadius = UDim.new(1, 0)

local floatGlow = Instance.new("UIStroke", FloatBtn)
floatGlow.Thickness = 2
floatGlow.Color = Color3.fromRGB(212, 175, 55)

task.spawn(function()
    while FloatBtn.Parent do
        local b = (math.sin(tick() * 3) + 1) / 2
        floatGlow.Transparency = 0.3 + (1 - b) * 0.5
        task.wait(0.03)
    end
end)

local MainFrame = Instance.new("Frame")
MainFrame.Size = UDim2.new(0, 340, 0, 380)
MainFrame.Position = UDim2.new(0.5, -170, 0.5, -190)
MainFrame.BackgroundColor3 = Color3.fromRGB(10, 10, 10)
MainFrame.BorderSizePixel = 0
MainFrame.Active = true
MainFrame.Visible = false
MainFrame.Parent = ScreenGui
Instance.new("UICorner", MainFrame).CornerRadius = UDim.new(0, 20)

local GoldBorder = Instance.new("Frame")
GoldBorder.Size = UDim2.new(1, 6, 1, 6)
GoldBorder.Position = UDim2.new(0, -3, 0, -3)
GoldBorder.BackgroundColor3 = Color3.fromRGB(212, 175, 55)
GoldBorder.BorderSizePixel = 0
GoldBorder.BackgroundTransparency = 0.25
GoldBorder.Parent = MainFrame
Instance.new("UICorner", GoldBorder).CornerRadius = UDim.new(0, 22)

task.spawn(function()
    while GoldBorder.Parent do
        local b = (math.sin(tick() * 2) + 1) / 2
        GoldBorder.BackgroundColor3 = Color3.fromRGB(180 + math.floor(75 * b), 140 + math.floor(55 * b), 20 + math.floor(60 * b))
        task.wait(0.03)
    end
end)

local TitleBar = Instance.new("Frame")
TitleBar.Size = UDim2.new(1, 0, 0, 44)
TitleBar.BackgroundColor3 = Color3.fromRGB(20, 20, 20)
TitleBar.BorderSizePixel = 0
TitleBar.Parent = MainFrame
Instance.new("UICorner", TitleBar).CornerRadius = UDim.new(0, 20)

local Title = Instance.new("TextLabel")
Title.Size = UDim2.new(1, -50, 1, 0)
Title.Position = UDim2.new(0, 15, 0, 0)
Title.BackgroundTransparency = 1
Title.Text = "🥷 عمو تشريب Hub"
Title.TextColor3 = Color3.fromRGB(212, 175, 55)
Title.Font = Enum.Font.GothamBold
Title.TextSize = 18
Title.TextXAlignment = Enum.TextXAlignment.Left
Title.Parent = TitleBar

local CloseBtn = Instance.new("TextButton")
CloseBtn.Size = UDim2.new(0, 34, 0, 34)
CloseBtn.Position = UDim2.new(1, -40, 0, 5)
CloseBtn.BackgroundColor3 = Color3.fromRGB(180, 40, 40)
CloseBtn.Text = "✕"
CloseBtn.TextColor3 = Color3.fromRGB(255, 255, 255)
CloseBtn.Font = Enum.Font.GothamBold
CloseBtn.TextSize = 18
CloseBtn.Parent = TitleBar
Instance.new("UICorner", CloseBtn).CornerRadius = UDim.new(0, 17)
CloseBtn.MouseButton1Click:Connect(function() MainFrame.Visible = false end)

local function makeDraggable(handle, target)
    local dragging = false
    local dragStart, startPos
    handle.InputBegan:Connect(function(input)
        if input.UserInputType == Enum.UserInputType.Touch or input.UserInputType == Enum.UserInputType.MouseButton1 then
            dragging = true
            dragStart = input.Position
            startPos = target.Position
        end
    end)
    handle.InputChanged:Connect(function(input)
        if dragging and (input.UserInputType == Enum.UserInputType.Touch or input.UserInputType == Enum.UserInputType.MouseMovement) then
            local delta = input.Position - dragStart
            target.Position = UDim2.new(startPos.X.Scale, startPos.X.Offset + delta.X, startPos.Y.Scale, startPos.Y.Offset + delta.Y)
        end
    end)
    handle.InputEnded:Connect(function(input)
        if input.UserInputType == Enum.UserInputType.Touch or input.UserInputType == Enum.UserInputType.MouseButton1 then
            dragging = false
        end
    end)
end
makeDraggable(TitleBar, MainFrame)

local function makeToggle(yPos, text, icon, defaultState, callback)
    local btn = Instance.new("TextButton")
    btn.Size = UDim2.new(1, -24, 0, 60)
    btn.Position = UDim2.new(0, 12, 0, yPos)
    btn.BackgroundColor3 = defaultState and Color3.fromRGB(25, 70, 25) or Color3.fromRGB(22, 22, 22)
    btn.BorderSizePixel = 2
    btn.BorderColor3 = defaultState and Color3.fromRGB(80, 220, 80) or Color3.fromRGB(50, 50, 50)
    btn.Text = ""
    btn.AutoButtonColor = false
    btn.Parent = MainFrame
    Instance.new("UICorner", btn).CornerRadius = UDim.new(0, 14)

    local iconLbl = Instance.new("TextLabel")
    iconLbl.Size = UDim2.new(0, 44, 1, 0)
    iconLbl.Position = UDim2.new(1, -46, 0, 0)
    iconLbl.BackgroundTransparency = 1
    iconLbl.Text = icon
    iconLbl.TextSize = 26
    iconLbl.Font = Enum.Font.GothamBold
    iconLbl.Parent = btn

    local textLbl = Instance.new("TextLabel")
    textLbl.Size = UDim2.new(0, 220, 1, 0)
    textLbl.Position = UDim2.new(0, 12, 0, 0)
    textLbl.BackgroundTransparency = 1
    textLbl.Text = text
    textLbl.TextColor3 = Color3.fromRGB(230, 230, 230)
    textLbl.Font = Enum.Font.GothamBold
    textLbl.TextSize = 15
    textLbl.TextXAlignment = Enum.TextXAlignment.Right
    textLbl.Parent = btn

    local dot = Instance.new("Frame")
    dot.Size = UDim2.new(0, 12, 0, 12)
    dot.Position = UDim2.new(0, 16, 0.5, -6)
    dot.BackgroundColor3 = defaultState and Color3.fromRGB(80, 220, 80) or Color3.fromRGB(100, 100, 100)
    dot.BorderSizePixel = 0
    dot.Parent = btn
    Instance.new("UICorner", dot).CornerRadius = UDim.new(1, 0)

    local state = defaultState
    local function updateVisual()
        btn.BackgroundColor3 = state and Color3.fromRGB(25, 70, 25) or Color3.fromRGB(22, 22, 22)
        btn.BorderColor3 = state and Color3.fromRGB(80, 220, 80) or Color3.fromRGB(50, 50, 50)
        dot.BackgroundColor3 = state and Color3.fromRGB(80, 220, 80) or Color3.fromRGB(100, 100, 100)
    end

    btn.MouseButton1Click:Connect(function()
        state = not state
        updateVisual()
        callback(state)
    end)

    return btn
end

-- Speed
local SpeedLabel = Instance.new("TextLabel")
SpeedLabel.Size = UDim2.new(0, 170, 0, 34)
SpeedLabel.Position = UDim2.new(0, 12, 0, 56)
SpeedLabel.BackgroundTransparency = 1
SpeedLabel.Text = "⚡ سرعة التجميع"
SpeedLabel.TextColor3 = Color3.fromRGB(200, 200, 200)
SpeedLabel.Font = Enum.Font.GothamBold
SpeedLabel.TextSize = 14
SpeedLabel.TextXAlignment = Enum.TextXAlignment.Right
SpeedLabel.Parent = MainFrame

local SpeedBox = Instance.new("TextBox")
SpeedBox.Size = UDim2.new(0, 80, 0, 34)
SpeedBox.Position = UDim2.new(1, -100, 0, 56)
SpeedBox.BackgroundColor3 = Color3.fromRGB(22, 22, 22)
SpeedBox.BorderSizePixel = 2
SpeedBox.BorderColor3 = Color3.fromRGB(212, 175, 55)
SpeedBox.Text = tostring(walkSpeed)
SpeedBox.TextColor3 = Color3.fromRGB(212, 175, 55)
SpeedBox.Font = Enum.Font.GothamBold
SpeedBox.TextSize = 16
SpeedBox.Parent = MainFrame
Instance.new("UICorner", SpeedBox).CornerRadius = UDim.new(0, 10)

SpeedBox.FocusLost:Connect(function()
    local n = tonumber(SpeedBox.Text)
    if n and n >= 16 and n <= 100 then
        walkSpeed = n
        FLY_SPEED = n
    else
        SpeedBox.Text = tostring(walkSpeed)
    end
end)

-- Toggles
local FarmBtn = makeToggle(100, "طيران + جمع", "✈️", false, function(state)
    farmActive = state
    if state then
        hasTeleportedToFirstCoin = false
    else
        local char = LocalPlayer.Character
        if char then
            local hum = char:FindFirstChildOfClass("Humanoid")
            if hum then
                hum.PlatformStand = false
                hum.WalkSpeed = 16
                hum.JumpPower = 50
            end
            for _, part in ipairs(char:GetDescendants()) do
                if part:IsA("BasePart") then part.CanCollide = true end
            end
        end
    end
end)

local FlingBtn = makeToggle(170, "فلنك القاتل", "💥", true, function(state)
    flingActive = state
end)

local AFKBtn = makeToggle(240, "مكافحة الطرد", "⏳", true, function(state)
    antiAFKActive = state
end)

-- Coin info
local CoinPanel = Instance.new("Frame")
CoinPanel.Size = UDim2.new(1, -24, 0, 44)
CoinPanel.Position = UDim2.new(0, 12, 0, 320)
CoinPanel.BackgroundColor3 = Color3.fromRGB(15, 15, 15)
CoinPanel.BorderSizePixel = 2
CoinPanel.BorderColor3 = Color3.fromRGB(212, 175, 55)
CoinPanel.Parent = MainFrame
Instance.new("UICorner", CoinPanel).CornerRadius = UDim.new(0, 12)

local CoinInfo = Instance.new("TextLabel")
CoinInfo.Size = UDim2.new(1, -12, 1, 0)
CoinInfo.Position = UDim2.new(0, 6, 0, 0)
CoinInfo.BackgroundTransparency = 1
CoinInfo.Text = "🪙 0 / 50"
CoinInfo.TextColor3 = Color3.fromRGB(212, 175, 55)
CoinInfo.Font = Enum.Font.GothamBold
CoinInfo.TextSize = 15
CoinInfo.Parent = CoinPanel

local floatDragging = false
local floatDragStart, floatStartPos
local floatMoved = false

FloatBtn.InputBegan:Connect(function(input)
    if input.UserInputType == Enum.UserInputType.Touch or input.UserInputType == Enum.UserInputType.MouseButton1 then
        floatDragging = true
        floatDragStart = input.Position
        floatStartPos = FloatBtn.Position
        floatMoved = false
    end
end)

FloatBtn.InputChanged:Connect(function(input)
    if floatDragging and (input.UserInputType == Enum.UserInputType.Touch or input.UserInputType == Enum.UserInputType.MouseMovement) then
        local delta = input.Position - floatDragStart
        if delta.Magnitude > 8 then
            floatMoved = true
            FloatBtn.Position = UDim2.new(floatStartPos.X.Scale, floatStartPos.X.Offset + delta.X, floatStartPos.Y.Scale, floatStartPos.Y.Offset + delta.Y)
        end
    end
end)

FloatBtn.InputEnded:Connect(function(input)
    if input.UserInputType == Enum.UserInputType.Touch or input.UserInputType == Enum.UserInputType.MouseButton1 then
        floatDragging = false
        if not floatMoved then
            MainFrame.Visible = not MainFrame.Visible
        end
    end
end)

-- ═══════════════════════════════════════
-- FARM LOOP (Stepped - before physics)
-- ═══════════════════════════════════════
RunService.Stepped:Connect(function()
    pcall(function()
        if not farmActive or pendingRespawn then return end

        local char = LocalPlayer.Character
        local hrp = char and char:FindFirstChild("HumanoidRootPart")
        local hum = char and char:FindFirstChildOfClass("Humanoid")
        if not hrp or not hum or hum.Health <= 0 then return end

        -- Force fly state
        hum.PlatformStand = true
        hum.WalkSpeed = 0
        hum.JumpPower = 0
        hum.AutoRotate = false

        -- Noclip ONLY non-HRP parts
        for _, part in ipairs(char:GetDescendants()) do
            if part:IsA("BasePart") and part.Name ~= "HumanoidRootPart" then
                if part.CanCollide then part.CanCollide = false end
            end
        end
        -- HRP stays collidable (prevent fall-through)
        hrp.CanCollide = true

        -- Find coin
        local coin, dist = getNearestCoin()
        if not coin then return end

        -- ═══ TELEPORT TO FIRST COIN (instant) ═══
        if not hasTeleportedToFirstCoin then
            hrp.CFrame = CFrame.new(coin.Position + Vector3.new(0, HOVER_HEIGHT, 0))
            hrp.Velocity = Vector3.zero
            hrp.AssemblyLinearVelocity = Vector3.zero
            hasTeleportedToFirstCoin = true
            return
        end

        -- ═══ RECOVERY: if fell below floor ═══
        if hrp.Position.Y < -50 then
            hrp.CFrame = CFrame.new(coin.Position + Vector3.new(0, HOVER_HEIGHT, 0))
            hrp.Velocity = Vector3.zero
            hrp.AssemblyLinearVelocity = Vector3.zero
            return
        end

        -- ═══ FLY to coin ═══
        local target = coin.Position + Vector3.new(0, HOVER_HEIGHT, 0)
        local delta = target - hrp.Position
        if delta.Magnitude > 1 then
            local step = math.min(FLY_SPEED / 60, delta.Magnitude)
            local newPos = hrp.Position + delta.Unit * step
            hrp.CFrame = CFrame.new(newPos)
        end

        -- Zero velocity (no falling)
        hrp.Velocity = Vector3.zero
        hrp.AssemblyLinearVelocity = Vector3.zero
        hrp.RotVelocity = Vector3.zero

        -- ═══ COLLECT ═══
        if dist < 6 then
            for _, part in ipairs(char:GetDescendants()) do
                if part:IsA("BasePart") then
                    pcall(function()
                        firetouchinterest(part, coin, 0)
                        firetouchinterest(part, coin, 1)
                    end)
                end
            end

            -- Track stuck coin
            if not ignoreCoins[coin] then
                ignoreCoins[coin] = tick()
            elseif type(ignoreCoins[coin]) == "number" and tick() - ignoreCoins[coin] > 1.5 then
                ignoreCoins[coin] = true
            end
        end
    end)
end)

-- Coin info update
local function updateCoinInfo()
    local cur, mx = getCoinCount()
    local count = #getAllCoins()
    CoinInfo.Text = "🪙 " .. cur .. " / " .. (mx > 0 and mx or 50) .. "  •  الخريطة: " .. count
end

RunService.Heartbeat:Connect(function()
    pcall(updateCoinInfo)
end)

-- Respawn handler
LocalPlayer.CharacterAdded:Connect(function(char)
    task.wait(0.5)
    hasTeleportedToFirstCoin = false
    if not farmActive then
        local hum = char:FindFirstChildOfClass("Humanoid")
        if hum then hum.WalkSpeed = 16 end
    end
end)
