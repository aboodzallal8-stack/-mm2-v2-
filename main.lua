--[[
    عمو تشريب Hub - Mobile v15 (WALK ONLY + REAL FLING)
    - Walk speed 27 (no fly, no teleport)
    - Fling murderer: continuous every 0.3s until dead
    - Reset at 50
--]]

local Players = game:GetService("Players")
local RunService = game:GetService("RunService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local VirtualUser = game:GetService("VirtualUser")
local CoreGui = game:GetService("CoreGui")

local LocalPlayer = Players.LocalPlayer

-- ========== Config ==========
local walkSpeed = 27  -- سرعة ثابتة 27

-- ========== States ==========
local farmActive = false
local flingMurdererActive = false
local antiAFKActive = true
local pendingRespawn = false
local lastFlingTime = 0

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

-- ========== Speed (fixed 27) ==========
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

-- ========== Murderer Detection (comprehensive) ==========
local function getMurderer()
    -- Method 1: Equipped in character
    for _, player in ipairs(Players:GetPlayers()) do
        if player == LocalPlayer then continue end
        local char = player.Character
        if char then
            for _, item in ipairs(char:GetChildren()) do
                if item:IsA("Tool") and item.Name == "Knife" then return player end
            end
            -- Check descendants too
            for _, item in ipairs(char:GetDescendants()) do
                if item:IsA("Tool") and item.Name == "Knife" then return player end
            end
        end
    end
    -- Method 2: In Backpack
    for _, player in ipairs(Players:GetPlayers()) do
        if player == LocalPlayer then continue end
        local bp = player:FindFirstChild("Backpack")
        if bp then
            for _, item in ipairs(bp:GetDescendants()) do
                if item:IsA("Tool") and item.Name == "Knife" then return player end
            end
        end
    end
    -- Method 3: Knife in workspace
    for _, obj in ipairs(workspace:GetDescendants()) do
        if obj:IsA("Tool") and obj.Name == "Knife" then
            local parent = obj.Parent
            if parent then
                local plr = Players:GetPlayerFromCharacter(parent)
                if plr and plr ~= LocalPlayer then return plr end
            end
        end
    end
    -- Method 4: Attributes
    for _, player in ipairs(Players:GetPlayers()) do
        if player == LocalPlayer then continue end
        local role = player:GetAttribute("Role") or player:GetAttribute("role")
        if role and tostring(role):lower():find("murder") then return player end
    end
    return nil
end

-- ========== REAL Fling (multi-method, continuous) ==========
local function flingMurderer(murderer)
    if not murderer then return end
    task.spawn(function()
        for attempt = 1, 30 do
            local char = murderer.Character
            if not char then break end
            local hrp = char:FindFirstChild("HumanoidRootPart")
            local hum = char:FindFirstChildOfClass("Humanoid")
            if not hrp or not hum or hum.Health <= 0 then break end

            -- Method 1: Velocity fling (spin + fly up)
            pcall(function()
                local bv = hrp:FindFirstChild("FlingBV") or Instance.new("BodyVelocity", hrp)
                bv.Name = "FlingBV"
                bv.MaxForce = Vector3.new(math.huge, math.huge, math.huge)
                bv.Velocity = Vector3.new(math.random(-5000, 5000), 100000, math.random(-5000, 5000))
            end)

            -- Method 2: Angular velocity (spin)
            pcall(function()
                local bav = hrp:FindFirstChild("FlingBAV") or Instance.new("BodyAngularVelocity", hrp)
                bav.Name = "FlingBAV"
                bav.MaxTorque = Vector3.new(math.huge, math.huge, math.huge)
                bav.AngularVelocity = Vector3.new(99999, 99999, 99999)
            end)

            -- Method 3: CFrame teleport to sky
            pcall(function()
                hrp.CFrame = CFrame.new(
                    math.random(-2000, 2000),
                    20000 + (attempt * 2000),
                    math.random(-2000, 2000)
                )
                hum.PlatformStand = true
            end)

            -- Method 4: Direct velocity
            pcall(function()
                hrp.Velocity = Vector3.new(math.random(-30000, 30000), 100000, math.random(-30000, 30000))
                hrp.RotVelocity = Vector3.new(math.random(-500, 500), math.random(-500, 500), math.random(-500, 500))
            end)

            task.wait(0.08)
        end

        -- Cleanup
        task.wait(0.3)
        pcall(function()
            local hum = murderer.Character and murderer.Character:FindFirstChildOfClass("Humanoid")
            if hum then hum.PlatformStand = false end
        end)
    end)
end

-- ========== Continuous Murderer Fling (every 0.3s until dead) ==========
task.spawn(function()
    while true do
        task.wait(0.3)
        if flingMurdererActive and not pendingRespawn then
            local murderer = getMurderer()
            if murderer and murderer.Character then
                local hum = murderer.Character:FindFirstChildOfClass("Humanoid")
                if hum and hum.Health > 0 then
                    if tick() - lastFlingTime > 1 then
                        lastFlingTime = tick()
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
        -- Instant fling on activate
        task.spawn(function()
            task.wait(0.3)
            local murderer = getMurderer()
            if murderer and murderer.Character then
                local hum = murderer.Character:FindFirstChildOfClass("Humanoid")
                if hum and hum.Health > 0 then
                    lastFlingTime = tick()
                    flingMurderer(murderer)
                    print("[INSTANT] Flinged: " .. murderer.Name)
                else
                    print("[INSTANT] Murderer dead, waiting for next...")
                end
            else
                print("[INSTANT] No murderer yet, will detect...")
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

local function getNearestCoin()
    local hrp = getHRP()
    if not hrp then return nil end
    local closest, dist = nil, math.huge
    for _, map in ipairs(workspace:GetChildren()) do
        if map:FindFirstChild("CoinContainer") then
            for _, coin in ipairs(map.CoinContainer:GetChildren()) do
                if coin:IsA("BasePart") and coin:FindFirstChild("TouchInterest") then
                    local d = (hrp.Position - coin.Position).Magnitude
                    if d < dist then closest, dist = coin, d end
                end
            end
        end
    end
    return closest, dist
end

-- ========== Auto Reset ==========
local function doAutoRespawn()
    if pendingRespawn then return end
    pendingRespawn = true

    local char = LocalPlayer.Character
    if char then
        local hum = char:FindFirstChildOfClass("Humanoid")
        if hum then
            hum.PlatformStand = false
            hum.WalkSpeed = walkSpeed
        end
    end

    -- Fling murderer before reset
    if flingMurdererActive then
        local murderer = getMurderer()
        if murderer and murderer.Character then
            local murdHum = murderer.Character:FindFirstChildOfClass("Humanoid")
            if murdHum and murdHum.Health > 0 then
                flingMurderer(murderer)
                task.wait(2)
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
end

-- Reset on 50 (event)
task.spawn(function()
    local remotes = ReplicatedStorage:WaitForChild("Remotes", 10)
    if not remotes then return end
    local gameplay = remotes:WaitForChild("Gameplay", 5)
    if not gameplay then return end
    local cc = gameplay:WaitForChild("CoinCollected", 5)
    if not cc then return end
    cc.OnClientEvent:Connect(function(_, current, max)
        if current and max and current >= max and not pendingRespawn then
            doAutoRespawn()
        end
    end)
end)

-- Reset polling backup
task.spawn(function()
    while true do
        task.wait(0.3)
        if farmActive and not pendingRespawn then
            local mainGui = LocalPlayer.PlayerGui:FindFirstChild("MainGUI")
            if mainGui then
                local gameGui = mainGui:FindFirstChild("Game")
                if gameGui then
                    local coinBags = gameGui:FindFirstChild("CoinBags")
                    if coinBags then
                        for _, bag in ipairs(coinBags:GetDescendants()) do
                            if bag:IsA("TextLabel") and bag.Name == "Coins" then
                                local cur, mx = bag.Text:match("(%d+)/(%d+)")
                                if cur and mx and tonumber(cur) >= tonumber(mx) then
                                    doAutoRespawn()
                                    break
                                end
                            end
                        end
                    end
                end
            end
        end
    end
end)

-- ========== FARM LOOP (WALK ONLY - 27 SPEED) ==========
task.spawn(function()
    while true do
        task.wait(0.1)
        pcall(function()
            if not farmActive or pendingRespawn then return end

            local char = LocalPlayer.Character
            local hrp = char and char:FindFirstChild("HumanoidRootPart")
            local hum = char and char:FindFirstChildOfClass("Humanoid")
            if not hrp or not hum or hum.Health <= 0 then return end

            -- Force walk speed 27
            hum.PlatformStand = false
            hum.WalkSpeed = walkSpeed
            hum.JumpPower = 50

            -- Restore collision (for proper collection)
            for _, part in ipairs(char:GetDescendants()) do
                if part:IsA("BasePart") then
                    if not part.CanCollide then part.CanCollide = true end
                end
            end

            local coin, dist = getNearestCoin()
            if not coin then return end

            -- Walk to coin (Humanoid:MoveTo = natural walking)
            hum:MoveTo(coin.Position)

            -- Extra firetouchinterest when close (backup)
            if dist < 5 then
                pcall(function()
                    firetouchinterest(hrp, coin, 0)
                    firetouchinterest(hrp, coin, 1)
                end)
            end
        end)
    end
end)

-- Coin info
local function updateCoinInfo()
    local count = 0
    local hrp = getHRP()
    if hrp then
        for _, map in ipairs(workspace:GetChildren()) do
            if map:FindFirstChild("CoinContainer") then
                for _, coin in ipairs(map.CoinContainer:GetChildren()) do
                    if coin:IsA("BasePart") and coin:FindFirstChild("TouchInterest") then
                        count = count + 1
                    end
                end
            end
        end
    end
    local bagTxt = "0"
    local mainGui = LocalPlayer.PlayerGui:FindFirstChild("MainGUI")
    if mainGui and mainGui:FindFirstChild("Game") and mainGui.Game:FindFirstChild("CoinBags") then
        for _, bag in ipairs(mainGui.Game.CoinBags:GetDescendants()) do
            if bag:IsA("TextLabel") and bag.Name == "Coins" then
                local cur = bag.Text:match("(%d+)")
                if cur and tonumber(cur) > 0 then bagTxt = cur end
            end
        end
    end
    CoinInfo.Text = "🪙 " .. bagTxt .. " / 50  •  الخريطة: " .. count
end

RunService.Heartbeat:Connect(function()
    pcall(updateCoinInfo)
end)

-- Enforce walk speed 27 continuously
RunService.Heartbeat:Connect(function()
    pcall(function()
        local char = LocalPlayer.Character
        if char then
            local hum = char:FindFirstChildOfClass("Humanoid")
            if hum and not pendingRespawn then
                if hum.WalkSpeed ~= walkSpeed then
                    hum.WalkSpeed = walkSpeed
                end
            end
        end
    end)
end)

LocalPlayer.CharacterAdded:Connect(function(char)
    task.wait(0.5)
    applySpeed()
end)
