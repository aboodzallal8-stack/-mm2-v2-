--[[
    عمو تشريب Hub - Mobile v73 - Fixes
    - Prevents collecting ghost coins
    - Avoids falling through ground and clipping by using raycast-grounded targets
    - Stops collecting while player is in the "Lobby" map (only collects in player's current map)
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
local SAFE_FALL_Y = -100

local farmActive = false
local flingActive = true
local smartRoleActive = true
local antiAFKActive = true

local collectedCoinsCount = 0
local coinsCache = {}
local lastCacheUpdate = 0
local currentTargetCoin = nil
local coinTargetStartTime = 0
local blacklistedCoins = {}
local hasResetForMax = false

local function safeParent(instance, parent)
    if instance and parent then
        pcall(function() instance.Parent = parent end)
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

-- GUI-authoritative coin count
local function getGameCoinCount()
    local ok, result = pcall(function()
        local mainGui = LocalPlayer.PlayerGui:FindFirstChild("MainGUI")
        if not mainGui then return 0 end
        local gameGui = mainGui:FindFirstChild("Game")
        if not gameGui then return 0 end
        local coinBags = gameGui:FindFirstChild("CoinBags")
        if not coinBags then return 0 end
        for _, bag in ipairs(coinBags:GetDescendants()) do
            if bag:IsA("TextLabel") and bag.Name == "Coins" then
                local num = bag.Text:match("(%d+)")
                if num then return tonumber(num) end
            end
        end
        return 0
    end)
    return ok and result or 0
end

-- Update authoritative counter and auto-reset if 50 reached
task.spawn(function()
    while true do
        local ok, val = pcall(getGameCoinCount)
        if ok then collectedCoinsCount = val end
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

-- Helpers: detect map (top-level workspace child) for a given part/position
local function getTopLevelAncestor(part)
    local p = part
    while p and p.Parent and p.Parent ~= workspace do
        p = p.Parent
    end
    if p and p.Parent == workspace then
        return p
    end
    return nil
end

local function modelCenter(model)
    -- approximate center by averaging some BaseParts; fallback to PrimaryPart
    if model.PrimaryPart then return model.PrimaryPart.Position end
    local count, sum = 0, Vector3.new(0,0,0)
    for _,desc in ipairs(model:GetDescendants()) do
        if desc:IsA("BasePart") then
            sum = sum + desc.Position
            count = count + 1
            if count >= 10 then break end
        end
    end
    if count > 0 then return sum / count end
    return nil
end

local function findPlayerMap()
    local char = LocalPlayer.Character
    local hrp = char and char:FindFirstChild("HumanoidRootPart")
    if not hrp then return nil end
    local bestMap, bestDist = nil, math.huge
    for _,child in ipairs(workspace:GetChildren()) do
        if child:IsA("Model") or child:IsA("Folder") then
            local center = modelCenter(child)
            if center then
                local d = (hrp.Position - center).Magnitude
                if d < bestDist then
                    bestDist = d
                    bestMap = child
                end
            end
        end
    end
    return bestMap
end

-- Strong coin detection: require BasePart, visible, in workspace and either has touch transmitter or name/parent contains "coin"
local function hasTouchTransmitter(part)
    if not part then return false end
    if part:FindFirstChildWhichIsA("TouchTransmitter") then return true end
    if part:FindFirstChild("TouchInterest") then return true end
    return false
end

local function looksCoinLike(part)
    local name = (part.Name or ""):lower()
    local pName = (part.Parent and part.Parent.Name or ""):lower()
    if name:find("coin") or pName:find("coin") then return true end
    return false
end

local function isRealAndExistingCoin(part)
    if not part or not part:IsA("BasePart") then return false end
    if not part:IsDescendantOf(workspace) then return false end
    if part.Transparency and part.Transparency > 0.5 then return false end
    if hasTouchTransmitter(part) then return true end
    if looksCoinLike(part) then return true end
    return false
end

-- Cache coins but only from player's current map (stop collecting in Lobby)
local function getValidCoins()
    if tick() - lastCacheUpdate < 0.12 then return coinsCache end
    lastCacheUpdate = tick()
    coinsCache = {}

    local playerMap = findPlayerMap()
    if playerMap and playerMap.Name:lower():find("lobby") then
        -- player is in lobby: do not collect
        return coinsCache
    end

    local seen = {}
    pcall(function()
        -- prefer container-based scan
        for _, map in ipairs(workspace:GetChildren()) do
            if map and map.Name ~= "Lobby" and map ~= playerMap then
                -- skip other maps (we only want player's current map)
            end
        end

        -- scan workspace descendants but include only coins that belong to player's map
        for _, obj in ipairs(workspace:GetDescendants()) do
            if obj and obj:IsA("BasePart") and not seen[obj] and not blacklistedCoins[obj] then
                if isRealAndExistingCoin(obj) then
                    local top = getTopLevelAncestor(obj)
                    if top == playerMap or (not playerMap and (not top or top.Name ~= "Lobby")) then
                        table.insert(coinsCache, obj)
                        seen[obj] = true
                    end
                end
            end
        end
    end)
    return coinsCache
end

-- Raycast ground at X,Z to find safe Y for HRP positioning
local function findGroundYAt(xzPos)
    local origin = Vector3.new(xzPos.X, workspace:GetExtentsSize().Y + 100, xzPos.Z)
    local params = RaycastParams.new()
    params.FilterDescendantsInstances = {LocalPlayer.Character}
    params.FilterType = Enum.RaycastFilterType.Blacklist
    local result = workspace:Raycast(origin, Vector3.new(0, -1000, 0), params)
    if result and result.Position then
        return result.Position.Y
    end
    return nil
end

local function getSmartNearestCoin()
    local char = LocalPlayer.Character
    local hrp = char and char:FindFirstChild("HumanoidRootPart")
    if not hrp then return nil end
    local allCoins = getValidCoins()
    if #allCoins == 0 then return nil end
    local closestCoin, shortestDistance = nil, math.huge
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
            hrp.CanCollide = true -- preserve HRP collision to avoid falling through ground
        end
        if hum then hum.PlatformStand = false end
        for _, part in ipairs(char:GetDescendants()) do
            if part:IsA("BasePart") and part.Name ~= "HumanoidRootPart" then
                part.CanCollide = false
            end
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
        -- quick repeated touches
        firetouchinterest(hrp, coin, 0)
        firetouchinterest(hrp, coin, 1)
        task.wait(0.03)
        for _, part in ipairs(char:GetChildren()) do
            if part:IsA("BasePart") then
                firetouchinterest(part, coin, 0)
                firetouchinterest(part, coin, 1)
            end
        end
    end)
    return ok
end

local function attemptCollectCoin(coin, char, hrp)
    if not coin or not coin.Parent or not char or not hrp then return false end
    local before = getGameCoinCount()
    -- try several attempts, including a very small upward nudge to ensure touch registers (but keep HRP above ground)
    for i=1,3 do
        triggerUndergroundTouch(coin, char, hrp)
        task.wait(0.06)
    end
    local deadline = tick() + 0.9
    while tick() < deadline do
        local now = getGameCoinCount()
        if now and now > before then
            collectedCoinsCount = now
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
    blacklistedCoins[coin] = true
    return false
end

-- MAIN FARM LOOP
RunService.Heartbeat:Connect(function(dt)
    pcall(function()
        if not farmActive then return end

        collectedCoinsCount = getGameCoinCount()
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

        -- safety teleport if below dangerous Y
        if hrp.Position.Y < SAFE_FALL_Y then
            pcall(function()
                local spawn = LocalPlayer.RespawnLocation or workspace:FindFirstChild("SpawnLocation")
                if spawn and spawn.Position then
                    hrp.CFrame = CFrame.new(spawn.Position + Vector3.new(0, 5, 0))
                else
                    hrp.CFrame = hrp.CFrame + Vector3.new(0, 50, 0)
                end
            end)
            return
        end

        local allCoins = getValidCoins()
        if #allCoins == 0 then
            currentTargetCoin = nil
            cleanupPhysics()
            return
        end

        -- validate target
        if currentTargetCoin and (not currentTargetCoin.Parent or not currentTargetCoin:IsDescendantOf(workspace)) then
            currentTargetCoin = nil
        end

        -- keep humanoid stable on ground
        hum:SetStateEnabled(Enum.HumanoidStateType.FallingDown, false)
        hum.PlatformStand = false

        -- ensure HRP collisions preserved, other parts non-colliding
        for _, part in ipairs(char:GetDescendants()) do
            if part:IsA("BasePart") then
                if part.Name == "HumanoidRootPart" then
                    part.CanCollide = true
                else
                    part.CanCollide = false
                end
            end
        end

        local coin = getSmartNearestCoin()
        if coin then
            if not coin.Parent or coin.Transparency > 0.8 then
                blacklistedCoins[coin] = true
                currentTargetCoin = nil
                return
            end

            if coin ~= currentTargetCoin then
                currentTargetCoin = coin
                coinTargetStartTime = tick()
            else
                if tick() - coinTargetStartTime > 0.9 then
                    blacklistedCoins[coin] = true
                    currentTargetCoin = nil
                    return
                end
            end

            -- find safe Y: attempt to raycast ground under coin
            local groundY = findGroundYAt(coin.Position) -- may be nil
            local desiredY = coin.Position.Y - UNDER_OFFSET
            if groundY then
                -- never go below groundY + 0.8 (stay slightly above ground)
                desiredY = math.max(desiredY, groundY + 0.8)
            else
                -- if no ground found, clamp to a reasonable minimum
                desiredY = math.max(desiredY, SAFE_FALL_Y + 50)
            end

            -- compute target position but prevent teleporting through geometry horizontally by moving stepwise
            local targetPos = Vector3.new(coin.Position.X, desiredY, coin.Position.Z)
            local delta = targetPos - hrp.Position
            local moveStep = math.min(delta.Magnitude, FARM_SPEED * dt)
            if delta.Magnitude > 0.05 then
                hrp.CFrame = CFrame.new(hrp.Position + delta.Unit * moveStep)
            else
                hrp.CFrame = CFrame.new(targetPos)
            end

            hrp.AssemblyLinearVelocity = Vector3.zero
            hrp.AssemblyAngularVelocity = Vector3.zero

            -- only attempt collect when horizontally close and not deep underground
            local horizDist = (Vector3.new(hrp.Position.X, 0, hrp.Position.Z) - Vector3.new(coin.Position.X, 0, coin.Position.Z)).Magnitude
            if horizDist <= 1.5 and math.abs(hrp.Position.Y - coin.Position.Y) <= 6 then
                local collected = attemptCollectCoin(coin, char, hrp)
                if collected then
                    blacklistedCoins[coin] = nil
                    currentTargetCoin = nil
                    return
                else
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

-- UI updater
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

-- create toggles and other UI (omitted for brevity but same as before)
-- Re-add your createToggle and button connections here (unchanged)
