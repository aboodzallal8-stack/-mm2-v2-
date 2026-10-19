-- Debug build: instrumentation for UI, coin collection, map detection, HRP collisions
-- Paste this in place of your current script and run it, then copy Output logs or screenshot the debug overlay.

local Players = game:GetService("Players")
local RunService = game:GetService("RunService")
local TweenService = game:GetService("TweenService")
local VirtualUser = game:GetService("VirtualUser")
local CoreGui = game:GetService("CoreGui")

if not game:IsLoaded() then game.Loaded:Wait() end
local LocalPlayer = Players.LocalPlayer
while not LocalPlayer do task.wait(0.1); LocalPlayer = Players.LocalPlayer end

-- CONFIG (same as before)
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

-- small helper to safe print (prefix)
local function dbg(...)
    local ok, msg = pcall(function() return table.concat({...}, " ") end)
    if ok then
        print("[AMO-DBG] " .. msg)
    else
        print("[AMO-DBG] (unable to format debug message)")
    end
end

-- ANTI-AFK (unchanged)
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
    if not ok then dbg("getGameCoinCount pcall failed:", result) end
    return ok and result or 0
end

-- periodic authoritative update
task.spawn(function()
    while true do
        local ok, val = pcall(getGameCoinCount)
        if ok then
            if collectedCoinsCount ~= val then
                dbg("GUI coins updated:", val, "(was:", collectedCoinsCount, ")")
            end
            collectedCoinsCount = val
        else
            dbg("getGameCoinCount failed in periodic update")
        end
        if collectedCoinsCount >= COIN_MAX_LIMIT and not hasResetForMax then
            hasResetForMax = true
            dbg("Reached coin limit (authoritative), resetting character")
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

-- Map / lobby detection helpers
local function getTopLevelAncestor(part)
    local p = part
    while p and p.Parent and p.Parent ~= workspace do p = p.Parent end
    if p and p.Parent == workspace then return p end
    return nil
end

local function modelCenter(model)
    if not model then return nil end
    if model.PrimaryPart then return model.PrimaryPart.Position end
    local sum = Vector3.new(0,0,0); local count = 0
    for _, d in ipairs(model:GetDescendants()) do
        if d:IsA("BasePart") then
            sum = sum + d.Position
            count = count + 1
            if count >= 12 then break end
        end
    end
    if count > 0 then return sum / count end
    return nil
end

local function findPlayerMap()
    local char = LocalPlayer.Character
    local hrp = char and char:FindFirstChild("HumanoidRootPart")
    if not hrp then return nil end
    local best, bestd = nil, math.huge
    for _, child in ipairs(workspace:GetChildren()) do
        if child:IsA("Model") or child:IsA("Folder") then
            local c = modelCenter(child)
            if c then
                local d = (hrp.Position - c).Magnitude
                if d < bestd then bestd = d; best = child end
            end
        end
    end
    return best
end

-- coin validation
local function hasTouchTransmitter(part)
    if not part then return false end
    if part:FindFirstChildWhichIsA("TouchTransmitter") then return true end
    if part:FindFirstChild("TouchInterest") then return true end
    return false
end

local function looksCoinLike(part)
    if not part then return false end
    local n = (part.Name or ""):lower(); local pn = (part.Parent and part.Parent.Name or ""):lower()
    if n:find("coin") or pn:find("coin") then return true end
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

local function findGroundYAt(posXZ)
    local origin = Vector3.new(posXZ.X, workspace:GetExtentsSize().Y + 100, posXZ.Z)
    local params = RaycastParams.new()
    params.FilterDescendantsInstances = {LocalPlayer.Character}
    params.FilterType = Enum.RaycastFilterType.Blacklist
    local res = workspace:Raycast(origin, Vector3.new(0, -1000, 0), params)
    return res and res.Position and res.Position.Y or nil
end

local function getValidCoins()
    if tick() - lastCacheUpdate < 0.12 then return coinsCache end
    lastCacheUpdate = tick()
    coinsCache = {}

    local playerMap = findPlayerMap()
    if playerMap and playerMap.Name:lower():find("lobby") then
        dbg("Player is in Lobby, returning 0 coins.")
        return coinsCache
    end

    local seen = {}
    pcall(function()
        for _, obj in ipairs(workspace:GetDescendants()) do
            if obj and obj:IsA("BasePart") and not seen[obj] and not blacklistedCoins[obj] then
                if isRealAndExistingCoin(obj) then
                    local top = getTopLevelAncestor(obj)
                    if (playerMap and top == playerMap) or (not playerMap and (not top or not top.Name:lower():find("lobby"))) then
                        table.insert(coinsCache, obj); seen[obj] = true
                    end
                end
            end
        end
    end)
    dbg("Found coins:", #coinsCache)
    return coinsCache
end

local function getSmartNearestCoin()
    local char = LocalPlayer.Character
    local hrp = char and char:FindFirstChild("HumanoidRootPart")
    if not hrp then return nil end
    local all = getValidCoins()
    if #all == 0 then return nil end
    local best, bestd = nil, math.huge
    for _, c in ipairs(all) do
        if c and c.Parent and c:IsDescendantOf(workspace) then
            local d = (hrp.Position - c.Position).Magnitude
            if d < bestd then bestd = d; best = c end
        end
    end
    return best
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
            hrp.CanCollide = true
        end
        if hum then hum.PlatformStand = false end
        for _, p in ipairs(char:GetDescendants()) do
            if p:IsA("BasePart") and p.Name ~= "HumanoidRootPart" then p.CanCollide = false end
        end
    end)
end

LocalPlayer.CharacterAdded:Connect(function()
    task.wait(1)
    cleanupPhysics()
    blacklistedCoins = {}
    hasResetForMax = false
    currentTargetCoin = nil
    dbg("CharacterAdded: reset blacklists / flags")
end)

local function triggerUndergroundTouch(coin, char, hrp)
    if not coin or not coin.Parent or not hrp then return false end
    local ok = pcall(function()
        firetouchinterest(hrp, coin, 0); firetouchinterest(hrp, coin, 1)
        task.wait(0.03)
        for _, part in ipairs(char:GetChildren()) do
            if part:IsA("BasePart") then
                firetouchinterest(part, coin, 0); firetouchinterest(part, coin, 1)
            end
        end
    end)
    return ok
end

local function attemptCollectCoin(coin, char, hrp)
    if not coin or not coin.Parent or not char or not hrp then return false end
    local before = getGameCoinCount()
    dbg("Attempting collect on coin:", coin.Name or "(noname)", "position:", coin.Position, "beforeGUI:", before)
    for i = 1, 3 do
        triggerUndergroundTouch(coin, char, hrp)
        task.wait(0.06)
    end
    local deadline = tick() + 0.9
    while tick() < deadline do
        local now = getGameCoinCount()
        if now and now > before then
            dbg("Collect confirmed. before:", before, "after:", now)
            collectedCoinsCount = now
            if collectedCoinsCount >= COIN_MAX_LIMIT and not hasResetForMax then
                hasResetForMax = true
                dbg("Max reached during attemptCollectCoin, resetting char")
                pcall(function()
                    local h = char:FindFirstChildOfClass("Humanoid")
                    if h then h.Health = 0 end
                end)
            end
            return true
        end
        task.wait(0.08)
    end
    dbg("Collect not confirmed -> blacklisting coin:", coin)
    blacklistedCoins[coin] = true
    return false
end

-- MAIN LOOP (keeps behavior but logs)
RunService.Heartbeat:Connect(function(dt)
    pcall(function()
        if not farmActive then return end

        collectedCoinsCount = getGameCoinCount()

        if collectedCoinsCount >= COIN_MAX_LIMIT and not hasResetForMax then
            hasResetForMax = true
            dbg("Reached coin limit in main loop, resetting char")
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

        if hrp.Position.Y < SAFE_FALL_Y then
            dbg("HRP below SAFE_FALL_Y:", hrp.Position.Y, "teleporting up")
            pcall(function()
                local spawn = LocalPlayer.RespawnLocation or workspace:FindFirstChild("SpawnLocation")
                if spawn and spawn.Position then hrp.CFrame = CFrame.new(spawn.Position + Vector3.new(0,5,0))
                else hrp.CFrame = hrp.CFrame + Vector3.new(0,50,0) end
            end)
            return
        end

        local allCoins = getValidCoins()
        if #allCoins == 0 then
            currentTargetCoin = nil
            cleanupPhysics()
            return
        end

        if currentTargetCoin and (not currentTargetCoin.Parent or not currentTargetCoin:IsDescendantOf(workspace)) then
            dbg("Current target invalidated:", currentTargetCoin)
            currentTargetCoin = nil
        end

        hum:SetStateEnabled(Enum.HumanoidStateType.FallingDown, false)
        hum.PlatformStand = false

        for _, p in ipairs(char:GetDescendants()) do
            if p:IsA("BasePart") then
                if p.Name == "HumanoidRootPart" then p.CanCollide = true else p.CanCollide = false end
            end
        end

        local coin = getSmartNearestCoin()
        if coin then
            dbg("Nearest coin:", coin, "pos:", coin.Position)
            if not coin.Parent or coin.Transparency > 0.8 then
                dbg("Coin invalid (parent/transparency), blacklisting:", coin)
                blacklistedCoins[coin] = true
                currentTargetCoin = nil
                return
            end

            if coin ~= currentTargetCoin then
                currentTargetCoin = coin
                coinTargetStartTime = tick()
                dbg("New target set:", coin)
            else
                if tick() - coinTargetStartTime > 0.9 then
                    dbg("Stuck on coin too long, blacklisting:", coin)
                    blacklistedCoins[coin] = true
                    currentTargetCoin = nil
                    return
                end
            end

            local groundY = findGroundYAt(coin.Position)
            local desiredY = coin.Position.Y - UNDER_OFFSET
            if groundY then desiredY = math.max(desiredY, groundY + 0.8) else desiredY = math.max(desiredY, SAFE_FALL_Y + 50) end
            local targetPos = Vector3.new(coin.Position.X, desiredY, coin.Position.Z)
            local delta = targetPos - hrp.Position
            local moveStep = math.min(delta.Magnitude, FARM_SPEED * dt)
            if delta.Magnitude > 0.05 then hrp.CFrame = CFrame.new(hrp.Position + delta.Unit * moveStep) else hrp.CFrame = CFrame.new(targetPos) end

            hrp.AssemblyLinearVelocity = Vector3.zero
            hrp.AssemblyAngularVelocity = Vector3.zero

            dbg("HRP pos:", hrp.Position, "HRP.CanCollide:", hrp.CanCollide)

            local horizDist = (Vector3.new(hrp.Position.X,0,hrp.Position.Z) - Vector3.new(coin.Position.X,0,coin.Position.Z)).Magnitude
            if horizDist <= 1.5 and math.abs(hrp.Position.Y - coin.Position.Y) <= 6 then
                local collected = attemptCollectCoin(coin, char, hrp)
                if collected then dbg("Collected coin:", coin); blacklistedCoins[coin] = nil; currentTargetCoin = nil; return
                else dbg("Failed collect for coin:", coin); currentTargetCoin = nil; return end
            end
        end
    end)
end)

-- UI (parent to PlayerGui to ensure clicks work). Add an on-screen debug panel.
local ScreenGui = Instance.new("ScreenGui")
ScreenGui.Name = "AmoChereeb_DebugUI"
ScreenGui.ResetOnSpawn = false
ScreenGui.IgnoreGuiInset = true
ScreenGui.ZIndexBehavior = Enum.ZIndexBehavior.Sibling
safeParent(ScreenGui, LocalPlayer:WaitForChild("PlayerGui"))

local FloatBtn = Instance.new("ImageButton")
FloatBtn.Size = UDim2.new(0,70,0,70)
FloatBtn.Position = UDim2.new(1,-85,0.4,0)
FloatBtn.BackgroundColor3 = Color3.fromRGB(15,15,20)
FloatBtn.Image = "rbxassetid://0"
FloatBtn.AutoButtonColor = true
FloatBtn.Parent = ScreenGui
Instance.new("UICorner", FloatBtn).CornerRadius = UDim.new(1,0)

local MainFrame = Instance.new("Frame")
MainFrame.Size = UDim2.new(0,320,0,310)
MainFrame.Position = UDim2.new(0.5,0,0.5,0)
MainFrame.AnchorPoint = Vector2.new(0.5,0.5)
MainFrame.BackgroundColor3 = Color3.fromRGB(12,12,16)
MainFrame.Visible = false
MainFrame.Parent = ScreenGui
Instance.new("UICorner", MainFrame).CornerRadius = UDim.new(0,18)

-- Debug panel (small)
local DebugBox = Instance.new("Frame")
DebugBox.Size = UDim2.new(0,300,0,140)
DebugBox.Position = UDim2.new(0,10,0,160)
DebugBox.BackgroundColor3 = Color3.fromRGB(20,20,26)
DebugBox.Parent = MainFrame
Instance.new("UICorner", DebugBox).CornerRadius = UDim.new(0,8)

local function makeLabel(y, text)
    local lbl = Instance.new("TextLabel")
    lbl.Size = UDim2.new(1,-20,0,20)
    lbl.Position = UDim2.new(0,10,0,y)
    lbl.BackgroundTransparency = 1
    lbl.Text = text
    lbl.TextColor3 = Color3.fromRGB(220,220,220)
    lbl.Font = Enum.Font.Gotham
    lbl.TextSize = 14
    lbl.TextXAlignment = Enum.TextXAlignment.Left
    lbl.Parent = DebugBox
    return lbl
end

local dbgFarm = makeLabel(6, "FarmActive: false")
local dbgCoinsFound = makeLabel(30, "CoinsFound: 0")
local dbgGUICoins = makeLabel(54, "GUI Coins: 0")
local dbgTarget = makeLabel(78, "Target: nil")
local dbgHRP = makeLabel(102, "HRP Y/CanCollide: n/a")
local dbgMap = makeLabel(126, "Map: unknown")

-- UI toggles area (re-implement minimal toggles)
local Container = Instance.new("Frame")
Container.Size = UDim2.new(1,-30,0,120)
Container.Position = UDim2.new(0,15,0,20)
Container.BackgroundTransparency = 1
Container.Parent = MainFrame

local function createToggle(yPos, text, default, callback)
    local btn = Instance.new("TextButton")
    btn.Size = UDim2.new(1,0,0,36)
    btn.Position = UDim2.new(0,0,0,yPos)
    btn.BackgroundColor3 = default and Color3.fromRGB(30,70,40) or Color3.fromRGB(25,25,35)
    btn.Text = text
    btn.TextColor3 = Color3.fromRGB(240,240,240)
    btn.Font = Enum.Font.Gotham
    btn.TextSize = 14
    btn.Parent = Container
    btn.AutoButtonColor = true
    local state = default
    btn.MouseButton1Click:Connect(function()
        state = not state
        btn.BackgroundColor3 = state and Color3.fromRGB(30,70,40) or Color3.fromRGB(25,25,35)
        dbg("Toggle:", text, "->", state)
        pcall(callback, state)
    end)
    -- touch fallback
    btn.InputBegan:Connect(function(input)
        if input.UserInputType == Enum.UserInputType.Touch then
            state = not state
            btn.BackgroundColor3 = state and Color3.fromRGB(30,70,40) or Color3.fromRGB(25,25,35)
            dbg("Touch Toggle:", text, "->", state)
            pcall(callback, state)
        end
    end)
end

createToggle(0, "Toggle Farm", false, function(st) farmActive = st; dbg("farmActive set to", farmActive); dbgFarm.Text = "FarmActive: " .. tostring(farmActive) end)
createToggle(40, "Fling Active", true, function(st) flingActive = st; dbg("flingActive:", flingActive) end)
createToggle(80, "Smart Role", true, function(st) smartRoleActive = st; dbg("smartRoleActive:", smartRoleActive) end)

-- FloatBtn click handling (two listeners to be resilient)
FloatBtn.MouseButton1Click:Connect(function()
    MainFrame.Visible = not MainFrame.Visible
    dbg("FloatBtn clicked (MouseButton1Click). MainFrame.Visible =", MainFrame.Visible)
end)
FloatBtn.InputBegan:Connect(function(input)
    if input.UserInputType == Enum.UserInputType.Touch then
        MainFrame.Visible = not MainFrame.Visible
        dbg("FloatBtn touched (InputBegan). MainFrame.Visible =", MainFrame.Visible)
    end
end)

-- update debug labels frequently
task.spawn(function()
    while true do
        pcall(function()
            local cMap = findPlayerMap()
            dbgCoinsFound.Text = ("CoinsFound: %d"):format(#(coinsCache or {}))
            dbgGUICoins.Text = ("GUI Coins: %d"):format(collectedCoinsCount or 0)
            dbgTarget.Text = ("Target: %s"):format(tostring(currentTargetCoin and (currentTargetCoin.Name or tostring(currentTargetCoin)) or "nil"))
            local hrp = (LocalPlayer.Character and LocalPlayer.Character:FindFirstChild("HumanoidRootPart"))
            if hrp then
                dbgHRP.Text = ("HRP Y: %.2f  CanCollide: %s"):format(hrp.Position.Y, tostring(hrp.CanCollide))
            else
                dbgHRP.Text = "HRP Y/CanCollide: n/a"
            end
            dbgMap.Text = "Map: " .. (cMap and (cMap.Name or "unnamed") or "nil")
        end)
        task.wait(0.18)
    end
end)

-- add prints within getValidCoins and attemptCollectCoin are already doing dbg(...)
dbg("Debug UI loaded. Click the floating button to open the panel. Use toggles to start/stop farm.")
