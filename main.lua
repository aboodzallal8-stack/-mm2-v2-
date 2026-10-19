--[[
    عمو تشريب Hub - Mobile v14
    - REAL murderer detection (instant + loop 0.15s)
    - REAL coin collection (walk to coin, natural touch)
    - Smart fly for far coins only
    - Fling murderer at 50 + on button press
--]]

local Players = game:GetService("Players")
local RunService = game:GetService("RunService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local VirtualUser = game:GetService("VirtualUser")
local CoreGui = game:GetService("CoreGui")

local LocalPlayer = Players.LocalPlayer

-- ========== Config ==========
local walkSpeed = 27
local FLY_SPEED = 100
local FLY_THRESHOLD = 30 -- لو أبعد من 30 ستود → طيران
local COLLECT_TIMEOUT = 2 -- ثانيتين max لكل كوين

-- ========== States ==========
local farmActive = false
local flingMurdererActive = false
local antiAFKActive = true
local pendingRespawn = false
local collectStartTime = 0
local currentCoin = nil
local lastFlingTime = 0
local flingedList = {}

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
        if hum and not farmActive then
            hum.WalkSpeed = walkSpeed
            hum.PlatformStand = false
        end
    end
end

applySpeed()

-- ========== INSTANT Murderer Detection (4 methods) ==========
local function getMurderer()
    -- 1: Character equipped
    for _, player in ipairs(Players:GetPlayers()) do
        if player == LocalPlayer then continue end
        local char = player.Character
        if char then
            for _, item in ipairs(char:GetChildren()) do
                if item:IsA("Tool") and item.Name == "Knife" then return player end
            end
        end
    end
    -- 2: Backpack (search descendants for Knife tool)
    for _, player in ipairs(Players:GetPlayers()) do
        if player == LocalPlayer then continue end
        local bp = player:FindFirstChild("Backpack")
        if bp then
            for _, item in ipairs(bp:GetDescendants()) do
                if item:IsA("Tool") and item.Name == "Knife" then return player end
            end
        end
    end
    -- 3: Workspace (equipped/dropped knife)
    for _, obj in ipairs(workspace:GetDescendants()) do
        if obj:IsA("Tool") and obj.Name == "Knife" then
            local char = obj.Parent
            if char then
                local plr = Players:GetPlayerFromCharacter(char)
                if plr and plr ~= LocalPlayer then return plr end
            end
        end
    end
    -- 4: Attributes
    for _, player in ipairs(Players:GetPlayers()) do
        if player == LocalPlayer then continue end
        local role = player:GetAttribute("Role") or player:GetAttribute("role") or player:GetAttribute("GameRole")
        if role then
            local r = tostring(role):lower()
            if r:find("murder") or r == "murderer" then return player end
        end
    end
    return nil
end

-- ========== Instant Fling ==========
local function flingMurderer(murderer)
    if not murderer then return end
    task.spawn(function()
        for attempt = 1, 15 do
            local char = murderer.Character
            if not char then break end
            local hrp = char:FindFirstChild("HumanoidRootPart")
            local hum = char:FindFirstChildOfClass("Humanoid")
            if not hrp or not hum or hum.Health <= 0 then break end

            pcall(function()
                local bv = Instance.new("BodyVelocity")
                bv.MaxForce = Vector3.new(math.huge, math.huge, math.huge)
                bv.Velocity = Vector3.new(math.random(-3000, 3000), 60000, math.random(-3000, 3000))
                bv.Parent = hrp
                task.delay(0.3, function() if bv and bv.Parent then bv:Destroy() end end)
            end)

            pcall(function()
                local bav = Instance.new("BodyAngularVelocity")
                bav.MaxTorque = Vector3.new(math.huge, math.huge, math.huge)
                bav.AngularVelocity = Vector3.new(9999, 9999, 9999)
                bav.Parent = hrp
                task.delay(0.3, function() if bav and bav.Parent then bav:Destroy() end end)
            end)

            pcall(function()
                hrp.CFrame = CFrame.new(math.random(-1000, 1000), 15000 + (attempt * 1000), math.random(-1000, 1000))
                hrp.Velocity = Vector3.new(0, 25000, 0)
                hum.PlatformStand = true
            end)

            task.wait(0.12)
        end
        pcall(function()
            local hum = murderer.Character and murderer.Character:FindFirstChildOfClass("Humanoid")
            if hum then hum.PlatformStand = false end
        end)
    end)
end

-- ========== Fast Murderer Loop (0.15s = instant) ==========
task.spawn(function()
    while true do
        task.wait(0.15)
        if flingMurdererActive and not pendingRespawn then
            if tick() - lastFlingTime > 3 then
                local murderer = getMurderer()
                if murderer and murderer.Character then
                    local hum = murderer.Character:FindFirstChildOfClass("Humanoid")
                    if hum and hum.Health > 0 and not flingedList[murderer.UserId] then
                        flingedList[murderer.UserId] = true
                        lastFlingTime = tick()
                        flingMurderer(murderer)
                        print("[Fling] Killed murderer: " .. murderer.Name)
                    end
                end
            end
        end
    end
end)

-- Clean flingedList on new round
task.spawn(function()
    local remotes = ReplicatedStorage:WaitForChild("Remotes", 20)
    if not remotes then return end
    local gameplay = remotes:WaitForChild("Gameplay", 10)
    if not gameplay then return end
    local rs = gameplay:WaitForChild("RoundStart", 10)
    if rs then
        rs.OnClientEvent:Connect(function()
            flingedList = {}
            lastFlingTime = 0
        end)
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
MainFrame.Size = UDim2.new(0, 340, 0, 350)
MainFrame.Position = UDim2.new(0.5, -170, 0.5, -175)
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
        if not farmActive then applySpeed() end
    else
        SpeedBox.Text = tostring(walkSpeed)
    end
end)

local FarmBtn = makeToggle(100, "جمع تلقائي", "🌾", false, function(state)
    farmActive = state
    if not state then
        currentCoin = nil
        local char = LocalPlayer.Character
        if char then
            local hum = char:FindFirstChildOfClass("Humanoid")
            if hum then
                hum.PlatformStand = false
                hum.WalkSpeed = walkSpeed
            end
            for _, part in ipairs(char:GetDescendants()) do
                if part:IsA("BasePart") then part.CanCollide = true end
            end
        end
    end
end)

local FlingMurdererBtn = makeToggle(166, "فلنك القاتل", "💥", false, function(state)
    flingMurdererActive = state
    if state then
        lastFlingTime = 0
        flingedList = {}
        -- 🔥 INSTANT FLING on button press!
        task.spawn(function()
            task.wait(0.2)
            local murderer = getMurderer()
            if murderer and murderer.Character then
                local hum = murderer.Character:FindFirstChildOfClass("Humanoid")
                if hum and hum.Health > 0 then
                    flingedList[murderer.UserId] = true
                    lastFlingTime = tick()
                    flingMurderer(murderer)
                    print("[INSTANT] Flinged: " .. murderer.Name)
                else
                    print("[INSTANT] No murderer found yet, will keep checking...")
                end
            else
                print("[INSTANT] No murderer found yet, will keep checking...")
            end
        end)
    end
end)

local AFKBtn = makeToggle(232, "مكافحة الطرد", "⏳", true, function(state)
    antiAFKActive = state
end)

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
    currentCoin = nil

    local char = LocalPlayer.Character
    if char then
        local hum = char:FindFirstChildOfClass("Humanoid")
        if hum then
            hum.PlatformStand = false
            hum.WalkSpeed = walkSpeed
        end
    end

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

-- ========== FARM LOOP (REAL WALKING COLLECTION) ==========
task.spawn(function()
    while true do
        task.wait(0.05)
        pcall(function()
            if not farmActive or pendingRespawn then return end

            local char = LocalPlayer.Character
            local hrp = char and char:FindFirstChild("HumanoidRootPart")
            local hum = char and char:FindFirstChildOfClass("Humanoid")
            if not hrp or not hum or hum.Health <= 0 then return end

            local coin, dist = getNearestCoin()
            if not coin then return end

            -- ========== MOVE TOWARD COIN ==========
            hum.PlatformStand = false  -- ✨ CRITICAL: normal humanoid state
            hum.WalkSpeed = walkSpeed
            hum.JumpPower = 50
            hum:MoveTo(coin.Position)

            -- ========== COLLECT WHEN CLOSE ==========
            if dist < 6 then
                -- نوقف ونضرب touch (المشي يشتغل هذا)
                pcall(function()
                    firetouchinterest(hrp, coin, 0)
                    task.wait(0.05)
                    firetouchinterest(hrp, coin, 1)
                end)
            end

            -- ========== FLY FOR FAR COINS (>30 studs) ==========
            if dist > FLY_THRESHOLD then
                -- طيران سريع (لكن آمن)
                hum.PlatformStand = true
                hum.WalkSpeed = 0
                local targetPos = coin.Position + Vector3.new(0, 3, 0)
                local delta = targetPos - hrp.Position
                local step = math.min(FLY_SPEED * 0.05, delta.Magnitude - 5)
                if step > 0 then
                    hrp.CFrame = CFrame.new(hrp.Position + delta.Unit * step)
                end
                -- اختراق جدران
                for _, part in ipairs(char:GetDescendants()) do
                    if part:IsA("BasePart") and part.Name ~= "HumanoidRootPart" then
                        if part.CanCollide then part.CanCollide = false end
                    end
                end
            else
                -- قريب: نرجع طبيعي عشان الجمع يشتغل
                for _, part in ipairs(char:GetDescendants()) do
                    if part:IsA("BasePart") then
                        if not part.CanCollide then part.CanCollide = true end
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
                if cur and tonumber(cur) > 0 then bagTxt = cur end
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
    currentCoin = nil
    if not farmActive then applySpeed() end
end)
