--[[
    عمو تشريب Hub - Mobile v5
    - Farm by walking (no teleport, no kick)
    - Murderer fling ONLY happens when bag reaches 50 (at reset)
    - If murderer detected at 50 coins -> fling them -> reset -> win
    - Clean GUI
--]]

local Players = game:GetService("Players")
local RunService = game:GetService("RunService")
local UserInputService = game:GetService("UserInputService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local VirtualUser = game:GetService("VirtualUser")
local CoreGui = game:GetService("CoreGui")

local LocalPlayer = Players.LocalPlayer

-- ========== Config ==========
local CoinLimit = 50
local walkSpeed = 27

-- ========== States ==========
local farmActive = false
local flingMurdererOnReset = false -- يصير الفلنك فقط عند 50 كوين
local antiAFKActive = true
local pendingRespawn = false

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
        if hum then hum.WalkSpeed = walkSpeed end
    end
end

applySpeed()

RunService.Heartbeat:Connect(function()
    pcall(function()
        local char = LocalPlayer.Character
        if char then
            local hum = char:FindFirstChildOfClass("Humanoid")
            if hum and hum.WalkSpeed ~= walkSpeed and not pendingRespawn then
                hum.WalkSpeed = walkSpeed
            end
        end
    end)
end)

-- ========== Murderer Detection ==========
local function getMurderer()
    for _, player in ipairs(Players:GetPlayers()) do
        if player == LocalPlayer then continue end
        
        -- 1) Knife in backpack (most reliable)
        local bp = player:FindFirstChild("Backpack")
        if bp and bp:FindFirstChild("Knife") then
            return player
        end
        
        -- 2) Knife equipped in character
        local char = player.Character
        if char then
            for _, tool in ipairs(char:GetChildren()) do
                if tool:IsA("Tool") and tool.Name == "Knife" then
                    return player
                end
            end
        end
    end
    return nil
end

-- ========== Kill Player (teleport to sky - guaranteed death) ==========
local function killPlayer(targetPlayer)
    if not targetPlayer or not targetPlayer.Character then return false end
    local char = targetPlayer.Character
    local hrp = char:FindFirstChild("HumanoidRootPart")
    local hum = char:FindFirstChildOfClass("Humanoid")
    if not hrp or not hum then return false end
    if hum.Health <= 0 then return false end

    task.spawn(function()
        for i = 1, 200 do
            if not hrp.Parent or not hum.Parent then break end
            if hum.Health <= 0 then break end
            pcall(function()
                hrp.CFrame = CFrame.new(
                    math.random(-100, 100),
                    10000 + (i * 150),
                    math.random(-100, 100)
                )
                hrp.Velocity = Vector3.new(0, 15000, 0)
                hum.PlatformStand = true
            end)
            task.wait(0.02)
        end
        pcall(function() hum.PlatformStand = false end)
    end)
    
    return true
end

-- ========== GUI ==========
local ScreenGui = Instance.new("ScreenGui")
ScreenGui.Name = "AmoChereebMobile"
ScreenGui.Parent = CoreGui
ScreenGui.ResetOnSpawn = false

-- Float button
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
MainFrame.Size = UDim2.new(0, 340, 0, 350)
MainFrame.Position = UDim2.new(0.5, -170, 0.5, -175)
MainFrame.BackgroundColor3 = Color3.fromRGB(10, 10, 10)
MainFrame.BorderSizePixel = 0
MainFrame.Active = true
MainFrame.Visible = false
MainFrame.ClipsDescendants = true
MainFrame.Parent = ScreenGui
Instance.new("UICorner", MainFrame).CornerRadius = UDim.new(0, 20)

-- Gold border
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

-- Drag
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

-- Toggle
local function makeToggle(yPos, text, icon, defaultState, callback)
    local btn = Instance.new("TextButton")
    btn.Size = UDim2.new(1, -24, 0, 56)
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

-- Speed setting
local SpeedLabel = Instance.new("TextLabel")
SpeedLabel.Size = UDim2.new(0, 170, 0, 34)
SpeedLabel.Position = UDim2.new(0, 12, 0, 56)
SpeedLabel.BackgroundTransparency = 1
SpeedLabel.Text = "⚡ سرعة المشي"
SpeedLabel.TextColor3 = Color3.fromRGB(200, 200, 200)
SpeedLabel.Font = Enum.Font.GothamBold
SpeedLabel.TextSize = 14
SpeedLabel.TextXAlignment = Enum.TextXAlignment.Right
SpeedLabel.Parent = MainFrame

local SpeedBox = Instance.new("TextBox")
SpeedBox.Size = UDim2.new(0, 80, 0, 34)
SpeedBox.Position = UDim2.new(1, -100, 0, 56)
SpeedBox.BackgroundColor3 = Color3.fromRGB(22, 22, 22)
SpeedBox.BorderSizePixel = 2
SpeedBox.BorderColor3 = Color3.fromRGB(212, 175, 55)
SpeedBox.Text = tostring(walkSpeed)
SpeedBox.TextColor3 = Color3.fromRGB(212, 175, 55)
SpeedBox.Font = Enum.Font.GothamBold
SpeedBox.TextSize = 16
SpeedBox.Parent = MainFrame
Instance.new("UICorner", SpeedBox).CornerRadius = UDim.new(0, 10)

SpeedBox.FocusLost:Connect(function()
    local n = tonumber(SpeedBox.Text)
    if n and n >= 16 and n <= 100 then
        walkSpeed = n
        applySpeed()
    else
        SpeedBox.Text = tostring(walkSpeed)
    end
end)

-- Toggles
local FarmBtn = makeToggle(100, "جمع تلقائي", "🌾", false, function(state)
    farmActive = state
end)

local FlingMurdererBtn = makeToggle(166, "فلنك القاتل عند 50", "💥", false, function(state)
    flingMurdererOnReset = state
end)

local AFKBtn = makeToggle(232, "مكافحة الطرد", "⏳", true, function(state)
    antiAFKActive = state
end)

-- Coin info
local CoinPanel = Instance.new("Frame")
CoinPanel.Size = UDim2.new(1, -24, 0, 44)
CoinPanel.Position = UDim2.new(0, 12, 0, 296)
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

-- Float drag
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

-- ✅ Auto Reset - Murderer fling happens HERE ONLY
local function doAutoRespawn()
    if pendingRespawn then return end
    pendingRespawn = true

    -- ⚡ لو الزر مفعل: نطير القاتل قبل الريست
    if flingMurdererOnReset then
        local murderer = getMurderer()
        if murderer and murderer.Character then
            local murdChar = murderer.Character
            local murdHum = murdChar:FindFirstChildOfClass("Humanoid")
            if murdHum and murdHum.Health > 0 then
                -- نطير القاتل
                killPlayer(murderer)
                task.wait(1.5) -- ننتظر شوي عشان يموت
            end
        end
    end

    -- ثم نريست أنفسنا
    local char = LocalPlayer.Character
    if char then
        local hum = char:FindFirstChildOfClass("Humanoid")
        if hum and hum.Health > 0 then
            pcall(function() hum.Health = 0 end)
        end
    end
    task.wait(3)
    pendingRespawn = false
    if farmActive then
        task.wait(0.3)
        applySpeed()
    end
end

-- Reset detection (event-based)
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

-- Polling backup (in case event doesn't fire)
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

-- Farm loop (WALK ONLY - no teleport)
task.spawn(function()
    while true do
        task.wait(0.1)
        pcall(function()
            if farmActive and not pendingRespawn then
                local coin, dist = getNearestCoin()
                if coin then
                    local char = LocalPlayer.Character
                    local hrp = char and char:FindFirstChild("HumanoidRootPart")
                    local hum = char and char:FindFirstChildOfClass("Humanoid")
                    if hrp and hum and hum.Health > 0 then
                        if dist < 6 then
                            -- نجبر الجمع بدون تيليبورت
                            pcall(function()
                                firetouchinterest(hrp, coin, 0)
                                task.wait(0.05)
                                firetouchinterest(hrp, coin, 1)
                            end)
                        else
                            -- يمشي عادي
                            hum:MoveTo(coin.Position)
                        end
                    end
                end
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
                if cur then bagTxt = cur end
            end
        end
    end
    CoinInfo.Text = "🪙 " .. bagTxt .. " / 50  •  الخريطة: " .. count
end

RunService.Heartbeat:Connect(function()
    pcall(updateCoinInfo)
end)

LocalPlayer.CharacterAdded:Connect(function(char)
    task.wait(0.5)
    applySpeed()
end)
