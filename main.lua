--[[
    عمو تشريب Hub - Mobile v73 AUTO RESET AT 50 COINS
    ==================================================
    - Auto Character Reset when Coins Reach Max (50) (server-validated)
    - Strict Real-Time Validity & Transparency Check (No Ghost Coins)
    - Underground Farm (8 Studs) at Speed 30
    - Precise collection verification (polls GUI after touch)
--]]

local Players = game:GetService("Players")
local RunService = game:GetService("RunService")
local TweenService = game:GetService("TweenService")
local VirtualUser = game:GetService("VirtualUser")
local CoreGui = game:GetService("CoreGui")

if not game:IsLoaded() then
    game.Loaded:Wait()
end

local LocalPlayer = Players.LocalPlayer
while not LocalPlayer do
    task.wait(0.1)
    LocalPlayer = Players.LocalPlayer
end

-- CONFIG
local FARM_SPEED = 30
local UNDER_OFFSET = 8
local COIN_MAX_LIMIT = 50

local farmActive = false
local flingActive = true
local smartRoleActive = true
local antiAFKActive = true

local collectedCoinsCount = 0 -- authoritative, updated from GUI
local coinsCache = {}
local lastCacheUpdate = 0
local currentTargetCoin = nil
local coinTargetStartTime = 0
local blacklistedCoins = {}
local hasResetForMax = false

local function safeParent(instance, parent)
    if instance and parent then
        pcall(function()
            instance.Parent = parent
        end)
    end
end

-- ANTI-AFK
task.spawn(function()
    while true do
        if antiAFKActive then
            pcall(function()
                if VirtualUser then
                    VirtualUser:CaptureController()
                    VirtualUser:ClickButton2(Vector2.new())
                end
            end)
        end
        task.wait(30)
    end
end)

-- STRONG COIN VALIDATION
local function hasTouchTransmitter(part)
    if not part then return false end
    if part:FindFirstChildWhichIsA("TouchTransmitter") then return true end
    if part:FindFirstChild("TouchInterest") then return true end
    return false
end

local function looksCoinLike(part)
    if not part or not part.Name then return false end
    local name = part.Name:lower()
    local parentName = (part.Parent and part.Parent.Name or ""):lower()
    if name:find("coin") or parentName:find("coin") then
        return true
    end
    return false
end

local function isRealAndExistingCoin(part)
    if not part or not part:IsA("BasePart") then
        return false
    end
    if not part:IsDescendantOf(workspace) then
        return false
    end
    -- filter out highly transparent or invisible parts
    if part.Transparency and part.Transparency > 0.5 then
        return false
    end
    -- prefer parts that have touch transmitters or coin-like names/parents
    if hasTouchTransmitter(part) then
        return true
    end
    if looksCoinLike(part) then
        -- accept looser name-based matches but ensure they are visible and in workspace
        return true
    end
    return false
end

-- Read coin count from GUI (authoritative)
local function getGameCoinCount()
    local success, result = pcall(function()
        local mainGui = LocalPlayer.PlayerGui:FindFirstChild("MainGUI")
        if not mainGui then return 0 end

        local gameGui = mainGui:FindFirstChild("Game")
        if not gameGui then return 0 end

        local coinBags = gameGui:FindFirstChild("CoinBags")
        if not coinBags then return 0 end

        for _, bag in ipairs(coinBags:GetDescendants()) do
            if bag:IsA("TextLabel") and bag.Name == "Coins" then
                local num = bag.Text:match("(%d+)")
                if num then
                    return tonumber(num)
                end
            end
        end

        return 0
    end)
    return success and result or 0
end

-- Keep an accurate UI-facing counter (polls GUI often)
task.spawn(function()
    while true do
        local ok, val = pcall(getGameCoinCount)
        if ok then
            collectedCoinsCount = val
        end
        -- If we reached max and haven't reset yet, reset now (authoritative)
        if collectedCoinsCount >= COIN_MAX_LIMIT and not hasResetForMax then
            hasResetForMax = true
            pcall(function()
                local char = LocalPlayer.Character
                if char and char:FindFirstChildOfClass("Humanoid") then
                    char:FindFirstChildOfClass("Humanoid").Health = 0
                end
            end)
        end
        task.wait(0.2)
    end
end)

-- CACHED coin finder with strict filtering and a fallback
local function getValidCoins()
    if tick() - lastCacheUpdate < 0.12 then
        return coinsCache
    end
    lastCacheUpdate = tick()
    coinsCache = {}

    local seen = {}
    pcall(function()
        -- prefer scanning known containers first
        for _, map in ipairs(workspace:GetChildren()) do
            if map and map.Name ~= "Lobby" then
                local container = map:FindFirstChild("CoinContainer") or map:FindFirstChild("Coins")
                if container then
                    for _, child in ipairs(container:GetDescendants()) do
                        if child and child:IsA("BasePart") and not seen[child] and not blacklistedCoins[child] then
                            if isRealAndExistingCoin(child) then
                                table.insert(coinsCache, child)
                                seen[child] = true
                            end
                        end
                    end
                end
            end
        end

        -- fallback: scan all workspace descendants but require strict checks
        if #coinsCache == 0 then
            for _, obj in ipairs(workspace:GetDescendants()) do
                if obj and obj:IsA("BasePart") and not seen[obj] and not blacklistedCoins[obj] then
                    if isRealAndExistingCoin(obj) then
                        table.insert(coinsCache, obj)
                        seen[obj] = true
                    end
                end
            end
        end
    end)
    return coinsCache
end

local function getSmartNearestCoin()
    local char = LocalPlayer.Character
    local hrp = char and char:FindFirstChild("HumanoidRootPart")
    if not hrp then return nil end

    local allCoins = getValidCoins()
    if #allCoins == 0 then return nil end

    local closestCoin = nil
    local shortestDistance = math.huge
    local hrpPos = hrp.Position

    for _, coin in ipairs(allCoins) do
        if coin and coin.Parent and coin:IsDescendantOf(workspace) then
            local dist = (hrpPos - coin.Position).Magnitude
            if dist < shortestDistance then
                shortestDistance = dist
                closestCoin = coin
            end
        end
    end
    return closestCoin
end

local function cleanupPhysics()
    pcall(function()
        local char = LocalPlayer.Character
        if not char then return end
        local hrp = char:FindFirstChild("HumanoidRootPart")
        local hum = char:FindFirstChildOfClass("Humanoid")
        if hrp then
            hrp.AssemblyLinearVelocity = Vector3.zero
            hrp.AssemblyAngularVelocity = Vector3.zero
        end
        if hum then
            hum.PlatformStand = false
        end
    end)
end

LocalPlayer.CharacterAdded:Connect(function()
    task.wait(1)
    cleanupPhysics()
    blacklistedCoins = {}
    hasResetForMax = false
    currentTargetCoin = nil
end)

local function triggerUndergroundTouch(coin, char, hrp)
    if not coin or not coin.Parent or not hrp then return false end
    local ok = pcall(function()
        -- Touch with HRP and all body parts; smaller delays between calls for reliability
        firetouchinterest(hrp, coin, 0)
        firetouchinterest(hrp, coin, 1)
        for _, part in ipairs(char:GetChildren()) do
            if part:IsA("BasePart") then
                firetouchinterest(part, coin, 0)
                firetouchinterest(part, coin, 1)
            end
        end
    end)
    return ok
end

-- Attempt to collect a coin and verify server increment; returns true if collection confirmed
local function attemptCollectCoin(coin, char, hrp)
    if not coin or not coin.Parent or not char or not hrp then
        return false
    end

    -- record coin count before touching
    local before = getGameCoinCount()
    -- attempt touch sequence
    pcall(function()
        -- do a couple of quick touch attempts with tiny waits for robustness
        triggerUndergroundTouch(coin, char, hrp)
        task.wait(0.05)
        triggerUndergroundTouch(coin, char, hrp)
    end)

    -- poll GUI for a short window to confirm server-side collection
    local deadline = tick() + 0.8
    while tick() < deadline do
        local now = getGameCoinCount()
        if now and now > before then
            -- confirmed collection
            collectedCoinsCount = now
            -- if reached limit, reset once
            if collectedCoinsCount >= COIN_MAX_LIMIT and not hasResetForMax then
                hasResetForMax = true
                pcall(function()
                    local h = char:FindFirstChildOfClass("Humanoid")
                    if h then h.Health = 0 end
                end)
            end
            return true
        end
        task.wait(0.08)
    end

    -- failed to confirm collection -> treat as ghost coin
    blacklistedCoins[coin] = true
    return false
end

-- MAIN FARM LOOP
RunService.Heartbeat:Connect(function(dt)
    pcall(function()
        if not farmActive then return end

        -- ensure we keep authoritative count updated
        collectedCoinsCount = getGameCoinCount()

        -- auto-reset if somehow reached limit outside collection sequence
        if collectedCoinsCount >= COIN_MAX_LIMIT and not hasResetForMax then
            hasResetForMax = true
            pcall(function()
                local char = LocalPlayer.Character
                if char and char:FindFirstChildOfClass("Humanoid") then
                    char:FindFirstChildOfClass("Humanoid").Health = 0
                end
            end)
            return
        end

        local char = LocalPlayer.Character
        local hrp = char and char:FindFirstChild("HumanoidRootPart")
        local hum = char and char:FindFirstChildOfClass("Humanoid")
        if not hrp or not hum or hum.Health <= 0 then return end

        local allCoins = getValidCoins()
        if #allCoins == 0 then
            blacklistedCoins = {}
            currentTargetCoin = nil
            cleanupPhysics()
            return
        end

        -- validate current target
        if currentTargetCoin then
            if not currentTargetCoin.Parent or not currentTargetCoin:IsDescendantOf(workspace) then
                currentTargetCoin = nil
            end
        end

        hum:SetStateEnabled(Enum.HumanoidStateType.FallingDown, false)
        hum.PlatformStand = true
        for _, part in ipairs(char:GetDescendants()) do
            if part:IsA("BasePart") then part.CanCollide = false end
        end

        local coin = getSmartNearestCoin()
        if coin then
            -- skip invalid coin
            if not coin.Parent or not coin:IsDescendantOf(workspace) or coin.Transparency > 0.8 then
                blacklistedCoins[coin] = true
                currentTargetCoin = nil
                return
            end

            -- start tracking a new target
            if coin ~= currentTargetCoin then
                currentTargetCoin = coin
                coinTargetStartTime = tick()
            else
                -- if stuck too long on same coin, blacklist and move on
                if tick() - coinTargetStartTime > 0.8 then
                    blacklistedCoins[coin] = true
                    currentTargetCoin = nil
                    return
                end
            end

            -- move under the coin smoothly (underground)
            local targetPos = Vector3.new(coin.Position.X, coin.Position.Y - UNDER_OFFSET, coin.Position.Z)
            local delta = targetPos - hrp.Position
            local moveStep = math.min(delta.Magnitude, FARM_SPEED * dt)
            if delta.Magnitude > 0.05 then
                hrp.CFrame = CFrame.new(hrp.Position + delta.Unit * moveStep)
            else
                hrp.CFrame = CFrame.new(targetPos)
            end

            hrp.AssemblyLinearVelocity = Vector3.zero
            hrp.AssemblyAngularVelocity = Vector3.zero

            -- only attempt collection when very close vertically/horizontally
            if (hrp.Position - Vector3.new(coin.Position.X, hrp.Position.Y, coin.Position.Z)).Magnitude <= 1.5 then
                local collected = attemptCollectCoin(coin, char, hrp)
                if collected then
                    -- successful: clear blacklist for this coin (it may be removed server-side)
                    blacklistedCoins[coin] = nil
                    currentTargetCoin = nil
                    return
                else
                    -- failed: coin already blacklisted inside attemptCollectCoin
                    currentTargetCoin = nil
                    return
                end
            end
        end
    end)
end)

-- UI (keeps showing authoritative collectedCoinsCount)
local ScreenGui = Instance.new("ScreenGui")
ScreenGui.Name = "AmoChereebUltimateV73"
ScreenGui.ResetOnSpawn = false
ScreenGui.IgnoreGuiInset = true
safeParent(ScreenGui, CoreGui)

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

local FloatImg = Instance.new("ImageLabel")
FloatImg.Size = UDim2.new(1, 0, 1, 0)
FloatImg.BackgroundTransparency = 1
FloatImg.Image = "rbxassetid://13214811808"
FloatImg.Parent = FloatBtn
Instance.new("UICorner", FloatImg).CornerRadius = UDim.new(1, 0)

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

local TitleBar = Instance.new("Frame")
TitleBar.Size = UDim2.new(1, 0, 0, 48)
TitleBar.BackgroundColor3 = Color3.fromRGB(20, 20, 26)
TitleBar.Parent = MainFrame

local TitleText = Instance.new("TextLabel")
TitleText.Size = UDim2.new(1, -50, 1, 0)
TitleText.Position = UDim2.new(0, 15, 0, 0)
TitleText.BackgroundTransparency = 1
TitleText.Text = "⚡ عمو تشريب Hub - v73"
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

-- UI updater: reads authoritative collectedCoinsCount
task.spawn(function()
    while true do
        pcall(function()
            local count = math.min(collectedCoinsCount or 0, COIN_MAX_LIMIT)
            CoinLabel.Text = "العملات المجمعة: " .. tostring(count) .. " / " .. tostring(COIN_MAX_LIMIT) .. " 🪙"
            local percent = math.clamp(count / COIN_MAX_LIMIT, 0, 1)
            TweenService:Create(ProgressBarFill, TweenInfo.new(0.18), {Size = UDim2.new(percent, 0, 1, 0)}):Play()
        end)
        task.wait(0.18)
    end
end)

local Container = Instance.new("Frame")
Container.Size = UDim2.new(1, -30, 0, 150)
Container.Position = UDim2.new(0, 15, 0, 130)
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

createToggle(0, "تجميع تحت الأرض (سرعة 30)", "🪙", false, function(st)
    farmActive = st
    if not st then cleanupPhysics() end
end)

createToggle(55, "فلنج القاتل التلقائي", "🌪️", true, function(st) flingActive = st end)
createToggle(110, "الحماية والنظام الذكي", "🧠", true, function(st) smartRoleActive = st end)

local isOpen = false
local function toggleUI()
    isOpen = not isOpen
    if isOpen then
        MainFrame.Visible = true
        MainFrame:TweenSize(UDim2.new(0, 320, 0, 310), Enum.EasingDirection.Out, Enum.EasingStyle.Back, 0.3, true)
    else
        MainFrame:TweenSize(UDim2.new(0, 0, 0, 0), Enum.EasingDirection.In, Enum.EasingStyle.Quad, 0.2, true, function()
            MainFrame.Visible = false
        end)
    end
end

FloatBtn.MouseButton1Click:Connect(toggleUI)
CloseBtn.MouseButton1Click:Connect(toggleUI)
