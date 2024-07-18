local OrionLib = loadstring(game:HttpGet(
                                ('https://raw.githubusercontent.com/shlexware/Orion/main/source')))()

local Window = OrionLib:MakeWindow({
    Name = [[<font color="rgb(255,0,0)">haha</font>]],
    HidePremium = false,
    SaveConfig = true,
    ConfigFolder = "OrionTest"
})

local Tab1 = Window:MakeTab({Name = "Main", Icon = "", PremiumOnly = false})
local Tab3 = Window:MakeTab({Name = "ESP", Icon = "", PremiumOnly = false})
local Tab2 = Window:MakeTab({Name = "Character", Icon = "", PremiumOnly = false})
local Expander = false

local HB_Settings = {
    Color = Color3.new(1, 0, 0), -- Default to red if not set
    Transparency = 0.5,
    Size = 2
}

local Player = game.Players.LocalPlayer

-- Function to add hitbox changes
function addHitBoxChanges()
    while Expander do
        wait(0.1)
        for i, plr in pairs(game.Players:GetPlayers()) do
            if plr ~= Player and plr.Team ~= Player.Team then
                local character = plr.Character
                if character then
                    local hrp = character:FindFirstChild("HumanoidRootPart")
                    if hrp then
                        hrp.Size = Vector3.new(HB_Settings.Size, HB_Settings.Size, HB_Settings.Size)
                        hrp.CanCollide = false
                        hrp.Transparency = HB_Settings.Transparency
                        hrp.Color = HB_Settings.Color
                    end
                end
            end
        end
    end

    -- Revert changes when Expander is false
    for i, plr in pairs(game.Players:GetPlayers()) do
        if plr ~= Player and plr.Team ~= Player.Team then
            local character = plr.Character
            if character then
                local hrp = character:FindFirstChild("HumanoidRootPart")
                if hrp then
                    hrp.Size = Vector3.new(2, 2, 2)
                    hrp.CanCollide = false
                    hrp.Transparency = 1
                    hrp.Color = Color3.new(1, 1, 1)
                end
            end
        end
    end
end

-- GUI Elements
Tab1:AddToggle({
    Name = "HitBox Expander",
    Default = false,
    Callback = function(v)
        Expander = v
        if Expander then
            addHitBoxChanges()
        end
    end
})

Tab1:AddToggle({
    Name = "AimBot",
    Default = false,
    Callback = function(v)
        Expander = v
        if Expander then
            HB_Settings.Size = 9999999
            HB_Settings.Transparency = 1
            addHitBoxChanges()
        end
    end
})

Tab1:AddSection({
    Name = "HitBox Configuration"
})

Tab1:AddColorpicker({
	Name = "HitBox Color",
	Default = Color3.fromRGB(255, 0, 0),
	Callback = function(Value)
		HB_Settings.Color = Value
        print(Value)
	end	  
})

Tab1:AddSlider({
    Name = "HitBox Size",
    Min = 2,
    Max = 50,
    Default = 2,
    Color = Color3.fromRGB(255, 0, 0),
    Increment = 1,
    ValueName = "Size",
    Callback = function(Value)
        HB_Settings.Size = Value
    end
})

Tab1:AddSlider({
    Name = "HitBox Transparency",
    Min = 0,
    Max = 1,
    Default = .5,
    Color = Color3.fromRGB(255, 0, 0),
    Increment = .1,
    ValueName = "Transparency",
    Callback = function(Value)
        HB_Settings.Transparency = Value
    end
})

Tab2:AddSlider({
    Name = "WalkSpeed",
    Min = 0,
    Max = 50,
    Default = 16,
    Color = Color3.fromRGB(255, 0, 0),
    Increment = 1,
    ValueName = "WalkSpeed",
    Callback = function(Value)
        Player.Character.Humanoid.WalkSpeed = Value
    end
})

Tab3:AddButton({
    Name = "Skeleton ESP",
    Callback = function(v)
        loadstring(game:HttpGet("https://raw.githubusercontent.com/Blissful4992/ESPs/main/SkeletonESP.lua"))()
    end
})