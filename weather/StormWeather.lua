-- STORM ADDON FOR TOWN

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Players = game:GetService("Players")
local RunService = game:GetService("RunService")
local TweenService = game:GetService("TweenService")
local Lighting = game:GetService("Lighting")
local Debris = game:GetService("Debris")

local Player = Players.LocalPlayer
local Camera = workspace.CurrentCamera
local Terrain = workspace.Terrain

local WeatherType = ReplicatedStorage:WaitForChild("WeatherType")
local WeatherEnabled = WeatherType:WaitForChild("WeatherEnabled")

local CONFIG = {
    Enabled = true,
    StormWeatherName = "storm",

    GridRadius = 6,
    CellSize = 20,
    TopHeight = 110,

    RainRateMultiplier = 1.9,
    RainSpeedMultiplier = 1.15,

    SplashChance = 5,
    SplashEmitCount = 1,

    MinLightningWait = 8,
    MaxLightningWait = 26,
    ClusterChance = 12,

    ThunderVolume = 0.85,
    MinThunderDelay = 1.8,
    MaxThunderDelay = 5.5,

    InstantBoomVolume = 1.1,
    InstantBoomSoundId = "rbxassetid://9114221327",

    BoltChance = 85,
    BoltLife = 0.16,


    PlayerStrikeChance = 11, 
    PlayerFireDuration = 4,
    PlayerFireLightBrightness = 2.5,

    UseStormLighting = true,
    UseClouds = true,
}

local Storm = {
    Active = false,

    Folder = nil,
    TopModel = nil,
    FloorModel = nil,

    TopParts = {},
    FloorParts = {},

    Connections = {},
    ThreadsAlive = false,

    RainSound = nil,

    RainTemplate = nil,
    SplashTemplate = nil,
    SoundTemplate = nil,

    OriginalLighting = {},
    OriginalClouds = nil,
    OriginalCloudCover = nil,
    OriginalCloudDensity = nil,
}

local function findTemplate(name, className)
    for _, obj in ipairs(game:GetDescendants()) do
        if obj.Name == name and (not className or obj:IsA(className)) then
            return obj
        end
    end

    return nil
end

local function loadOriginalRainAssets()
    Storm.RainTemplate = findTemplate("RainEffect", "ParticleEmitter")
    Storm.SplashTemplate = findTemplate("RainSplash", "ParticleEmitter")
    Storm.SoundTemplate = findTemplate("RainSound", "Sound")
end

local function addConnection(con)
    table.insert(Storm.Connections, con)
    return con
end

local function disconnectAll()
    for _, con in ipairs(Storm.Connections) do
        if con then
            con:Disconnect()
        end
    end

    table.clear(Storm.Connections)
end

local function saveLighting()
    Storm.OriginalLighting = {
        Brightness = Lighting.Brightness,
        Ambient = Lighting.Ambient,
        OutdoorAmbient = Lighting.OutdoorAmbient,
        FogColor = Lighting.FogColor,
        FogStart = Lighting.FogStart,
        FogEnd = Lighting.FogEnd,
        ClockTime = Lighting.ClockTime,
    }
end

local function restoreLighting()
    local old = Storm.OriginalLighting

    if old.Brightness ~= nil then
        Lighting.Brightness = old.Brightness
        Lighting.Ambient = old.Ambient
        Lighting.OutdoorAmbient = old.OutdoorAmbient
        Lighting.FogColor = old.FogColor
        Lighting.FogStart = old.FogStart
        Lighting.FogEnd = old.FogEnd
        Lighting.ClockTime = old.ClockTime
    end
end

local function saveClouds()
    local clouds = Terrain:FindFirstChildOfClass("Clouds")

    if not clouds then
        clouds = Instance.new("Clouds")
        clouds.Name = "StormGeneratedClouds"
        clouds.Cover = 0.35
        clouds.Density = 0.35
        clouds.Parent = Terrain
    end

    Storm.OriginalClouds = clouds
    Storm.OriginalCloudCover = clouds.Cover
    Storm.OriginalCloudDensity = clouds.Density
end

local function restoreClouds()
    local clouds = Storm.OriginalClouds

    if clouds and clouds.Parent then
        TweenService:Create(
            clouds,
            TweenInfo.new(3, Enum.EasingStyle.Sine),
            {
                Cover = Storm.OriginalCloudCover or 0.35,
                Density = Storm.OriginalCloudDensity or 0.35,
            }
        ):Play()
    end
end

local function clearStorm()
    Storm.Active = false
    Storm.ThreadsAlive = false

    disconnectAll()

    if Storm.RainSound then
        TweenService:Create(
            Storm.RainSound,
            TweenInfo.new(0.6, Enum.EasingStyle.Sine),
            { Volume = 0 }
        ):Play()

        Debris:AddItem(Storm.RainSound, 0.75)
        Storm.RainSound = nil
    end

    if Storm.Folder then
        Storm.Folder:Destroy()
        Storm.Folder = nil
    end

    table.clear(Storm.TopParts)
    table.clear(Storm.FloorParts)

    restoreLighting()
    restoreClouds()
end

local function makeCell(name, parent)
    local part = Instance.new("Part")
    part.Name = name
    part.CanQuery = false
    part.CanCollide = false
    part.CanTouch = false
    part.CastShadow = false
    part.Transparency = 1
    part.Anchored = true
    part.Locked = true
    part.Size = Vector3.new(CONFIG.CellSize, 0.2, CONFIG.CellSize)
    part.Parent = parent

    return part
end

local function createFallbackRainEmitter()
    local emitter = Instance.new("ParticleEmitter")
    emitter.Name = "WeatherEffect"
    emitter.Texture = "rbxassetid://243098098"

    emitter.Rate = 420
    emitter.Lifetime = NumberRange.new(0.45, 0.8)
    emitter.Speed = NumberRange.new(95, 145)
    emitter.Acceleration = Vector3.new(18, -170, 8)

    emitter.Color = ColorSequence.new({
        ColorSequenceKeypoint.new(0, Color3.fromRGB(195, 220, 255)),
        ColorSequenceKeypoint.new(1, Color3.fromRGB(100, 160, 255)),
    })

    emitter.Transparency = NumberSequence.new({
        NumberSequenceKeypoint.new(0, 0.05),
        NumberSequenceKeypoint.new(0.75, 0.25),
        NumberSequenceKeypoint.new(1, 1),
    })

    emitter.Size = NumberSequence.new({
        NumberSequenceKeypoint.new(0, 0.085),
        NumberSequenceKeypoint.new(1, 0),
    })

    emitter.LightEmission = 0.45
    emitter.SpreadAngle = Vector2.new(8, 8)
    emitter.Rotation = NumberRange.new(0, 360)
    emitter.RotSpeed = NumberRange.new(-30, 30)
    emitter.LockedToPart = false
    emitter.Enabled = true

    return emitter
end

local function createFallbackSplashEmitter()
    local emitter = Instance.new("ParticleEmitter")
    emitter.Name = "WeatherEffect"
    emitter.Texture = "rbxassetid://243098098"

    emitter.Rate = 0
    emitter.Lifetime = NumberRange.new(0.12, 0.32)
    emitter.Speed = NumberRange.new(7, 20)
    emitter.Acceleration = Vector3.new(0, -45, 0)

    emitter.Color = ColorSequence.new({
        ColorSequenceKeypoint.new(0, Color3.fromRGB(180, 210, 255)),
        ColorSequenceKeypoint.new(1, Color3.fromRGB(80, 135, 255)),
    })

    emitter.Transparency = NumberSequence.new({
        NumberSequenceKeypoint.new(0, 0.05),
        NumberSequenceKeypoint.new(1, 1),
    })

    emitter.Size = NumberSequence.new({
        NumberSequenceKeypoint.new(0, 0.18),
        NumberSequenceKeypoint.new(1, 0),
    })

    emitter.LightEmission = 0.55
    emitter.SpreadAngle = Vector2.new(180, 180)
    emitter.Rotation = NumberRange.new(0, 360)
    emitter.RotSpeed = NumberRange.new(-180, 180)
    emitter.Enabled = false

    return emitter
end

local function cloneRainEmitter()
    local emitter

    if Storm.RainTemplate then
        emitter = Storm.RainTemplate:Clone()
    else
        emitter = createFallbackRainEmitter()
    end

    emitter.Name = "WeatherEffect"

    emitter.Rate = emitter.Rate * CONFIG.RainRateMultiplier
    emitter.Speed = NumberRange.new(
        emitter.Speed.Min * CONFIG.RainSpeedMultiplier,
        emitter.Speed.Max * CONFIG.RainSpeedMultiplier
    )

    emitter.Enabled = true

    return emitter
end

local function cloneSplashEmitter()
    local emitter

    if Storm.SplashTemplate then
        emitter = Storm.SplashTemplate:Clone()
    else
        emitter = createFallbackSplashEmitter()
    end

    emitter.Name = "WeatherEffect"
    emitter.Rate = 0
    emitter.Enabled = false

    return emitter
end

local function createTopRainGrid()
    local model = Instance.new("Model")
    model.Name = "StormTopEffects"
    model.Parent = Storm.Folder
    Storm.TopModel = model

    local center = Instance.new("Part")
    center.Name = "GridCenter"
    center.Anchored = true
    center.CanCollide = false
    center.CanQuery = false
    center.CanTouch = false
    center.Transparency = 1
    center.Size = Vector3.new(1, 1, 1)
    center.CFrame = CFrame.new(0, CONFIG.TopHeight, 0)
    center.Parent = model

    model.PrimaryPart = center

    for x = -CONFIG.GridRadius, CONFIG.GridRadius do
        for z = -CONFIG.GridRadius, CONFIG.GridRadius do
            local part = makeCell("StormRainCell", model)

            part.CFrame = CFrame.new(
                x * CONFIG.CellSize,
                CONFIG.TopHeight,
                z * CONFIG.CellSize
            )

            local emitter = cloneRainEmitter()
            emitter.Parent = part

            table.insert(Storm.TopParts, {
                Part = part,
                X = x,
                Z = z,
            })
        end
    end
end

local function createFloorSplashGrid()
    local model = Instance.new("Model")
    model.Name = "StormFloorEffects"
    model.Parent = Storm.Folder
    Storm.FloorModel = model

    for x = -CONFIG.GridRadius, CONFIG.GridRadius do
        for z = -CONFIG.GridRadius, CONFIG.GridRadius do
            local part = makeCell("StormSplashCell", model)

            part.CFrame = CFrame.new(
                x * CONFIG.CellSize,
                CONFIG.TopHeight,
                z * CONFIG.CellSize
            )

            local emitter = cloneSplashEmitter()
            emitter.Parent = part

            table.insert(Storm.FloorParts, {
                Part = part,
                X = x,
                Z = z,
            })
        end
    end

    if Storm.FloorParts[1] then
        model.PrimaryPart = Storm.FloorParts[1].Part
    end
end

local function playRainSound()
    local sound

    if Storm.SoundTemplate then
        sound = Storm.SoundTemplate:Clone()
    else
        sound = Instance.new("Sound")
        sound.SoundId = "rbxassetid://9120396436"
        sound.Volume = 0.35
    end

    sound.Name = "StormRainSound"
    sound.Looped = true
    sound.Volume = 0
    sound.Parent = Camera
    sound:Play()

    local targetVolume = 0.45

    local original = sound:FindFirstChild("OriginalVolume")
    if original and original:IsA("NumberValue") then
        targetVolume = math.max(original.Value, 0.35)
    end

    TweenService:Create(
        sound,
        TweenInfo.new(1.2, Enum.EasingStyle.Sine),
        { Volume = targetVolume }
    ):Play()

    Storm.RainSound = sound
end

local function rayIgnoreCheck(part)
    if not part then
        return false
    end

    local parent = part.Parent
    local grandparent = parent and parent.Parent

    if part.Transparency >= 1 and part.CanCollide == false then
        return true
    end

    if parent and parent:FindFirstChildOfClass("Humanoid") then
        return true
    end

    if grandparent and grandparent:FindFirstChildOfClass("Humanoid") then
        return true
    end

    if parent and parent.ClassName == "Tool" then
        return true
    end

    return false
end

local function raycastDown(origin, direction, distance, ignoreList, params, depth)
    depth = depth or 1

    if not params then
        params = RaycastParams.new()
        params.IgnoreWater = true
        params.RespectCanCollide = true
        params.FilterType = Enum.RaycastFilterType.Exclude
        params.FilterDescendantsInstances = ignoreList or {}
    end

    local result = workspace:Raycast(origin + direction * 0.01, direction * distance, params)

    if not result then
        return nil, origin + direction * distance, nil, nil
    end

    local hit = result.Instance
    local pos = result.Position
    local normal = result.Normal
    local material = result.Material

    local remaining = distance - (pos - origin).Magnitude

    if hit and rayIgnoreCheck(hit) and remaining > 0 and depth < 100 then
        params:AddToFilter(hit)
        return raycastDown(origin, direction, distance, ignoreList, params, depth + 1)
    end

    return hit, pos, normal, material
end

local function updateStormGrid()
    if not Storm.Active or not Storm.TopModel or not Storm.TopModel.PrimaryPart then
        return
    end

    local camCF = Camera.CFrame
    local camPos = camCF.Position
    local _, yaw, _ = camCF:ToOrientation()

    local baseCF = CFrame.new(camPos) * CFrame.fromOrientation(0, yaw, 0)

    Storm.TopModel:SetPrimaryPartCFrame(
        CFrame.new(camPos.X, camPos.Y + CONFIG.TopHeight, camPos.Z)
    )

    local closestSplashPos = nil

    for i, rainData in ipairs(Storm.TopParts) do
        local rainPart = rainData.Part

        if rainPart and rainPart.Parent then
            local targetPos = (
                baseCF * CFrame.new(
                    rainData.X * CONFIG.CellSize,
                    CONFIG.TopHeight,
                    rainData.Z * CONFIG.CellSize
                )
            ).Position

            local hit, groundPos = raycastDown(
                targetPos,
                Vector3.new(0, -1, 0),
                350,
                { Camera, Storm.Folder }
            )

            if groundPos then
                rainPart.Position = Vector3.new(
                    targetPos.X,
                    groundPos.Y + CONFIG.TopHeight,
                    targetPos.Z
                )

                local rainEmitter = rainPart:FindFirstChildOfClass("ParticleEmitter")
                if rainEmitter then
                    local distanceToGround = (rainPart.Position - groundPos).Magnitude

                    if rainEmitter.Speed.Max > 0 then
                        rainEmitter.Lifetime = NumberRange.new(
                            math.clamp(
                                1 / (rainEmitter.Speed.Max / distanceToGround),
                                0.25,
                                1.2
                            )
                        )
                    end
                end

                local splashData = Storm.FloorParts[i]
                local splashPart = splashData and splashData.Part

                if splashPart and splashPart.Parent then
                    splashPart.Position = groundPos + Vector3.new(0, 0.08, 0)

                    if not closestSplashPos then
                        closestSplashPos = splashPart.Position
                    elseif (splashPart.Position - Camera.CFrame.Position).Magnitude < (closestSplashPos - Camera.CFrame.Position).Magnitude then
                        closestSplashPos = splashPart.Position
                    end

                    local splashEmitter = splashPart:FindFirstChildOfClass("ParticleEmitter")
                    local _, onScreen = Camera:WorldToScreenPoint(splashPart.Position)

                    if splashEmitter and hit and onScreen and math.random(1, CONFIG.SplashChance) == 1 then
                        splashEmitter:Emit(CONFIG.SplashEmitCount)
                    end
                end
            end
        end
    end

    if Storm.RainSound and closestSplashPos then
        local distance = math.max((closestSplashPos - Camera.CFrame.Position).Magnitude, 1)
        local distVolume = 14 / distance
        Storm.RainSound.Volume = math.clamp(distVolume, 0.18, 0.65)
    end
end

local function applyStormLighting()
    if not CONFIG.UseStormLighting then
        return
    end

    saveLighting()

    Lighting.Brightness = 0.85
    Lighting.ClockTime = 18
    Lighting.Ambient = Color3.fromRGB(45, 50, 75)
    Lighting.OutdoorAmbient = Color3.fromRGB(35, 40, 65)
    Lighting.FogColor = Color3.fromRGB(70, 80, 115)
    Lighting.FogStart = 0
    Lighting.FogEnd = 275
end

local function applyClouds()
    if not CONFIG.UseClouds then
        return
    end

    saveClouds()

    local clouds = Storm.OriginalClouds
    if clouds and clouds.Parent then
        TweenService:Create(
            clouds,
            TweenInfo.new(4, Enum.EasingStyle.Sine),
            {
                Cover = 0.92,
                Density = 0.9,
            }
        ):Play()
    end
end

local function lightningFlash(brightness)
    local flash = Instance.new("ColorCorrectionEffect")
    flash.Name = "StormLightningFlash"
    flash.Brightness = 0
    flash.Contrast = 0
    flash.Saturation = -0.1
    flash.TintColor = Color3.fromRGB(225, 235, 255)
    flash.Parent = Lighting

    local t1 = TweenService:Create(
        flash,
        TweenInfo.new(0.025, Enum.EasingStyle.Linear),
        {
            Brightness = brightness,
            Contrast = 0.35,
        }
    )

    local t2 = TweenService:Create(
        flash,
        TweenInfo.new(math.random(18, 36) / 100, Enum.EasingStyle.Sine),
        {
            Brightness = 0,
            Contrast = 0,
        }
    )

    t1:Play()

    t1.Completed:Connect(function()
        if flash and flash.Parent then
            t2:Play()
        end
    end)

    t2.Completed:Connect(function()
        if flash then
            flash:Destroy()
        end
    end)
end

local function makeBoltSegment(parent, fromPos, toPos, thickness)
    local distance = (toPos - fromPos).Magnitude
    local midpoint = (fromPos + toPos) / 2

    local part = Instance.new("Part")
    part.Name = "LightningSegment"
    part.Anchored = true
    part.CanCollide = false
    part.CanQuery = false
    part.CanTouch = false
    part.CastShadow = false
    part.Material = Enum.Material.Neon
    part.Color = Color3.fromRGB(225, 240, 255)
    part.Transparency = 0.02
    part.Size = Vector3.new(thickness, thickness, distance)
    part.CFrame = CFrame.new(midpoint, toPos)
    part.Parent = parent

    local light = Instance.new("PointLight")
    light.Name = "LightningGlow"
    light.Color = Color3.fromRGB(185, 215, 255)
    light.Brightness = 5
    light.Range = 22
    light.Shadows = false
    light.Parent = part
end

local function createLightningBolt()
    local model = Instance.new("Model")
    model.Name = "StormLightningBolt"
    model.Parent = Camera

    local side = math.random(0, 1) == 0 and -1 or 1

    local startOffset = Vector3.new(
        math.random(25, 90) * side,
        math.random(80, 135),
        -math.random(55, 145)
    )

    local startPos = Camera.CFrame.Position + Camera.CFrame:VectorToWorldSpace(startOffset)
    local currentPos = startPos

    local segments = math.random(6, 11)

    for i = 1, segments do
        local nextPos = currentPos + Camera.CFrame:VectorToWorldSpace(Vector3.new(
            math.random(-18, 18),
            -math.random(12, 28),
            math.random(-15, 15)
        ))

        local thickness = math.max(0.08, 0.45 - i * 0.035)
        makeBoltSegment(model, currentPos, nextPos, thickness)

        if math.random(1, 100) <= 35 then
            local branchEnd = nextPos + Camera.CFrame:VectorToWorldSpace(Vector3.new(
                math.random(-28, 28),
                -math.random(5, 18),
                math.random(-22, 22)
            ))

            makeBoltSegment(model, nextPos, branchEnd, thickness * 0.55)
        end

        currentPos = nextPos
    end

    Debris:AddItem(model, CONFIG.BoltLife)
end

local function playInstantLightningBoom()
    local boom = Instance.new("Sound")
    boom.Name = "InstantLightningBoom"
    boom.SoundId = CONFIG.InstantBoomSoundId
    boom.Volume = CONFIG.InstantBoomVolume * (math.random(90, 120) / 100)
    boom.PlaybackSpeed = math.random(85, 110) / 100
    boom.RollOffMaxDistance = 10000
    boom.Parent = Camera

    boom:Play()
    Debris:AddItem(boom, 8)
end

local function playThunder()
    local thunder = Instance.new("Sound")
    thunder.Name = "StormThunder"
    thunder.SoundId = "rbxassetid://9114221327"
    thunder.Volume = CONFIG.ThunderVolume * (math.random(80, 120) / 100)
    thunder.PlaybackSpeed = math.random(75, 115) / 100
    thunder.RollOffMaxDistance = 10000
    thunder.Parent = Camera

    thunder:Play()
    Debris:AddItem(thunder, 8)
end

local function getCharacterRoot()
    local character = Player.Character
    if not character then
        return nil, nil
    end

    local root =
        character:FindFirstChild("HumanoidRootPart")
        or character:FindFirstChild("Torso")
        or character:FindFirstChild("UpperTorso")

    return character, root
end

local function createHarmlessPlayerStrike()
    local character, root = getCharacterRoot()
    if not character or not root then
        return
    end

    if character:FindFirstChild("HarmlessLightningStrikeActive") then
        return
    end

    local tag = Instance.new("BoolValue")
    tag.Name = "HarmlessLightningStrikeActive"
    tag.Parent = character
    Debris:AddItem(tag, CONFIG.PlayerFireDuration + 0.5)

    local boltModel = Instance.new("Model")
    boltModel.Name = "PlayerHarmlessLightningBolt"
    boltModel.Parent = Camera

    local topPos = root.Position + Vector3.new(
        math.random(-8, 8),
        math.random(55, 75),
        math.random(-8, 8)
    )

    local currentPos = topPos
    local segments = 7

    for i = 1, segments do
        local alpha = i / segments
        local targetPos = topPos:Lerp(root.Position + Vector3.new(0, 2, 0), alpha)

        local jitter = Vector3.new(
            math.random(-5, 5),
            math.random(-2, 2),
            math.random(-5, 5)
        )

        local nextPos = targetPos + jitter
        local thickness = math.max(0.08, 0.42 - i * 0.04)

        makeBoltSegment(boltModel, currentPos, nextPos, thickness)
        currentPos = nextPos
    end

    Debris:AddItem(boltModel, 0.18)

    local light = Instance.new("PointLight")
    light.Name = "HarmlessLightningLight"
    light.Color = Color3.fromRGB(150, 210, 255)
    light.Brightness = CONFIG.PlayerFireLightBrightness
    light.Range = 16
    light.Shadows = false
    light.Parent = root

    TweenService:Create(
        light,
        TweenInfo.new(CONFIG.PlayerFireDuration, Enum.EasingStyle.Quad, Enum.EasingDirection.Out),
        {
            Brightness = 0,
            Range = 0,
        }
    ):Play()

    Debris:AddItem(light, CONFIG.PlayerFireDuration + 0.25)

    local sparks = Instance.new("ParticleEmitter")
    sparks.Name = "HarmlessLightningSparks"
    sparks.Texture = "rbxassetid://243098098"
    sparks.Rate = 70
    sparks.Lifetime = NumberRange.new(0.25, 0.65)
    sparks.Speed = NumberRange.new(5, 16)
    sparks.Acceleration = Vector3.new(0, 10, 0)
    sparks.LightEmission = 1
    sparks.SpreadAngle = Vector2.new(180, 180)
    sparks.Rotation = NumberRange.new(0, 360)
    sparks.RotSpeed = NumberRange.new(-180, 180)

    sparks.Color = ColorSequence.new({
        ColorSequenceKeypoint.new(0, Color3.fromRGB(120, 190, 255)),
        ColorSequenceKeypoint.new(0.5, Color3.fromRGB(255, 255, 255)),
        ColorSequenceKeypoint.new(1, Color3.fromRGB(80, 130, 255)),
    })

    sparks.Size = NumberSequence.new({
        NumberSequenceKeypoint.new(0, 0.18),
        NumberSequenceKeypoint.new(1, 0),
    })

    sparks.Transparency = NumberSequence.new({
        NumberSequenceKeypoint.new(0, 0),
        NumberSequenceKeypoint.new(1, 1),
    })

    sparks.Parent = root
    Debris:AddItem(sparks, CONFIG.PlayerFireDuration)

    local fire = Instance.new("Fire")
    fire.Name = "HarmlessLightningFire"
    fire.Color = Color3.fromRGB(80, 170, 255)
    fire.SecondaryColor = Color3.fromRGB(255, 255, 255)
    fire.Heat = 4
    fire.Size = 5
    fire.Parent = root

    Debris:AddItem(fire, CONFIG.PlayerFireDuration)

    local zap = Instance.new("Sound")
    zap.Name = "HarmlessLightningZap"
    zap.SoundId = "rbxassetid://9114221327"
    zap.Volume = 0.45
    zap.PlaybackSpeed = 1.45
    zap.Parent = root
    zap:Play()

    Debris:AddItem(zap, 4)

    lightningFlash(0.45)
end

local function lightningStrike()
    if not Storm.Active then
        return
    end

    local style = math.random(1, 5)
    local brightness = math.random(35, 95) / 100

    if style == 1 then
        lightningFlash(brightness)

    elseif style == 2 then
        lightningFlash(brightness * 0.45)

        task.delay(math.random(4, 11) / 100, function()
            if Storm.Active then
                lightningFlash(brightness)
            end
        end)

    elseif style == 3 then
        lightningFlash(0.2)

        task.delay(math.random(5, 12) / 100, function()
            if Storm.Active then
                lightningFlash(brightness * 0.65)
            end
        end)

        task.delay(math.random(13, 25) / 100, function()
            if Storm.Active then
                lightningFlash(brightness)
            end
        end)

    elseif style == 4 then
        lightningFlash(brightness * 0.25)

        task.delay(0.06, function()
            if Storm.Active then
                lightningFlash(brightness * 0.3)
            end
        end)

    else
        lightningFlash(brightness)
    end

    playInstantLightningBoom()

    if math.random(1, 100) <= CONFIG.BoltChance then
        createLightningBolt()
    end

    if math.random(1, 100) <= CONFIG.PlayerStrikeChance then
        createHarmlessPlayerStrike()
    end

    local delayTime = math.random(
        math.floor(CONFIG.MinThunderDelay * 100),
        math.floor(CONFIG.MaxThunderDelay * 100)
    ) / 100

    task.delay(delayTime, function()
        if Storm.Active then
            playThunder()
        end
    end)
end

local function startRandomLightningLoop()
    Storm.ThreadsAlive = true

    task.spawn(function()
        while Storm.ThreadsAlive and Storm.Active do
            local waitTime = math.random(
                math.floor(CONFIG.MinLightningWait * 100),
                math.floor(CONFIG.MaxLightningWait * 100)
            ) / 100

            task.wait(waitTime)

            if not Storm.ThreadsAlive or not Storm.Active then
                break
            end

            lightningStrike()

            if math.random(1, 100) <= CONFIG.ClusterChance then
                task.delay(math.random(10, 35) / 100, function()
                    if Storm.Active then
                        lightningStrike()
                    end
                end)

                if math.random(1, 2) == 1 then
                    task.delay(math.random(45, 110) / 100, function()
                        if Storm.Active then
                            lightningStrike()
                        end
                    end)
                end
            end
        end
    end)
end

local function startStorm()
    clearStorm()

    if not CONFIG.Enabled then
        return
    end

    if not WeatherEnabled.Value then
        return
    end

    if string.lower(tostring(WeatherType.Value)) ~= string.lower(CONFIG.StormWeatherName) then
        return
    end

    Storm.Active = true

    loadOriginalRainAssets()

    Storm.Folder = Instance.new("Folder")
    Storm.Folder.Name = "StormWeatherEffects"
    Storm.Folder.Parent = Camera

    applyStormLighting()
    applyClouds()

    createTopRainGrid()
    createFloorSplashGrid()
    playRainSound()

    addConnection(RunService.RenderStepped:Connect(function()
        updateStormGrid()
    end))

    startRandomLightningLoop()

    task.delay(math.random(30, 180) / 100, function()
        if Storm.Active then
            lightningStrike()
        end
    end)
end

local function refresh()
    if WeatherEnabled.Value and string.lower(tostring(WeatherType.Value)) == string.lower(CONFIG.StormWeatherName) then
        startStorm()
    else
        clearStorm()
    end
end

WeatherType.Changed:Connect(refresh)
WeatherEnabled.Changed:Connect(refresh)

refresh()
