-- STANDALONE READABLE AUTOFARM - Amo Chereeb Edition
-- Modified: bag limit 50, custom Arabic titles, brand updates.
-- Use only where permitted. Client automation may violate game rules.


local Players = game:GetService("Players")
local TweenService = game:GetService("TweenService")
local UserInputService = game:GetService("UserInputService")
local RunService = game:GetService("RunService")
local MarketplaceService = game:GetService("MarketplaceService")
local VirtualUser = game:GetService("VirtualUser")

if not RunService:IsClient() then
    return
end

local player = Players.LocalPlayer
while not player do
    Players:GetPropertyChangedSignal("LocalPlayer"):Wait()
    player = Players.LocalPlayer
end


local uiInstanceNew = Instance.new

local GUI_NAME = "AmoChereebGUI"
local WINDOW_WIDTH = 560
local WINDOW_HEIGHT = 560
local COLLAPSED_HEIGHT = 160
local STATS_WIDTH = 360
local STATS_HEIGHT = 388
local UI_SCALE = 0.75

local UI_ASSETS = {
    MainSkin = "rbxassetid://105563478392149",
    StatsSkin = "rbxassetid://76134977932038",
    Glow = "rbxassetid://79824554467644",
}
local NEON_SETTINGS = {
    FireEnabled = true,
    FireStrength = 0.90,
    UpdateRate = 30,
}

local MOTION_SETTINGS = {
    FoldDuration = 0.50,
    DragResponse = 20,
}
-- ✅ Bag limit is always 50 (no elite dependency)
local BAG_LIMIT_DEFAULT = 50
local BAG_LIMIT_ELITE = 50
local ELITE_GAMEPASS_ID = 429957
local MAX_FARM_DISTANCE = 180
local fireTouch = (typeof(firetouchinterest) == "function" and firetouchinterest)
    or (typeof(firetouchtransmitter) == "function" and firetouchtransmitter)
    or nil
local FLY_BELOW_OFFSET = fireTouch and 2.8 or 0.75
local originalOcclusionMode = player.DevCameraOcclusionMode

local Theme = {
    Navy = Color3.fromRGB(12, 7, 19),
    NavySoft = Color3.fromRGB(25, 17, 36),
    Card = Color3.fromRGB(30, 21, 41),
    CardHover = Color3.fromRGB(39, 27, 53),
    OrangeNeon = Color3.fromRGB(255, 137, 20),
    OrangeSoft = Color3.fromRGB(232, 83, 13),
    OrangeBright = Color3.fromRGB(255, 204, 122),
    Red = Color3.fromRGB(243, 115, 133),
    Cyan = Color3.fromRGB(181, 69, 255),
    Aqua = Color3.fromRGB(142, 83, 193),
    Blue = Color3.fromRGB(59, 39, 77),
    Gold = Color3.fromRGB(255, 204, 122),
    Orange = Color3.fromRGB(255, 151, 39),
    Coral = Color3.fromRGB(248, 118, 65),
    White = Color3.fromRGB(250, 243, 255),
    Muted = Color3.fromRGB(202, 155, 236),
    Dim = Color3.fromRGB(132, 110, 151),
    Web = Color3.fromRGB(172, 144, 189),
    Lime = Color3.fromRGB(177, 216, 106),
}

local function create(className, properties, parent)
    local object = uiInstanceNew(className)
    for property, value in pairs(properties or {}) do
        object[property] = value
    end
    object.Parent = parent
    return object
end

local function addCorner(parent, radius)
    return create("UICorner", { CornerRadius = UDim.new(0, radius) }, parent)
end

local function addStroke(parent, color, thickness, transparency)
    return create("UIStroke", {
        ApplyStrokeMode = Enum.ApplyStrokeMode.Border,
        Color = color,
        Thickness = thickness or 1,
        Transparency = transparency or 0,
    }, parent)
end

local function addGradient(parent, colors, rotation, transparency)
    local keypoints = {}
    for index, entry in ipairs(colors) do
        keypoints[index] = ColorSequenceKeypoint.new(entry[1], entry[2])
    end
    return create("UIGradient", {
        Color = ColorSequence.new(keypoints),
        Rotation = rotation or 0,
        Transparency = transparency or NumberSequence.new(0),
    }, parent)
end

local activeTweens = setmetatable({}, { __mode = "k" })
local function smoothTween(object, duration, goals, style, direction)
    if activeTweens[object] then
        activeTweens[object]:Cancel()
    end
    local animation = TweenService:Create(
        object,
        TweenInfo.new(
            duration or 0.28,
            style or Enum.EasingStyle.Sine,
            direction or Enum.EasingDirection.Out
        ),
        goals
    )
    activeTweens[object] = animation
    animation.Completed:Once(function()
        if activeTweens[object] == animation then
            activeTweens[object] = nil
        end
    end)
    animation:Play()
    return animation
end

local guiParent = player:WaitForChild("PlayerGui")
-- ✅ Cleanup all past editions (including old Halloween)
for _, previousName in ipairs({ GUI_NAME, "SkoblikoSummerNeonGUI", "SkoblikoHalloweenGUI" }) do
    local previous = guiParent:FindFirstChild(previousName)
    if previous then
        previous:Destroy()
    end
end

local state = {
    alive = true,
    closing = false,
    minimized = false,
    autofarm = false,
    farmSpeed = 25,
    farmed = 0,
    dieOnFullBag = false,
    protection = false,
    farmPaused = false,
    pauseReason = "",
    bagCount = 0,
    bagLimit = BAG_LIMIT_DEFAULT,
    bagFound = false,
    sessionStarted = os.clock(),
}

local connections = {}
local farmConnection
local cameraConnection
local cleaned = false
local cleanupRadar = function() end
local collisionCache = {}
local humanoidCache = setmetatable({}, { __mode = "k" })

local function connect(signal, callback)
    local connection = signal:Connect(callback)
    if not state.alive then
        connection:Disconnect()
        return connection
    end
    table.insert(connections, connection)
    return connection
end

local function restoreCharacter()
    pcall(function()
        player.DevCameraOcclusionMode = originalOcclusionMode
    end)

    local character = player.Character
    for humanoid, saved in pairs(humanoidCache) do
        if humanoid.Parent then
            humanoid.PlatformStand = saved.PlatformStand
            humanoid.AutoRotate = saved.AutoRotate
        end
        humanoidCache[humanoid] = nil
    end

    for part, oldCanCollide in pairs(collisionCache) do
        if part and part.Parent then
            part.CanCollide = oldCanCollide
        end
    end
    table.clear(collisionCache)
end

local function cleanup()
    if cleaned then return end
    cleaned = true
    cleanupRadar()
    state.alive = false
    state.autofarm = false
    restoreCharacter()

    if cameraConnection then
        cameraConnection:Disconnect()
        cameraConnection = nil
    end
    if farmConnection then
        farmConnection:Disconnect()
        farmConnection = nil
    end
    for _, connection in ipairs(connections) do
        connection:Disconnect()
    end
    table.clear(connections)
end

local coinBlacklist = {}
local coinTouchFails = setmetatable({}, { __mode = "k" })
local deadCoins = setmetatable({}, { __mode = "k" })
local coinPresence = setmetatable({}, { __mode = "k" })
local roundRetiredCoins = setmetatable({}, { __mode = "k" })
local currentTarget
local retargetAccumulator = 0
local farmIdle = false
local roundEnded = false

local PICKUP_CONTAINERS = {
    coincontainer = true, candycontainer = true, tokencontainer = true,
    eggcontainer = true, giftcontainer = true, beachballcontainer = true,
}
local PICKUP_NAMES = {
    coin = true, candy = true, token = true, egg = true,
    snow = true, gift = true, present = true, beachball = true,
    shell = true, star = true, gem = true,
}
local coinSet = {}
local trackedContainers = {}
local lastRadarSweep = -math.huge
local registryVersion = 0

local function isPickupContainer(container)
    return (container:IsA("Folder") or container:IsA("Model"))
        and PICKUP_CONTAINERS[string.lower(container.Name)] == true
        and container:IsDescendantOf(workspace)
end

local function isCoinPart(coin)
    if not coin:IsA("BasePart") then return false end
    local coinID=coin:GetAttribute("CoinID")
    if type(coinID)=="string" and PICKUP_NAMES[string.lower(coinID)] then return true end
    local name = string.lower(coin.Name)
    local currency = string.match(name, "^(%a+)_server$") or name
    return PICKUP_NAMES[currency] == true
end

local function isVisiblePart(part)
    return part.Transparency < 0.99 and part.LocalTransparencyModifier < 0.99
end

local function hasPickupVisual(coin)
    if isVisiblePart(coin) then return true end
    for _, child in ipairs(coin:GetDescendants()) do
        if child:IsA("BasePart") and isVisiblePart(child) then
            return true
        end
    end
    return false
end

local function isCoinAvailable(coin)
    if not coin or not coinSet[coin] or not isCoinPart(coin)
        or not coin:IsDescendantOf(workspace)
        or not coin.Parent or not trackedContainers[coin.Parent]
        or not isPickupContainer(coin.Parent) then
        return false
    end
    local visual=coin:FindFirstChild("CoinVisual")
    local collected=coin:GetAttribute("Collected")==true
        or (visual and visual:GetAttribute("Collected")==true)
    local present = not collected and coin.CanTouch and hasPickupVisual(coin)
    local previousPresence = coinPresence[coin]
    coinPresence[coin] = present
    if not present then return false end
    if previousPresence == false then
        deadCoins[coin] = nil
        coinTouchFails[coin] = nil
        coinBlacklist[coin] = nil
        roundRetiredCoins[coin] = nil
    end
    return not deadCoins[coin] and not roundRetiredCoins[coin]
end

local function registerCoin(coin)
    if isCoinPart(coin) and not coinSet[coin] then
        coinSet[coin] = true
        registryVersion += 1
    end
end

local function unregisterCoin(coin)
    if coinSet[coin] then registryVersion += 1 end
    coinSet[coin] = nil
    coinBlacklist[coin] = nil
    coinTouchFails[coin] = nil
    deadCoins[coin] = nil
    coinPresence[coin] = nil
    roundRetiredCoins[coin] = nil
    if currentTarget == coin then currentTarget = nil end
end

local function unwatchContainer(container)
    local entry = trackedContainers[container]
    if not entry then return end
    trackedContainers[container] = nil
    for _, connection in ipairs(entry) do connection:Disconnect() end
    for coin in pairs(coinSet) do
        if coin.Parent == container or not coin:IsDescendantOf(workspace) then
            unregisterCoin(coin)
        end
    end
    registryVersion += 1
end

local function watchContainer(container)
    if trackedContainers[container] or not isPickupContainer(container) then return end
    local entry = {}
    trackedContainers[container] = entry
    table.insert(entry, container.ChildAdded:Connect(registerCoin))
    table.insert(entry, container.ChildRemoved:Connect(unregisterCoin))
    table.insert(entry, container.AncestryChanged:Connect(function()
        if not container:IsDescendantOf(workspace) then unwatchContainer(container) end
    end))
    for _, coin in ipairs(container:GetChildren()) do registerCoin(coin) end
    registryVersion += 1
end

cleanupRadar = function()
    for container in pairs(trackedContainers) do unwatchContainer(container) end
    table.clear(coinSet)
    table.clear(coinBlacklist)
    table.clear(coinPresence)
    table.clear(coinTouchFails)
    table.clear(deadCoins)
    table.clear(roundRetiredCoins)
    currentTarget = nil
end

local function radarSweep(force)
    if not force and os.clock() - lastRadarSweep < 3 then return end
    lastRadarSweep = os.clock()
    for container in pairs(trackedContainers) do
        if not isPickupContainer(container) then unwatchContainer(container) end
    end
    for coin in pairs(coinSet) do
        if not coin:IsDescendantOf(workspace) or not trackedContainers[coin.Parent] then
            unregisterCoin(coin)
        end
    end
    for _, object in ipairs(workspace:GetDescendants()) do
        if isPickupContainer(object) then watchContainer(object) end
    end
end

connect(workspace.DescendantAdded, function(object)
    if isPickupContainer(object) then watchContainer(object) end
end)
radarSweep(true)


local CLUSTER_RADIUS = 24
local CLUSTER_BONUS = 7

local lastPickTime = -math.huge
local lastPickCoin = nil
local lastPickScore = math.huge
local lastPickHadResult = false
local lastPickVersion = -1

local function findClosestItem(rootPart)
    local now = os.clock()

    if now - lastPickTime < 0.15 and lastPickVersion == registryVersion then
        if not lastPickHadResult then
            return nil, math.huge, math.huge
        end
        local cached = lastPickCoin
        if isCoinAvailable(cached) and not coinBlacklist[cached]
            and (cached.Position - rootPart.Position).Magnitude <= MAX_FARM_DISTANCE then
            return cached, (cached.Position - rootPart.Position).Magnitude, lastPickScore
        end
    end
    lastPickTime = now

    for coin, timestamp in pairs(coinBlacklist) do
        if not coin.Parent or now - timestamp > 1.5 then
            coinBlacklist[coin] = nil
        end
    end

    radarSweep(false)

    local candidates = {}
    for coin in pairs(coinSet) do
        if isCoinAvailable(coin) and not coinBlacklist[coin]
            and (coin.Position - rootPart.Position).Magnitude <= MAX_FARM_DISTANCE then
            table.insert(candidates, coin)
        end
    end
    local count = #candidates
    local rootPosition = rootPart.Position
    local positions = table.create(count)
    local distances = table.create(count)
    local order = table.create(count)
    for index = 1, count do
        local position = candidates[index].Position
        positions[index] = position
        distances[index] = (position - rootPosition).Magnitude
        order[index] = index
    end
    table.sort(order, function(a, b)
        return distances[a] < distances[b]
    end)

    local best, bestDistance, bestScore = nil, math.huge, math.huge
    local maxBonus = 6 * CLUSTER_BONUS
    for _, index in ipairs(order) do
        local distance = distances[index]
        if distance - maxBonus >= bestScore then
            break
        end
        local position = positions[index]
        local neighbors = 0
        for otherIndex = 1, count do
            if otherIndex ~= index and (positions[otherIndex] - position).Magnitude <= CLUSTER_RADIUS then
                neighbors += 1
                if neighbors >= 6 then
                    break
                end
            end
        end
        local score = distance - neighbors * CLUSTER_BONUS
        if score < bestScore then
            best = candidates[index]
            bestDistance = distance
            bestScore = score
        end
    end

    lastPickVersion = registryVersion
    lastPickCoin = best
    lastPickScore = bestScore
    lastPickHadResult = best ~= nil

    return best, bestDistance, bestScore
end

local function isRoundOver()
    for _, guiName in ipairs({ "Scoreboard", "Scoreboard_Phone" }) do
        local scoreboard = guiParent:FindFirstChild(guiName)
        if scoreboard and scoreboard:IsA("ScreenGui") and scoreboard.Enabled then
            for _, modeFrame in ipairs(scoreboard:GetChildren()) do
                if modeFrame:IsA("GuiObject") and modeFrame.Visible then
                    return true
                end
            end
        end
    end
    return false
end

farmConnection = RunService.Heartbeat:Connect(function(deltaTime)
    if not state.alive then return end

    if not state.autofarm then
        state.farmPaused = false
        state.pauseReason = ""
        return
    end

    local character = player.Character
    if not character then
        state.farmPaused = true
        state.pauseReason = "RESPAWN"
        return
    end

    local rootPart = character:FindFirstChild("HumanoidRootPart")
    local humanoid = character:FindFirstChildOfClass("Humanoid")
    if not rootPart or not humanoid or humanoid.Health <= 0 then
        state.farmPaused = true
        state.pauseReason = "RESPAWN"
        return
    end

    if isRoundOver() then
        if not roundEnded then
            roundEnded = true
            radarSweep(true)
            for coin in pairs(coinSet) do roundRetiredCoins[coin] = true end
            registryVersion += 1
        end
        for coin in pairs(coinSet) do isCoinAvailable(coin) end
        currentTarget = nil
        state.farmPaused = true
        state.pauseReason = "ROUND END"
        restoreCharacter()
        rootPart.AssemblyLinearVelocity = Vector3.zero
        rootPart.AssemblyAngularVelocity = Vector3.zero
        return
    end

    roundEnded = false

    if not isCoinAvailable(currentTarget) or coinBlacklist[currentTarget] then
        local candidate, candidateDistance = findClosestItem(rootPart)

        if candidate and candidateDistance <= MAX_FARM_DISTANCE then
            currentTarget = candidate
            state.farmPaused = false
            state.pauseReason = ""
        else
            currentTarget = nil
            state.farmPaused = true
            state.pauseReason = candidate and "TOO FAR" or "WAITING"
        end
    end

    retargetAccumulator += deltaTime
    if currentTarget and retargetAccumulator >= 0.5 then
        retargetAccumulator = 0
        local candidate, candidateDistance, candidateScore = findClosestItem(rootPart)
        if candidate and currentTarget and candidate ~= currentTarget and candidateDistance <= MAX_FARM_DISTANCE then
            local currentDistance = (currentTarget.Position - rootPart.Position).Magnitude
            if currentDistance > 15 and candidateScore + 12 < currentDistance then
                currentTarget = candidate
            end
        end
    end

    local target = currentTarget
    if not isCoinAvailable(target) then
        currentTarget = nil
        state.farmPaused = true
        state.pauseReason = "WAITING"
        if not farmIdle then
            farmIdle = true
            restoreCharacter()
            rootPart.AssemblyLinearVelocity = Vector3.zero
            rootPart.AssemblyAngularVelocity = Vector3.zero
        end
        return
    end
    farmIdle = false

    local targetPosition = target.Position - Vector3.new(0, FLY_BELOW_OFFSET, 0)
    local offset = targetPosition - rootPart.Position
    local distance = offset.Magnitude

    if distance > MAX_FARM_DISTANCE then
        currentTarget = nil
        state.farmPaused = true
        state.pauseReason = "TOO FAR"
        restoreCharacter()
        rootPart.AssemblyLinearVelocity = Vector3.zero
        rootPart.AssemblyAngularVelocity = Vector3.zero
        return
    end

    state.farmPaused = false
    state.pauseReason = ""

    if player.DevCameraOcclusionMode ~= Enum.DevCameraOcclusionMode.Invisicam then
        pcall(function()
            player.DevCameraOcclusionMode = Enum.DevCameraOcclusionMode.Invisicam
        end)
    end

    for _, part in ipairs(character:GetDescendants()) do
        if part:IsA("BasePart") then
            if collisionCache[part] == nil then
                collisionCache[part] = part.CanCollide
            end
            part.CanCollide = false
        end
    end

    if not humanoidCache[humanoid] then
        humanoidCache[humanoid] = {
            PlatformStand = humanoid.PlatformStand,
            AutoRotate = humanoid.AutoRotate,
        }
    end
    humanoid.PlatformStand = true
    rootPart.AssemblyLinearVelocity = Vector3.zero
    rootPart.AssemblyAngularVelocity = Vector3.zero

    if distance <= 0.45 then
        if fireTouch then
            pcall(fireTouch, rootPart, target, 0)
            pcall(fireTouch, rootPart, target, 1)
        end
        coinBlacklist[target] = os.clock()
        local bagFull = state.bagFound and state.bagLimit > 0
            and state.bagCount >= state.bagLimit
        if not bagFull then
            coinTouchFails[target] = (coinTouchFails[target] or 0) + 1
            if coinTouchFails[target] >= 3 then
                deadCoins[target] = true
            end
        end
        currentTarget = nil
        return
    end

    if distance <= 0.001 then return end

    local safeDelta = math.min(deltaTime, 1 / 30)
    local step = math.min(state.farmSpeed * safeDelta, math.max(distance - 0.1, 0))
    local nextPosition = rootPart.Position + offset.Unit * step

    local flatOffset = Vector3.new(offset.X, 0, offset.Z)
    if flatOffset.Magnitude > 0.05 then
        rootPart.CFrame = CFrame.lookAt(nextPosition, nextPosition + flatOffset.Unit) * CFrame.Angles(-math.pi / 2, 0, 0)
    else
        rootPart.CFrame = rootPart.CFrame.Rotation + nextPosition
    end
end)

-- ================= ANTI FLING / ANTI VOID =================
local lastSafePosition = nil
local lastFramePosition = nil
local safePosAccumulator = 0
local voidThreshold = -440
do
    local ok, destroyHeight = pcall(function()
        return workspace.FallenPartsDestroyHeight
    end)
    if ok and typeof(destroyHeight) == "number" then
        voidThreshold = destroyHeight + 80
    end
end

connect(RunService.Heartbeat, function(deltaTime)
    if not state.alive or state.closing or not state.protection then
        lastSafePosition = nil
        lastFramePosition = nil
        safePosAccumulator = 0
        return
    end

    local character = player.Character
    local rootPart = character and character:FindFirstChild("HumanoidRootPart")
    local humanoid = character and character:FindFirstChildOfClass("Humanoid")
    if not rootPart or not humanoid or humanoid.Health <= 0 then return end

    local farmingActively = state.autofarm and not state.farmPaused

    local velocity = rootPart.AssemblyLinearVelocity
    local horizontalSpeed = Vector3.new(velocity.X, 0, velocity.Z).Magnitude
    local flingLimit = farmingActively and 300 or 120
    if horizontalSpeed > flingLimit
        or velocity.Y > 150
        or velocity.Y < -260
        or rootPart.AssemblyAngularVelocity.Magnitude > 60 then
        rootPart.AssemblyLinearVelocity = Vector3.zero
        rootPart.AssemblyAngularVelocity = Vector3.zero
        if lastFramePosition then
            rootPart.CFrame = rootPart.CFrame.Rotation + lastFramePosition
        end
    end

    if lastFramePosition and (rootPart.Position - lastFramePosition).Magnitude > 120 then
        lastFramePosition = rootPart.Position
        lastSafePosition = nil
        safePosAccumulator = 0
    end

    local inVoid = rootPart.Position.Y < voidThreshold
    if inVoid and lastSafePosition and not farmingActively then
        rootPart.AssemblyLinearVelocity = Vector3.zero
        rootPart.AssemblyAngularVelocity = Vector3.zero
        rootPart.CFrame = CFrame.new(lastSafePosition + Vector3.new(0, 3, 0))
    end

    safePosAccumulator += deltaTime
    if safePosAccumulator >= 0.5 then
        safePosAccumulator = 0
        if not humanoid.PlatformStand
            and humanoid.FloorMaterial ~= Enum.Material.Air
            and rootPart.AssemblyLinearVelocity.Magnitude < 60 then
            lastSafePosition = rootPart.Position
        end
    end

    lastFramePosition = rootPart.Position
end)

-- ================= ANTI AFK =================
connect(player.Idled, function()
    if not state.alive or state.closing or not state.autofarm then return end
    pcall(function()
        VirtualUser:CaptureController()
        VirtualUser:ClickButton2(Vector2.new())
    end)
end)


local screenGui = create("ScreenGui", {
    Name = GUI_NAME,
    DisplayOrder = 1000,
    IgnoreGuiInset = true,
    ResetOnSpawn = false,
    ZIndexBehavior = Enum.ZIndexBehavior.Sibling,
}, guiParent)

connect(screenGui.AncestryChanged, function(_, parent)
    if parent == nil then
        cleanup()
    end
end)


local holder = create("Frame", {
    Name = "Holder", AnchorPoint = Vector2.new(0.5, 0.5),
    BackgroundTransparency = 1, ClipsDescendants = false,
    Position = UDim2.fromScale(0.5, 0.5),
    Size = UDim2.fromOffset(WINDOW_WIDTH, WINDOW_HEIGHT),
}, screenGui)
local responsiveScale = create("UIScale", { Scale = 1 }, holder)
local statsScale
local uiLayout = { stats = nil, mainMoved = false, statsMoved = false }

local function updateScale()
    local camera = workspace.CurrentCamera
    if not camera then return end
    local viewport = camera.ViewportSize
    local stacked = viewport.X < 680
    local scale
    if stacked then
        scale = math.min(UI_SCALE, (viewport.X - 32) / WINDOW_WIDTH,
            (viewport.Y - 40) / (WINDOW_HEIGHT - 32 + STATS_HEIGHT))
    else
        scale = math.min(UI_SCALE, (viewport.X - 40) / (WINDOW_WIDTH - 36 + STATS_WIDTH),
            (viewport.Y - 40) / WINDOW_HEIGHT)
    end
    scale = math.max(0.3, scale)
    responsiveScale.Scale = scale
    if statsScale then statsScale.Scale = scale end
    if uiLayout.stacked ~= stacked then
        uiLayout.mainMoved = false
        uiLayout.statsMoved = false
        uiLayout.stacked = stacked
    end
    if not uiLayout.mainMoved then
        holder.Position = stacked
            and UDim2.new(0.5, 0, 0.5, -(STATS_HEIGHT - 32) * scale / 2)
            or UDim2.new(0.5, -(STATS_WIDTH - 36) * scale / 2, 0.5, 0)
    end
    if uiLayout.stats and not uiLayout.statsMoved then
        uiLayout.stats.Position = stacked
            and UDim2.new(0.5, 0, 0.5, (WINDOW_HEIGHT - 32) * scale / 2)
            or UDim2.new(0.5, (WINDOW_WIDTH - 36) * scale / 2, 0.5, 0)
    end
end

local function clampWindow()
    local camera = workspace.CurrentCamera
    if not camera then return end
    local viewport = camera.ViewportSize
    local scale = responsiveScale.Scale
    local halfWidth = WINDOW_WIDTH * scale / 2
    local fullHalfHeight = WINDOW_HEIGHT * scale / 2
    local visibleHeight = (uiLayout.visibleHeight or WINDOW_HEIGHT) * scale
    local position = holder.Position
    local x = position.X.Scale * viewport.X + position.X.Offset
    local y = position.Y.Scale * viewport.Y + position.Y.Offset
    x = math.clamp(x, halfWidth + 8, math.max(halfWidth + 8, viewport.X - halfWidth - 8))
    y = math.clamp(y, fullHalfHeight + 8,
        math.max(fullHalfHeight + 8, viewport.Y - visibleHeight + fullHalfHeight - 8))
    holder.Position = UDim2.fromOffset(x, y)
end

local function clampStats()
    local camera = workspace.CurrentCamera
    if not camera or not uiLayout.stats or not statsScale then return end
    local viewport = camera.ViewportSize
    local halfWidth, halfHeight = STATS_WIDTH * statsScale.Scale / 2, STATS_HEIGHT * statsScale.Scale / 2
    local position = uiLayout.stats.Position
    local x = position.X.Scale * viewport.X + position.X.Offset
    local y = position.Y.Scale * viewport.Y + position.Y.Offset
    uiLayout.stats.Position = UDim2.fromOffset(
        math.clamp(x, halfWidth + 8, math.max(halfWidth + 8, viewport.X - halfWidth - 8)),
        math.clamp(y, halfHeight + 8, math.max(halfHeight + 8, viewport.Y - halfHeight - 8))
    )
end

local function refreshViewport()
    updateScale()
    clampWindow()
    clampStats()
end

local function bindCamera()
    if not state.alive then return end
    if cameraConnection then cameraConnection:Disconnect() end
    local camera = workspace.CurrentCamera
    if camera then
        cameraConnection = camera:GetPropertyChangedSignal("ViewportSize"):Connect(refreshViewport)
    end
    refreshViewport()
end
connect(workspace:GetPropertyChangedSignal("CurrentCamera"), bindCamera)
bindCamera()

local SoundService = game:GetService("SoundService")
local function playUiSound(speed, volume)
    pcall(function()
        local sound = Instance.new("Sound")
        sound.SoundId = "rbxasset://sounds/button.wav"
        sound.PlaybackSpeed, sound.Volume = speed or 1, volume or 0.45
        sound.PlayOnRemove, sound.Parent = true, SoundService
        sound:Destroy()
    end)
end

local neon = {groups = {}, images = {}, assetStates = {}}
neon.opacity = create("NumberValue", {Name = "NeonVisibility", Value = 0}, screenGui)
function neon:integer(value)
    local reversed = string.reverse(string.format("%.0f", value))
    local grouped = string.gsub(reversed, "(%d%d%d)", "%1,")
    return (string.gsub(string.reverse(grouped), "^,", ""))
end
function neon:image(parent, name, key, position, size, z, color)
    local image = create("ImageLabel", {Name = name, Active = false,
        BackgroundTransparency = 1, BorderSizePixel = 0, Image = UI_ASSETS[key],
        ImageColor3 = color or Color3.new(1,1,1), ImageTransparency = 0,
        ScaleType = Enum.ScaleType.Stretch, Position = position, Size = size, ZIndex = z}, parent)
    table.insert(self.images, image)
    return image
end
function neon:assetResult(asset, status)
    self.assetStates[tostring(asset)] = status
end

function neon:fire(parent, main)
    local group = {main = main, wisps = {}, embers = {}, auras = {}}
    group.root = create("Frame", {Name = "LivingEdgeGlow", BackgroundTransparency = 1,
        Active = false, ClipsDescendants = false, Size = parent.Size, ZIndex = 1}, parent)
    local count = main and 12 or 8
    for side = 1,2 do
        local color = side == 1 and Color3.fromRGB(255,112,12) or Color3.fromRGB(177,46,255)
        local aura = self:image(group.root, "EdgeHaze"..side, "Glow", UDim2.new(), UDim2.new(), 1, color)
        aura.AnchorPoint = Vector2.new(0.5,0.5)
        table.insert(group.auras, {object = aura, side = side})
        for index = 1,count do
            local phase = (index*0.618033989 + side*0.27) % 1
            local outer = self:image(group.root, "FlameWisp", "Glow", UDim2.new(), UDim2.new(), 2, color)
            outer.AnchorPoint = Vector2.new(0.5,1)
            local fade = NumberSequence.new({NumberSequenceKeypoint.new(0,1),
                NumberSequenceKeypoint.new(0.18,0.25),NumberSequenceKeypoint.new(0.55,0),
                NumberSequenceKeypoint.new(1,1)})
            addGradient(outer,{{0,Color3.new(1,1,1)},{1,Color3.new(1,1,1)}},90,fade)
            local core = self:image(group.root, "FlameCore", "Glow", UDim2.new(), UDim2.new(), 3,
                side == 1 and Color3.fromRGB(255,211,96) or Color3.fromRGB(229,167,255))
            core.AnchorPoint = Vector2.new(0.5,1)
            addGradient(core,{{0,Color3.new(1,1,1)},{1,Color3.new(1,1,1)}},90,fade)
            table.insert(group.wisps, {outer = outer, core = core, side = side,
                phase = phase, lane = (index-0.5)/count, life = 1.05+(index%5)*0.17,
                width = 48+(index%4)*8, height = 48+(index%5)*8})
        end
        for index = 1,3 do
            local ember = create("Frame", {Name = "Ember", Active = false, BorderSizePixel = 0,
                BackgroundColor3 = color, BackgroundTransparency = 1, Size = UDim2.fromOffset(2,2),
                AnchorPoint = Vector2.new(0.5,0.5), ZIndex = 3}, group.root)
            addCorner(ember,99)
            table.insert(group.embers, {object = ember, side = side, phase = index*0.29+side*0.11})
        end
    end
    table.insert(self.groups,group)
    return group
end
function neon:update(t)
    local visibility = math.clamp(self.opacity.Value,0,1)
    for _,g in ipairs(self.groups) do
        local width = g.root.Size.X.Offset
        local height = g.root.Size.Y.Offset
        local top = width*(g.main and 0.075 or 0.105)
        local folded = g.main and math.clamp((WINDOW_HEIGHT-height)/(WINDOW_HEIGHT-COLLAPSED_HEIGHT),0,1) or 0
        local bottom = g.main and (WINDOW_HEIGHT*0.914+(WINDOW_HEIGHT*0.236-WINDOW_HEIGHT*0.914)*folded) or ((height-width)+width*0.88)
        local left, right = width*(g.main and 0.078 or 0.091),width*(g.main and 0.923 or 0.908)
        local strength = math.clamp(NEON_SETTINGS.FireStrength,0,1)*visibility
        if not NEON_SETTINGS.FireEnabled then strength = 0 end
        for _,a in ipairs(g.auras) do
            a.object.Position = UDim2.fromOffset(a.side==1 and left or right,(top+bottom)/2)
            a.object.Size = UDim2.fromOffset(65,bottom-top+48)
            a.object.ImageTransparency = 1-(0.12+0.015*math.sin(t*1.7+a.side))*strength
        end
        for _,p in ipairs(g.wisps) do
            local age = (t/p.life+p.phase)%1
            local envelope = math.sin(age*math.pi)^1.3
            local flicker = 0.82+0.11*math.sin(t*13+p.phase*19)+0.07*math.sin(t*23+p.phase*31)
            local baseY = top+50+p.lane*math.max(10,bottom-top-52)
            local y = baseY-age*(28+p.phase*24)
            local direction = p.side==1 and -1 or 1
            local x = (p.side==1 and left or right)+direction*(3+age*7)+math.sin(age*6+p.phase*13)*3
            local stretch = 0.68+math.sin(age*math.pi)*0.55
            local h = p.height*stretch*(g.main and (1-folded*0.4) or 1)
            local w = p.width*(1-age*0.42)
            p.outer.Position = UDim2.fromOffset(x,y)
            p.outer.Size = UDim2.fromOffset(w,h)
            p.outer.Rotation = direction*(math.sin(t*3+p.phase*12)*9-4)
            p.outer.ImageTransparency = 1-envelope*flicker*0.48*strength
            p.core.Position = UDim2.fromOffset(x-direction*2,y)
            p.core.Size = UDim2.fromOffset(w*0.46,h*0.68)
            p.core.Rotation = p.outer.Rotation*0.6
            p.core.ImageTransparency = 1-envelope*flicker*0.21*strength
        end
        for _,p in ipairs(g.embers) do
            local age = (t*0.31+p.phase)%1
            local direction = p.side==1 and -1 or 1
            p.object.Position = UDim2.fromOffset((p.side==1 and left or right)+direction*(8+age*12)
                +math.sin(age*7+p.phase*9)*3, bottom-age*(bottom-top+20))
            p.object.BackgroundTransparency = 1-math.sin(age*math.pi)^2*0.45*strength
        end
    end
end

local window = create("CanvasGroup", {Name = "Window", BackgroundTransparency = 1,
    GroupColor3 = Color3.new(1,1,1), GroupTransparency = 1, BorderSizePixel = 0,
    Size = UDim2.fromOffset(WINDOW_WIDTH,WINDOW_HEIGHT), ZIndex = 10},holder)
local mainFire = neon:fire(holder,true)
mainFire.root.Size = window.Size
connect(window:GetPropertyChangedSignal("Size"),function() mainFire.root.Size = window.Size end)
local mainSkin = neon:image(window,"MainSkin","MainSkin",UDim2.fromOffset(0,0),
    UDim2.fromOffset(WINDOW_WIDTH,WINDOW_HEIGHT),1)

-- ✅ Custom Arabic title overlay (covers baked "MM2 HALLOWEEN" text)
local mainTitleBg = create("Frame",{
    Name = "CustomMainTitleBg",
    BackgroundColor3 = Theme.Navy,
    BackgroundTransparency = 0.15,
    BorderSizePixel = 0,
    Position = UDim2.fromOffset(WINDOW_WIDTH * 0.12, WINDOW_HEIGHT * 0.08),
    Size = UDim2.fromOffset(WINDOW_WIDTH * 0.76, WINDOW_HEIGHT * 0.08),
    ZIndex = 21,
}, window)
addCorner(mainTitleBg, 10)
addStroke(mainTitleBg, Theme.OrangeNeon, 1.5, 0.3)

create("TextLabel",{
    Name = "CustomMainTitle",
    BackgroundTransparency = 1,
    Size = UDim2.fromScale(1, 1),
    Text = "عمو تشريب",
    Font = Enum.Font.GothamBold,
    TextSize = 26,
    TextColor3 = Theme.OrangeBright,
    TextXAlignment = Enum.TextXAlignment.Center,
    TextYAlignment = Enum.TextYAlignment.Center,
    ZIndex = 22,
}, mainTitleBg)

local compactHeader = create("CanvasGroup",{Name = "CompactHeader",Visible = false,
    GroupColor3 = Color3.new(1,1,1),GroupTransparency = 0,
    Position = UDim2.fromOffset(0.078*WINDOW_WIDTH,0.072*WINDOW_HEIGHT),
    Size = UDim2.fromOffset(0.845*WINDOW_WIDTH,0.164*WINDOW_HEIGHT),
    BackgroundColor3 = Theme.Navy, BorderSizePixel = 0, ClipsDescendants = true,ZIndex = 2},window)
addCorner(compactHeader,17)
local compactImage = neon:image(compactHeader,"CroppedHeader","MainSkin",
    UDim2.fromOffset(-0.078*WINDOW_WIDTH,-0.072*WINDOW_HEIGHT),UDim2.fromOffset(WINDOW_WIDTH,WINDOW_HEIGHT),2)
local compactRim = create("Frame",{Name = "CompactRoundedRim",Visible = false,Active = false,
    BackgroundTransparency = 1,Position = compactHeader.Position,Size = compactHeader.Size,ZIndex = 3},window)
addCorner(compactRim,17)
local compactStroke = addStroke(compactRim,Color3.new(1,1,1),1.5,0.08)
addGradient(compactStroke,{{0,Theme.OrangeNeon},{1,Theme.Cyan}},0)
local header = create("Frame",{Name = "Header",Active = true,BackgroundTransparency = 1,
    Size = UDim2.fromOffset(WINDOW_WIDTH,WINDOW_HEIGHT*0.235),ZIndex = 20},window)
local function headerButton(name,x,text)
    local b = create("TextButton",{Name = name,AutoButtonColor = false,BackgroundTransparency = 1,
        Position = UDim2.fromOffset(x*WINDOW_WIDTH,0.143*WINDOW_HEIGHT),
        Size = UDim2.fromOffset(0.061*WINDOW_WIDTH,0.056*WINDOW_HEIGHT),
        Text = text,Font = Enum.Font.GothamBold,TextSize = 24,TextColor3 = Theme.White,ZIndex = 23},header)
    connect(b.MouseEnter,function() smoothTween(b,0.15,{TextColor3 = Theme.OrangeBright}) end)
    connect(b.MouseLeave,function() smoothTween(b,0.15,{TextColor3 = Theme.White}) end)
    return b
end
local minimizeButton = headerButton("Minimize",0.760,"—")
local closeButton = headerButton("Close",0.832,"×")
local content = create("CanvasGroup",{Name = "Content",BackgroundTransparency = 1,
    GroupColor3 = Color3.new(1,1,1),GroupTransparency = 0,
    Size = UDim2.fromOffset(WINDOW_WIDTH,WINDOW_HEIGHT),ZIndex = 12},window)
local CARD_LAYOUT = {
    ["Auto Farm"] = {0.108,0.247,0.786,0.129,0.286},
    ["Auto Respawn"] = {0.108,0.394,0.786,0.120,0.429},
    ["FarmSpeed"] = {0.108,0.531,0.786,0.166},
    ["Anti Fling / Void"] = {0.108,0.713,0.786,0.116,0.745},
}
local function makeCard(name)
    local s = CARD_LAYOUT[name]
    local card = create("Frame",{Name = name,BackgroundTransparency = 1,BorderSizePixel = 0,
        Position = UDim2.fromOffset(s[1]*WINDOW_WIDTH,s[2]*WINDOW_HEIGHT),
        Size = UDim2.fromOffset(s[3]*WINDOW_WIDTH,s[4]*WINDOW_HEIGHT),ZIndex = 12},content)
    return card
end
local function makeToggleCard(y,title,subtitle,colorA,colorB,callback)
    local s = CARD_LAYOUT[title]
    local card = makeCard(title)
    local trackWidth,trackHeight = WINDOW_WIDTH*0.11,WINDOW_HEIGHT*0.05
    local track = create("Frame",{Name = "ToggleTrack",BorderSizePixel = 0,
        BackgroundColor3 = Theme.Blue,
        Position = UDim2.fromOffset((0.77-s[1])*WINDOW_WIDTH,(s[5]-s[2])*WINDOW_HEIGHT),
        Size = UDim2.fromOffset(trackWidth,trackHeight),ZIndex = 15},card)
    addCorner(track,99)
    local stroke = addStroke(track,Theme.Aqua,1,0.3)
    addGradient(track,{{0,Color3.new(1,0.84,0.93)},{1,Color3.new(0.74,0.52,0.84)}},90)
    local radius = trackHeight/2
    local knob = create("Frame",{Name = "ToggleKnob",BorderSizePixel = 0,
        AnchorPoint = Vector2.new(0.5,0.5),Position = UDim2.new(0,radius,0.5,0),
        Size = UDim2.fromOffset(trackHeight-6,trackHeight-6),BackgroundColor3 = Theme.White,ZIndex = 16},track)
    addCorner(knob,99)
    addGradient(knob,{{0,Color3.new(1,1,1)},{1,Color3.new(0.88,0.8,0.95)}},90)
    local haloFrame = create("Frame",{Name = "ToggleHalo",BackgroundTransparency = 1,
        Size = UDim2.fromScale(1,1),Active = false,ZIndex = 14},track)
    addCorner(haloFrame,99)
    local halo = addStroke(haloFrame,Theme.OrangeNeon,5,1)
    if title == "Auto Farm" then
        neon.farmDot = create("Frame",{Name = "FarmStatusDot",BackgroundColor3 = Theme.Red,BorderSizePixel = 0,
            Position = UDim2.fromOffset((0.243-s[1])*WINDOW_WIDTH,(0.343-s[2])*WINDOW_HEIGHT),
            Size = UDim2.fromOffset(10,10),ZIndex = 15},card)
        addCorner(neon.farmDot,99)
        neon.farmStatus = create("TextLabel",{Name = "FarmStatus",BackgroundTransparency = 1,
            Position = UDim2.fromOffset((0.273-s[1])*WINDOW_WIDTH,(0.329-s[2])*WINDOW_HEIGHT),
            Size = UDim2.fromOffset(0.43*WINDOW_WIDTH,0.044*WINDOW_HEIGHT),
            Text = "OFF",Font = Enum.Font.GothamBold,TextSize = 18,TextColor3 = Theme.Red,
            TextXAlignment = Enum.TextXAlignment.Left,TextTruncate = Enum.TextTruncate.AtEnd,ZIndex = 15},card)
    end
    local hitbox = create("TextButton",{Name = "ToggleHitbox",BackgroundTransparency = 1,
        AutoButtonColor = false,Size = UDim2.fromScale(1,1),Text = "",ZIndex = 18},card)
    local value = false
    local function setValue(nextValue)
        value = nextValue == true
        smoothTween(track,0.22,{BackgroundColor3 = value and Theme.OrangeNeon or Theme.Blue})
        smoothTween(stroke,0.22,{Color = value and Theme.OrangeBright or Theme.Aqua})
        smoothTween(halo,0.22,{Transparency = value and 0.86 or 1})
        smoothTween(knob,0.22,{Position = value and UDim2.new(1,-radius,0.5,0) or UDim2.new(0,radius,0.5,0)})
        callback(value)
    end
    connect(hitbox.Activated,function()
        if state.closing or state.minimized then return end
        setValue(not value)
        playUiSound(value and 1.2 or 0.9,0.4)
    end)
    connect(hitbox.MouseEnter,function() smoothTween(stroke,0.15,{Transparency = 0.05}) end)
    connect(hitbox.MouseLeave,function() smoothTween(stroke,0.15,{Transparency = 0.3}) end)
    return setValue
end

local setAutofarmEnabled = makeToggleCard(
    58,
    "Auto Farm",
    "",
    Theme.Cyan,
    Theme.Coral,
    function(enabled)
        state.autofarm = enabled
        if not enabled then
            currentTarget = nil
            restoreCharacter()
        end
    end
)

local bagKillTriggered = false
local bagStartFarmed = state.farmed
local bagCheckEnabledAt = 0
local bagFullConfirmations = 0
local bagResetArmed = false

-- ================= INTERFACE BAG SCANNER =================
local trackedBagLabel = nil
local lastBagScan = 0

local function labelContext(object)
    local parts = { object.Name }
    local ancestor = object.Parent
    for _ = 1, 6 do
        if not ancestor then break end
        table.insert(parts, ancestor.Name)
        ancestor = ancestor.Parent
    end
    return string.lower(table.concat(parts, " "))
end

local function isBagVisible(object)
    local ancestor = object
    while ancestor and ancestor ~= guiParent do
        if ancestor:IsA("LuaSourceContainer") then return false end
        if ancestor:IsA("GuiObject") and not ancestor.Visible then return false end
        if ancestor:IsA("ScreenGui") and not ancestor.Enabled then return false end
        ancestor = ancestor.Parent
    end
    return ancestor == guiParent
end

local function parseBagText(object)
    if object:IsDescendantOf(screenGui) or not isBagVisible(object) then return nil end
    if not (object:IsA("TextLabel") or object:IsA("TextButton")) then
        return nil
    end

    local text = object.Text or ""
    text = string.gsub(text, "<[^<>]->", "")
    text = string.gsub(text, ",", "")
    local currentText, capacityText = string.match(text, "^%s*(%d+)%s*/%s*(%d+)%s*$")
    if currentText then
        return tonumber(currentText), tonumber(capacityText)
    end

    local plain = string.match(text, "^%s*(%d+)%s*$")
    if plain then
        return tonumber(plain), nil
    end

    return nil
end

local trackedBagContainer = nil
local lastDeepContainerScan = 0

local function findCoinBagContainer(playerGui)
    if trackedBagContainer and trackedBagContainer.Parent then
        return trackedBagContainer
    end
    trackedBagContainer = nil

    local mainGui = playerGui:FindFirstChild("MainGUI")
    local gameFrame = mainGui and mainGui:FindFirstChild("Game")
    local coinBags = gameFrame and gameFrame:FindFirstChild("CoinBags")
    local container = coinBags and coinBags:FindFirstChild("Container")
    if container then
        trackedBagContainer = container
        return container
    end

    if os.clock() - lastDeepContainerScan < 1.5 then
        return nil
    end
    lastDeepContainerScan = os.clock()
    for _, object in ipairs(playerGui:GetDescendants()) do
        if object.Name == "CoinBags" then
            local found = object:FindFirstChild("Container") or object
            trackedBagContainer = found
            return found
        end
    end
    return nil
end

local function findCoinBagLabel(playerGui)
    local container = findCoinBagContainer(playerGui)
    if not container then return nil end

    local fallbackLabel = nil
    for _, bag in ipairs(container:GetChildren()) do
        if bag:IsA("GuiObject") then
            local currencyFrame = bag:FindFirstChild("CurrencyFrame")
            local icon = currencyFrame and currencyFrame:FindFirstChild("Icon")
            local label = icon and icon:FindFirstChild("Coins")
            if not label then
                label = bag:FindFirstChild("Coins", true)
            end
            if label and label:IsA("TextLabel") then
                if isBagVisible(label) and parseBagText(label)~=nil then
                    return label
                end
                if bag.Name == "Coin" or not fallbackLabel then
                    fallbackLabel = label
                end
            end
        end
    end
    return nil
end

local function bagShowsFull(label)
    local icon = label and label.Parent
    local currencyFrame = icon and icon.Parent
    local bag = currencyFrame and currencyFrame.Parent
    local fullLabel = bag and bag:FindFirstChild("Full")
    if fullLabel and fullLabel:IsA("TextLabel") then
        return isBagVisible(fullLabel)
    end
    return false
end

local announcedBagPath = nil
local function announceBagLabel(label)
    local path = label:GetFullName()
    if path ~= announcedBagPath then
        announcedBagPath = path
        print("[عمو تشريب] coin counter found:", path)
    end
end

local function scanBagFromInterface()
    if trackedBagLabel and trackedBagLabel.Parent then
        local current, capacity = parseBagText(trackedBagLabel)
        if current then
            return current, capacity
        end
    end
    trackedBagLabel = nil

    local playerGui = player:FindFirstChild("PlayerGui")
    if not playerGui then return nil end

    local exactLabel = findCoinBagLabel(playerGui)
    if exactLabel then
        local current, capacity = parseBagText(exactLabel)
        if current then
            trackedBagLabel = exactLabel
            announceBagLabel(exactLabel)
            return current, capacity
        end
    end

    if os.clock() - lastBagScan < 1.5 then
        return nil
    end
    lastBagScan = os.clock()

    local bestLabel, bestCurrent, bestCapacity, bestScore = nil, nil, nil, 0
    for _, object in ipairs(playerGui:GetDescendants()) do
        local current, capacity = parseBagText(object)
        if current and object.Visible then
            local context = labelContext(object)
            local score = 0
            if string.find(context, "coin", 1, true) then score += 4 end
            if string.find(context, "bag", 1, true) then score += 3 end
            if string.find(context, "candy", 1, true) then score += 2 end
            if string.find(context, "currency", 1, true) then score += 1 end
            if object.Name == "Coins" then score += 4 end
            if capacity == BAG_LIMIT_DEFAULT or capacity == BAG_LIMIT_ELITE then
                score += 5
            end

            local currencyContext = string.find(context, "coin", 1, true)
                or string.find(context, "bag", 1, true)
                or string.find(context, "candy", 1, true)
                or string.find(context, "currency", 1, true)
            if currencyContext and score >= 3 and score > bestScore then
                bestLabel = object
                bestCurrent = current
                bestCapacity = capacity
                bestScore = score
            end
        end
    end

    if bestLabel then
        trackedBagLabel = bestLabel
        announceBagLabel(bestLabel)
        return bestCurrent, bestCapacity
    end

    return nil
end

local lastSeenBagCount = nil
local lastSeenBagLabel = nil

local function updateBagFromInterface()
    local current, capacity = scanBagFromInterface()
    if current then
        if lastSeenBagLabel~=trackedBagLabel then lastSeenBagCount=nil end
        lastSeenBagLabel=trackedBagLabel
        if state.autofarm and lastSeenBagCount ~= nil and current > lastSeenBagCount then
            state.farmed += current - lastSeenBagCount
        end
        lastSeenBagCount = current
        state.bagFound = true
        state.bagCount = current
        if current < state.bagLimit then bagResetArmed = true end
        if capacity == BAG_LIMIT_DEFAULT or capacity == BAG_LIMIT_ELITE then
            state.bagLimit = capacity
        end
        if bagShowsFull(trackedBagLabel) then
            state.bagCount = math.max(state.bagCount, state.bagLimit)
        end
    else
        state.bagFound = false
        state.bagCount = 0
        lastSeenBagCount = nil
        bagFullConfirmations = 0
    end
end

-- ✅ Bag limit always 50 (no elite dependency)
state.bagLimit = 50

local function stopAutofarmOnDeath(character)
    if not state.alive or state.closing or player.Character ~= character then return end
    restoreCharacter()
    lastSafePosition = nil
    lastFramePosition = nil
    safePosAccumulator = 0
    currentTarget = nil
    state.bagFound = false
    state.bagCount = 0
    trackedBagLabel = nil
    trackedBagContainer = nil
    lastSeenBagCount = nil
    lastSeenBagLabel = nil
    bagFullConfirmations = 0
    bagCheckEnabledAt = os.clock()
    bagResetArmed = false
    bagKillTriggered = false
    bagStartFarmed = state.farmed
    if state.autofarm then
        state.farmPaused = true
        state.pauseReason = "RESPAWN"
    end
    local humanoid = character:FindFirstChildOfClass("Humanoid") or character:WaitForChild("Humanoid", 8)
    if not humanoid or not state.alive or state.closing
        or player.Character ~= character then return end

    connect(humanoid.Died, function()
        if not state.alive or player.Character ~= character then return end
        currentTarget = nil
        state.farmPaused = state.autofarm
        state.pauseReason = state.autofarm and "RESPAWN" or ""
        restoreCharacter()
    end)
end

if player.Character then
    task.defer(stopAutofarmOnDeath, player.Character)
end
connect(player.CharacterAdded, stopAutofarmOnDeath)

local setDieOnFullBagEnabled = makeToggleCard(
    116,
    "Auto Respawn",
    "",
    Theme.Coral,
    Theme.Gold,
    function(enabled)
        state.dieOnFullBag = enabled
        bagKillTriggered = false
        bagFullConfirmations = 0
        if enabled then
            bagStartFarmed = state.farmed
            bagCheckEnabledAt = os.clock()
        end
    end
)

local function killCharacterWhenBagIsFull()
    if not state.alive or state.closing or not state.autofarm
        or bagKillTriggered or not state.dieOnFullBag or not state.bagFound then
        bagFullConfirmations = 0
        return
    end

    -- ✅ Reset when bag counter reaches 50
    if state.bagCount < state.bagLimit or not bagResetArmed
        or os.clock() - bagCheckEnabledAt < 3 then
        bagFullConfirmations = 0
        return
    end
    bagFullConfirmations += 1
    if bagFullConfirmations < 2 then return end
    local currentCharacter = player.Character
    local currentHumanoid = currentCharacter and currentCharacter:FindFirstChildOfClass("Humanoid")
    if not currentHumanoid or currentHumanoid.Health <= 0 then return end
    bagKillTriggered = true
    bagResetArmed = false
    currentTarget = nil
    state.farmPaused = state.autofarm
    state.pauseReason = state.autofarm and "RESET" or ""
    restoreCharacter()

    local character = player.Character
    local humanoid = character and character:FindFirstChildOfClass("Humanoid")
    if humanoid and humanoid.Health > 0 then
        humanoid.Health = 0
        humanoid:ChangeState(Enum.HumanoidStateType.Dead)
        task.delay(0.05, function()
            if state.alive and not state.closing and state.autofarm
                and state.dieOnFullBag and player.Character == character and character.Parent then
                character:BreakJoints()
            end
        end)
    end
end

local speedCard = makeCard("FarmSpeed")
local speedOutline = addStroke(speedCard,Theme.OrangeNeon,1,1)
addCorner(speedCard,10)
local speedLabel = create("TextLabel",{Name = "SpeedValue",BackgroundTransparency = 1,
    Position = UDim2.fromOffset((0.727-0.108)*WINDOW_WIDTH,(0.56-0.531)*WINDOW_HEIGHT),
    Size = UDim2.fromOffset(0.13*WINDOW_WIDTH,0.043*WINDOW_HEIGHT),
    Text = tostring(state.farmSpeed),Font = Enum.Font.GothamBold,TextSize = 24,TextColor3 = Theme.White,ZIndex = 15},speedCard)
local slider = create("Frame",{Name = "SpeedSlider",BackgroundTransparency = 1,BorderSizePixel = 0,
    Position = UDim2.fromOffset((0.14-0.108)*WINDOW_WIDTH,(0.639-0.531)*WINDOW_HEIGHT),
    Size = UDim2.fromOffset(0.724*WINDOW_WIDTH,0.016*WINDOW_HEIGHT),ZIndex = 15},speedCard)
local initialProgress = (state.farmSpeed-20)/10
local sliderFill = create("Frame",{Name = "SpeedFill",BackgroundColor3 = Color3.new(1,1,1),BorderSizePixel = 0,
    Size = UDim2.fromScale(initialProgress,1),ZIndex = 15},slider)
addCorner(sliderFill,99)
addGradient(sliderFill,{{0,Theme.OrangeSoft},{1,Color3.fromRGB(255,209,28)}},0)
local sliderKnob = create("Frame",{Name = "SpeedKnob",BackgroundColor3 = Theme.White,BorderSizePixel = 0,
    AnchorPoint = Vector2.new(0.5,0.5),Position = UDim2.new(initialProgress,0,0.5,0),
    Size = UDim2.fromOffset(20,20),ZIndex = 17},slider)
addCorner(sliderKnob,99)
addStroke(sliderKnob,Theme.OrangeNeon,3,0)
addGradient(sliderKnob,{{0,Color3.new(1,1,1)},{1,Color3.new(1,0.88,0.67)}},90)
local knobHalo = create("Frame",{Name = "KnobHalo",BackgroundTransparency = 1,
    Size = UDim2.fromScale(1,1),Active = false,ZIndex = 16},sliderKnob)
addCorner(knobHalo,99)
addStroke(knobHalo,Theme.OrangeNeon,8,0.85)
for _,s in ipairs({{"20",0,Enum.TextXAlignment.Left},{"30",1,Enum.TextXAlignment.Right}}) do
    create("TextLabel",{Name = "SpeedLimit",BackgroundTransparency = 1,AnchorPoint = Vector2.new(s[2],0),
        Position = UDim2.new(s[2],0,0,15),Size = UDim2.fromOffset(28,18),Text = s[1],
        Font = Enum.Font.GothamMedium,TextSize = 13,TextColor3 = Theme.Muted,TextXAlignment = s[3],ZIndex = 15},slider)
end
local sliderHitbox = create("TextButton",{Name = "SliderHitbox",AutoButtonColor = false,BackgroundTransparency = 1,
    Position = UDim2.fromOffset(-8,-15),Size = UDim2.new(1,16,1,30),Text = "",ZIndex = 18},slider)

local sliderDragging = false
local sliderInput
local displayedProgress = initialProgress
local targetProgress = initialProgress

local function setSpeedTarget(screenX)
    local width = slider.AbsoluteSize.X
    if width <= 0 then return end
    targetProgress = math.clamp((screenX - slider.AbsolutePosition.X) / width, 0, 1)
    state.farmSpeed = math.floor(20 + targetProgress * 10 + 0.5)
    speedLabel.Text = tostring(state.farmSpeed)
end

connect(sliderHitbox.InputBegan, function(input)
    if input.UserInputType == Enum.UserInputType.MouseButton1 or input.UserInputType == Enum.UserInputType.Touch then
        sliderDragging = true
        sliderInput = input
        setSpeedTarget(input.Position.X)
        smoothTween(sliderKnob, 0.22, { Size = UDim2.fromOffset(24, 24) }, Enum.EasingStyle.Back)
    end
end)

connect(UserInputService.InputChanged, function(input)
    if not sliderDragging then return end
    local mouse = input.UserInputType == Enum.UserInputType.MouseMovement
    local touch = sliderInput and sliderInput.UserInputType == Enum.UserInputType.Touch and input == sliderInput
    if mouse or touch then
        setSpeedTarget(input.Position.X)
    end
end)

connect(UserInputService.InputEnded, function(input)
    if not sliderDragging then return end
    local mouseReleased = sliderInput and sliderInput.UserInputType == Enum.UserInputType.MouseButton1
        and input.UserInputType == Enum.UserInputType.MouseButton1
    if input == sliderInput or mouseReleased then
        sliderDragging = false
        sliderInput = nil
        smoothTween(sliderKnob, 0.3, { Size = UDim2.fromOffset(20, 20) }, Enum.EasingStyle.Back)
    end
end)

connect(sliderHitbox.MouseEnter,function()
    smoothTween(speedOutline,0.2,{Transparency = 0.72})
end)
connect(sliderHitbox.MouseLeave,function()
    smoothTween(speedOutline,0.2,{Transparency = 1})
end)

local setProtectionEnabled = makeToggleCard(
    258,
    "Anti Fling / Void",
    "",
    Theme.Aqua,
    Theme.Blue,
    function(enabled)
        state.protection = enabled
    end
)

local footer = create("Frame",{Name = "FooterMarker",BackgroundTransparency = 1,Size = UDim2.fromOffset(0,0)},window)
local statsPanel = create("Frame",{Name = "FarmSummary",AnchorPoint = Vector2.new(0.5,0.5),Active = true,
    BackgroundTransparency = 1,ClipsDescendants = false,Position = UDim2.fromScale(0.75,0.5),
    Size = UDim2.fromOffset(STATS_WIDTH,STATS_HEIGHT),ZIndex = 40},screenGui)
uiLayout.stats = statsPanel
statsScale = create("UIScale",{Scale = 1},statsPanel)
local statsSurface = create("CanvasGroup",{Name = "StatsSurface",BackgroundTransparency = 1,
    GroupColor3 = Color3.new(1,1,1),GroupTransparency = 1,Size = UDim2.fromScale(1,1),ZIndex = 10},statsPanel)
local statsFire = neon:fire(statsPanel,false)
statsFire.root.Size = UDim2.fromOffset(STATS_WIDTH,STATS_HEIGHT)
local statsSkin
do
    local artSize = STATS_WIDTH
    local gap = STATS_HEIGHT-artSize
    local cut = artSize*0.28
    local backing = create("Frame",{Name = "StatsOpaqueBackplate",Active = false,
        Position = UDim2.fromOffset(artSize*0.108,artSize*0.12),
        Size = UDim2.fromOffset(artSize*0.79,artSize*0.75+gap),
        BackgroundColor3 = Theme.Navy,BackgroundTransparency = 0,BorderSizePixel = 0,ZIndex = 0},statsSurface)
    addCorner(backing,16)
    local function slice(name,sourceY,sourceHeight,targetY,targetHeight)
        local clip = create("Frame",{Name = name,Active = false,BackgroundTransparency = 1,
            ClipsDescendants = true,Position = UDim2.fromOffset(0,targetY),
            Size = UDim2.fromOffset(artSize,targetHeight),ZIndex = 1},statsSurface)
        local scaleY = targetHeight/sourceHeight
        return neon:image(clip,name.."Image","StatsSkin",
            UDim2.fromOffset(0,-sourceY*scaleY),UDim2.fromOffset(artSize,artSize*scaleY),1)
    end
    statsSkin = slice("StatsHeaderArt",0,cut,0,cut)
    slice("StatsStatusArtBand",cut,artSize*0.01,cut,gap)
    slice("StatsBodyArt",cut,artSize-cut,cut+gap,artSize-cut)
end
local statsHeader = create("Frame",{Name = "StatsHeader",Active = true,BackgroundTransparency = 1,
    Position = UDim2.fromOffset(STATS_WIDTH*0.12,STATS_WIDTH*0.14),
    Size = UDim2.fromOffset(STATS_WIDTH*0.76,STATS_WIDTH*0.14),ZIndex = 20},statsSurface)

-- ✅ Custom Arabic stats title overlay (covers baked "HALLOWEEN STATS" text)
local statsTitleBg = create("Frame",{
    Name = "CustomStatsTitleBg",
    BackgroundColor3 = Theme.Navy,
    BackgroundTransparency = 0.15,
    BorderSizePixel = 0,
    Position = UDim2.fromOffset(STATS_WIDTH * 0.12, STATS_WIDTH * 0.14),
    Size = UDim2.fromOffset(STATS_WIDTH * 0.76, STATS_WIDTH * 0.14),
    ZIndex = 21,
}, statsSurface)
addCorner(statsTitleBg, 10)
addStroke(statsTitleBg, Theme.OrangeNeon, 1.5, 0.3)

create("TextLabel",{
    Name = "CustomStatsTitle",
    BackgroundTransparency = 1,
    Size = UDim2.fromScale(1, 1),
    Text = "عمو تشريب Stats",
    Font = Enum.Font.GothamBold,
    TextSize = 20,
    TextColor3 = Theme.OrangeBright,
    TextXAlignment = Enum.TextXAlignment.Center,
    TextYAlignment = Enum.TextYAlignment.Center,
    ZIndex = 22,
}, statsTitleBg)

local statsBadge = create("Frame",{Name = "StatsStatusBadge",Active = false,
    Position = UDim2.fromOffset(STATS_WIDTH*0.15,STATS_WIDTH*0.28+2),
    Size = UDim2.fromOffset(STATS_WIDTH*0.74,STATS_HEIGHT-STATS_WIDTH-4),
    BackgroundColor3 = Color3.fromRGB(25,12,36),BackgroundTransparency = 0.08,BorderSizePixel = 0,ZIndex = 21},statsSurface)
addCorner(statsBadge,9)
addStroke(statsBadge,Theme.Aqua,1,0.35)
local statsDot = create("Frame",{Name = "StatsStatusDot",BorderSizePixel = 0,BackgroundColor3 = Theme.Red,
    AnchorPoint = Vector2.new(0,0.5),Position = UDim2.new(0,9,0.5,0),
    Size = UDim2.fromOffset(10,10),ZIndex = 22},statsBadge)
addCorner(statsDot,99)
local statsStatus = create("TextLabel",{Name = "StatsStatus",BackgroundTransparency = 1,
    Position = UDim2.fromOffset(27,0),Size = UDim2.new(1,-34,1,0),
    Text = "OFF",TextSize = 16,Font = Enum.Font.GothamBold,TextColor3 = Theme.Red,
    TextXAlignment = Enum.TextXAlignment.Left,TextTruncate = Enum.TextTruncate.AtEnd,ZIndex = 22},statsBadge)
connect(statsStatus:GetPropertyChangedSignal("TextColor3"),function() statsDot.BackgroundColor3 = statsStatus.TextColor3 end)
local function makeStatValue(name,y,h,size,initial)
    local value = create("TextLabel",{Name = "Value_"..name,BackgroundTransparency = 1,
        Position = UDim2.fromOffset(STATS_WIDTH*0.59,STATS_WIDTH*y+STATS_HEIGHT-STATS_WIDTH),
        Size = UDim2.fromOffset(STATS_WIDTH*0.285,STATS_WIDTH*h),
        Text = initial,TextSize = size,TextScaled = true,TextWrapped = false,
        Font = Enum.Font.GothamBold,TextColor3 = Theme.White,TextXAlignment = Enum.TextXAlignment.Right,ZIndex = 15},statsSurface)
    create("UITextSizeConstraint",{MinTextSize = 9,MaxTextSize = size},value)
    return value
end
local farmedStat = makeStatValue("Collected",0.344,0.071,30,"0")
local timeStat = makeStatValue("Session",0.463,0.05,21,"00:00")
local rateStat = makeStatValue("Per Hour",0.559,0.05,21,"0")
local speedStat = makeStatValue("Speed",0.657,0.05,21,tostring(state.farmSpeed))
local bagStat = makeStatValue("Bag",0.756,0.05,21,"0/"..tostring(state.bagLimit))
refreshViewport()

local foldMotion = {value = 0, from = 0, target = 0, elapsed = 0, running = false}
local dragMotion = {main = nil, stats = nil}

local function applyFoldVisuals(progress)
    local p = math.clamp(progress,0,1)
    local height = WINDOW_HEIGHT+(COLLAPSED_HEIGHT-WINDOW_HEIGHT)*p
    local panelHeight = WINDOW_HEIGHT*(0.842+(0.164-0.842)*p)
    local blend = math.clamp(p/0.12,0,1)
    window.Size = UDim2.fromOffset(WINDOW_WIDTH,height)
    uiLayout.visibleHeight = height
    compactHeader.Size = UDim2.fromOffset(0.845*WINDOW_WIDTH,panelHeight)
    compactRim.Size = compactHeader.Size
    compactHeader.Visible, compactRim.Visible = p > 0,p > 0
    compactHeader.GroupTransparency = 0
    compactStroke.Transparency = 1-0.92*blend
    mainSkin.ImageTransparency = blend
    mainSkin.Visible = p < 0.12
    content.GroupTransparency = math.clamp(p/0.32,0,1)
    content.Visible, footer.Visible = p < 0.32,p < 0.32
    clampWindow()
end

local function updateFold(deltaTime)
    if not foldMotion.running then return end
    foldMotion.elapsed = math.min(MOTION_SETTINGS.FoldDuration,foldMotion.elapsed+deltaTime)
    local time = foldMotion.elapsed/MOTION_SETTINGS.FoldDuration
    local eased = (1-math.cos(math.pi*time))/2
    foldMotion.value = foldMotion.from+(foldMotion.target-foldMotion.from)*eased
    if time >= 1 then
        foldMotion.value = foldMotion.target
        foldMotion.running = false
    end
    applyFoldVisuals(foldMotion.value)
end

local function boundDragPosition(position,isStats)
    local camera = workspace.CurrentCamera
    if not camera then return position end
    local viewport = camera.ViewportSize
    local scale = isStats and statsScale.Scale or responsiveScale.Scale
    local width = isStats and STATS_WIDTH or WINDOW_WIDTH
    local height = isStats and STATS_HEIGHT or WINDOW_HEIGHT
    local visibleHeight = isStats and height or (uiLayout.visibleHeight or WINDOW_HEIGHT)
    local halfWidth,halfHeight = width*scale/2,height*scale/2
    return UDim2.fromOffset(
        math.clamp(position.X.Scale*viewport.X+position.X.Offset,
            halfWidth+8,math.max(halfWidth+8,viewport.X-halfWidth-8)),
        math.clamp(position.Y.Scale*viewport.Y+position.Y.Offset,
            halfHeight+8,math.max(halfHeight+8,viewport.Y-visibleHeight*scale+halfHeight-8))
    )
end

local function followDrag(object,key,isStats,alpha)
    local target = dragMotion[key]
    if not target then return end
    target = boundDragPosition(target,isStats)
    dragMotion[key] = target
    local camera = workspace.CurrentCamera
    if not camera then return end
    local viewport = camera.ViewportSize
    local position = object.Position
    local x = position.X.Scale*viewport.X+position.X.Offset
    local y = position.Y.Scale*viewport.Y+position.Y.Offset
    local dx,dy = target.X.Offset-x,target.Y.Offset-y
    if math.abs(dx)+math.abs(dy) < 0.25 then
        object.Position = target
        dragMotion[key] = nil
    else
        object.Position = UDim2.fromOffset(x+dx*alpha,y+dy*alpha)
    end
end

local function updateDrag(deltaTime)
    local alpha = 1-math.exp(-MOTION_SETTINGS.DragResponse*deltaTime)
    followDrag(holder,"main",false,alpha)
    followDrag(statsPanel,"stats",true,alpha)
end

local statsDragging = false
local statsDragInput
local statsDragStart
local statsStartPosition

connect(statsHeader.InputBegan,function(input)
    if state.closing then return end
    if input.UserInputType == Enum.UserInputType.MouseButton1 or input.UserInputType == Enum.UserInputType.Touch then
        uiLayout.statsMoved = true
        statsDragging,statsDragInput = true,input
        statsDragStart,statsStartPosition = input.Position,statsPanel.Position
        dragMotion.stats = nil
    end
end)

connect(UserInputService.InputChanged,function(input)
    if not statsDragging or not statsDragInput then return end
    local mouse = input.UserInputType == Enum.UserInputType.MouseMovement
    local touch = statsDragInput.UserInputType == Enum.UserInputType.Touch and input == statsDragInput
    if not mouse and not touch then return end
    local delta = input.Position-statsDragStart
    dragMotion.stats = boundDragPosition(UDim2.new(
        statsStartPosition.X.Scale,statsStartPosition.X.Offset+delta.X,
        statsStartPosition.Y.Scale,statsStartPosition.Y.Offset+delta.Y),true)
end)

connect(UserInputService.InputEnded,function(input)
    if not statsDragInput then return end
    local released = statsDragInput.UserInputType == Enum.UserInputType.MouseButton1
        and input.UserInputType == Enum.UserInputType.MouseButton1
    if input == statsDragInput or released then statsDragging,statsDragInput = false,nil end
end)

local dragging = false
local dragInput
local dragStart
local holderStart

local function pointInside(object,point)
    local topLeft,size = object.AbsolutePosition,object.AbsoluteSize
    return point.X >= topLeft.X and point.X <= topLeft.X+size.X
        and point.Y >= topLeft.Y and point.Y <= topLeft.Y+size.Y
end

connect(header.InputBegan,function(input)
    if state.closing then return end
    if input.UserInputType ~= Enum.UserInputType.MouseButton1 and input.UserInputType ~= Enum.UserInputType.Touch then return end
    if pointInside(minimizeButton,input.Position) or pointInside(closeButton,input.Position) then return end
    uiLayout.mainMoved = true
    dragging,dragInput = true,input
    dragStart,holderStart = input.Position,holder.Position
    dragMotion.main = nil
end)

connect(UserInputService.InputChanged,function(input)
    if not dragging or not dragInput then return end
    local mouse = input.UserInputType == Enum.UserInputType.MouseMovement
    local touch = dragInput.UserInputType == Enum.UserInputType.Touch and input == dragInput
    if not mouse and not touch then return end
    local delta = input.Position-dragStart
    dragMotion.main = boundDragPosition(UDim2.new(
        holderStart.X.Scale,holderStart.X.Offset+delta.X,
        holderStart.Y.Scale,holderStart.Y.Offset+delta.Y),false)
end)

connect(UserInputService.InputEnded,function(input)
    if not dragInput then return end
    local released = dragInput.UserInputType == Enum.UserInputType.MouseButton1
        and input.UserInputType == Enum.UserInputType.MouseButton1
    if input == dragInput or released then dragging,dragInput = false,nil end
end)

local function setMinimized(value)
    if state.closing or state.minimized == value then return end
    state.minimized = value
    minimizeButton.Text = value and "+" or "—"
    foldMotion.from = foldMotion.value
    foldMotion.target = value and 1 or 0
    foldMotion.elapsed,foldMotion.running = 0,true
end

connect(minimizeButton.Activated, function()
    setMinimized(not state.minimized)
end)

connect(closeButton.Activated, function()
    if state.closing then return end
    state.closing = true
    state.autofarm = false
    restoreCharacter()
    smoothTween(window, 0.26, { GroupTransparency = 1 }, Enum.EasingStyle.Quart)
    smoothTween(statsSurface, 0.26, { GroupTransparency = 1 }, Enum.EasingStyle.Quart)
    smoothTween(neon.opacity, 0.26, { Value = 0 })
    task.delay(0.28, function()
        cleanup()
        if screenGui.Parent then screenGui:Destroy() end
    end)
end)

local elapsed = 0
local statsAccumulator = 0
local lastDecorUpdate = 0
connect(RunService.RenderStepped, function(deltaTime)
    if not state.alive then return end
    elapsed += deltaTime
    updateFold(deltaTime)
    updateDrag(deltaTime)
    statsAccumulator += deltaTime

    if statsAccumulator >= 0.2 then
        statsAccumulator = 0
        local sessionSeconds = math.max(0, os.clock() - state.sessionStarted)
        local wholeSeconds = math.floor(sessionSeconds)
        local minutes = math.floor(wholeSeconds / 60)
        local seconds = wholeSeconds % 60
        local perHour = sessionSeconds > 0 and (state.farmed / sessionSeconds) * 3600 or 0

        farmedStat.Text = neon:integer(state.farmed)
        timeStat.Text = string.format("%02d:%02d", minutes, seconds)
        rateStat.Text = neon:integer(perHour)
        speedStat.Text = tostring(state.farmSpeed)
        updateBagFromInterface()
        bagStat.Text = string.format("%d/%d%s", state.bagCount, state.bagLimit, state.bagFound and "" or " (?)")
        bagStat.TextColor3 = state.bagCount >= state.bagLimit and Theme.Coral or Theme.OrangeBright
        if not state.autofarm then
            statsStatus.Text = "OFF"
            statsStatus.TextColor3 = Theme.Red
        elseif state.farmPaused then
            statsStatus.Text = state.pauseReason
            statsStatus.TextColor3 = Theme.Gold
        else
            statsStatus.Text = "FARMING"
            statsStatus.TextColor3 = Theme.OrangeNeon
        end
        if neon.farmStatus then
            neon.farmStatus.Text = statsStatus.Text
            neon.farmStatus.TextColor3 = statsStatus.TextColor3
            neon.farmDot.BackgroundColor3 = statsStatus.TextColor3
        end
        killCharacterWhenBagIsFull()
    end

    if math.abs(targetProgress - displayedProgress) > 0.0005 then
        displayedProgress += (targetProgress - displayedProgress) * math.min(1, deltaTime * 18)
        sliderFill.Size = UDim2.fromScale(displayedProgress, 1)
        sliderKnob.Position = UDim2.new(displayedProgress, 0, 0.5, 0)
    end

    if elapsed - lastDecorUpdate >= 1 / NEON_SETTINGS.UpdateRate then
        lastDecorUpdate = elapsed
        neon:update(elapsed)
    end
end)

smoothTween(window,0.4,{GroupTransparency=0},Enum.EasingStyle.Quart)
smoothTween(statsSurface,0.4,{GroupTransparency=0},Enum.EasingStyle.Quart)
smoothTween(neon.opacity,0.6,{Value=1},Enum.EasingStyle.Sine)
playUiSound(1,0.4)

task.spawn(function()
    local unique,seen={},{}
    for _,image in ipairs(neon.images) do
        if not seen[image.Image] then
            seen[image.Image]=true
            table.insert(unique,image)
        end
    end
    local ok,message=pcall(function()
        game:GetService("ContentProvider"):PreloadAsync(unique,function(asset,status)
            if not state.alive then return end
            neon:assetResult(asset,status)
            if status~=Enum.AssetFetchStatus.Success then
                warn("[عمو تشريب] image not loaded: "..tostring(asset).." ("..tostring(status)..")")
            end
        end)
    end)
    if not ok and state.alive then warn("[عمو تشريب] preload: "..tostring(message)) end
end)
