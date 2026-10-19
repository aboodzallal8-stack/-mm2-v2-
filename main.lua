--[[
    عمو تشريب Hub - Mobile Edition
    - Floating draggable circle button
    - Auto farm (max 50) with auto reset
    - Auto fling murderer (if you're innocent)
    - NEW: If you're murderer, fling ALL players when bag full then reset
    - Walk speed control (default 27)
    - Anti-AFK included
--]]

local Players = game:GetService("Players")
local RunService = game:GetService("RunService")
local UserInputService = game:GetService("UserInputService")
local TweenService = game:GetService("TweenService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local VirtualUser = game:GetService("VirtualUser")
local CoreGui = game:GetService("CoreGui")

local LocalPlayer = Players.LocalPlayer
local Camera = workspace.CurrentCamera

-- ========== Config ==========
local CoinLimit = 50
local walkSpeed = 27
local flyDistance = 100

-- ========== States ==========
local farmActive = false
local autoFlingActive = false
local murdererAutoFlingActive = true   -- الميزة الجديدة (مفعلة افتراضياً)
local antiAFKActive = true
local pendingRespawn = false
local flingCooldown = 0

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

-- ========== Speed System (auto 27) ==========
local function applySpeed()
    local char = LocalPlayer.Character
    if char then
        local hum = char:FindFirstChildOfClass("Humanoid")
        if hum then hum.WalkSpeed = walkSpeed end
    end
end

applySpeed()

RunService.Heartbeat:Connect(function()
    local char = LocalPlayer.Character
    if char then
        local hum = char:FindFirstChildOfClass("Humanoid")
        if hum and hum.WalkSpeed ~= walkSpeed then
            pcall(function() hum.WalkSpeed = walkSpeed end)
        end
    end
end)

LocalPlayer.CharacterAdded:Connect(function()
    task.wait(0.5)
    applySpeed()
end)

-- ========== Fling System ==========
local function flingTarget(targetPlayer)
    if not targetPlayer or not targetPlayer.Character then return end
    local char = targetPlayer.Character
    local hrp = char:FindFirstChild("HumanoidRootPart")
    if not hrp then return end

    local bv = Instance.new("BodyVelocity")
    bv.Name = "FlingBypass"
    bv.Velocity = Vector3.new(0, 5000, 0)
    bv.MaxForce = Vector3.new(math.huge, math.huge, math.huge)
    bv.Parent = hrp

    task.spawn(function()
        for i = 1, 80 do
            if not hrp.Parent then break end
            pcall(function()
                hrp.CFrame = hrp.CFrame * CFrame.Angles(math.rad(90), math.rad(45), math.rad(30))
                hrp.Velocity = Vector3.new(math.random(-2000, 2000), 3000, math.random(-2000, 2000))
            end)
            task.wait(0.015)
        end
        if bv and bv.Parent then bv:Destroy() end
    end)
end

local function detectMurderer()
    for _, player in ipairs(Players:GetPlayers()) do
        if player ~= LocalPlayer and player.Character then
            for _, tool in ipairs(player.Character:GetChildren()) do
                if tool:IsA("Tool") and tool.Name == "Knife" then
                    return player
                end
            end
            local bp = player:FindFirstChild("Backpack")
            if bp and bp:FindFirstChild("Knife") then
                return player
            end
        end
    end
    return nil
end

local function isLocalMurderer()
    local char = LocalPlayer.Character
    if not char then return false end
    for _, tool in ipairs(char:GetChildren()) do
        if tool:IsA("Tool") and tool.Name == "Knife" then return true end
    end
    local bp = LocalPlayer:FindFirstChild("Backpack")
    if bp and bp:FindFirstChild("Knife") then return true end
    return false
end

local function flingAllOtherPlayers()
    for _, player in ipairs(Players:GetPlayers()) do
        if player ~= LocalPlayer and player.Character then
            local hum = player.Character:FindFirstChildOfClass("Humanoid")
            if hum and hum.Health > 0 then
                flingTarget(player)
            end
        end
    end
end

-- فلنك القاتل (لما تكون بريء)
task.spawn(function()
    while true do
        task.wait(1)
        if autoFlingActive and (tick() - flingCooldown) > 2.5 then
            local murderer = detectMurderer()
            if murderer and murderer.Character then
                local myChar = LocalPlayer.Character
                local murdChar = murderer.Character
                if myChar and murdChar then
                    local myRoot = myChar:FindFirstChild("HumanoidRootPart")
                    local murdRoot = murdChar:FindFirstChild("HumanoidRootPart")
                    if myRoot and murdRoot then
                        local dist = (myRoot.Position - murdRoot.Position).Magnitude
                        if dist < 200 then
                            flingTarget(murderer)
                            flingCooldown = tick()
                        end
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

-- Floating circle button
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

-- Main panel
local MainFrame = Instance.new("Frame")
MainFrame.Size = UDim2.new(0, 320, 0, 370)
MainFrame.Position = UDim2.new(0.5, -160, 0.5, -185)
MainFrame.BackgroundColor3 = Color3.fromRGB(10, 10, 10)
MainFrame.BorderSizePixel = 0
MainFrame.Active = true
MainFrame.Visible = false
MainFrame.ClipsDescendants = true
MainFrame.Parent = ScreenGui
Instance.new("UICorner", MainFrame).CornerRadius = UDim.new(0, 18)

-- Gold border
local GoldBorder = Instance.new("Frame")
GoldBorder.Size = UDim2.new(1, 6, 1, 6)
GoldBorder.Position = UDim2.new(0, -3, 0, -3)
GoldBorder.BackgroundColor3 = Color3.fromRGB(212, 175, 55)
GoldBorder.BorderSizePixel = 0
GoldBorder.BackgroundTransparency = 0.25
GoldBorder.Parent = MainFrame
Instance.new("UICorner", GoldBorder).CornerRadius = UDim.new(0, 20)

task.spawn(function()
    while GoldBorder.Parent do
        local b = (math.sin(tick() * 2) + 1) / 2
        GoldBorder.BackgroundColor3 = Color3.fromRGB(
            180 + math.floor(75 * b),
            140 + math.floor(55 * b),
            20 + math.floor(60 * b)
        )
        task.wait(0.03)
    end
end)

-- Title bar
local TitleBar = Instance.new("Frame")
TitleBar.Size = UDim2.new(1, 0, 0, 40)
TitleBar.BackgroundColor3 = Color3.fromRGB(20, 20, 20)
TitleBar.BorderSizePixel = 0
TitleBar.Parent = MainFrame
Instance.new("UICorner", TitleBar).CornerRadius = UDim.new(0, 18)

local Title = Instance.new("TextLabel")
Title.Size = UDim2.new(1, -50, 1, 0)
Title.Position = UDim2.new(0, 15, 0, 0)
Title.BackgroundTransparency = 1
Title.Text = "عمو تشريب Hub"
Title.TextColor3 = Color3.fromRGB(212, 175, 55)
Title.Font = Enum.Font.GothamBold
Title.TextSize = 20
Title.Parent = TitleBar

local CloseBtn = Instance.new("TextButton")
CloseBtn.Size = UDim2.new(0, 32, 0, 32)
CloseBtn.Position = UDim2.new(1, -36, 0, 4)
CloseBtn.BackgroundColor3 = Color3.fromRGB(180, 40, 40)
CloseBtn.Text = "✕"
CloseBtn.TextColor3 = Color3.fromRGB(255, 255, 255)
CloseBtn.Font = Enum.Font.GothamBold
CloseBtn.TextSize = 18
CloseBtn.Parent = TitleBar
Instance.new("UICorner", CloseBtn).CornerRadius = UDim.new(0, 16)
CloseBtn.MouseButton1Click:Connect(function() MainFrame.Visible = false end)

-- Drag system (touch + mouse)
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

-- Helpers
local function makeLabel(yPos, text, icon)
    local lbl = Instance.new("TextLabel")
    lbl.Size = UDim2.new(0, 170, 0, 30)
    lbl.Position = UDim2.new(0, 12, 0, yPos)
    lbl.BackgroundTransparency = 1
    lbl.Text = icon and (icon .. " " .. text) or text
    lbl.TextColor3 = Color3.fromRGB(200, 200, 200)
    lbl.Font = Enum.Font.Gotham
    lbl.TextSize = 13
    lbl.TextXAlignment = Enum.TextXAlignment.Left
    lbl.Parent = MainFrame
    return lbl
end

local function makeTextBox(yPos, default)
    local tb = Instance.new("TextBox")
    tb.Size = UDim2.new(0, 75, 0, 32)
    tb.Position = UDim2.new(1, -90, 0, yPos)
    tb.BackgroundColor3 = Color3.fromRGB(25, 25, 25)
    tb.BorderSizePixel = 1
    tb.BorderColor3 = Color3.fromRGB(60, 60, 60)
    tb.Text = default
    tb.TextColor3 = Color3.fromRGB(212, 175, 55)
    tb.Font = Enum.Font.GothamBold
    tb.TextSize = 15
    tb.Parent = MainFrame
    Instance.new("UICorner", tb).CornerRadius = UDim.new(0, 8)
    return tb
end

-- Speed
local speedLabel = makeLabel(50, "سرعة المشي", "⚡")
local speedBox = makeTextBox(50, "27")
speedBox.FocusLost:Connect(function()
    local n = tonumber(speedBox.Text)
    if n and n >= 16 and n <= 100 then
        walkSpeed = n
        applySpeed()
    else
        speedBox.Text = tostring(walkSpeed)
    end
end)

-- Fly distance
local flyLabel = makeLabel(88, "مسافة الطيران", "✈️")
local flyBox = makeTextBox(88, "100")
flyBox.FocusLost:Connect(function()
    local n = tonumber(flyBox.Text)
    if n and n >= 30 and n <= 1000 then
        flyDistance = n
    else
        flyBox.Text = tostring(flyDistance)
    end
end)

-- Toggle helper
local function makeToggle(yPos, text, icon, callback)
    local btn = Instance.new("TextButton")
    btn.Size = UDim2.new(1, -24, 0, 44)
    btn.Position = UDim2.new(0, 12, 0, yPos)
    btn.BackgroundColor3 = Color3.fromRGB(25, 25, 25)
    btn.BorderSizePixel = 2
    btn.BorderColor3 = Color3.fromRGB(60, 60, 60)
    btn.Text = icon and (icon .. " " .. text) or text
    btn.TextColor3 = Color3.fromRGB(220, 220, 220)
    btn.Font = Enum.Font.GothamBold
    btn.TextSize = 14
    btn.AutoButtonColor = false
    btn.Parent = MainFrame
    Instance.new("UICorner", btn).CornerRadius = UDim.new(0, 10)
    btn.MouseButton1Click:Connect(callback)
    return btn
end

local FarmBtn = makeToggle(126, "جمع تلقائي : OFF", "🌾", function()
    farmActive = not farmActive
    FarmBtn.Text = farmActive and "🌾 جمع تلقائي : ON" or "🌾 جمع تلقائي : OFF"
    FarmBtn.BorderColor3 = farmActive and Color3.fromRGB(212, 175, 55) or Color3.fromRGB(60, 60, 60)
end)

local FlingBtn = makeToggle(175, "فلنك القاتل : OFF", "💥", function()
    autoFlingActive = not autoFlingActive
    FlingBtn.Text = autoFlingActive and "💥 فلنك القاتل : ON" or "💥 فلنك القاتل : OFF"
    FlingBtn.BorderColor3 = autoFlingActive and Color3.fromRGB(212, 175, 55) or Color3.fromRGB(60, 60, 60)
end)

-- ✅ الميزة الجديدة: فلنك الكل عند القتل (لما تكون أنت القاتل)
local MurdererAutoFlingBtn = makeToggle(224, "فلنك الكل كقاتل : ON", "🔪", function()
    murdererAutoFlingActive = not murdererAutoFlingActive
    MurdererAutoFlingBtn.Text = murdererAutoFlingActive and "🔪 فلنك الكل كقاتل : ON" or "🔪 فلنك الكل كقاتل : OFF"
    MurdererAutoFlingBtn.BorderColor3 = murdererAutoFlingActive and Color3.fromRGB(212, 175, 55) or Color3.fromRGB(60, 60, 60)
end)
MurdererAutoFlingBtn.BorderColor3 = Color3.fromRGB(212, 175, 55)

local AFKBtn = makeToggle(273, "مكافحة الطرد : ON", "⏳", function()
    antiAFKActive = not antiAFKActive
    AFKBtn.Text = antiAFKActive and "⏳ مكافحة الطرد : ON" or "⏳ مكافحة الطرد : OFF"
    AFKBtn.BorderColor3 = antiAFKActive and Color3.fromRGB(212, 175, 55) or Color3.fromRGB(60, 60, 60)
end)
AFKBtn.BorderColor3 = Color3.fromRGB(212, 175, 55)

-- Coin info
local CoinInfo = Instance.new("TextLabel")
CoinInfo.Size = UDim2.new(1, -24, 0, 26)
CoinInfo.Position = UDim2.new(0, 12, 0, 330)
CoinInfo.BackgroundTransparency = 1
CoinInfo.Text = "🪙 القطع: 0/50 | الأقرب: N/A"
CoinInfo.TextColor3 = Color3.fromRGB(212, 175, 55)
CoinInfo.Font = Enum.Font.GothamBold
CoinInfo.TextSize = 12
CoinInfo.Parent = MainFrame

-- Float button drag/tap
local floatDragging = false
local floatDragStart, floatStartPos
local floatMoved = false
local floatEmergencyFired = false

FloatBtn.InputBegan:Connect(function(input)
    if input.UserInputType == Enum.UserInputType.Touch or input.UserInputType == Enum.UserInputType.MouseButton1 then
        floatDragging = true
        floatDragStart = input.Position
        floatStartPos = FloatBtn.Position
        floatMoved = false
        floatEmergencyFired = false
        task.delay(2, function()
            if floatDragging and not floatMoved and not floatEmergencyFired then
                floatEmergencyFired = true
                farmActive = false
                autoFlingActive = false
                FarmBtn.Text = "🌾 جمع تلقائي : OFF"
                FlingBtn.Text = "💥 فلنك القاتل : OFF"
                FarmBtn.BorderColor3 = Color3.fromRGB(60, 60, 60)
                FlingBtn.BorderColor3 = Color3.fromRGB(60, 60, 60)
            end
        end)
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
        if not floatMoved and not floatEmergencyFired then
            MainFrame.Visible = not MainFrame.Visible
        end
    end
end)

-- ========== Farm System ==========
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

-- ✅ التعديل الجديد: لو أنت القاتل والميزة شغالة → فلنك الكل قبل الريست
local function doAutoRespawn()
    if pendingRespawn then return end
    pendingRespawn = true

    local wasMurderer = isLocalMurderer()

    if wasMurderer and murdererAutoFlingActive then
        flingAllOtherPlayers()
        task.wait(1.2)  -- ننتظر شوي عشان الفلنك يأثر
    end

    local char = LocalPlayer.Character
    if char then
        local hum = char:FindFirstChildOfClass("Humanoid")
        if hum and hum.Health > 0 then
            pcall(function() hum.Health = 0 end)
        end
    end
    task.wait(3)
    pendingRespawn = false
end

-- Reset on bag full (event-based)
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

-- Polling backup
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

-- Farm loop
task.spawn(function()
    while true do
        task.wait(0.08)
        if farmActive and not pendingRespawn then
            local coin = getNearestCoin()
            if coin then
                local hrp = getHRP()
                if hrp then
                    hrp.CFrame = coin.CFrame + Vector3.new(0, 2, 0)
                    task.wait(0.04)
                end
            end
        end
    end
end)

-- Coin info
local function updateCoinInfo()
    local count = 0
    local nearText = "N/A"
    local hrp = getHRP()
    if hrp then
        local closest = math.huge
        for _, map in ipairs(workspace:GetChildren()) do
            if map:FindFirstChild("CoinContainer") then
                for _, coin in ipairs(map.CoinContainer:GetChildren()) do
                    if coin:IsA("BasePart") and coin:FindFirstChild("TouchInterest") then
                        count = count + 1
                        local d = (hrp.Position - coin.Position).Magnitude
                        if d < closest then closest = d end
                    end
                end
            end
        end
        if closest ~= math.huge then nearText = math.floor(closest) .. " studs" end
    end
    CoinInfo.Text = "🪙 القطع: " .. count .. "/50 | الأقرب: " .. nearText
end

RunService.Heartbeat:Connect(function()
    pcall(function()
        updateCoinInfo()
    end)
end)
