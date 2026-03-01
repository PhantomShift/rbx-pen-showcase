
local CaptureService = game:GetService("CaptureService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")
local UserInputService = game:GetService("UserInputService")
local StarterGui = game:GetService("StarterGui")

local Promise = require(ReplicatedStorage.Packages.Promise)

local Compositor = require(ReplicatedStorage.Shared.Compositor)

local Gallery = {}

local ScreenGui = Instance.new("ScreenGui")
ScreenGui.Name = "_GALLERY_MANAGER_SCREENGUI"
ScreenGui.Parent = game:GetService("Players").LocalPlayer.PlayerGui
ScreenGui.IgnoreGuiInset = true
ScreenGui.DisplayOrder = 9999
ScreenGui.Enabled = false

local CaptureFrame = Instance.new("ImageLabel")
CaptureFrame.Parent = ScreenGui
CaptureFrame.Position = UDim2.fromScale(0.5, 0.5)
CaptureFrame.AnchorPoint = Vector2.new(0.5, 0.5)
CaptureFrame.BackgroundColor3 = Color3.new(1, 1, 1)
CaptureFrame.ZIndex = 9999

local CaptureBackground = Instance.new("Frame")
CaptureBackground.Parent = ScreenGui
CaptureBackground.BackgroundColor3 = Color3.new(0.5, 0.5, 0.5)
CaptureBackground.Size = UDim2.fromScale(1, 1)
CaptureBackground.ZIndex = CaptureFrame.ZIndex - 1

local AspectRatio = Instance.new("UIAspectRatioConstraint")
AspectRatio.AspectType = Enum.AspectType.ScaleWithParentSize
AspectRatio.Parent = CaptureFrame

-- local function GalleryEnabled()
--     return CaptureService:PromptCaptureGalleryPermissionAsync(Enum.CaptureGalleryPermission.ReadAndUpload)
-- end

function Gallery.Save(base: EditableImage, layers: {buffer}, resolution: Vector2) : Promise.TypedPromise<string?>
    local success: boolean
    local temp: buffer
    success, temp = pcall(base.ReadPixelsBuffer, base, Vector2.zero, resolution)

    if not success then
        return Promise.reject("Failed to read image data")
    end

    -- Note - This doesn't seem to actually work.
    -- CoreGui seem to always be present in screenshots if UICaptureMode is set to All. 
    local uiOverride = RunService.RenderStepped:Connect(function()
        StarterGui:SetCoreGuiEnabled(Enum.CoreGuiType.All, false)
        UserInputService.MouseIconEnabled = false
    end)

    local function cleanup()
        if uiOverride ~= nil then
            uiOverride:Disconnect()
            uiOverride = nil
        end
        ScreenGui.Enabled = false
        CaptureFrame.Image = ""
        StarterGui:SetCoreGuiEnabled(Enum.CoreGuiType.All, true)
        UserInputService.MouseIconEnabled = true
        base:WritePixelsBuffer(Vector2.zero, resolution, temp)
    end

    return Promise.new(function(resolve, reject, onCancel)
        if not Compositor.cascadeOverFastDirect(base, temp, layers, resolution) then
            reject("Failed to allocate scratch buffer for compositing (out of memory)")
        end
        
        ScreenGui.Enabled = true
        CaptureFrame.ImageContent = Content.fromObject(base)
        CaptureFrame.Size = UDim2.fromOffset(resolution.X, resolution.Y)
        AspectRatio.AspectRatio = resolution.X / resolution.Y
        
        local screenshotSuccess: Enum.ScreenshotCaptureResult
        local capture: Capture
        success, screenshotSuccess, capture = Promise.new(function(res)
            CaptureService:TakeScreenshotCaptureAsync(res, { UICaptureMode = Enum.UICaptureMode.All })
        end):await()
        
        task.wait()
        
        if not success or screenshotSuccess ~= Enum.ScreenshotCaptureResult.Success then
            reject("Failed to take screenshot")
        end

        cleanup()

        local saveResult: { [string]: boolean }
        success, saveResult = Promise.new(function(res)
            CaptureService:PromptSaveCapturesToGallery({capture}, res)
        end):await()

        if not success then
            reject("Error occurred during save screenshot prompt")
        end

        if saveResult[capture] then
            resolve(capture)
        else
            resolve(nil)
        end
    end):finally(cleanup)
end

return Gallery