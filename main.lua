--[[
    عمو تشريب Hub - Mobile v26 SMART
    ==================================
    - Smart zombie: 2+ killers OR 2+ zombies → auto kill all
    - Zombie at 50: kill all instead of reset
    - Smart sheriff: 2+ murderers → collect 50 → kill nearest murderer
--]]

local Players = game:GetService("Players")
local RunService = game:GetService("RunService")
local VirtualUser = game:GetService("VirtualUser")
local CoreGui = game:GetService("CoreGui")

local LocalPlayer = Players.LocalPlayer

-- ═══════════════════════════════════════
-- CONFIG
-- ═══════════════════════════════════════
local walkSpeed = 27
local FLY_SPEED = 27
local HOVER_HEIGHT = 3
local COLLECT_RADIUS = 6
local COIN_LIMIT = 50
local SMART_THRESHOLD = 2  -- عدد القتلة/الزومبي للتفعيل التلقائي

-- ═══════════════════════════════════════
-- STATES
-- ═══════════════════════════════════════
local farmActive = false
local flingActive = true
local zombieKillActive = true
local smartZombieActive = true    -- الزومبي الذكي
local smartSheriffActive = true   -- الشريف الذكي
local antiAFKActive = true
local pendingRespawn = false
local lastResetTime = 0
local stuckCoins = {}
local firstTeleportDone = false
local cachedMurderer = nil
local collectedCoins = 0
local lastCoinCount = 0
local currentCoin = nil
local sheriffKillInProgress = false

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
-- ROLE DETECTION
-- ═══════════════════════════════════════
local function isLocalZombie()
    local char = LocalPlayer.Character
    if not char then return false end
    for _, attr in ipairs({"Role", "role", "GameRole", "Team", "Class"}) do
        local r = LocalPlayer:GetAttribute(attr)
        if r and tostring(r):lower():find("zombie") then return true end
    end
    if LocalPlayer.Team and LocalPlayer.Team.Name:lower():find("zombie") then return true end
    -- Check tools
    local bp = LocalPlayer:FindFirstChild("Backpack")
    local searchIn = {char, bp}
    for _, container in ipairs(searchIn) do
        if container then
            for _, tool in ipairs(container:GetChildren()) do
                if tool:IsA("Tool") then
                    local tn = tool.Name:lower()
                    if tn:find("zombie") or tn:find("infect") or tn:find("claw") then return true end
                end
            end
        end
    end
    -- Skin color
    local torso = char:FindFirstChild("Torso") or char:FindFirstChild("UpperTorso")
    if torso and torso:IsA("BasePart") then
        local r, g, b = torso.Color.R, torso.Color.G, torso.Color.B
        if g > 0.4 and g > r * 1.5 and g > b * 1.5 then return true end
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

local function isPlayerMurderer(player)
    if not player or player == LocalPlayer then return false end
    local bp = player:FindFirstChild("Backpack")
    if bp then
        for _, item in ipairs(bp:GetChildren()) do
            if item.Name == "Knife" then return true end
        end
    end
    local char = player.Character
    if char then
        for _, item in ipairs(char:GetChildren()) do
            if item:IsA("Tool") and item.Name == "Knife" then return true end
        end
    end
    for _, attr in ipairs({"Role", "role", "GameRole"}) do
        local r = player:GetAttribute(attr)
        if r and tostring(r):lower():find("murder") then return true end
    end
    return false
end

local function isLocalSheriff()
    local bp = LocalPlayer:FindFirstChild("Backpack")
    if bp then
        for _, item in ipairs(bp:GetChildren()) do
            if item.Name == "Gun" then return true end
        end
    end
    local char = LocalPlayer.Character
    if char then
        for _, item in ipairs(char:GetChildren()) do
            if item:IsA("Tool") and item.Name == "Gun" then return true end
        end
    end
    return false
end

-- ═══════════════════════════════════════
-- COUNTERS
-- ═══════════════════════════════════════
local function countMurderers()
    local count = 0
    for _, player in ipairs(Players:GetPlayers()) do
        if player ~= LocalPlayer and isPlayerMurderer(player) then
            count = count + 1
        end
    end
    return count
end

local function countZombies()
    local count = 0
    for _, player in ipairs(Players:GetPlayers()) do
        if player ~= LocalPlayer and isPlayerZombie(player) then
            count = count + 1
        end
    end
    return count
end

-- ═══════════════════════════════════════
-- FLING HELPERS
-- ═══════════════════════════════════════
local function flingPlayer(player)
    if not player or player == LocalPlayer then return end
    local char = player.Character
    if not char then return end
    local hrp = char:FindFirstChild("HumanoidRootPart")
    local hum = char:FindFirstChildOfClass("Humanoid")
    if not hrp or not hum or hum.Health <= 0 then return end

    pcall(function()
        hum.PlatformStand = true
        hrp.CanCollide = false
        hrp.AssemblyLinearVelocity = Vector3.new(
            math.random(-500, 500),
            500000,
            math.random(-500, 500)
        )
        hrp.Velocity = Vector3.new(0, 500000, 0)
    end)
end

local function killAllExcept(shouldSkipFn)
    for _, player in ipairs(Players:GetPlayers()) do
        if player == LocalPlayer then continue end
        if shouldSkipFn and shouldSkipFn(player) then continue end
        flingPlayer(player)
    end
end

local function zombieKillAll()
    -- Zombie kills everyone except other zombies
    killAllExcept(isPlayerZombie)
end

-- ═══════════════════════════════════════
-- SMART ZOMBIE AUTO-KILL
-- ═══════════════════════════════════════
RunService.Heartbeat:Connect(function()
    if not smartZombieActive or pendingRespawn then return end
    if not isLocalZombie() then return end

    local murdererCount = countMurderers()
    local zombieCount = countZombies()

    -- Auto-kill if 2+ murderers OR 2+ zombies
    if murdererCount >= SMART_THRESHOLD or zombieCount >= SMART_THRESHOLD then
        zombieKillAll()
    end
end)

-- ═══════════════════════════════════════
-- ZOMBIE KILL ALL BUTTON (always kills)
-- ═══════════════════════════════════════
RunService.Heartbeat:Connect(function()
    if not zombieKillActive or pendingRespawn then return end
    if not isLocalZombie() then return end
    -- This only triggers via the button or at 50 coins
    -- Smart auto-kill is separate (above)
end)

-- ═══════════════════════════════════════
-- SHERIFF SMART: Kill nearest murderer
-- ═══════════════════════════════════════
local function killNearestMurderer()
    if sheriffKillInProgress then return end
    sheriffKillInProgress = true

    local myChar = LocalPlayer.Character
    local myHRP = myChar and myChar:FindFirstChild("HumanoidRootPart")
    if not myHRP then
        sheriffKillInProgress = false
        return
    end

    -- Find nearest murderer
    local nearest = nil
    local nearestDist = math.huge
    for _, player in ipairs(Players:GetPlayers()) do
        if player == LocalPlayer then continue end
        if not isPlayerMurderer(player) then continue end
        local char = player.Character
        if char then
            local hrp = char:FindFirstChild("HumanoidRootPart")
            local hum = char:FindFirstChildOfClass("Humanoid")
            if hrp and hum and hum.Health > 0 then
                local d = (myHRP.Position - hrp.Position).Magnitude
                if d < nearestDist then
                    nearestDist = d
                    nearest = player
                end
            end
        end
    end

    if not nearest then
        sheriffKillInProgress = false
        return
    end

    -- Teleport to murderer
    local targetChar = nearest.Character
    local targetHRP = targetChar and targetChar:FindFirstChild("HumanoidRootPart")
    if not targetHRP then
        sheriffKillInProgress = false
        return
    end

    myHRP.CFrame = targetHRP.CFrame + Vector3.new(0, 0, 4)
    task.wait(0.2)

    -- Fling murderer (kill)
    flingPlayer(nearest)

    -- Keep flinging for 2 seconds
    for i = 1, 40 do
        local h = nearest.Character and nearest.Character:FindFirstChildOfClass("Humanoid")
        if not h or h.Health <= 0 then break end
        flingPlayer(nearest)
        task.wait(0.05)
    end

    task.wait(1)
    sheriffKillInProgress = false
end

-- ═══════════════════════════════════════
-- MURDERER SCAN (for regular fling)
-- ═══════════════════════════════════════
task.spawn(function()
    while true do
        task.wait(0.3)
        -- Find any murderer
        for _, player in ipairs(Players:GetPlayers()) do
            if player ~= LocalPlayer and isPlayerMurderer(player) then
                cachedMurderer = player
                break
            end
        end
    end
end)

-- ═══════════════════════════════════════
-- REGULAR FLING MURDERER
-- ═══════════════════════════════════════
RunService.Heartbeat:Connect(function()
    if not flingActive or pendingRespawn then return end
    if sheriffKillInProgress then return end
    if not cachedMurderer or cachedMurderer == LocalPlayer then return end
    flingPlayer(cachedMurderer)
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
        if map.Name ~= "Lobby" and map:FindFirstChild("CoinContainer") then
            for _, coin in ipairs(map.CoinContainer:GetChildren()) do
                if coin:IsA("BasePart") and coin:FindFirstChild("TouchInterest") then
                    if stuckCoins[coin] ~= true then
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

local function getUICoinCount()
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

-- ═══════════════════════════════════════
-- RESET OR SMART ACTION AT 50
-- ═══════════════════════════════════════
local function handle50Coins()
    if pendingRespawn then return end
    if tick() - lastResetTime < 5 then return end
    pendingRespawn = true
    lastResetTime = tick()

    local char = LocalPlayer.Character
    local hum = char and char:FindFirstChildOfClass("Humanoid")

    -- ═══ ZOMBIE: kill all instead of reset ═══
    if isLocalZombie() and zombieKillActive then
        print("[50] Zombie mode - killing all")
        for i = 1, 60 do  -- 3 seconds of killing
            zombieKillAll()
            task.wait(0.05)
        end
        -- Then reset
        if hum then
            hum.PlatformStand = false
            hum.WalkSpeed = 16
        end
        if hum and hum.Health > 0 then
            pcall(function() hum.Health = 0 end)
        end
        task.wait(3)
        pendingRespawn = false
        stuckCoins = {}
        firstTeleportDone = false
        collectedCoins = 0
        lastCoinCount = 0
        return
    end

    -- ═══ SHERIFF: kill nearest murderer if 2+ exist ═══
    if isLocalSheriff() and smartSheriffActive then
        local murdererCount = countMurderers()
        if murdererCount >= SMART_THRESHOLD then
            print("[50] Sheriff smart - killing nearest murderer")
            killNearestMurderer()
            -- Then reset
            if hum then
                hum.PlatformStand = false
                hum.WalkSpeed = 16
            end
            if hum and hum.Health > 0 then
                pcall(function() hum.Health = 0 end)
            end
            task.wait(3)
            pendingRespawn = false
            stuckCoins = {}
            firstTeleportDone = false
            collectedCoins = 0
            lastCoinCount = 0
            return
        end
    end

    -- ═══ NORMAL RESET ═══
    print("[50] Normal reset")
    if char then
        if hum then
            hum.PlatformStand = false
            hum.WalkSpeed = 16
        end
        for _, part in ipairs(char:GetDescendants()) do
            if part:IsA("BasePart") then part.CanCollide = true end
        end
    end

    -- Fling murderer before reset
    if cachedMurderer and cachedMurderer ~= LocalPlayer and cachedMurderer.Character then
        for i = 1, 60 do
            local h = cachedMurderer.Character:FindFirstChildOfClass("Humanoid")
            if not h or h.Health <= 0 then break end
            flingPlayer(cachedMurderer)
            task.wait(0.05)
        end
    end

    if char then
        if hum and hum.Health > 0 then
            pcall(function() hum.Health = 0 end)
        end
    end
    task.wait(3)
    pendingRespawn = false
    stuckCoins = {}
    firstTeleportDone = false
    collectedCoins = 0
    lastCoinCount = 0
    currentCoin = nil
end

-- ═══════════════════════════════════════
-- FLY LOOP (Stepped - physics before)
-- ═══════════════════════════════════════
RunService.Stepped:Connect(function()
    pcall(function()
        if not farmActive or pendingRespawn then return end

        local char = LocalPlayer.Character
        local hrp = char and char:FindFirstChild("HumanoidRootPart")
        local hum = char and char:FindFirstChildOfClass("Humanoid")
        if not hrp or not hum or hum.Health <= 0 then return end

        -- Count coins
        local coins = getAllCoins()
        local currentCount = #coins
        if lastCoinCount > currentCount and lastCoinCount > 0 then
            collectedCoins = collectedCoins + (lastCoinCount - currentCount)
        end
        if lastCoinCount == 0 and currentCount > 5 then
            collectedCoins = 0
            firstTeleportDone = false
            stuckCoins = {}
        end
        lastCoinCount = currentCount

        -- Check 50
        if collectedCoins >= COIN_LIMIT then
            handle50Coins()
            return
        end
        local uiCur, uiMax = getUICoinCount()
        if uiMax >= 40 and uiCur >= uiMax then
            handle50Coins()
            return
        end

        if currentCount == 0 then return end

        local coin, dist = getNearestCoin()
        if not coin then return end
        currentCoin = coin

        if not firstTeleportDone then
            hrp.CFrame = CFrame.new(coin.Position + Vector3.new(0, HOVER_HEIGHT, 0))
            hrp.Velocity = Vector3.zero
            hrp.AssemblyLinearVelocity = Vector3.zero
            firstTeleportDone = true
            return
        end

        if hrp.Position.Y < -50 then
            hrp.CFrame = CFrame.new(coin.Position + Vector3.new(0, HOVER_HEIGHT, 0))
            hrp.Velocity = Vector3.zero
            return
        end

        hum.PlatformStand = true
        hum.WalkSpeed = 0
        hum.JumpPower = 0
        hum.AutoRotate = false

        for _, part in ipairs(char:GetDescendants()) do
            if part:IsA("BasePart") and part.Name ~= "HumanoidRootPart" then
                if part.CanCollide then part.CanCollide = false end
            end
        end
        hrp.CanCollide = true

        local target = coin.Position + Vector3.new(0, HOVER_HEIGHT, 0)
        local delta = target - hrp.Position
        if delta.Magnitude > 0.5 then
            local step = math.min(FLY_SPEED / 60, delta.Magnitude)
            hrp.CFrame = CFrame.new(hrp.Position + delta.Unit * step)
        end
        hrp.Velocity = Vector3.zero
        hrp.AssemblyLinearVelocity = Vector3.zero
    end)
end)

-- ═══════════════════════════════════════
-- COLLECT LOOP (Heartbeat - after physics)
-- ═══════════════════════════════════════
RunService.Heartbeat:Connect(function()
    pcall(function()
        if not farmActive or pendingRespawn then return end
        if sheriffKillInProgress then return end

        local char = LocalPlayer.Character
        local hrp = char and char:FindFirstChild("HumanoidRootPart")
        local hum = char and char:FindFirstChildOfClass("Humanoid")
        if not hrp or not hum or hum.Health <= 0 then return end

        local coin = currentCoin
        if not coin or not coin.Parent or not coin:IsDescendantOf(workspace) then return end

        local dist = (hrp.Position - coin.Position).Magnitude
        if dist > COLLECT_RADIUS then return end

        hum.PlatformStand = false
        hum.WalkSpeed = 0
        hum.JumpPower = 0

        hrp.CFrame = CFrame.new(coin.Position)
        hrp.Velocity = Vector3.zero
        hrp.AssemblyLinearVelocity = Vector3.zero

        pcall(function()
            firetouchinterest(hrp, coin, 0)
            firetouchinterest(hrp, coin, 1)
        end)

        for _, part in ipairs(char:GetDescendants()) do
            if part:IsA("BasePart") and part ~= hrp then
                pcall(function()
                    firetouchinterest(part, coin, 0)
                    firetouchinterest(part, coin, 1)
                end)
            end
        end

        if not stuckCoins[coin] then
            stuckCoins[coin] = tick()
        elseif type(stuckCoins[coin]) == "number" and tick() - stuckCoins[coin] > 2 then
            stuckCoins[coin] = true
        end
    end)
end)

-- ═══════════════════════════════════════
-- GUI
-- ═══════════════════════════════════════
local ScreenGui = Instance.new("ScreenGui")
ScreenGui.Name = "AmoChereebMobile"
ScreenGui.Parent = CoreGui
ScreenGui.ResetOnSpawn = false
ScreenGui.ZIndexBehavior = Enum.ZIndexBehavior.Sibling

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
FloatBtn.Active = true
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
MainFrame.Size = UDim2.new(0, 340, 0, 510)
MainFrame.Position = UDim2.new(0.5, -170, 0.5, -255)
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
TitleBar.Size = UDim2.new(1, 0, 0, 50)
TitleBar.BackgroundColor3 = Color3.fromRGB(20, 20, 20)
TitleBar.BorderSizePixel = 0
TitleBar.Active = true
TitleBar.Parent = MainFrame
Instance.new("UICorner", TitleBar).CornerRadius = UDim.new(0, 20)

local Title = Instance.new("TextLabel")
Title.Size = UDim2.new(1, -50, 1, 0)
Title.Position = UDim2.new(0, 15, 0, 0)
Title.BackgroundTransparency = 1
Title.Text = "🥷 عمو تشريب Hub  ⋮⋮"
Title.TextColor3 = Color3.fromRGB(212, 175, 55)
Title.Font = Enum.Font.GothamBold
Title.TextSize = 18
Title.TextXAlignment = Enum.TextXAlignment.Left
Title.Parent = TitleBar

local CloseBtn = Instance.new("TextButton")
CloseBtn.Size = UDim2.new(0, 36, 0, 36)
CloseBtn.Position = UDim2.new(1, -42, 0, 7)
CloseBtn.BackgroundColor3 = Color3.fromRGB(180, 40, 40)
CloseBtn.Text = "✕"
CloseBtn.TextColor3 = Color3.fromRGB(255, 255, 255)
CloseBtn.Font = Enum.Font.GothamBold
CloseBtn.TextSize = 20
CloseBtn.Active = true
CloseBtn.Parent = TitleBar
Instance.new("UICorner", CloseBtn).CornerRadius = UDim.new(0, 18)
CloseBtn.MouseButton1Click:Connect(function() MainFrame.Visible = false end)

-- Drag system
local dragging = false
local dragStartPos = nil
local dragStartFramePos = nil

TitleBar.InputBegan:Connect(function(input)
    if input.UserInputType == Enum.UserInputType.Touch or input.UserInputType == Enum.UserInputType.MouseButton1 then
        dragging = true
        dragStartPos = Vector2.new(input.Position.X, input.Position.Y)
        dragStartFramePos = MainFrame.Position
    end
end)

game:GetService("UserInputService").InputChanged:Connect(function(input)
    if not dragging then return end
    if input.UserInputType == Enum.UserInputType.Touch or input.UserInputType == Enum.UserInputType.MouseMovement then
        local currentPos = Vector2.new(input.Position.X, input.Position.Y)
        local delta = currentPos - dragStartPos
        MainFrame.Position = UDim2.new(
            dragStartFramePos.X.Scale,
            dragStartFramePos.X.Offset + delta.X,
            dragStartFramePos.Y.Scale,
            dragStartFramePos.Y.Offset + delta.Y
        )
    end
end)

game:GetService("UserInputService").InputEnded:Connect(function(input)
    if input.UserInputType == Enum.UserInputType.Touch or input.UserInputType == Enum.UserInputType.MouseButton1 then
        dragging = false
    end
end)

-- Toggle helper
local function makeToggle(yPos, text, icon, defaultState, callback)
    local btn = Instance.new("TextButton")
    btn.Size = UDim2.new(1, -24, 0, 60)
    btn.Position = UDim2.new(0, 12, 0, yPos)
    btn.BackgroundColor3 = defaultState and Color3.fromRGB(25, 70, 25) or Color3.fromRGB(22, 22, 22)
    btn.BorderSizePixel = 2
    btn.BorderColor3 = defaultState and Color3.fromRGB(80, 220, 80) or Color3.fromRGB(50, 50, 50)
    btn.Text = ""
    btn.AutoButtonColor = false
    btn.Active = true
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
    textLbl.TextSize = 14
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
SpeedLabel.Position = UDim2.new(0, 12, 0, 62)
SpeedLabel.BackgroundTransparency = 1
SpeedLabel.Text = "⚡ سرعة التجميع"
SpeedLabel.TextColor3 = Color3.fromRGB(200, 200, 200)
SpeedLabel.Font = Enum.Font.GothamBold
SpeedLabel.TextSize = 14
SpeedLabel.TextXAlignment = Enum.TextXAlignment.Right
SpeedLabel.Parent = MainFrame

local SpeedBox = Instance.new("TextBox")
SpeedBox.Size = UDim2.new(0, 80, 0, 34)
SpeedBox.Position = UDim2.new(1, -100, 0, 62)
SpeedBox.BackgroundColor3 = Color3.fromRGB(22, 22, 22)
SpeedBox.BorderSizePixel = 2
SpeedBox.BorderColor3 = Color3.fromRGB(212, 175, 55)
SpeedBox.Text = tostring(walkSpeed)
SpeedBox.TextColor3 = Color3.fromRGB(212, 175, 55)
SpeedBox.Font = Enum.Font.GothamBold
SpeedBox.TextSize = 16
SpeedBox.Active = true
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

-- Buttons
local FarmBtn = makeToggle(106, "طيران + جمع", "✈️", false, function(state)
    farmActive = state
    if state then
        firstTeleportDone = false
        stuckCoins = {}
        currentCoin = nil
    else
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
        currentCoin = nil
    end
end)

local FlingBtn = makeToggle(176, "فلنك القاتل", "💥", true, function(state)
    flingActive = state
end)

local ZombieBtn = makeToggle(246, "قتل الكل كزومبي", "🧟", true, function(state)
    zombieKillActive = state
end)

local SmartZombieBtn = makeToggle(316, "زومبي ذكي", "🧠", true, function(state)
    smartZombieActive = state
end)

local SmartSheriffBtn = makeToggle(386, "شريف ذكي", "🔫", true, function(state)
    smartSheriffActive = state
end)

local AFKBtn = makeToggle(456, "مكافحة الطرد", "⏳", true, function(state)
    antiAFKActive = state
end)

-- Coin panel
local CoinPanel = Instance.new("Frame")
CoinPanel.Size = UDim2.new(1, -24, 0, 40)
CoinPanel.Position = UDim2.new(0, 12, 0, 522)
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

-- Adjust main frame size (need more height)
MainFrame.Size = UDim2.new(0, 340, 0, 570)
MainFrame.Position = UDim2.new(0.5, -170, 0.5, -285)
CoinPanel.Position = UDim2.new(0, 12, 0, 522)

-- Float button drag
local fbDragging = false
local fbStartPos = nil
local fbStartBtnPos = nil
local fbMoved = false

FloatBtn.InputBegan:Connect(function(input)
    if input.UserInputType == Enum.UserInputType.Touch or input.UserInputType == Enum.UserInputType.MouseButton1 then
        fbDragging = true
        fbStartPos = Vector2.new(input.Position.X, input.Position.Y)
        fbStartBtnPos = FloatBtn.Position
        fbMoved = false
    end
end)

game:GetService("UserInputService").InputChanged:Connect(function(input)
    if not fbDragging then return end
    if input.UserInputType == Enum.UserInputType.Touch or input.UserInputType == Enum.UserInputType.MouseMovement then
        local currentPos = Vector2.new(input.Position.X, input.Position.Y)
        local delta = currentPos - fbStartPos
        if delta.Magnitude > 8 then
            fbMoved = true
            FloatBtn.Position = UDim2.new(
                fbStartBtnPos.X.Scale,
                fbStartBtnPos.X.Offset + delta.X,
                fbStartBtnPos.Y.Scale,
                fbStartBtnPos.Y.Offset + delta.Y
            )
        end
    end
end)

game:GetService("UserInputService").InputEnded:Connect(function(input)
    if input.UserInputType == Enum.UserInputType.Touch or input.UserInputType == Enum.UserInputType.MouseButton1 then
        if fbDragging and not fbMoved then
            MainFrame.Visible = not MainFrame.Visible
        end
        fbDragging = false
    end
end)

-- Coin info update
local function updateCoinInfo()
    local uiCur, uiMax = getUICoinCount()
    local mapCount = #getAllCoins()
    local displayCount = uiCur > 0 and uiCur or collectedCoins
    local displayMax = uiMax > 0 and uiMax or COIN_LIMIT
    local roleTag = ""
    if isLocalZombie() then roleTag = " 🧟"
    elseif isLocalSheriff() then roleTag = " 🔫"
    elseif isPlayerMurderer(LocalPlayer) then roleTag = " 🔪"
    else roleTag = " 👤"
    end
    local murderers = countMurderers()
    local zombies = countZombies()
    CoinInfo.Text = "🪙 " .. displayCount .. "/" .. displayMax .. roleTag ..
                    "  •  قتلة: " .. murderers ..
                    "  •  زومبي: " .. zombies
end

RunService.Heartbeat:Connect(function()
    pcall(updateCoinInfo)
end)

LocalPlayer.CharacterAdded:Connect(function(char)
    task.wait(0.5)
    firstTeleportDone = false
    currentCoin = nil
    sheriffKillInProgress = false
    if not farmActive then
        local hum = char:FindFirstChildOfClass("Humanoid")
        if hum then hum.WalkSpeed = 16 end
    end
end)
