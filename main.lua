--[[
    عمو تشريب Hub - Mobile v16 ULTIMATE
    - Smart reset (only at 50 with verification)
    - Real collection (MoveTo + micro CFrame)
    - Smart fling (repeat until dead)
    - Escape system (dodge murderer + knife)
    - Walk speed 27 (no fly)
--]]

local Players = game:GetService("Players")
local RunService = game:GetService("RunService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local VirtualUser = game:GetService("VirtualUser")
local CoreGui = game:GetService("CoreGui")

local LocalPlayer = Players.LocalPlayer

-- ========== Config ==========
local walkSpeed = 27
local DANGER_DISTANCE = 6
local KNIFE_DANGER = 12
local COLLECT_THRESHOLD = 5

-- ========== States ==========
local farmActive = false
local flingMurdererActive = false
local antiAFKActive = true
local pendingRespawn = false
local lastFlingTime = 0
local flingedThisRound = {}
local lastResetTime = 0
local ignoreCoins = {}
local lastCoinTarget = nil
local lastCoinTime = 0

-- ========== Anti-AFK ==========
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

-- ========== Speed ==========
local function applySpeed()
    local char = LocalPlayer.Character
    if char then
        local hum = char:FindFirstChildOfClass("Humanoid")
        if hum then
            hum.WalkSpeed = walkSpeed
            hum.PlatformStand = false
        end
    end
end

applySpeed()

-- ========== Murderer Detection ==========
local function getMurderer()
    for _, player in ipairs(Players:GetPlayers()) do
        if player == LocalPlayer then continue end
        local char = player.Character
        if char then
            for _, item in ipairs(char:GetDescendants()) do
                if item:IsA("Tool") and item.Name == "Knife" then return player end
            end
        end
    end
    for _, player in ipairs(Players:GetPlayers()) do
        if player == LocalPlayer then continue end
        local bp = player:FindFirstChild("Backpack")
        if bp then
            for _, item in ipairs(bp:GetDescendants()) do
                if item:IsA("Tool") and item.Name == "Knife" then return player end
            end
        end
    end
    for _, obj in ipairs(workspace:GetDescendants()) do
        if obj:IsA("Tool") and obj.Name == "Knife" then
            local parent = obj.Parent
            if parent then
                local plr = Players:GetPlayerFromCharacter(parent)
                if plr and plr ~= LocalPlayer then return plr end
            end
        end
    end
    return nil
end

local function getMurdererDistance()
    local murderer = getMurderer()
    if not murderer or not murderer.Character then return math.huge, nil end
    local myChar = LocalPlayer.Character
    if not myChar then return math.huge, murderer end
    local myHRP = myChar:FindFirstChild("HumanoidRootPart")
    local murdHRP = murderer.Character:FindFirstChild("HumanoidRootPart")
    if not myHRP or not murdHRP then return math.huge, murderer end
    return (myHRP.Position - murdHRP.Position).Magnitude, murderer
end

local function isThrownKnifeNearby()
    local myChar = LocalPlayer.Character
    if not myChar then return false end
    local myHRP = myChar:FindFirstChild("HumanoidRootPart")
    if not myHRP then return false end
    for _, obj in ipairs(workspace:GetChildren()) do
        if obj:IsA("Tool") and obj.Name == "Knife" then
            local handle = obj:FindFirstChild("Handle")
            if handle and handle:IsA("BasePart") then
                if (myHRP.Position - handle.Position).Magnitude < KNIFE_DANGER then
                    return true
                end
            end
        end
    end
    return false
end

-- ========== Fling ==========
local function flingMurderer(murderer)
    if not murderer then return end
    task.spawn(function()
        for attempt = 1, 25 do
            local char = murderer.Character
            if not char then break end
            local hrp = char:FindFirstChild("HumanoidRootPart")
            local hum = char:FindFirstChildOfClass("Humanoid")
            if not hrp or not hum or hum.Health <= 0 then break end

            pcall(function()
                local bv = hrp:FindFirstChild("FlingBV") or Instance.new("BodyVelocity", hrp)
                bv.Name = "FlingBV"
                bv.MaxForce = Vector3.new(math.huge, math.huge, math.huge)
                bv.Velocity = Vector3.new(math.random(-4000, 4000), 90000, math.random(-4000, 4000))
            end)

            pcall(function()
                local bav = hrp:FindFirstChild("FlingBAV") or Instance.new("BodyAngularVelocity", hrp)
                bav.Name = "FlingBAV"
                bav.MaxTorque = Vector3.new(math.huge, math.huge, math.huge)
                bav.AngularVelocity = Vector3.new(999999, 999999, 999999)
            end)

            pcall(function()
                hrp.CFrame = CFrame.new(math.random(-1500, 1500), 18000 + attempt * 1200, math.random(-1500, 1500))
                hum.PlatformStand = true
            end)

            task.wait(0.09)
        end

        pcall(function()
            local hum = murderer.Character and murderer.Character:FindFirstChildOfClass("Humanoid")
            if hum then hum.PlatformStand = false end
        end)
    end)
end

-- Smart continuous fling (repeat until dead)
task.spawn(function()
    while true do
        task.wait(0.2)
        if flingMurdererActive and not pendingRespawn then
            local murderer = getMurderer()
            if murderer and murderer.Character then
                local hum = murderer.Character:FindFirstChildOfClass("Humanoid")
                if hum and hum.Health > 0 then
                    -- First time or repeat every 2 seconds
                    if not flingedThisRound[murderer.UserId] or (tick() - lastFlingTime > 2) then
                        lastFlingTime = tick()
                        flingedThisRound[murderer.UserId] = true
                        print("[Fling] Attacking: " .. murderer.Name)
                        flingMurderer(murderer)
                    end
                end
            end
        end
    end
end)

-- ========== GUI ==========
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
MainFrame.Size = UDim2.new(0, 340, 0, 320)
MainFrame.Position = UDim2.new(0.5, -170, 0.5, -160)
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

local FarmBtn = makeToggle(60, "جمع تلقائي", "🌾", false, function(state)
    farmActive = state
    if not state then
        local char = LocalPlayer.Character
        if char then
            local hum = char:FindFirstChildOfClass("Humanoid")
            if hum then
                hum.PlatformStand = false
                hum.WalkSpeed = walkSpeed
            end
        end
    end
end)

local FlingMurdererBtn = makeToggle(130, "فلنك القاتل", "💥", false, function(state)
    flingMurdererActive = state
    if state then
        lastFlingTime = 0
        -- Instant fling attempt
        task.spawn(function()
            task.wait(0.3)
            local murderer = getMurderer()
            if murderer and murderer.Character then
                local hum = murderer.Character:FindFirstChildOfClass("Humanoid")
                if hum and hum.Health > 0 then
                    flingedThisRound[murderer.UserId] = true
                    lastFlingTime = tick()
                    flingMurderer(murderer)
                    print("[INSTANT] Flinged: " .. murderer.Name)
                end
            end
        end)
    end
end)

local AFKBtn = makeToggle(200, "مكافحة الطرد", "⏳", true, function(state)
    antiAFKActive = state
end)

local CoinPanel = Instance.new("Frame")
CoinPanel.Size = UDim2.new(1, -24, 0, 44)
CoinPanel.Position = UDim2.new(0, 12, 0, 268)
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

-- ========== Helpers ==========
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
                    if not ignoreCoins[coin] then
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
    if not mainGui then return 0, 50 end
    local gameGui = mainGui:FindFirstChild("Game")
    if not gameGui then return 0, 50 end
    local coinBags = gameGui:FindFirstChild("CoinBags")
    if not coinBags then return 0, 50 end
    for _, bag in ipairs(coinBags:GetDescendants()) do
        if bag:IsA("TextLabel") and bag.Name == "Coins" then
            local cur, mx = bag.Text:match("(%d+)/(%d+)")
            if cur and mx then
                return tonumber(cur), tonumber(mx)
            end
        end
    end
    return 0, 50
end

local function isInRound()
    local mainGui = LocalPlayer.PlayerGui:FindFirstChild("MainGUI")
    if not mainGui then return false end
    local gameGui = mainGui:FindFirstChild("Game")
    if not gameGui then return false end
    local timer = gameGui:FindFirstChild("Timer")
    if timer and timer.Visible then return true end
    local earnedXP = gameGui:FindFirstChild("EarnedXP")
    if earnedXP and earnedXP.Visible then return true end
    return false
end

-- ========== Reset ==========
local function doAutoRespawn()
    if pendingRespawn then return end
    if tick() - lastResetTime < 5 then return end
    pendingRespawn = true
    lastResetTime = tick()
    print("[Reset] Triggered")

    local char = LocalPlayer.Character
    if char then
        local hum = char:FindFirstChildOfClass("Humanoid")
        if hum then
            hum.PlatformStand = false
            hum.WalkSpeed = walkSpeed
        end
    end

    -- Fling murderer BEFORE reset
    if flingMurdererActive then
        local murderer = getMurderer()
        if murderer and murderer.Character then
            local murdHum = murderer.Character:FindFirstChildOfClass("Humanoid")
            if murdHum and murdHum.Health > 0 then
                flingMurderer(murderer)
                -- Wait until dead (max 3 sec)
                local startWait = tick()
                while tick() - startWait < 3 do
                    if not murderer.Character then break end
                    local h = murderer.Character:FindFirstChildOfClass("Humanoid")
                    if not h or h.Health <= 0 then break end
                    task.wait(0.2)
                end
            end
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
    flingedThisRound = {}
    ignoreCoins = {}
end

-- Smart reset (verified + in round)
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

-- ========== Escape System ==========
local function findEscapeCoin(murderer)
    local coins = getAllCoins()
    if #coins == 0 then return nil end
    local myHRP = getHRP()
    if not myHRP then return nil end
    local murdHRP = murderer and murderer.Character and murderer.Character:FindFirstChild("HumanoidRootPart")
    if not murdHRP then
        local c = getNearestCoin()
        return c
    end

    local bestCoin, bestScore = nil, -math.huge
    for _, coin in ipairs(coins) do
        local distFromMurderer = (coin.Position - murdHRP.Position).Magnitude
        local distFromMe = (coin.Position - myHRP.Position).Magnitude
        local score = distFromMurderer - (distFromMe * 0.25)
        if score > bestScore then
            bestScore = score
            bestCoin = coin
        end
    end
    return bestCoin
end

-- ========== FARM LOOP (REAL COLLECTION) ==========
task.spawn(function()
    while true do
        task.wait(0.08)
        pcall(function()
            if not farmActive or pendingRespawn then return end

            local char = LocalPlayer.Character
            local hrp = char and char:FindFirstChild("HumanoidRootPart")
            local hum = char and char:FindFirstChildOfClass("Humanoid")
            if not hrp or not hum or hum.Health <= 0 then return end

            hum.PlatformStand = false
            hum.WalkSpeed = walkSpeed
            hum.JumpPower = 50

            -- Restore collision
            for _, part in ipairs(char:GetDescendants()) do
                if part:IsA("BasePart") then
                    if not part.CanCollide then part.CanCollide = true end
                end
            end

            -- ========== DANGER CHECK ==========
            local murdererDist, murderer = getMurdererDistance()
            local knifeDanger = isThrownKnifeNearby()

            if murdererDist < DANGER_DISTANCE or knifeDanger then
                -- 🚨 ESCAPE
                local escapeCoin = findEscapeCoin(murderer)
                if escapeCoin then
                    hum:MoveTo(escapeCoin.Position)
                    return
                end
            end

            -- ========== COLLECT ==========
            local coin, dist = getNearestCoin()
            if not coin then return end

            -- Track coin (if same for > 2 sec, ignore it)
            if lastCoinTarget == coin then
                if tick() - lastCoinTime > 2 then
                    ignoreCoins[coin] = true
                    lastCoinTarget = nil
                    return
                end
            else
                lastCoinTarget = coin
                lastCoinTime = tick()
            end

            -- Walk towards coin
            hum:MoveTo(coin.Position)

            -- Close: micro-step + touch
            if dist < COLLECT_THRESHOLD then
                local dir = coin.Position - hrp.Position
                if dir.Magnitude > 0.1 then
                    -- Small safe step (0.7 stud per frame = 42/sec, safe)
                    local step = math.min(0.7, dir.Magnitude)
                    hrp.CFrame = CFrame.new(hrp.Position + dir.Unit * step)
                end

                -- Fire touch from ALL body parts
                for _, part in ipairs(char:GetDescendants()) do
                    if part:IsA("BasePart") then
                        pcall(function()
                            firetouchinterest(part, coin, 0)
                            firetouchinterest(part, coin, 1)
                        end)
                    end
                end
            end
        end)
    end
end)

-- Speed enforcement
RunService.Heartbeat:Connect(function()
    pcall(function()
        local char = LocalPlayer.Character
        if char and not pendingRespawn then
            local hum = char:FindFirstChildOfClass("Humanoid")
            if hum and hum.WalkSpeed ~= walkSpeed then
                hum.WalkSpeed = walkSpeed
            end
        end
    end)
end)

-- Coin info
local function updateCoinInfo()
    local cur, mx = getCoinCount()
    local count = #getAllCoins()
    CoinInfo.Text = "🪙 " .. cur .. " / " .. mx .. "  •  الخريطة: " .. count
end

RunService.Heartbeat:Connect(function()
    pcall(updateCoinInfo)
end)

-- Respawn
LocalPlayer.CharacterAdded:Connect(function(char)
    task.wait(0.5)
    applySpeed()
    flingedThisRound = {}
    ignoreCoins = {}
    lastCoinTarget = nil
end)
