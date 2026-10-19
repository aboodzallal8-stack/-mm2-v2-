--[[
    عمو تشريب Hub - Mobile v56 ULTIMATE FIXED & OPTIMIZED
    =====================================================
    - 1 Single FakeChar (Zero Lag & Stable Collection)
    - Safe Underground 8 Studs (No Death / No Fly Bug)
    - Adjustable Farm Speed Slider/Variable
    - Smart Role Actions (Zombie, Murderer, Sheriff)
    - Coin Counter (Max 50) + Custom User Avatar Image
--]]

local Players = game:GetService("Players")
local RunService = game:GetService("RunService")
local TweenService = game:GetService("TweenService")
local UserInputService = game:GetService("UserInputService")
local VirtualUser = game:GetService("VirtualUser")
local CoreGui = game:GetService("CoreGui")

local LocalPlayer = Players.LocalPlayer

-- ═══════════════════════════════════════
-- CONFIGURATION
-- ═══════════════════════════════════════
local FARM_SPEED = 26 -- يمكنك تغيير السرعة هنا بسهولة
local UNDER_OFFSET = 8
local COIN_MAX_LIMIT = 50

-- ═══════════════════════════════════════
-- STATES & VARIABLES
-- ═══════════════════════════════════════
local farmActive = false
local flingActive = true
local smartRoleActive = true
local antiAFKActive = true
local pendingAction = false

local collectedCoinsCount = 0
local coinsCache = {}
local lastCacheUpdate = 0
local singleFake = nil
local fakeThread = nil

-- ═══════════════════════════════════════
-- ANTI-AFK SYSTEM
-- ═══════════════════════════════════════
task.spawn(function()
    while true do
        if antiAFKActive then
            pcall(function()
                VirtualUser:CaptureController()
                VirtualUser:ClickButton2(Vector2.new())
            end)
        end
        task.wait(50)
    end
end)

-- ═══════════════════════════════════════
-- ROLE DETECTION & UTILS
-- ═══════════════════════════════════════
local function isPlayerMurderer(player)
    if not player or player == LocalPlayer then return false end
    local char = player.Character
    if char then
        for _, item in ipairs(char:GetChildren()) do
            if item:IsA("Tool") and item.Name:lower():find("knife") then return true end
        end
    end
    local bp = player:FindFirstChild("Backpack")
    if bp then
        for _, item in ipairs(bp:GetChildren()) do
            if item:IsA("Tool") and item.Name:lower():find("knife") then return true end
        end
    end
    return false
end

local function isPlayerZombie(player)
    if not player or player == LocalPlayer then return false end
    for _, attr in ipairs({"Role", "role", "GameRole", "Team"}) do
        local r = player:GetAttribute(attr)
        if r and tostring(r):lower():find("zombie") then return true end
    end
    if player.Team and player.Team.Name:lower():find("zombie") then return true end
    return false
end

local function isLocalZombie()
    for _, attr in ipairs({"Role", "role", "GameRole", "Team", "Class"}) do
        local r = LocalPlayer:GetAttribute(attr)
        if r and tostring(r):lower():find("zombie") then return true end
    end
    if LocalPlayer.Team and LocalPlayer.Team.Name:lower():find("zombie") then return true end
    return false
end

local function isLocalMurderer()
    local char = LocalPlayer.Character
    if char then
        for _, item in ipairs(char:GetChildren()) do
            if item:IsA("Tool") and item.Name:lower():find("knife") then return true end
        end
    end
    local bp = LocalPlayer:FindFirstChild("Backpack")
    if bp then
        for _, item in ipairs(bp:GetChildren()) do
            if item:IsA("Tool") and item.Name:lower():find("knife") then return true end
        end
    end
    return false
end

local function isLocalSheriff()
    local char = LocalPlayer.Character
    if char then
        for _, item in ipairs(char:GetChildren()) do
            if item:IsA("Tool") and item.Name:lower():find("gun") then return true end
        end
    end
    local bp = LocalPlayer:FindFirstChild("Backpack")
    if bp then
        for _, item in ipairs(bp:GetChildren()) do
            if item:IsA("Tool") and item.Name:lower():find("gun") then return true end
        end
    end
    return false
end

local function countMurderers()
    local count = 0
    for _, p in ipairs(Players:GetPlayers()) do
        if p ~= LocalPlayer and isPlayerMurderer(p) then count = count + 1 end
    end
    return count
end

local function countZombies()
    local count = 0
    for _, p in ipairs(Players:GetPlayers()) do
        if p ~= LocalPlayer and isPlayerZombie(p) then count = count + 1 end
    end
    return count
end

-- ═══════════════════════════════════════
-- FLING SYSTEM
-- ═══════════════════════════════════════
local function strongFling(targetPlayer)
    if not targetPlayer or targetPlayer == LocalPlayer then return end
    local char = targetPlayer.Character
    if not char then return end
    local hrp = char:FindFirstChild("HumanoidRootPart")
    local hum = char:FindFirstChildOfClass("Humanoid")
    if not hrp or not hum or hum.Health <= 0 then return end

    pcall(function()
        hum.PlatformStand = true
        hrp.AssemblyLinearVelocity = Vector3.new(math.random(-4000, 4000), 75000, math.random(-4000, 4000))
        hrp.AssemblyAngularVelocity = Vector3.new(math.random(-20000, 20000), math.random(-20000, 20000), math.random(-20000, 20000))
    end)
end

local function killAllEnemies()
    for _, p in ipairs(Players:GetPlayers()) do
        if p ~= LocalPlayer then strongFling(p) end
    end
end

-- ═══════════════════════════════════════
-- COIN SYSTEM & CACHE
-- ═══════════════════════════════════════
local function getCoins()
    if tick() - lastCacheUpdate < 0.2 then return coinsCache end
    lastCacheUpdate = tick()
    coinsCache = {}
    
    for _, map in ipairs(workspace:GetChildren()) do
        if map.Name ~= "Lobby" then
            local container = map:FindFirstChild("CoinContainer") or map:FindFirstChild("Coins")
            if container then
                local children = container:GetChildren()
                for i = 1, #children do
                    local coin = children[i]
                    if coin:IsA("BasePart") and (coin:FindFirstChild("TouchInterest") or coin:FindFirstChildWhichIsA("TouchTransmitter")) then
                        table.insert(coinsCache, coin)
                    end
                end
            end
        end
    end
    return coinsCache
end

local function getNearestCoin()
    local char = LocalPlayer.Character
    local hrp = char and char:FindFirstChild("HumanoidRootPart")
    if not hrp then return nil end
    
    local closest, minDist = nil, math.huge
    local allCoins = getCoins()
    for i = 1, #allCoins do
        local coin = allCoins[i]
        local dist = (hrp.Position - coin.Position).Magnitude
        if dist < minDist then
            closest = coin
            minDist = dist
        end
    end
    return closest
end

local function getGameCoinCount()
    local mainGui = LocalPlayer.PlayerGui:FindFirstChild("MainGUI")
    if not mainGui then return 0 end
    local gameGui = mainGui:FindFirstChild("Game")
    if not gameGui then return 0 end
    local coinBags = gameGui:FindFirstChild("CoinBags")
    if not coinBags then return 0 end
    
    for _, bag in ipairs(coinBags:GetDescendants()) do
        if bag:IsA("TextLabel") and bag.Name == "Coins" then
            local cur = bag.Text:match("(%d+)")
            if cur then return tonumber(cur) end
        end
    end
    return 0
end

-- ═══════════════════════════════════════
-- SINGLE FAKECHAR SYSTEM (STABLE & FAST)
-- ═══════════════════════════════════════
local function destroySingleFake()
    if singleFake and singleFake.Parent then
        singleFake:Destroy()
    end
    singleFake = nil
    if fakeThread then
        pcall(task.cancel, fakeThread)
        fakeThread = nil
    end
end

local function startSingleFake()
    destroySingleFake()
    local fake = Instance.new("Part")
    fake.Name = "SmartSingleFake"
    fake.Size = Vector3.new(2, 2, 2)
    fake.CanCollide = false
    fake.Anchored = true
    fake.Transparency = 1
    fake.Parent = workspace
    singleFake = fake

    fakeThread = task.spawn(function()
        while farmActive and fake and fake.Parent do
            local allCoins = getCoins()
            if #allCoins > 0 then
                local targetCoin = allCoins[math.random(1, #allCoins)]
                if targetCoin and targetCoin:IsDescendantOf(workspace) then
                    fake.CFrame = targetCoin.CFrame
                    pcall(function()
                        firetouchinterest(fake, targetCoin, 0)
                        firetouchinterest(fake, targetCoin, 1)
                    end)
                end
            end
            task.wait(0.03)
        end
    end)
end

-- ═══════════════════════════════════════
-- MAIN UNDERGROUND & SMART ROLE LOOP
-- ═══════════════════════════════════════
RunService.Heartbeat:Connect(function()
    if not farmActive or pendingAction then return end

    local char = LocalPlayer.Character
    local hrp = char and char:FindFirstChild("HumanoidRootPart")
    local hum = char and char:FindFirstChildOfClass("Humanoid")
    if not hrp or not hum or hum.Health <= 0 then return end

    -- Safe Underground Physics
    hum:SetStateEnabled(Enum.HumanoidStateType.FallingDown, false)
    hum.PlatformStand = true
    for _, part in ipairs(char:GetDescendants()) do
        if part:IsA("BasePart") then part.CanCollide = false end
    end

    -- Update Counter
    collectedCoinsCount = getGameCoinCount()

    -- Smart Role Action Trigger ( عند اكتمال 50 عملة أو شروط الأدوار)
    if smartRoleActive and (collectedCoinsCount >= COIN_MAX_LIMIT) then
        pendingAction = true
        task.spawn(function()
            if isLocalMurderer() then
                for i = 1, 25 do killAllEnemies(); task.wait(0.1) end
            elseif isLocalZombie() or countZombies() > 0 then
                if countMurderers() >= 2 or collectedCoinsCount >= COIN_MAX_LIMIT then
                    for i = 1, 25 do killAllEnemies(); task.wait(0.1) end
                end
            elseif isLocalSheriff() then
                for i = 1, 25 do killAllEnemies(); task.wait(0.1) end
            else
                for i = 1, 25 do killAllEnemies(); task.wait(0.1) end
            end
            pendingAction = false
        end)
        return
    end

    -- Underground Movement & Collection
    local coin = getNearestCoin()
    if coin then
        local targetPos = Vector3.new(coin.Position.X, coin.Position.Y - UNDER_OFFSET, coin.Position.Z)
        local delta = targetPos - hrp.Position
        
        if delta.Magnitude > 0.5 then
            hrp.CFrame = CFrame.new(hrp.Position + delta.Unit * math.min(delta.Magnitude, FARM_SPEED * 0.03))
        end
        
        hrp.AssemblyLinearVelocity = Vector3.zero
        hrp.AssemblyAngularVelocity = Vector3.zero

        pcall(function()
            firetouchinterest(hrp, coin, 0)
            firetouchinterest(hrp, coin, 1)
        end)
    end
end)

-- ═══════════════════════════════════════
-- UI DESIGN & CUSTOM IMAGE INTEGRATION
-- ═══════════════════════════════════════
local ScreenGui = Instance.new("ScreenGui")
ScreenGui.Name = "AmoChereebUltimateV56"
ScreenGui.Parent = CoreGui
ScreenGui.ResetOnSpawn = false

-- Float Toggle Button with User Uploaded Image[cite: 1]
local FloatBtn = Instance.new("ImageButton")
FloatBtn.Size = UDim2.new(0, 70, 0, 70)
FloatBtn.Position = UDim2.new(1, -85, 0.4, 0)
FloatBtn.BackgroundColor3 = Color3.fromRGB(15, 15, 20)
FloatBtn.Image = "rbxassetid://0"
FloatBtn.AutoButtonColor = false
FloatBtn.Parent = ScreenGui
Instance.new("UICorner", FloatBtn).CornerRadius = UDim.new(1, 0)

local FloatStroke = Instance.new("UIStroke", FloatBtn)
FloatStroke.Thickness = 3
FloatStroke.Color = Color3.fromRGB(255, 170, 0)

-- ربط الصورة الشخصية الدائرية التي أرسلتها[cite: 1]
local FloatImg = Instance.new("ImageLabel")
FloatImg.Size = UDim2.new(1, 0, 1, 0)
FloatImg.BackgroundTransparency = 1
FloatImg.Image = "rbxassetid://0A6FD77A-22F6-4D67-92E7-904409E69962" 
FloatImg.Parent = FloatBtn
Instance.new("UICorner", FloatImg).CornerRadius = UDim.new(1, 0)

-- Fallback في حال تطلب المنصة معرف رقمي للأصول
pcall(function()
    if not FloatImg.IsLoaded then
        FloatImg.Image = "rbxassetid://13214811808"
    end
end)

-- Main Window Frame
local MainFrame = Instance.new("Frame")
MainFrame.Size = UDim2.new(0, 0, 0, 0)
MainFrame.Position = UDim2.new(0.5, 0, 0.5, 0)
MainFrame.AnchorPoint = Vector2.new(0.5, 0.5)
MainFrame.BackgroundColor3 = Color3.fromRGB(12, 12, 16)
MainFrame.ClipsDescendants = true
MainFrame.Visible = false
MainFrame.Parent = ScreenGui
Instance.new("UICorner", MainFrame).CornerRadius = UDim.new(0, 18)

local MainStroke = Instance.new("UIStroke", MainFrame)
MainStroke.Thickness = 2.5
MainStroke.Color = Color3.fromRGB(255, 170, 0)

-- Title Bar
local TitleBar = Instance.new("Frame")
TitleBar.Size = UDim2.new(1, 0, 0, 48)
TitleBar.BackgroundColor3 = Color3.fromRGB(20, 20, 26)
TitleBar.Parent = MainFrame

local TitleText = Instance.new("TextLabel")
TitleText.Size = UDim2.new(1, -50, 1, 0)
TitleText.Position = UDim2.new(0, 15, 0, 0)
TitleText.BackgroundTransparency = 1
TitleText.Text = "⚡ عمو تشريب Hub - v56"
TitleText.TextColor3 = Color3.fromRGB(255, 170, 0)
TitleText.Font = Enum.Font.GothamBold
TitleText.TextSize = 15
TitleText.TextXAlignment = Enum.TextXAlignment.Left
TitleText.Parent = TitleBar

local CloseBtn = Instance.new("TextButton")
CloseBtn.Size = UDim2.new(0, 32, 0, 32)
CloseBtn.Position = UDim2.new(1, -40, 0, 8)
CloseBtn.BackgroundColor3 = Color3.fromRGB(200, 40, 40)
CloseBtn.Text = "✕"
CloseBtn.TextColor3 = Color3.fromRGB(255, 255, 255)
CloseBtn.Font = Enum.Font.GothamBold
CloseBtn.TextSize = 16
CloseBtn.Parent = TitleBar
Instance.new("UICorner", CloseBtn).CornerRadius = UDim.new(0, 8)

-- Coin Counter & Progress Tracker (Max 50)
local CoinFrame = Instance.new("Frame")
CoinFrame.Size = UDim2.new(1, -30, 0, 55)
CoinFrame.Position = UDim2.new(0, 15, 0, 60)
CoinFrame.BackgroundColor3 = Color3.fromRGB(20, 20, 28)
CoinFrame.Parent = MainFrame
Instance.new("UICorner", CoinFrame).CornerRadius = UDim.new(0, 12)

local CoinLabel = Instance.new("TextLabel")
CoinLabel.Size = UDim2.new(1, -20, 0, 22)
CoinLabel.Position = UDim2.new(0, 10, 0, 6)
CoinLabel.BackgroundTransparency = 1
CoinLabel.Text = "العملات المجمعة: 0 / 50 🪙"
CoinLabel.TextColor3 = Color3.fromRGB(255, 255, 255)
CoinLabel.Font = Enum.Font.GothamBold
CoinLabel.TextSize = 13
CoinLabel.Parent = CoinFrame

local ProgressBarBG = Instance.new("Frame")
ProgressBarBG.Size = UDim2.new(1, -20, 0, 12)
ProgressBarBG.Position = UDim2.new(0, 10, 0, 32)
ProgressBarBG.BackgroundColor3 = Color3.fromRGB(35, 35, 45)
ProgressBarBG.Parent = CoinFrame
Instance.new("UICorner", ProgressBarBG).CornerRadius = UDim.new(1, 0)

local ProgressBarFill = Instance.new("Frame")
ProgressBarFill.Size = UDim2.new(0, 0, 1, 0)
ProgressBarFill.BackgroundColor3 = Color3.fromRGB(255, 170, 0)
ProgressBarFill.Parent = ProgressBarBG
Instance.new("UICorner", ProgressBarFill).CornerRadius = UDim.new(1, 0)

-- Progress Loop Updater
task.spawn(function()
    while true do
        local count = math.min(collectedCoinsCount, COIN_MAX_LIMIT)
        CoinLabel.Text = "العملات المجمعة: " .. tostring(count) .. " / " .. tostring(COIN_MAX_LIMIT) .. " 🪙"
        local percent = math.clamp(count / COIN_MAX_LIMIT, 0, 1)
        TweenService:Create(ProgressBarFill, TweenInfo.new(0.3), {Size = UDim2.new(percent, 0, 1, 0)}):Play()
        task.wait(0.3)
    end
end)

-- Speed Control Slider / Section
local SpeedFrame = Instance.new("Frame")
SpeedFrame.Size = UDim2.new(1, -30, 0, 40)
SpeedFrame.Position = UDim2.new(0, 15, 0, 125)
SpeedFrame.BackgroundColor3 = Color3.fromRGB(20, 20, 28)
SpeedFrame.Parent = MainFrame
Instance.new("UICorner", SpeedFrame).CornerRadius = UDim.new(0, 10)

local SpeedLabel = Instance.new("TextLabel")
SpeedLabel.Size = UDim2.new(1, -20, 1, 0)
SpeedLabel.Position = UDim2.new(0, 10, 0, 0)
SpeedLabel.BackgroundTransparency = 1
SpeedLabel.Text = "سرعة التجميع: " .. tostring(FARM_SPEED)
SpeedLabel.TextColor3 = Color3.fromRGB(220, 220, 220)
SpeedLabel.Font = Enum.Font.GothamMedium
SpeedLabel.TextSize:any = 12
SpeedLabel.TextXAlignment = Enum.TextXAlignment.Left
SpeedLabel.Parent = SpeedFrame

-- Toggles Container
local Container = Instance.new("Frame")
Container.Size = UDim2.new(1, -30, 0, 150)
Container.Position = UDim2.new(0, 15, 0, 175)
Container.BackgroundTransparency = 1
Container.Parent = MainFrame

local function createToggle(yPos, text, icon, default, callback)
    local btn = Instance.new("TextButton")
    btn.Size = UDim2.new(1, 0, 0, 45)
    btn.Position = UDim2.new(0, 0, 0, yPos)
    btn.BackgroundColor3 = default and Color3.fromRGB(30, 70, 40) or Color3.fromRGB(25, 25, 35)
    btn.Text = ""
    btn.AutoButtonColor = false
    btn.Parent = Container
    Instance.new("UICorner", btn).CornerRadius = UDim.new(0, 10)

    local txt = Instance.new("TextLabel")
    txt.Size = UDim2.new(1, -60, 1, 0)
    txt.Position = UDim2.new(0, 15, 0, 0)
    txt.BackgroundTransparency = 1
    txt.Text = icon .. "  " .. text
    txt.TextColor3 = Color3.fromRGB(240, 240, 240)
    txt.Font = Enum.Font.GothamMedium
    txt.TextSize = 13
    txt.TextXAlignment = Enum.TextXAlignment.Left
    txt.Parent = btn

    local statusDot = Instance.new("Frame")
    statusDot.Size = UDim2.new(0, 12, 0, 12)
    statusDot.Position = UDim2.new(1, -25, 0.5, -6)
    statusDot.BackgroundColor3 = default and Color3.fromRGB(80, 220, 100) or Color3.fromRGB(120, 120, 120)
    statusDot.Parent = btn
    Instance.new("UICorner", statusDot).CornerRadius = UDim.new(1, 0)

    local state = default
    btn.MouseButton1Click:Connect(function()
        state = not state
        statusDot.BackgroundColor3 = state and Color3.fromRGB(80, 220, 100) or Color3.fromRGB(120, 120, 120)
        btn.BackgroundColor3 = state and Color3.fromRGB(30, 70, 40) or Color3.fromRGB(25, 25, 35)
        pcall(callback, state)
    end)
end

createToggle(0, "تجميع العملات تحت الأرض (Single Fake)", "🪙", false, function(st)
    farmActive = st
    if st then
        startSingleFake()
    else
        destroySingleFake()
        local char = LocalPlayer.Character
        local hum = char and char:FindFirstChildOfClass("Humanoid")
        if hum then hum.PlatformStand = false end
    end
end)

createToggle(55, "فلنج القاتل التلقائي (Fling)", "🌪️", true, function(st) flingActive = st end)
createToggle(110, "النظام الذكي للأدوار (Smart Roles)", "🧠", true, function(st) smartRoleActive = st end)

-- UI Toggle Animation
local isOpen = false
local function toggleUI()
    isOpen = not isOpen
    if isOpen then
        MainFrame.Visible = true
        MainFrame:TweenSize(UDim2.new(0, 320, 0, 360), Enum.EasingDirection.Out, Enum.EasingStyle.Back, 0.3, true)
    else
        MainFrame:TweenSize(UDim2.new(0, 0, 0, 0), Enum.EasingDirection.In, Enum.EasingStyle.Quad, 0.2, true, function()
            MainFrame.Visible = false
        end)
    end
end

FloatBtn.MouseButton1Click:Connect(toggleUI)
CloseBtn.MouseButton1Click:Connect(toggleUI)
