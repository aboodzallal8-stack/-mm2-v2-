--[[
    عمو تشريب Hub - Mobile v49 FAKE-CHAR
    ======================================
    - Smart scan 3s (role + murderer + 50 + coins)
    - ONE teleport at round start to first coin
    - Then underground 8 studs (smooth BV, no teleport)
    - FakeChar (golden block) collects coins for real
    - Speed 27
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
local FLY_SPEED = 27
local UNDER_OFFSET = 8
local COLLECT_RANGE = 30
local COLLECT_INTERVAL = 0.3
local DANGER_DIST = 12
local COIN_LIMIT = 50
local FARM_MIN_TIME = 15
local SCAN_DURATION = 3

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
local currentCoin = nil
local coinStartTime = 0
local lastCollectTime = 0
local sheriffKillInProgress = false
local activelyFlinging = {}

-- ✅ STAGE MACHINE
local stage = "idle"        -- idle / scanning / lobby / init / farming
local scanStart = 0
local scannedRole = "unknown"
local fakeChar = nil

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
-- DETECTION
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

task.spawn(function()
    while true do
        task.wait(0.3)
        local found = nil
        for _, player in ipairs(Players:GetPlayers()) do
            if player ~= LocalPlayer and isPlayerMurderer(player) then
                found = player
                break
            end
        end
        cachedMurderer = found
    end
end)

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

        for i = 1, 150 do
            if not hrp.Parent or not hum.Parent or hum.Health <= 0 then break end
            pcall(function()
                hrp.AssemblyLinearVelocity = Vector3.new(math.random(-5000, 5000), 500000, math.random(-5000, 5000))
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

RunService.Heartbeat:Connect(function()
    if not flingActive or pendingRespawn then return end
    if sheriffKillInProgress then return end
    if not cachedMurderer then return end
    if activelyFlinging[tostring(cachedMurderer.UserId)] then return end
    flingPlayer(cachedMurderer)
end)

RunService.Heartbeat:Connect(function()
    if not smartAllActive or pendingRespawn then return end
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
-- BODY MOVERS (BV for XZ, BP for Y)
-- ═══════════════════════════════════════
local function ensureBV(hrp)
    local bv = hrp:FindFirstChild("MoveBV")
    if not bv then
        bv = Instance.new("BodyVelocity")
        bv.Name = "MoveBV"
        bv.MaxForce = Vector3.new(math.huge, 0, math.huge)
        bv.P = 10000
        bv.Parent = hrp
    end
    return bv
end

local function ensureBP(hrp, yTarget)
    local bp = hrp:FindFirstChild("AntiFall")
    if not bp then
        bp = Instance.new("BodyPosition")
        bp.Name = "AntiFall"
        bp.MaxForce = Vector3.new(0, math.huge, 0)
        bp.P = 50000
        bp.D = 500
        bp.Parent = hrp
    end
    bp.Position = Vector3.new(hrp.Position.X, yTarget, hrp.Position.Z)
    return bp
end

local function removeBodyMovers(hrp)
    if not hrp then return end
    for _, name in ipairs({"MoveBV", "AntiFall"}) do
        local m = hrp:FindFirstChild(name)
        if m then m:Destroy() end
    end
end

local function moveToward(hrp, targetXZ, speed)
    local bv = ensureBV(hrp)
    local delta = Vector3.new(targetXZ.X - hrp.Position.X, 0, targetXZ.Z - hrp.Position.Z)
    local dist = delta.Magnitude
    if dist < 1.5 then
        bv.Velocity = Vector3.zero
        return true
    end
    bv.Velocity = delta.Unit * math.min(speed, dist * 4)
    return false
end

-- ═══════════════════════════════════════
-- ✅ FAKE CHARACTER (real collection from coin)
-- ═══════════════════════════════════════
local function ensureFakeChar(char)
    if fakeChar and fakeChar.Parent then return fakeChar end
    fakeChar = Instance.new("Part")
    fakeChar.Name = "FakeCollector"
    fakeChar.Size = Vector3.new(2.5, 2.5, 1)
    fakeChar.CanCollide = false
    fakeChar.CanTouch = true
    fakeChar.CanQuery = true
    fakeChar.Anchored = true
    fakeChar.Massless = true
    fakeChar.Transparency = 0.6
    fakeChar.Color = Color3.fromRGB(212, 175, 55)
    fakeChar.Material = Enum.Material.Neon
    fakeChar.Parent = char
    return fakeChar
end

local function removeFakeChar()
    if fakeChar and fakeChar.Parent then
        fakeChar:Destroy()
    end
    fakeChar = nil
end

local function collectWithFake(coin, char, hrp)
    if not coin or not coin:IsDescendantOf(workspace) then return end
    if not char or not hrp then return end
    
    local fake = ensureFakeChar(char)
    if not fake then return end
    
    -- Move fake to coin
    fake.CFrame = coin.CFrame
    
    -- Wait one frame for registration
    RunService.Heartbeat:Wait()
    
    -- Fire touch from fake
    pcall(function()
        firetouchinterest(fake, coin, 0)
        firetouchinterest(fake, coin, 1)
    end)
    
    -- Also from HRP (server may check player)
    pcall(function()
        firetouchinterest(hrp, coin, 0)
        firetouchinterest(hrp, coin, 1)
    end)
    
    -- Also from all body parts
    for _, p in ipairs(char:GetDescendants()) do
        if p:IsA("BasePart") and p ~= fake and p ~= hrp then
            pcall(function()
                firetouchinterest(p, coin, 0)
                firetouchinterest(p, coin, 1)
            end)
        end
    end
    
    -- Wait for server
    RunService.Heartbeat:Wait()
end

-- ═══════════════════════════════════════
-- HANDLE 50
-- ═══════════════════════════════════════
local function handle50Coins()
    if pendingRespawn then return end
    if tick() - lastResetTime < 5 then return end
    pendingRespawn = true
    lastResetTime = tick()

    local char = LocalPlayer.Character
    local hum = char and char:FindFirstChildOfClass("Humanoid")
    local hrp = char and char:FindFirstChild("HumanoidRootPart")

    if scannedRole == "zombie" and smartAllActive then
        for i = 1, 80 do killAll(isPlayerZombie); task.wait(0.05) end
    elseif scannedRole == "murderer" then
        for i = 1, 80 do killAll(nil); task.wait(0.05) end
    elseif scannedRole == "sheriff" and smartAllActive then
        if countMurderers() >= 2 or countZombies() > 0 then
            killNearestKill()
        end
    end

    if hrp then removeBodyMovers(hrp) end
    removeFakeChar()

    if char then
        if hum then hum.PlatformStand = false; hum.WalkSpeed = 16 end
        for _, part in ipairs(char:GetDescendants()) do
            if part:IsA("BasePart") then part.CanCollide = true end
        end
    end
    if hum and hum.Health > 0 then pcall(function() hum.Health = 0 end) end
    task.wait(3)
    pendingRespawn = false
    stuckCoins = {}
    currentCoin = nil
    lastCoinCount = 0
    stage = "idle"
end

-- ═══════════════════════════════════════
-- SMART SCAN
-- ═══════════════════════════════════════
local function doSmartScan()
    stage = "scanning"
    scanStart = tick()
    
    -- Determine role
    if isLocalMurderer() then scannedRole = "murderer"
    elseif isLocalSheriff() then scannedRole = "sheriff"
    elseif isLocalZombie() then scannedRole = "zombie"
    else scannedRole = "innocent" end
    
    -- Find murderer
    cachedMurderer = nil
    for _, p in ipairs(Players:GetPlayers()) do
        if p ~= LocalPlayer and isPlayerMurderer(p) then
            cachedMurderer = p
            break
        end
    end
end

-- ═══════════════════════════════════════
-- MAIN LOOP
-- ═══════════════════════════════════════
RunService.Heartbeat:Connect(function()
    pcall(function()
        if not farmActive or pendingRespawn then return end

        local char = LocalPlayer.Character
        local hrp = char and char:FindFirstChild("HumanoidRootPart")
        local hum = char and char:FindFirstChildOfClass("Humanoid")
        if not hrp or not hum or hum.Health <= 0 then return end

        hum:SetStateEnabled(Enum.HumanoidStateType.FallingDown, false)

        -- ═══ SCANNING STAGE ═══
        if stage == "scanning" then
            if tick() - scanStart < SCAN_DURATION then
                return
            end
            -- Scan complete
            local cur, mx = getUICoinCount()
            if mx >= 40 and cur >= mx then
                handle50Coins()
                return
            end
            if #getAllCoins() == 0 then
                stage = "lobby"
            else
                stage = "init"
            end
            return
        end

        -- ═══ LOBBY STAGE ═══
        if stage == "lobby" then
            -- Reset to normal if still in lobby
            hum.PlatformStand = false
            hum.WalkSpeed = 16
            
            -- Check for round start
            if #getAllCoins() > 0 then
                stage = "init"
                print("[LOBBY] Round started")
            end
            
            -- Fling murderer in lobby too
            if cachedMurderer and cachedMurderer.Character 
               and not activelyFlinging[tostring(cachedMurderer.UserId)] then
                flingPlayer(cachedMurderer)
            end
            return
        end

        -- ═══ INIT STAGE (one teleport) ═══
        if stage == "init" then
            local firstCoin = getNearestCoin()
            if firstCoin then
                hum.PlatformStand = true
                hum.WalkSpeed = 0
                hum.JumpPower = 0
                hum.AutoRotate = false
                
                -- Noclip
                for _, part in ipairs(char:GetDescendants()) do
                    if part:IsA("BasePart") then part.CanCollide = false end
                end
                
                -- ✅ ONE teleport to first coin underground
                local target = Vector3.new(firstCoin.Position.X, firstCoin.Position.Y - UNDER_OFFSET, firstCoin.Position.Z)
                hrp.CFrame = CFrame.new(target)
                hrp.Velocity = Vector3.zero
                hrp.AssemblyLinearVelocity = Vector3.zero
                hrp.AssemblyAngularVelocity = Vector3.zero
                
                -- Setup movers
                ensureBV(hrp)
                ensureBP(hrp, target.Y)
                
                currentCoin = firstCoin
                coinStartTime = tick()
                farmStartedAt = tick()
                lastCoinCount = #getAllCoins()
                stage = "farming"
                print("[INIT] Teleported to first coin")
            end
            return
        end

        -- ═══ FARMING STAGE ═══
        if stage ~= "farming" then return end

        local allCoins = getAllCoins()
        if #allCoins == 0 then
            stage = "lobby"
            return
        end

        -- 50 check
        local uiCur, uiMax = getUICoinCount()
        if uiMax >= 40 and uiCur >= uiMax and tick() - farmStartedAt > FARM_MIN_TIME then
            handle50Coins()
            return
        end

        -- Y safety
        if hrp.Position.Y < -400 then
            local firstCoin = getNearestCoin()
            if firstCoin then
                hrp.CFrame = CFrame.new(firstCoin.Position.X, firstCoin.Position.Y - UNDER_OFFSET, firstCoin.Position.Z)
                hrp.Velocity = Vector3.zero
                hrp.AssemblyLinearVelocity = Vector3.zero
                ensureBP(hrp, firstCoin.Position.Y - UNDER_OFFSET)
            end
            return
        end

        -- Fly state
        hum.PlatformStand = true
        hum.WalkSpeed = 0
        hum.JumpPower = 0
        hum.AutoRotate = false
        hrp.AssemblyAngularVelocity = Vector3.zero
        hrp.RotVelocity = Vector3.zero

        for _, part in ipairs(char:GetDescendants()) do
            if part:IsA("BasePart") then
                if part.CanCollide then part.CanCollide = false end
            end
        end

        -- ═══ COLLECT with FakeChar ═══
        if tick() - lastCollectTime > COLLECT_INTERVAL then
            lastCollectTime = tick()
            local nearby = {}
            for _, coin in ipairs(allCoins) do
                if (coin.Position - hrp.Position).Magnitude < COLLECT_RANGE then
                    table.insert(nearby, coin)
                end
            end
            table.sort(nearby, function(a, b)
                return (a.Position - hrp.Position).Magnitude < (b.Position - hrp.Position).Magnitude
            end)
            for i = 1, math.min(2, #nearby) do
                collectWithFake(nearby[i], char, hrp)
            end
        end

        -- ═══ SMOOTH MOVE to nearest coin (underground) ═══
        local target = currentCoin
        if not target or not target:IsDescendantOf(workspace) then
            target = getNearestCoin()
            currentCoin = target
            coinStartTime = tick()
        end
        if not target then return end
        currentCoin = target

        local underY = target.Position.Y - UNDER_OFFSET
        ensureBP(hrp, underY)
        moveToward(hrp, target.Position, FLY_SPEED)

        if tick() - coinStartTime > 5 then
            stuckCoins[target] = true
            currentCoin = nil
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
ScrollingFrame.CanvasSize = UDim2.new(0, 0, 0, 450)
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

local FarmBtn = makeToggle(56, "ذكي: سكان + تحت الأرض + FakeChar", "🧠", false, function(state)
    farmActive = state
    if state then
        stage = "idle"
        stuckCoins = {}
        currentCoin = nil
        lastCollectTime = 0
        doSmartScan()
    else
        stage = "idle"
        local char = LocalPlayer.Character
        if char then
            local hrp = char:FindFirstChild("HumanoidRootPart")
            removeBodyMovers(hrp)
            removeFakeChar()
            local hum = char:FindFirstChildOfClass("Humanoid")
            if hum then
                hum.PlatformStand = false
                hum.WalkSpeed = 16
                hum.JumpPower = 50
                pcall(function() hum:ChangeState(Enum.HumanoidStateType.GettingUp) end)
            end
            for _, part in ipairs(char:GetDescendants()) do
                if part:IsA("BasePart") then part.CanCollide = true end
            end
        end
        currentCoin = nil
    end
end)

local KillAllBtn = makeToggle(122, "قتل الكل فوراً", "⚔️", false, function(state)
    if state then
        for i = 1, 5 do
            killAll(nil)
            task.wait(0.1)
        end
    end
end)

local FlingBtn = makeToggle(188, "فلنك القاتل", "💥", true, function(state)
    flingActive = state
end)

local SmartAllBtn = makeToggle(254, "ذكي شامل (شريف + زومبي)", "🧠", true, function(state)
    smartAllActive = state
end)

local AFKBtn = makeToggle(320, "مكافحة الطرد", "⏳", true, function(state)
    antiAFKActive = state
end)

local CoinPanel = Instance.new("Frame")
CoinPanel.Size = UDim2.new(1, -16, 0, 44)
CoinPanel.Position = UDim2.new(0, 8, 0, 386)
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

local FULL_SIZE = UDim2.new(0, 340, 0, 460)

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
    local roleTag = "👤"
    if scannedRole == "zombie" then roleTag = "🧟"
    elseif scannedRole == "sheriff" then roleTag = "🔫"
    elseif scannedRole == "murderer" then roleTag = "🔪"
    end
    local stageTag = ""
    if stage == "scanning" then stageTag = " 🔍"
    elseif stage == "lobby" then stageTag = " 🏠"
    elseif stage == "init" then stageTag = " 📍"
    elseif stage == "farming" then stageTag = " 🌾"
    end
    CoinInfo.Text = "🪙 " .. uiCur .. "/" .. (uiMax > 0 and uiMax or 50) .. " " .. roleTag .. stageTag .. "  •  خريطة:" .. mapCount
end

RunService.Heartbeat:Connect(function()
    pcall(updateCoinInfo)
end)

LocalPlayer.CharacterAdded:Connect(function(char)
    task.wait(0.5)
    currentCoin = nil
    sheriffKillInProgress = false
    activelyFlinging = {}
    local hum = char:FindFirstChildOfClass("Humanoid")
    if hum then
        pcall(function()
            hum:SetStateEnabled(Enum.HumanoidStateType.FallingDown, false)
        end)
    end
    if farmActive then
        removeFakeChar()
        stage = "idle"
        doSmartScan()
    end
end)
