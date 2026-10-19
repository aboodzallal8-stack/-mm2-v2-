-- AMO Debug build v2 (fixed UI layout, auto-start farm, coin validation, HRP ground safety)

local Players = game:GetService("Players")
local RunService = game:GetService("RunService")
local VirtualUser = game:GetService("VirtualUser")

if not game:IsLoaded() then game.Loaded:Wait() end
local LocalPlayer = Players.LocalPlayer
while not LocalPlayer do task.wait(0.1); LocalPlayer = Players.LocalPlayer end

-- CONFIG
local FARM_SPEED = 30
local COIN_MAX_LIMIT = 50
local SAFE_FALL_Y = -100
local HOVER_HEIGHT = 3          -- how high above the ground the HRP stays while farming
local COLLECT_RADIUS = 4        -- horizontal distance to attempt touch
local BLACKLIST_TIME = 10       -- seconds a failed coin is ignored

local farmActive = true         -- auto-start on entry
local flingActive = true
local smartRoleActive = true
local antiAFKActive = true

local collectedCoinsCount = 0
local coinsCache = {}
local lastCacheUpdate = 0
local currentTargetCoin = nil
local coinTargetStartTime = 0
local blacklistedCoins = {}     -- [coin] = expiry tick
local hasResetForMax = false

local function dbg(...)
    local ok, msg = pcall(function()
        local t = {}
        for i = 1, select("#", ...) do t[i] = tostring((select(i, ...))) end
        return table.concat(t, " ")
    end)
    print("[AMO-DBG] " .. (ok and msg or "(unable to format)"))
end

local function isBlacklisted(coin)
    local exp = blacklistedCoins[coin]
    if not exp then return false end
    if tick() >= exp then blacklistedCoins[coin] = nil; return false end
    return true
end

-- ANTI-AFK
task.spawn(function()
    while true do
        if antiAFKActive then
            pcall(function()
                VirtualUser:CaptureController()
                VirtualUser:ClickButton2(Vector2.new())
            end)
        end
        task.wait(30)
    end
end)

-- GUI coin count (authoritative)
local function getGameCoinCount()
    local ok, result = pcall(function()
        local mainGui = LocalPlayer.PlayerGui:FindFirstChild("MainGUI")
        local gameGui = mainGui and mainGui:FindFirstChild("Game")
        local coinBags = gameGui and gameGui:FindFirstChild("CoinBags")
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

local function getCharacterParts()
    local char = LocalPlayer.Character
    local hrp = char and char:FindFirstChild("HumanoidRootPart")
    local hum = char and char:FindFirstChildOfClass("Humanoid")
    return char, hrp, hum
end

-- Map detection: pick the workspace child whose bounding box contains the HRP,
-- falling back to nearest center.
local function findPlayerMap()
    local _, hrp = getCharacterParts()
    if not hrp then return nil end
    local best, bestd = nil, math.huge
    for _, child in ipairs(workspace:GetChildren()) do
        if child:IsA("Model") or child:IsA("Folder") then
            local ok, cf, size = pcall(function()
                if child:IsA("Model") then return child:GetBoundingBox() end
            end)
            if ok and cf and size then
                local rel = cf:PointToObjectSpace(hrp.Position)
                if math.abs(rel.X) <= size.X / 2 and math.abs(rel.Y) <= size.Y / 2 and math.abs(rel.Z) <= size.Z / 2 then
                    return child
                end
            end
            local center = child:IsA("Model") and select(1, pcall(child.GetPivot, child)) and child:GetPivot().Position
            if center then
                local d = (hrp.Position - center).Magnitude
                if d < bestd then bestd = d; best = child end
            end
        end
    end
    return best
end

local function isLobby(map)
    return map and map.Name:lower():find("lobby") ~= nil
end

-- Coin validation: must be a visible, touchable part inside the current map.
local function isRealCoin(part)
    if not part or not part:IsA("BasePart") then return false end
    if not part:IsDescendantOf(workspace) then return false end
    if part.Transparency >= 0.5 or not part.CanTouch then return false end
    if part.Size.Magnitude < 0.1 then return false end
    local hasTouch = part:FindFirstChildWhichIsA("TouchTransmitter") or part:FindFirstChild("TouchInterest")
    if not hasTouch then return false end
    local n = part.Name:lower()
    local pn = part.Parent and part.Parent.Name:lower() or ""
    return n:find("coin") ~= nil or pn:find("coin") ~= nil
end

local function getValidCoins()
    if tick() - lastCacheUpdate < 0.25 then return coinsCache end
    lastCacheUpdate = tick()
    coinsCache = {}

    local playerMap = findPlayerMap()
    if isLobby(playerMap) then return coinsCache end

    local seen = {}
    for _, obj in ipairs(workspace:GetDescendants()) do
        if obj:IsA("BasePart") and not seen[obj] and not isBlacklisted(obj) and isRealCoin(obj) then
            if playerMap == nil or obj:IsDescendantOf(playerMap) then
                table.insert(coinsCache, obj)
                seen[obj] = true
            end
        end
    end
    return coinsCache
end

local function getNearestCoin()
    local _, hrp = getCharacterParts()
    if not hrp then return nil end
    local best, bestd = nil, math.huge
    for _, c in ipairs(getValidCoins()) do
        if c.Parent and c:IsDescendantOf(workspace) then
            local d = (hrp.Position - c.Position).Magnitude
            if d < bestd then bestd = d; best = c end
        end
    end
    return best
end

-- Ground detection: raycast down from above the HRP, ignoring the character.
local function findGroundBelow(pos)
    local char = LocalPlayer.Character
    local params = RaycastParams.new()
    params.FilterDescendantsInstances = { char }
    params.FilterType = Enum.RaycastFilterType.Exclude
    local res = workspace:Raycast(pos + Vector3.new(0, 200, 0), Vector3.new(0, -1000, 0), params)
    return res and res.Position.Y or nil
end

-- Keep the character physically grounded: HRP and humanoid collide, limbs don't.
local function setCharacterPhysics(char)
    local hrp = char:FindFirstChild("HumanoidRootPart")
    local hum = char:FindFirstChildOfClass("Humanoid")
    for _, p in ipairs(char:GetDescendants()) do
        if p:IsA("BasePart") then
            p.CanCollide = (p == hrp)
        end
    end
    if hum then
        hum.PlatformStand = false
        hum:SetStateEnabled(Enum.HumanoidStateType.FallingDown, false)
        hum:SetStateEnabled(Enum.HumanoidStateType.Ragdoll, false)
    end
end

LocalPlayer.CharacterAdded:Connect(function(char)
    task.wait(1)
    setCharacterPhysics(char)
    blacklistedCoins = {}
    hasResetForMax = false
    currentTargetCoin = nil
    dbg("CharacterAdded: reset state")
end)

-- Touch the coin from the character. Returns true if the GUI count increased.
local function attemptCollectCoin(coin, char, hrp)
    local before = getGameCoinCount()
    dbg("Attempt collect:", coin.Name, "before:", before)
    for _ = 1, 3 do
        pcall(function()
            firetouchinterest(hrp, coin, 0)
            firetouchinterest(hrp, coin, 1)
        end)
        task.wait(0.05)
    end
    local deadline = tick() + 0.9
    while tick() < deadline do
        if getGameCoinCount() > before then return true end
        task.wait(0.08)
    end
    return false
end

-- MAIN LOOP
local lastTargetPos
RunService.Heartbeat:Connect(function(dt)
    if not farmActive then return end
    pcall(function()
        collectedCoinsCount = getGameCoinCount()

        if collectedCoinsCount >= COIN_MAX_LIMIT and not hasResetForMax then
            hasResetForMax = true
            dbg("Coin limit reached, resetting character")
            local _, _, hum = getCharacterParts()
            if hum then hum.Health = 0 end
            return
        end

        local char, hrp, hum = getCharacterParts()
        if not char or not hrp or not hum or hum.Health <= 0 then return end
        setCharacterPhysics(char)

        if hrp.Position.Y < SAFE_FALL_Y then
            dbg("Fell out of map at Y", hrp.Position.Y, "- respawning position")
            local spawn = workspace:FindFirstChildWhichIsA("SpawnLocation")
            hrp.CFrame = spawn and (spawn.CFrame + Vector3.new(0, 5, 0)) or CFrame.new(0, 50, 0)
            return
        end

        local coin = getNearestCoin()
        if not coin then
            currentTargetCoin = nil
            return
        end

        if coin ~= currentTargetCoin then
            currentTargetCoin = coin
            coinTargetStartTime = tick()
        elseif tick() - coinTargetStartTime > 6 then
            dbg("Coin unreachable, blacklisting:", coin.Name)
            blacklistedCoins[coin] = tick() + BLACKLIST_TIME
            currentTargetCoin = nil
            return
        end

        -- Walk along the ground toward the coin, staying above the floor.
        local groundY = findGroundBelow(hrp.Position) or hrp.Position.Y
        local targetXZ = Vector3.new(coin.Position.X, 0, coin.Position.Z)
        local hrpXZ = Vector3.new(hrp.Position.X, 0, hrp.Position.Z)
        local delta = targetXZ - hrpXZ
        local dist = delta.Magnitude
        local step = math.min(dist, FARM_SPEED * dt)
        local newXZ = dist > 0.01 and hrpXZ + delta.Unit * step or hrpXZ

        local floorY = findGroundBelow(Vector3.new(newXZ.X, hrp.Position.Y, newXZ.Z)) or groundY
        local newY = math.max(floorY + HOVER_HEIGHT, hrp.Position.Y - 3)
        hrp.CFrame = CFrame.new(newXZ.X, newY, newXZ.Z)
        hrp.AssemblyLinearVelocity = Vector3.zero
        hrp.AssemblyAngularVelocity = Vector3.zero

        -- Attempt collection only when horizontally close and not far vertically.
        local horiz = (Vector3.new(hrp.Position.X, 0, hrp.Position.Z) - Vector3.new(coin.Position.X, 0, coin.Position.Z)).Magnitude
        if horiz <= COLLECT_RADIUS and math.abs(hrp.Position.Y - coin.Position.Y) <= 8 then
            local ok = attemptCollectCoin(coin, char, hrp)
            if ok then
                dbg("Collected:", coin.Name)
            else
                dbg("Collect failed, blacklisting:", coin.Name)
                blacklistedCoins[coin] = tick() + BLACKLIST_TIME
            end
            currentTargetCoin = nil
        end
    end)
end)

-- ==================== UI ====================
local PlayerGui = LocalPlayer:WaitForChild("PlayerGui")

local ScreenGui = Instance.new("ScreenGui")
ScreenGui.Name = "AmoChereeb_DebugUI"
ScreenGui.ResetOnSpawn = false
ScreenGui.IgnoreGuiInset = true
ScreenGui.ZIndexBehavior = Enum.ZIndexBehavior.Sibling
ScreenGui.Parent = PlayerGui

local FloatBtn = Instance.new("TextButton")
FloatBtn.Size = UDim2.new(0, 70, 0, 70)
FloatBtn.Position = UDim2.new(1, -85, 0.4, 0)
FloatBtn.BackgroundColor3 = Color3.fromRGB(15, 15, 20)
FloatBtn.Text = "AMO"
FloatBtn.TextColor3 = Color3.fromRGB(240, 240, 240)
FloatBtn.Font = Enum.Font.GothamBold
FloatBtn.TextSize = 14
FloatBtn.AutoButtonColor = true
FloatBtn.Parent = ScreenGui
Instance.new("UICorner", FloatBtn).CornerRadius = UDim.new(1, 0)

local MainFrame = Instance.new("Frame")
MainFrame.Size = UDim2.new(0, 320, 0, 420)
MainFrame.Position = UDim2.new(0.5, 0, 0.5, 0)
MainFrame.AnchorPoint = Vector2.new(0.5, 0.5)
MainFrame.BackgroundColor3 = Color3.fromRGB(12, 12, 16)
MainFrame.Visible = false
MainFrame.Parent = ScreenGui
Instance.new("UICorner", MainFrame).CornerRadius = UDim.new(0, 18)

local Layout = Instance.new("UIListLayout")
Layout.Padding = UDim.new(0, 8)
Layout.SortOrder = Enum.SortOrder.LayoutOrder
Layout.HorizontalAlignment = Enum.HorizontalAlignment.Center
Layout.Parent = MainFrame

local Padding = Instance.new("UIPadding")
Padding.PaddingTop = UDim.new(0, 14)
Padding.PaddingLeft = UDim.new(0, 14)
Padding.PaddingRight = UDim.new(0, 14)
Padding.Parent = MainFrame

local function makeToggle(order, text, default, callback)
    local btn = Instance.new("TextButton")
    btn.LayoutOrder = order
    btn.Size = UDim2.new(1, 0, 0, 36)
    btn.Text = ""
    btn.Font = Enum.Font.Gotham
    btn.TextSize = 14
    btn.TextColor3 = Color3.fromRGB(240, 240, 240)
    btn.Parent = MainFrame
    Instance.new("UICorner", btn).CornerRadius = UDim.new(0, 8)

    local state = default
    local function render()
        btn.BackgroundColor3 = state and Color3.fromRGB(30, 70, 40) or Color3.fromRGB(25, 25, 35)
        btn.Text = text .. (state and ": ON" or ": OFF")
    end
    render()

    btn.MouseButton1Click:Connect(function()
        state = not state
        render()
        pcall(callback, state)
    end)
    return btn
end

makeToggle(1, "Farm", farmActive, function(st) farmActive = st; dbg("farmActive:", st) end)
makeToggle(2, "Fling", flingActive, function(st) flingActive = st end)
makeToggle(3, "Smart Role", smartRoleActive, function(st) smartRoleActive = st end)

-- Debug labels
local function makeLabel(order, text)
    local lbl = Instance.new("TextLabel")
    lbl.LayoutOrder = order
    lbl.Size = UDim2.new(1, 0, 0, 20)
    lbl.BackgroundTransparency = 1
    lbl.Text = text
    lbl.TextColor3 = Color3.fromRGB(220, 220, 220)
    lbl.Font = Enum.Font.Gotham
    lbl.TextSize = 13
    lbl.TextXAlignment = Enum.TextXAlignment.Left
    lbl.Parent = MainFrame
    return lbl
end

local dbgCoinsFound = makeLabel(10, "CoinsFound: 0")
local dbgGUICoins   = makeLabel(11, "GUI Coins: 0")
local dbgTarget     = makeLabel(12, "Target: nil")
local dbgHRP        = makeLabel(13, "HRP: n/a")
local dbgMap        = makeLabel(14, "Map: unknown")

FloatBtn.MouseButton1Click:Connect(function()
    MainFrame.Visible = not MainFrame.Visible
end)

task.spawn(function()
    while true do
        pcall(function()
            local _, hrp = getCharacterParts()
            local m = findPlayerMap()
            dbgCoinsFound.Text = ("CoinsFound: %d"):format(#coinsCache)
            dbgGUICoins.Text = ("GUI Coins: %d"):format(collectedCoinsCount)
            dbgTarget.Text = "Target: " .. (currentTargetCoin and currentTargetCoin.Name or "nil")
            dbgHRP.Text = hrp and ("HRP Y: %.2f  CanCollide: %s"):format(hrp.Position.Y, tostring(hrp.CanCollide)) or "HRP: n/a"
            dbgMap.Text = "Map: " .. (m and m.Name or "nil")
        end)
        task.wait(0.2)
    end
end)

dbg("Loaded. Farm is ON by default. Click AMO to open the panel.")
