local OrionLib = loadstring(game:HttpGet(
                                ('https://raw.githubusercontent.com/shlexware/Orion/main/source')))()

local Window = OrionLib:MakeWindow({
    Name = "HitBox Extender",
    HidePremium = false,
    SaveConfig = true,
    ConfigFolder = "OrionTest"
})

local Tab1 = Window:MakeTab({Name = "Main", Icon = "", PremiumOnly = false})

local Size = 2
local ESP = false

Tab1:AddSlider({
    Name = "HitBox",
    Min = 2,
    Max = 25,
    Default = 2,
    Color = Color3.fromRGB(255, 0, 0),
    Increment = 1,
    ValueName = "Size",
    Callback = function(Value)
        for i, v in pairs(workspace:GetChildren()) do
            if v:FindFirstChild("Humanoid") then
                Size = Value
                if v.Name == game.Players.LocalPlayer.Name then
                    print("")
                else
                    v.HumanoidRootPart.Transparency = 0.5
                    v.HumanoidRootPart.Color = Color3.fromRGB(255, 0, 0)
                    v.HumanoidRootPart.Size = Vector3.new(Value, Value, Value)
                end
            end
        end
    end
})


function hitboxfix(v)
    if v.Name == game.Players.LocalPlayer.Name then
        print("")
    else
        v.HumanoidRootPart.Transparency = 0.5
        v.HumanoidRootPart.Color = Color3.fromRGB(255, 0, 0)
        v.HumanoidRootPart.Size = Vector3.new(Size, Size, Size)
    end
end

game.Players.PlayerAdded:Connect(function(p)
    p.CharacterAdded:Connect(function(c)
        if Size >= 2 then hitboxfix(c) end
    end)
end)

workspace.ChildAdded:Connect(function()
    if Size >= 2 then
        for i, v in pairs(workspace:GetChildren()) do
            if v:FindFirstChild("Humanoid") then
                if v.Name == game.Players.LocalPlayer.Name then
                    print("")
                else
                    v.HumanoidRootPart.Transparency = 0.5
                    v.HumanoidRootPart.Color = Color3.fromRGB(255, 0, 0)
                    v.HumanoidRootPart.Size = Vector3.new(Size, Size, Size)
                end
            end
        end
    end
end)
