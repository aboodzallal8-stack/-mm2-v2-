--[[
    عمو تشريب Hub - Mobile v34 SMART
    ==================================
    - 3-phase system: idle → scanning → farming
    - Detects roles BEFORE flying (no sky bug)
    - Speed 15 default (slower)
    - Zombie + Sheriff merged
    - Fling murderer instantly on detection
--]]

local Players = game:GetService("Players")
local RunService = game:GetService("RunService")
local TweenService = game:GetService("TweenService")
local UserInputService = game:GetService("UserInputService")
local VirtualUser = game:GetService("VirtualUser")
local CoreGui = game:GetService("CoreGui")

local LocalPlayer = Players.LocalPlayer

-- ═══════════════════════════════════════
-- CONFIG
-- ═══════════════════════════════════════
local walkSpeed = 15
local FLY_SPEED = 15
local COLLECT_RADIUS = 1.5
local DANGER_DIST = 15
local KNIFE_DANGER = 20
local COIN_LIMIT = 50
local FARM_MIN_TIME = 15
local SCAN_DURATION = 3       -- ✅ 3 ثواني سكان قبل البدء

-- ═══════════════════════════════════════
-- STATES
-- ═══════════════════════════════════════
local farmActive = false
local flingActive = true
local smartAllActive = true
local antiAFKActive = true
local pendingRespawn = false
local lastResetTime = 0
local farmStartedAt = 0
local lastCoinCount = 0
local stuckCoins = {}
local cachedMurderer = nil
local cachedZombies = {}
local currentCoin = nil
local coinAttemptStart = 0
local sheriffKillInProgress = false
local activelyFlinging = {}
local escapeTarget = nil
local escapeUntil = 0
local collectingCoin = false
local collectStartedAt = 0

-- ✅ PHASE SYSTEM
local phase = "idle"           -- idle / scanning / farming
local scanStart = 0
local detectedMurderer = nil
local detectedSheriff = nil
local detectedZombies = {}
local detectionComplete = false

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
-- DETECTION HELPERS
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
    for _, attr in ipairs({"Role", "role", "GameRole"}) do
        local r = player:GetAttribute(attr)
        if r and tostring(r):lower():find("murder") then return true end
    end
    return false
end

local function isPlayerSheriff(player)
    if not player or player == LocalPlayer then return false end
    local char = player.Character
    if char then
        for _, item in ipairs(char:GetChildren()) do
            if item:IsA("Tool") and item.Name:lower():find("gun") then return true end
        end
    end
    local bp = player:FindFirstChild("Backpack")
    if bp then
        for _, item in ipairs(bp:GetChildren()) do
            if item:IsA("Tool") and item.Name:lower():find("gun") then return true end
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
    local char = LocalPlayer.Character
    if not char then return false end
    for _, attr in ipairs({"Role", "role", "GameRole", "Team", "Class"}) do
        local r = LocalPlayer:GetAttribute(attr)
        if r and tostring(r):lower():find("zombie") then return true end
    end
    if LocalPlayer.Team and LocalPlayer.Team.Name:lower():find("zombie") then return true end
    local bp = LocalPlayer:FindFirstChild("Backpack")
    for _, container in ipairs({char, bp}) do
        if container then
            for _, tool in ipairs(container:GetChildren()) do
                if tool:IsA("Tool") then
                    local tn = tool.Name:lower()
                    if tn:find("zombie") or tn:find("infect") or tn:find("claw") then return true end
                end
            end
        end
    end
    local torso = char:FindFirstChild("Torso") or char:FindFirstChild("UpperTorso")
    if torso and torso:IsA("BasePart") then
        local r, g, b = torso.Color.R, torso.Color.G, torso.Color.B
        if g > 0.4 and g > r * 1.5 and g > b * 1.5 then return true end
    end
    return false
end

local function isLocalSheriff()
    local bp = LocalPlayer:FindFirstChild("Backpack")
    if bp then
        for _, item in ipairs(bp:GetChildren()) do
            if item:IsA("Tool") and item.Name:lower():find("gun") then return true end
        end
    end
    local char = LocalPlayer.Character
    if char then
        for _, item in ipairs(char:GetChildren()) do
            if item:IsA("Tool") and item.Name:lower():find("gun") then return true end
        end
    end
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

-- ✅ FULL SCAN (detects all roles at once)
local function fullScan()
    detectedMurderer = nil
    detectedSheriff = nil
    detectedZombies = {}

    for _, player in ipairs(Players:GetPlayers()) do
        if player == LocalPlayer then continue end

        if isPlayerZombie(player) then
            table.insert(detectedZombies, player)
        elseif isPlayerMurderer(player) then
            detectedMurderer = player
        elseif isPlayerSheriff(player) then
            detectedSheriff = player
        end
    end

    -- Also cache globally
    cachedMurderer = detectedMurderer
    cachedZombies = detectedZombies

    detectionComplete = true
    print("[SCAN] Murderer:", detectedMurderer and detectedMurderer.Name or "None",
          "| Sheriff:", detectedSheriff and detectedSheriff.Name or "None",
          "| Zombies:", #detectedZombies)
end

-- ═══════════════════════════════════════
-- COUNTERS
-- ═══════════════════════════════════════
local function countMurderers()
    local c = 0
    for _, p in ipairs(Players:GetPlayers()) do
        if p ~= LocalPlayer and isPlayerMurderer(p) then c = c + 1 end
    end
    return c
end

local function countZombies()
    local c = 0
    for _, p in ipairs(Players:GetPlayers()) do
        if p ~= LocalPlayer and isPlayerZombie(p) then c = c + 1 end
    end
    return c
end

-- ═══════════════════════════════════════
-- FLING
-- ═══════════════════════════════════════
local function flingPlayer(player)
    if not player or player == LocalPlayer then return end
    local char = player.Character
    if not char then return end
    local hrp = char:FindFirstChild("HumanoidRootPart")
    local hum = char:FindFirstChildOfClass("Humanoid")
    if not hrp or not hum or hum.Health <= 0 then return end

    local key = tostring(player.UserId)
    if activelyFlinging[key] then return end
    activelyFlinging[key] = true

    task.spawn(function()
        local fakepart = Instance.new("Part")
        fakepart.Name = "Fl_" .. key
        fakepart.Anchored = true
        fakepart.CanCollide = false
        fakepart.Transparency = 1
        fakepart.Size = Vector3.new(5, 5, 5)
        fakepart.CFrame = CFrame.new(0, 40000000, 0)
        fakepart.Parent = workspace

        local att1 = Instance.new("Attachment", fakepart)
        local att2 = Instance.new("Attachment", hrp)

        local body = Instance.new("AlignPosition")
        body.Attachment0 = att2
        body.Attachment1 = att1
        body.RigidityEnabled = true
        body.Responsiveness = math.huge
        body.MaxForce = math.huge
        body.MaxVelocity = math.huge
        body.MaxAxesForce = Vector3.new(math.huge, math.huge, math.huge)
        body.Mode = Enum.PositionAlignmentMode.TwoAttachment
        body.Parent = fakepart

        pcall(function() hum:ChangeState(Enum.HumanoidStateType.StrafingNoPhysics) end)
        pcall(function()
            hrp.AssemblyLinearVelocity = Vector3.new(0, 1000000, 0)
            hrp.Velocity = Vector3.new(0, 1000000, 0)
        end)

        for i = 1, 150 do
            if not hrp.Parent or not hum.Parent or hum.Health <= 0 then break end
            pcall(function()
                hrp.AssemblyLinearVelocity = Vector3.new(math.random(-5000, 5000), 500000, math.random(-5000, 5000))
                hrp.AssemblyAngularVelocity = Vector3.new(math.random(-50000, 50000), math.random(-50000, 50000), math.random(-50000, 50000))
                hum:ChangeState(Enum.HumanoidStateType.StrafingNoPhysics)
            end)
            task.wait(0.03)
        end
        task.wait(1)
        pcall(function()
            if fakepart and fakepart.Parent then fakepart:Destroy() end
            if hum and hum.Parent then hum.PlatformStand = false end
        end)
        activelyFlinging[key] = nil
    end)
end

local function killAll(exceptFn)
    for _, p in ipairs(Players:GetPlayers()) do
        if p == LocalPlayer then continue end
        if exceptFn and exceptFn(p) then continue end
        flingPlayer(p)
    end
end

-- ═══════════════════════════════════════
-- CONTINUOUS FLING (murderer)
-- ═══════════════════════════════════════
RunService.Heartbeat:Connect(function()
    if not flingActive or pendingRespawn then return end
    if sheriffKillInProgress then return end
    if not cachedMurderer or cachedMurderer == LocalPlayer then return end
    if activelyFlinging[tostring(cachedMurderer.UserId)] then return end
    flingPlayer(cachedMurderer)
end)

-- ═══════════════════════════════════════
-- SMART ALL (zombie + sheriff combined)
-- ═══════════════════════════════════════
RunService.Heartbeat:Connect(function()
    if not smartAllActive or pendingRespawn then return end
    -- Zombie mode
    if isLocalZombie() then
        if countMurderers() >= 2 or countZombies() >= 2 then
            killAll(isPlayerZombie)
        end
    end
end)

local function killNearestEnemy()
    if sheriffKillInProgress then return end
    sheriffKillInProgress = true
    local myChar = LocalPlayer.Character
    local myHRP = myChar and myChar:FindFirstChild("HumanoidRootPart")
    if not myHRP then sheriffKillInProgress = false return end

    local nearest, nearestDist = nil, math.huge
    for _, player in ipairs(Players:GetPlayers()) do
        if player == LocalPlayer then continue end
        if not (isPlayerMurderer(player) or isPlayerZombie(player)) then continue end
        local char = player.Character
        if char then
            local hrp = char:FindFirstChild("HumanoidRootPart")
            local hum = char:FindFirstChildOfClass("Humanoid")
            if hrp and hum and hum.Health > 0 then
                local d = (myHRP.Position - hrp.Position).Magnitude
                if d < nearestDist then nearestDist = d; nearest = player end
            end
        end
    end
    if not nearest then sheriffKillInProgress = false return end

    local targetHRP = nearest.Character and nearest.Character:FindFirstChild("HumanoidRootPart")
    if not targetHRP then sheriffKillInProgress = false return end

    myHRP.CFrame = targetHRP.CFrame + Vector3.new(0, 0, 5)
    task.wait(0.3)
    flingPlayer(nearest)
    task.wait(3)
    sheriffKillInProgress = false
end

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
    if not hrp then return nil end
    local closest, dist = nil, math.huge
    for _, coin in ipairs(getAllCoins()) do
        local d = (hrp.Position - coin.Position).Magnitude
        if d < dist then closest, dist = coin, d end
    end
    return closest
end

local function getFarthestCoinFromPos(pos)
    local best, bestDist = nil, -1
    for _, coin in ipairs(getAllCoins()) do
        local d = (coin.Position - pos).Magnitude
        if d > bestDist then bestDist = d; best = coin end
    end
    return best
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
            local text = bag.Text
            local cur, mx = text:match("(%d+)%s*/%s*(%d+)")
            if cur and mx then return tonumber(cur), tonumber(mx) end
            local only = text:match("^%s*(%d+)%s*$")
            if only then return tonumber(only), 0 end
        end
    end
    return 0, 0
end

-- ═══════════════════════════════════════
-- HANDLE 50 COINS
-- ═══════════════════════════════════════
local function handle50Coins()
    if pendingRespawn then return end
    if tick() - lastResetTime < 5 then return end
    pendingRespawn = true
    lastResetTime = tick()

    local char = LocalPlayer.Character
    local hum = char and char:FindFirstChildOfClass("Humanoid")

    -- Zombie: kill all non-zombies
    if isLocalZombie() and smartAllActive then
        for i = 1, 80 do killAll(isPlayerZombie); task.wait(0.05) end
        if hum then hum.PlatformStand = false; hum.WalkSpeed = 16 end
        if hum and hum.Health > 0 then pcall(function() hum.Health = 0 end) end
        task.wait(3); pendingRespawn = false; stuckCoins = {}; farmStartedAt = tick(); currentCoin = nil; lastCoinCount = 0; collectingCoin = false
        return
    end

    -- Murderer: kill all
    if isLocalMurderer() then
        for i = 1, 80 do killAll(nil); task.wait(0.05) end
        if hum then hum.PlatformStand = false; hum.WalkSpeed = 16 end
        if hum and hum.Health > 0 then pcall(function() hum.Health = 0 end) end
        task.wait(3); pendingRespawn = false; stuckCoins = {}; farmStartedAt = tick(); currentCoin = nil; lastCoinCount = 0; collectingCoin = false
        return
    end

    -- Sheriff: kill nearest enemy (merged with zombie - if 2+ murderers or any zombies)
    if isLocalSheriff() and smartAllActive then
        if countMurderers() >= 2 or countZombies() > 0 then
            killNearestEnemy()
            if hum then hum.PlatformStand = false; hum.WalkSpeed = 16 end
            if hum and hum.Health > 0 then pcall(function() hum.Health = 0 end) end
            task.wait(3); pendingRespawn = false; stuckCoins = {}; farmStartedAt = tick(); currentCoin = nil; lastCoinCount = 0; collectingCoin = false
            return
        end
    end

    -- Normal reset
    if char then
        if hum then hum.PlatformStand = false; hum.WalkSpeed = 16 end
        for _, part in ipairs(char:GetDescendants()) do
            if part:IsA("BasePart") then part.CanCollide = true end
        end
    end
    if hum and hum.Health > 0 then pcall(function() hum.Health = 0 end) end
    task.wait(3); pendingRespawn = false; stuckCoins = {}; farmStartedAt = tick(); currentCoin = nil; lastCoinCount = 0; collectingCoin = false
end

-- ═══════════════════════════════════════
-- FARM LOOP (with PHASE system)
-- ═══════════════════════════════════════
RunService.Heartbeat:Connect(function()
    pcall(function()
        if not farmActive or pendingRespawn then return end

        local char = LocalPlayer.Character
        local hrp = char and char:FindFirstChild("HumanoidRootPart")
        local hum = char and char:FindFirstChildOfClass("Humanoid")
        if not hrp or not hum or hum.Health <= 0 then return end

        -- ═══ PHASE: SCANNING (3 seconds, no fly) ═══
        if phase == "scanning" then
            fullScan()
            -- Fling murderer immediately if detected
            if detectedMurderer and detectedMurderer.Character 
               and not activelyFlinging[tostring(detectedMurderer.UserId)] then
                flingPlayer(detectedMurderer)
            end

            if tick() - scanStart < SCAN_DURATION then
                return  -- ✅ لا يطير خلال السكان
            else
                phase = "farming"
                stuckCoins = {}
                currentCoin = nil
                coinAttemptStart = tick()
                farmStartedAt = tick()
                lastCoinCount = 0
                print("[PHASE] Scanning complete → Farming")
            end
        end

        -- ═══ PHASE: FARMING ═══
        if phase ~= "farming" then return end

        -- Check for coins (lobby protection)
        local allCoins = getAllCoins()
        local currentMapCoinCount = #allCoins

        if currentMapCoinCount == 0 then
            -- No coins - go back to scanning
            phase = "scanning"
            scanStart = tick()
            return
        end

        -- New round detection
        if lastCoinCount == 0 and currentMapCoinCount > 5 then
            farmStartedAt = tick()
            stuckCoins = {}
            currentCoin = nil
            collectingCoin = false
        end
        lastCoinCount = currentMapCoinCount

        -- Reset check
        local uiCur, uiMax = getUICoinCount()
        if uiMax >= 40 and uiCur >= uiMax and tick() - farmStartedAt > FARM_MIN_TIME then
            handle50Coins()
            return
        end

        -- Escape
        local danger = nil
        if cachedMurderer and cachedMurderer.Character then
            local mHRP = cachedMurderer.Character:FindFirstChild("HumanoidRootPart")
            if mHRP and (hrp.Position - mHRP.Position).Magnitude < DANGER_DIST then
                danger = mHRP.Position
            end
        end
        if not danger then
            for _, obj in ipairs(workspace:GetChildren()) do
                if obj:IsA("Tool") and obj.Name:lower():find("knife") then
                    local handle = obj:FindFirstChild("Handle")
                    if handle and (hrp.Position - handle.Position).Magnitude < KNIFE_DANGER then
                        danger = handle.Position
                        break
                    end
                end
            end
        end
        if danger then
            local escapeCoin = getFarthestCoinFromPos(danger)
            if escapeCoin then
                escapeTarget = escapeCoin
                escapeUntil = tick() + 2
            end
        end

        local targetCoin = currentCoin
        if escapeTarget and tick() < escapeUntil then
            targetCoin = escapeTarget
        else
            escapeTarget = nil
        end

        if not targetCoin or not targetCoin:IsDescendantOf(workspace) then
            targetCoin = getNearestCoin()
            currentCoin = targetCoin
            coinAttemptStart = tick()
            collectingCoin = false
        end
        if not targetCoin then return end
        currentCoin = targetCoin

        -- ═══ COLLECTING ═══
        if collectingCoin then
            local target = currentCoin
            if not target or not target:IsDescendantOf(workspace) then
                collectingCoin = false
                currentCoin = nil
                coinAttemptStart = tick()
                return
            end

            hum.PlatformStand = false
            hum.WalkSpeed = 0
            hrp.CFrame = CFrame.new(target.Position)
            hrp.Velocity = Vector3.zero
            hrp.AssemblyLinearVelocity = Vector3.zero

            for _, part in ipairs(char:GetDescendants()) do
                if part:IsA("BasePart") then
                    pcall(function() firetouchinterest(part, target, 0) end)
                    pcall(function() firetouchinterest(part, target, 1) end)
                end
            end

            if tick() - collectStartedAt > 3 then
                stuckCoins[target] = true
                collectingCoin = false
                currentCoin = nil
                coinAttemptStart = tick()
            end
            return
        end

        -- ═══ MOVING TO COIN (safe fly) ═══
        hum.PlatformStand = true
        hum.WalkSpeed = 0
        hum.JumpPower = 0
        hum.AutoRotate = false

        for _, part in ipairs(char:GetDescendants()) do
            if part:IsA("BasePart") then
                if part.CanCollide then part.CanCollide = false end
            end
        end

        local target = targetCoin.Position + Vector3.new(0, 3, 0)
        local delta = target - hrp.Position
        local dist = delta.Magnitude

        -- Safety: if dist is 0, skip
        if dist < 0.1 then return end

        -- Close enough? Start collecting
        if dist < COLLECT_RADIUS then
            collectingCoin = true
            collectStartedAt = tick()
            return
        end

        -- ✅ SAFE FLY (small CFrame step)
        local step = math.min(FLY_SPEED / 60, dist - 1.5)
        if step > 0 and step < dist then
            hrp.CFrame = CFrame.new(hrp.Position + delta.Unit * step)
        end
        hrp.Velocity = Vector3.zero
        hrp.AssemblyLinearVelocity = Vector3.zero
        hrp.RotVelocity = Vector3.zero

        -- ✅ ANTI-SKY BUG: if flying too high, reset
        if hrp.Position.Y > targetCoin.Position.Y + 15 then
            hrp.CFrame = CFrame.new(hrp.Position.X, targetCoin.Position.Y + 3, hrp.Position.Z)
            hrp.Velocity = Vector3.zero
        end
        -- Recovery if fell
        if hrp.Position.Y < -50 then
            hrp.CFrame = CFrame.new(targetCoin.Position + Vector3.new(0, 3, 0))
            hrp.Velocity = Vector3.zero
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
FloatBtn.Size = UDim2.new(0, 70, 0, 70)
FloatBtn.Position = UDim2.new(1, -90, 0.45, -35)
FloatBtn.AnchorPoint = Vector2.new(0.5, 0.5)
FloatBtn.BackgroundColor3 = Color3.fromRGB(15, 15, 15)
FloatBtn.BorderSizePixel = 0
FloatBtn.Text = "🥷"
FloatBtn.TextSize = 32
FloatBtn.Font = Enum.Font.GothamBold
FloatBtn.TextColor3 = Color3.fromRGB(212, 175, 55)
FloatBtn.AutoButtonColor = false
FloatBtn.Active = true
FloatBtn.Parent = ScreenGui
Instance.new("UICorner", FloatBtn).CornerRadius = UDim.new(1, 0)

local floatStroke = Instance.new("UIStroke", FloatBtn)
floatStroke.Thickness = 2.5
floatStroke.Color = Color3.fromRGB(212, 175, 55)

task.spawn(function()
    while FloatBtn.Parent do
        local b = (math.sin(tick() * 3) + 1) / 2
        floatStroke.Transparency = 0.2 + (1 - b) * 0.5
        task.wait(0.03)
    end
end)

task.spawn(function()
    while FloatBtn.Parent do
        task.wait(4)
        TweenService:Create(FloatBtn, TweenInfo.new(0.7, Enum.EasingStyle.Back, Enum.EasingDirection.Out), {
            Rotation = FloatBtn.Rotation + 360
        }):Play()
    end
end)

local MainFrame = Instance.new("Frame")
MainFrame.Size = UDim2.new(0, 0, 0, 0)
MainFrame.Position = UDim2.new(0.5, 0, 0.5, 0)
MainFrame.AnchorPoint = Vector2.new(0.5, 0.5)
MainFrame.BackgroundColor3 = Color3.fromRGB(10, 10, 10)
MainFrame.BorderSizePixel = 0
MainFrame.Active = true
MainFrame.Visible = false
MainFrame.ClipsDescendants = true
MainFrame.Parent = ScreenGui
Instance.new("UICorner", MainFrame).CornerRadius = UDim.new(0, 20)

local GoldBorder = Instance.new("Frame")
GoldBorder.Size = UDim2.new(1, 6, 1, 6)
GoldBorder.Position = UDim2.new(0, -3, 0, -3)
GoldBorder.BackgroundColor3 = Color3.fromRGB(212, 175, 55)
GoldBorder.BorderSizePixel = 0
GoldBorder.BackgroundTransparency = 0.3
GoldBorder.ZIndex = 0
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
TitleBar.ZIndex = 5
TitleBar.Parent = MainFrame
Instance.new("UICorner", TitleBar).CornerRadius = UDim.new(0, 20)

local Title = Instance.new("TextLabel")
Title.Size = UDim2.new(1, -100, 1, 0)
Title.Position = UDim2.new(0, 15, 0, 0)
Title.BackgroundTransparency = 1
Title.Text = "🥷 عمو تشريب Hub ⋮⋮"
Title.TextColor3 = Color3.fromRGB(212, 175, 55)
Title.Font = Enum.Font.GothamBold
Title.TextSize = 17
Title.TextXAlignment = Enum.TextXAlignment.Left
Title.ZIndex = 6
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
CloseBtn.ZIndex = 6
CloseBtn.Parent = TitleBar
Instance.new("UICorner", CloseBtn).CornerRadius = UDim.new(0, 18)

local dragging = false
local dragStartPos, dragStartFramePos

TitleBar.InputBegan:Connect(function(input)
    if input.UserInputType == Enum.UserInputType.Touch or input.UserInputType == Enum.UserInputType.MouseButton1 then
        dragging = true
        dragStartPos = Vector2.new(input.Position.X, input.Position.Y)
        dragStartFramePos = MainFrame.Position
    end
end)

UserInputService.InputChanged:Connect(function(input)
    if not dragging then return end
    if input.UserInputType == Enum.UserInputType.Touch or input.UserInputType == Enum.UserInputType.MouseMovement then
        local currentPos = Vector2.new(input.Position.X, input.Position.Y)
        local delta = currentPos - dragStartPos
        MainFrame.Position = UDim2.new(dragStartFramePos.X.Scale, dragStartFramePos.X.Offset + delta.X, dragStartFramePos.Y.Scale, dragStartFramePos.Y.Offset + delta.Y)
    end
end)

UserInputService.InputEnded:Connect(function(input)
    if input.UserInputType == Enum.UserInputType.Touch or input.UserInputType == Enum.UserInputType.MouseButton1 then
        dragging = false
    end
end)

local ScrollingFrame = Instance.new("ScrollingFrame")
ScrollingFrame.Size = UDim2.new(1, -8, 1, -60)
ScrollingFrame.Position = UDim2.new(0, 4, 0, 54)
ScrollingFrame.BackgroundTransparency = 1
ScrollingFrame.BorderSizePixel = 0
ScrollingFrame.CanvasSize = UDim2.new(0, 0, 0, 380)
ScrollingFrame.ScrollBarThickness = 6
ScrollingFrame.ScrollBarImageColor3 = Color3.fromRGB(212, 175, 55)
ScrollingFrame.ScrollingDirection = Enum.ScrollingDirection.Y
ScrollingFrame.ElasticBehavior = Enum.ElasticBehavior.WhenScrollable
ScrollingFrame.ZIndex = 2
ScrollingFrame.Parent = MainFrame

local function makeToggle(yPos, text, icon, defaultState, callback)
    local btn = Instance.new("TextButton")
    btn.Size = UDim2.new(1, -16, 0, 60)
    btn.Position = UDim2.new(0, 8, 0, yPos)
    btn.BackgroundColor3 = defaultState and Color3.fromRGB(25, 70, 25) or Color3.fromRGB(22, 22, 22)
    btn.BorderSizePixel = 2
    btn.BorderColor3 = defaultState and Color3.fromRGB(80, 220, 80) or Color3.fromRGB(50, 50, 50)
    btn.Text = ""
    btn.AutoButtonColor = false
    btn.Active = true
    btn.ZIndex = 3
    btn.Parent = ScrollingFrame
    Instance.new("UICorner", btn).CornerRadius = UDim.new(0, 14)

    local iconLbl = Instance.new("TextLabel")
    iconLbl.Size = UDim2.new(0, 44, 1, 0)
    iconLbl.Position = UDim2.new(1, -46, 0, 0)
    iconLbl.BackgroundTransparency = 1
    iconLbl.Text = icon
    iconLbl.TextSize = 26
    iconLbl.Font = Enum.Font.GothamBold
    iconLbl.ZIndex = 4
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
    textLbl.ZIndex = 4
    textLbl.Parent = btn

    local dot = Instance.new("Frame")
    dot.Size = UDim2.new(0, 12, 0, 12)
    dot.Position = UDim2.new(0, 16, 0.5, -6)
    dot.BackgroundColor3 = defaultState and Color3.fromRGB(80, 220, 80) or Color3.fromRGB(100, 100, 100)
    dot.BorderSizePixel = 0
    dot.ZIndex = 4
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

local SpeedLabel = Instance.new("TextLabel")
SpeedLabel.Size = UDim2.new(0, 170, 0, 34)
SpeedLabel.Position = UDim2.new(0, 8, 0, 10)
SpeedLabel.BackgroundTransparency = 1
SpeedLabel.Text = "⚡ سرعة التجميع"
SpeedLabel.TextColor3 = Color3.fromRGB(200, 200, 200)
SpeedLabel.Font = Enum.Font.GothamBold
SpeedLabel.TextSize = 14
SpeedLabel.TextXAlignment = Enum.TextXAlignment.Right
SpeedLabel.ZIndex = 3
SpeedLabel.Parent = ScrollingFrame

local SpeedBox = Instance.new("TextBox")
SpeedBox.Size = UDim2.new(0, 80, 0, 34)
SpeedBox.Position = UDim2.new(1, -96, 0, 10)
SpeedBox.BackgroundColor3 = Color3.fromRGB(22, 22, 22)
SpeedBox.BorderSizePixel = 2
SpeedBox.BorderColor3 = Color3.fromRGB(212, 175, 55)
SpeedBox.Text = tostring(walkSpeed)
SpeedBox.TextColor3 = Color3.fromRGB(212, 175, 55)
SpeedBox.Font = Enum.Font.GothamBold
SpeedBox.TextSize = 16
SpeedBox.Active = true
SpeedBox.ZIndex = 3
SpeedBox.Parent = ScrollingFrame
Instance.new("UICorner", SpeedBox).CornerRadius = UDim.new(0, 10)

SpeedBox.FocusLost:Connect(function()
    local n = tonumber(SpeedBox.Text)
    if n and n >= 10 and n <= 30 then
        walkSpeed = n
        FLY_SPEED = n
    else
        SpeedBox.Text = tostring(walkSpeed)
    end
end)

local FarmBtn = makeToggle(56, "طيران + جمع + هروب", "✈️", false, function(state)
    farmActive = state
    if state then
        phase = "scanning"
        scanStart = tick()
        detectionComplete = false
        stuckCoins = {}
        currentCoin = nil
        coinAttemptStart = tick()
        farmStartedAt = tick()
        lastCoinCount = 0
        escapeTarget = nil
        collectingCoin = false
        print("[PHASE] Starting scan...")
    else
        phase = "idle"
        local char = LocalPlayer.Character
        if char then
            local hum = char:FindFirstChildOfClass("Humanoid")
            if hum then hum.PlatformStand = false; hum.WalkSpeed = 16 end
            for _, part in ipairs(char:GetDescendants()) do
                if part:IsA("BasePart") then part.CanCollide = true end
            end
        end
        currentCoin = nil
        collectingCoin = false
    end
end)

local FlingBtn = makeToggle(122, "فلنك القاتل", "💥", true, function(state)
    flingActive = state
end)

local SmartAllBtn = makeToggle(188, "ذكي شامل (شريف + زومبي)", "🧠", true, function(state)
    smartAllActive = state
end)

local AFKBtn = makeToggle(254, "مكافحة الطرد", "⏳", true, function(state)
    antiAFKActive = state
end)

local CoinPanel = Instance.new("Frame")
CoinPanel.Size = UDim2.new(1, -16, 0, 44)
CoinPanel.Position = UDim2.new(0, 8, 0, 320)
CoinPanel.BackgroundColor3 = Color3.fromRGB(15, 15, 15)
CoinPanel.BorderSizePixel = 2
CoinPanel.BorderColor3 = Color3.fromRGB(212, 175, 55)
CoinPanel.ZIndex = 3
CoinPanel.Parent = ScrollingFrame
Instance.new("UICorner", CoinPanel).CornerRadius = UDim.new(0, 12)

local CoinInfo = Instance.new("TextLabel")
CoinInfo.Size = UDim2.new(1, -12, 1, 0)
CoinInfo.Position = UDim2.new(0, 6, 0, 0)
CoinInfo.BackgroundTransparency = 1
CoinInfo.Text = "🪙 0 / 50"
CoinInfo.TextColor3 = Color3.fromRGB(212, 175, 55)
CoinInfo.Font = Enum.Font.GothamBold
CoinInfo.TextSize = 13
CoinInfo.ZIndex = 4
CoinInfo.Parent = CoinPanel

local FULL_SIZE = UDim2.new(0, 340, 0, 400)

local function openMenu()
    MainFrame.Visible = true
    MainFrame.Size = UDim2.new(0, 0, 0, 0)
    TweenService:Create(MainFrame, TweenInfo.new(0.35, Enum.EasingStyle.Back, Enum.EasingDirection.Out), {
        Size = FULL_SIZE
    }):Play()
end

local function closeMenu()
    local tw = TweenService:Create(MainFrame, TweenInfo.new(0.2, Enum.EasingStyle.Quad, Enum.EasingDirection.In), {
        Size = UDim2.new(0, 0, 0, 0)
    })
    tw:Play()
    tw.Completed:Once(function()
        MainFrame.Visible = false
        MainFrame.Size = FULL_SIZE
    end)
end

CloseBtn.MouseButton1Click:Connect(closeMenu)

local fbDragging = false
local fbStartPos, fbStartBtnPos
local fbMoved = false

FloatBtn.InputBegan:Connect(function(input)
    if input.UserInputType == Enum.UserInputType.Touch or input.UserInputType == Enum.UserInputType.MouseButton1 then
        fbDragging = true
        fbStartPos = Vector2.new(input.Position.X, input.Position.Y)
        fbStartBtnPos = FloatBtn.Position
        fbMoved = false
    end
end)

UserInputService.InputChanged:Connect(function(input)
    if not fbDragging then return end
    if input.UserInputType == Enum.UserInputType.Touch or input.UserInputType == Enum.UserInputType.MouseMovement then
        local currentPos = Vector2.new(input.Position.X, input.Position.Y)
        local delta = currentPos - fbStartPos
        if delta.Magnitude > 8 then
            fbMoved = true
            FloatBtn.Position = UDim2.new(fbStartBtnPos.X.Scale, fbStartBtnPos.X.Offset + delta.X, fbStartBtnPos.Y.Scale, fbStartBtnPos.Y.Offset + delta.Y)
        end
    end
end)

UserInputService.InputEnded:Connect(function(input)
    if input.UserInputType == Enum.UserInputType.Touch or input.UserInputType == Enum.UserInputType.MouseButton1 then
        if fbDragging and not fbMoved then
            if MainFrame.Visible then closeMenu() else openMenu() end
        end
        fbDragging = false
    end
end)

local function updateCoinInfo()
    local uiCur, uiMax = getUICoinCount()
    local mapCount = #getAllCoins()
    local displayCount = uiCur > 0 and uiCur or 0
    local displayMax = uiMax > 0 and uiMax or COIN_LIMIT
    local roleTag = ""
    if isLocalZombie() then roleTag = " 🧟"
    elseif isLocalSheriff() then roleTag = " 🔫"
    elseif isLocalMurderer() then roleTag = " 🔪"
    else roleTag = " 👤"
    end
    local escapeTag = escapeTarget and " 🏃" or ""
    local collectTag = collectingCoin and " ✋" or ""
    local lobbyTag = (mapCount == 0) and " (لوبي)" or ""
    local phaseTag = ""
    if phase == "scanning" then phaseTag = " 🔍"
    elseif phase == "farming" then phaseTag = " 🌾"
    end
    CoinInfo.Text = "🪙 " .. displayCount .. "/" .. displayMax .. roleTag .. escapeTag .. collectTag .. phaseTag .. lobbyTag
end

RunService.Heartbeat:Connect(function()
    pcall(updateCoinInfo)
end)

LocalPlayer.CharacterAdded:Connect(function(char)
    task.wait(0.5)
    currentCoin = nil
    coinAttemptStart = tick()
    sheriffKillInProgress = false
    activelyFlinging = {}
    escapeTarget = nil
    collectingCoin = false
    if farmActive then
        phase = "scanning"
        scanStart = tick()
        detectionComplete = false
    end
    if not farmActive then
        local hum = char:FindFirstChildOfClass("Humanoid")
        if hum then hum.WalkSpeed = 16 end
    end
end)
