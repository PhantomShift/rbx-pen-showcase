local CollectionService = game:GetService("CollectionService")
local ContextActionService = game:GetService("ContextActionService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local UserInputService = game:GetService("UserInputService")
local GuiService = game:GetService("GuiService")
local RunService = game:GetService("RunService")
local Players = game:GetService("Players")

local PlayerGui = Players.LocalPlayer.PlayerGui

local OSGL = require(ReplicatedStorage.Packages.OSGL)
local ColorPicker = require(ReplicatedStorage.External.ColorPicker)

local CurveEditor = require(ReplicatedStorage.Shared.CurveEditor)

local History = require(script.History)

local HEIGHT = 1024
local WIDTH = 1024
local RESOLUTION = Vector2.new(WIDTH, HEIGHT)
local CANVAS_BASE = Vector2.new(512, 512)

local MainWindow = script.Parent.MainWindow
local DrawWindow = MainWindow.DrawWindow
local SettingsWindow = MainWindow.SettingsWindow
local TopBar = MainWindow.TopBar
local BottomBar = MainWindow.BottomBar

local Canvas = DrawWindow.Canvas
local Preview = MainWindow.Preview
local RightDock = MainWindow.RightDock

local Prompt = MainWindow.Prompt

Prompt.Close.Activated:Connect(function()
	Prompt.Visible = false
end)
local function ShowPrompt(text: string)
	Prompt.TextBox.Text =text
	Prompt.Visible = true
end
Prompt.Visible = false

-- At 1024x1024, each indvidual EditableImage takes up a little over 4MB.
-- Given the limit of 32MB total on the client for EditableImages,
-- this means only 7 maximum resolution EditableImages can be used.
-- TODO: Use raw buffers as layers and implement layer compositing,
-- which should be able to achieve all necessary layering operations with only 3 actual EditableImages
-- (one for active drawing layer and two for each combined layer above and below it)
local MAX_LAYERS = if RunService:IsStudio() then 1000 else 4

local CanvasLayers = Canvas.Layers
local LayerList = RightDock.LayerSelect.LayerList
local LayerSelectTemplate = LayerList.LayerSelectTemplate
local NewLayer = RightDock.LayerSelect.NewLayer
local CanvasMem = BottomBar.CanvasMem

LayerSelectTemplate.Parent = nil

local layers = {} :: {{
	label: ImageLabel,
	image: OSGL.Window,
	selector: TextButton,
}}
local curr_layer = 0

local function UpdateLayerStatuses()
	local mem = 0
	for i, layer in layers do
		layer.label.ZIndex = i
		layer.selector.LayoutOrder = -i
		if i == curr_layer then
			CollectionService:AddTag(layer.selector.Button, "Primary")
		else
			CollectionService:RemoveTag(layer.selector.Button, "Primary")
		end
		mem += WIDTH * HEIGHT * 4 * 2
	end
	CanvasMem.Text = string.format("Canvas Memory: %0.3fMB", mem / (1024 * 1024))
end

local function CreateLayer()
	local index = #layers + 1
	if index > MAX_LAYERS then
		ShowPrompt(`This client currently only allows for {MAX_LAYERS} layers.`)
		return 0
	end
	local label = Instance.new("ImageLabel")
	label.Size = UDim2.fromScale(1, 1)
	label.BackgroundColor3 = Color3.new(1, 1, 1)
	label.BackgroundTransparency = 1
	label.Name = `Layer{index}`
	local selector = LayerSelectTemplate:Clone()
	selector.LayoutOrder = -index
	selector.Button.Text = label.Name
	local result = OSGL.Window.from(label, WIDTH, HEIGHT)
	if result.isOk then
		local image = result:Unwrap()
		image:AddRenderers(selector.Preview)
		label.Parent = CanvasLayers
		selector.Parent = LayerList
		local this = {
			label = label,
			image = image,
			selector = selector
		}
		table.insert(layers, this)
		selector.Button.Activated:Connect(function()
			if UserInputService:GetLastInputType().Name:match("Gamepad") then
				return
			end
			curr_layer = table.find(layers, this)
			UpdateLayerStatuses()
		end)
		selector.MoveUp.Activated:Connect(function()
			local i = table.find(layers, this)
			if i < #layers then
				History.pushUndoClear(History.LayerSwap(i, i + 1))
				local other = layers[i+1]
				layers[i+1] = this
				layers[i] = other
				if i == curr_layer then
					curr_layer += 1
				elseif i + 1 == curr_layer then
					curr_layer = i
				end
				UpdateLayerStatuses()
			end
		end)
		selector.MoveDown.Activated:Connect(function()
			local i = table.find(layers, this)
			if i > 1 then
				History.pushUndoClear(History.LayerSwap(i, i - 1))
				local other = layers[i-1]
				layers[i-1] = this
				layers[i] = other
				if i == curr_layer then
					curr_layer -= 1
				elseif i - 1 == curr_layer then
					curr_layer = i
				end
				UpdateLayerStatuses()
			end
		end)
		curr_layer = index
		UpdateLayerStatuses()
		return index
	else
		warn(`Failed to create layer: {result:UnwrapErr()}`)
		label:Destroy()
		return 0
	end
end

local function DeleteLayer(index: number)
	local layer = table.remove(layers, index)
	if layer == nil then
		return
	end
	
	local buf = layer.image.buffer
	layer.label:Destroy()
	layer.selector:Destroy()
	
	UpdateLayerStatuses()
	
	return buf
end

NewLayer.Activated:Connect(function()
	local index = CreateLayer()
	if index > 0 then
		History.pushUndo({
			__type = "LayerModify",
			layer = index,
			last_layer = index - 1,
			modification = "Exists",
			status = true,
			
			size = 0,
		})
	end
end)

CreateLayer()

local isDrawing = false
local erasing = false
local stroke_width = 8
local stroke_color = OSGL.color.new(0, 0, 0, 255)
local eraser_color = OSGL.color.new(0, 0, 0, 0)
local pressure = 0
local usePressure = true
--local usePressure = false
local last_input: Vector3 = nil
local zoom_percent = 1

local ZoomEntry = BottomBar.ZoomSelector.Entry

local function updateZoom()
	local new = CANVAS_BASE * zoom_percent
	Canvas.Size = UDim2.fromOffset(new.X, new.Y)
	ZoomEntry.Text = `{math.round(zoom_percent * 10000) / 100}%`
end

local PixelBrush = require(script.PixelBrush)

local Picker = ColorPicker.new({
	--Parent = script.Parent,
	--Position = UDim2.new(1, -300, 0, 0), 
	ZIndex = 99,
	Position = UDim2.new(), 
	RealTimeEventCalling = true,
	Scale = 0.5,
})
Picker.ColorChanged:Connect(function(newcolor, transparency)
	stroke_color = OSGL.color.new(
		math.round(newcolor.R * 255),
		math.round(newcolor.G * 255),
		math.round(newcolor.B * 255),
		math.round((1 - transparency) * 255)
	)
end)
Picker:SetColor(Color3.new(0, 0, 0))
task.defer(function()
	local p = Picker.Instance
	p.Parent = RightDock.ColorPickContainer
	p.Size = UDim2.fromScale(1, 1)
	p.AutomaticSize = Enum.AutomaticSize.Y
	
	p.Options.Close.Visible = false
	p.Topbar.Button.Active = false
	p.Topbar.Button.Interactable = false
	--Picker._windowAdjust:Destroy()
end)

ContextActionService:BindActionAtPriority("NoRMBDrag", function()
	return Enum.ContextActionResult.Sink
end, false, Enum.ContextActionPriority.High.Value, Enum.UserInputType.MouseButton2)


-- Stroke width stuff
local Slider = TopBar.StrokeWidthSlider
local Sink = Slider.Sink
local Bar = Sink.Bar
local Handle = Bar.Handle

local MIN_WIDTH = 1
local MAX_WIDTH = 32

local function UpdateWidth(width: number)
	local rounded = math.round(width * 1000) / 1000 
	stroke_width = rounded
	Handle.Position = UDim2.fromScale((rounded - 1) / (MAX_WIDTH - 1) , 0.5)
	Handle.Size = UDim2.fromOffset(rounded, rounded)
	Preview.Size = Handle.Size
	Slider.NumberLabel.Text = `{rounded}px`
end
UpdateWidth(stroke_width)

local function OnSliderInput(input)
	if isDrawing then return end
	if #UserInputService:GetMouseButtonsPressed() == 0 then return end
	if input.UserInputType == Enum.UserInputType.MouseMovement or input.UserInputType == Enum.UserInputType.MouseButton1 then
		local posx = input.Position.X
		if math.clamp(posx, Bar.AbsolutePosition.X, Bar.AbsolutePosition.X + Bar.AbsoluteSize.X) ~= posx then
			return
		end

		local ratio = (posx - Bar.AbsolutePosition.X) / Bar.AbsoluteSize.X
		UpdateWidth(math.round(math.lerp(MIN_WIDTH, MAX_WIDTH, ratio)))
	end
end

Sink.InputChanged:Connect(OnSliderInput)
Sink.InputBegan:Connect(OnSliderInput)

local Clear = RightDock.Clear

Clear.Activated:Connect(function()
	History.pushUndoClear(History.LayerClear(curr_layer, layers[curr_layer].image.buffer))
	
	layers[curr_layer].image:Clear()
	layers[curr_layer].image:Render()
end)



-- Undo/Redo Handlers

local function undoStroke(stroke: History.Stroke)
	local layer = layers[stroke.layer]
	buffer.copy(layer.image.buffer, stroke.undo_offset, stroke.undo_data)
end
local function redoCircleStroke(stroke: History.Stroke)
	local inputs = stroke.redo_data:Len()
	if inputs == 0 then
		return
	end
	
	local image = layers[stroke.layer].image

	local last_input = stroke.redo_data:Get(0)
	image:Circle(last_input.X, last_input.Y, math.round(last_input.Z * stroke.width), stroke.color)

	for i = 1, inputs - 1 do
		local input = stroke.redo_data:Get(i)
		image:Circle(input.X, input.Y, math.round(input.Z * stroke.width), stroke.color)

		local distance = ((input - last_input) * Vector3.new(1, 1)).Magnitude
		local interp_steps = math.round(distance / 2)
		for step = 1, interp_steps do
			local interp = last_input:Lerp(input, step / interp_steps)
			image:Circle(math.round(interp.X), math.round(interp.Y), math.round(stroke.width * interp.Z), stroke.color)
		end

		last_input = input
	end
end

local function undoLayerModify(modify: History.LayerModify) : number
	if modify.modification == "Exists" then
		if modify.status then
			-- Delete layer
			DeleteLayer(modify.layer)
			curr_layer = modify.layer - 1
			UpdateLayerStatuses()
			return 0
		else
			-- Regenerate layer
			local i = CreateLayer()
			local layer = layers[i]
			layer.label.Name = modify.saved_name
			layer.selector.Text = modify.saved_name
			table.remove(layers, i)
			table.insert(modify.layer)
			buffer.copy(layer.image.buffer, 0, modify.saved)
			UpdateLayerStatuses()
			return modify.layer
		end
	elseif modify.modification == "Visible" then
		warn("Unimplemented undo/redo: LayerModify:Visible")
		return 0
	end
	
	return 0
end
local function redoLayerModify(modify: History.LayerModify)
	if modify.modification == "Exists" then
		if modify.status then
			-- Create fresh layer
			-- Note: currently under the assumption that new layers are always put at the top
			-- and is immediately selected
			CreateLayer()
		else
			-- Delete layer
			DeleteLayer(modify.layer)
			curr_layer = modify.last_layer
		end
	elseif modify.modification == "Visible" then
		warn("Unimplemented undo/redo: LayerModify:Visible")
	end
	UpdateLayerStatuses()
end

local function undoRedoSwap(swap: History.LayerSwap)
	local temp = layers[swap.a]
	layers[swap.a] = layers[swap.b]
	layers[swap.b] = temp
	if curr_layer == swap.a then
		curr_layer = swap.b
	elseif curr_layer == swap.b then
		curr_layer = swap.a
	end
	UpdateLayerStatuses()
end

local function undoLayerClear(clear: History.LayerClear)
	layers[clear.layer].image:Buffer(clear.saved, WIDTH, HEIGHT, 0, 0)
	layers[clear.layer].image:Render()
end
local function redoLayerClear(clear: History.LayerClear)
	layers[clear.layer].image:Clear()
	layers[clear.layer].image:Render()	
end

local function onUndoRequest()
	if History.inStroke() then
		return
	end
	
	local command = History.popUndo()
	if command == nil then
		return
	end
	
	if command.__type:match("Stroke") then
		undoStroke(command)
		History.pushRedo(command)
		layers[command.layer].image:Render()
	elseif command.__type == "LayerSwap" then
		undoRedoSwap(command)
		History.pushRedo(command)
	elseif command.__type == "LayerModify" then
		local index = undoLayerModify(command)
		if index > 0 then
			layers[index].image:Render()
		end
		History.pushRedo(command)
	elseif command.__type == "LayerClear" then
		undoLayerClear(command)
		History.pushRedo(command)
	else
		warn(`Unhandled undo command of type {command.__type}`)
		History.pushUndo(command)
	end
	History.Dump()
end

local function onRedoRequest()
	if History.inStroke() then
		return
	end

	local command = History.popRedo()
	if command == nil then
		return
	end
	
	if command.__type == "CircleStroke" then
		redoCircleStroke(command)
		History.pushUndo(command)
		layers[command.layer].image:Render()
	elseif command.__type == "LayerSwap" then
		undoRedoSwap(command)
		History.pushUndo(command)
	elseif command.__type == "LayerModify" then
		redoLayerModify(command)
		History.pushUndo(command)
	elseif command.__type == "LayerClear" then
		redoLayerClear(command)
		History.pushUndo(command)
	else
		warn(`Unhandled undo command of type {command.__type}`)
		History.pushRedo(command)
	end
	History.Dump()
end

UserInputService.InputBegan:Connect(function(io)
	if not UserInputService:IsKeyDown(Enum.KeyCode.LeftControl) then
		return
	end
	print(io.KeyCode)
	
	if io.KeyCode == Enum.KeyCode.Z and UserInputService:IsKeyDown("LeftShift") or io.KeyCode == Enum.KeyCode.Y then
		onRedoRequest()
	elseif io.KeyCode == Enum.KeyCode.Z then
		onUndoRequest()
	end
end)

local UndoButton = TopBar.Undo
local RedoButton = TopBar.Redo
UndoButton.Activated:Connect(onUndoRequest)
RedoButton.Activated:Connect(onRedoRequest)

local DrawButton = TopBar.Draw
local EraseButton = TopBar.Erase

local function ToggleErasing(toggle: boolean?)
	if toggle == nil then
		toggle = not erasing
	end
	if toggle then
		erasing = true
		CollectionService:AddTag(EraseButton, "Secondary")
		CollectionService:RemoveTag(DrawButton, "Secondary")
	else
		erasing = false
		CollectionService:AddTag(DrawButton, "Secondary")
		CollectionService:RemoveTag(EraseButton, "Secondary")
	end
end

DrawButton.Activated:Connect(function()
	ToggleErasing(false)
end)
EraseButton.Activated:Connect(function()
	ToggleErasing(true)
end)

local MIN_ZOOM = 0.02
local MAX_ZOOM = 16
local ZOOM_SNAPS = { 0.02, 0.05, 0.125, 0.167, 0.25, 0.33, 0.5, 0.67, 1, 1.33, 2, 2.67, 4, 8 }
-- Binary search is probably overkill so
local function getSnapNearest(zoom: number, greater: boolean?) : number
	local closest = 0
	local cdt = math.huge
	local dt
	for i, snap in ZOOM_SNAPS do
		if greater then
			if snap > zoom then
				return i
			end
		elseif snap < zoom then
			dt = math.abs(zoom - snap)
			if dt < cdt then
				closest = i
				cdt = dt
			else
				return closest
			end
		end
	end
	return closest
end

local zoom_snap = 9
local function updateZoomSnapped(snap: number)
	zoom_snap = snap
	zoom_percent = ZOOM_SNAPS[zoom_snap]
	updateZoom()
end

local function snapIncrement(n: number)
	if table.find(ZOOM_SNAPS, zoom_percent) then
		updateZoomSnapped(math.clamp(zoom_snap + n, 1, #ZOOM_SNAPS))
	else
		local i = getSnapNearest(zoom_percent, n == 1)
		if i > 0 then
			updateZoomSnapped(i)
		end
	end
end

local function onDrawWindowScroll(io: InputObject)
	if io.UserInputType == Enum.UserInputType.MouseWheel then
		print(io.Position)
		local sign = math.sign(io.Position.Z)
		for i = sign, io.Position.Z, sign do
			snapIncrement(sign)
		end
	end
end

ZoomEntry.FocusLost:Connect(function(submitted)
	if submitted then
		local s = ZoomEntry.Text:match("^%d*%.?%d+") or ""
		local v = tonumber(s)
		if v ~= nil then
			zoom_percent = math.clamp(math.round(v * 1000) / 1000, MIN_ZOOM, MAX_ZOOM)
		end
	end
	updateZoom()
end)

local ZoomMinus = BottomBar.ZoomSelector.Minus
local ZoomPlus = BottomBar.ZoomSelector.Plus

ZoomMinus.Activated:Connect(function()
	snapIncrement(-1)	
end)
ZoomPlus.Activated:Connect(function()
	snapIncrement(1)
end)

local HistoryMemLabel = BottomBar.HistorySize
History.memoryChanged:Connect(function()
	HistoryMemLabel.Text = string.format("Raw History Size: %.3fMB", History.getMemMB())
end)

BottomBar.Settings.Activated:Connect(function()
	SettingsWindow.Visible = not SettingsWindow.Visible
end)
SettingsWindow.TitleBar.Close.Activated:Connect(function()
	SettingsWindow.Visible = false
end)


local SettingsListButtons = SettingsWindow.Content.SettingsList
local SettingsPages = SettingsWindow.Content.Pages

local PenSettings = SettingsPages.PenSettings
local PressureCurveEditor = CurveEditor.new(PenSettings.PressureCurve, {Color3 = Color3.new(1, 1, 1)})
PenSettings.PressureCurveReset.Activated:Connect(function()
	PressureCurveEditor:Reset()
end)

DrawWindow.InputBegan:Connect(onDrawWindowScroll)
DrawWindow.InputChanged:Connect(onDrawWindowScroll)

UserInputService.InputChanged:Connect(function(io, _gp)
	if io.KeyCode == Enum.KeyCode.ButtonR2 then
		pressure = PressureCurveEditor:GetCurveY(io.Position.Z)
	end
end)

Canvas.InputBegan:Connect(function(input)
	if input.UserInputType == Enum.UserInputType.MouseButton1 then
		isDrawing = true
	end
end)

Canvas.InputEnded:Connect(function(input)
	if input.UserInputType == Enum.UserInputType.MouseButton1 then
		isDrawing = false
	end
end)

-- Actions that sink mouse input when pressed down
local KeyModifierTools = {
	{
		KeyCode = Enum.KeyCode.LeftControl,
		Nested = {
			{
				KeyCode = Enum.KeyCode.Space,
				Tool = function(input: Vector3)
					local delta = input - last_input
					zoom_percent = math.clamp(zoom_percent + delta.X * 0.0015 * zoom_percent, MIN_ZOOM, MAX_ZOOM)
					updateZoom()
				end,
			}
		},
	},
	{
		KeyCode = Enum.KeyCode.Space,
		Tool = function(input: Vector3)
			local delta = input - last_input
			Canvas.Position += UDim2.fromOffset(delta.X, delta.Y)
		end,
	},
	{
		KeyCode = Enum.KeyCode.LeftShift,
		Tool = function(input: Vector3)
			local delta = input - last_input
			UpdateWidth(math.clamp(stroke_width + delta.X * 0.05, MIN_WIDTH, MAX_WIDTH))
		end,
	},
}

local function GetModifierTool(nest) : ((Vector3) -> ())?
	local search = if nest ~= nil then nest else KeyModifierTools
	for _, val in search do
		if UserInputService:IsKeyDown(val.KeyCode) then
			if val.Tool then
				return val.Tool
			elseif val.Nested then
				local tool = GetModifierTool(val.Nested)
				if tool ~= nil then
					return tool
				end
			end
		end
	end
	
	return nil
end

-- Temporary, replace with a proper shortcuts manager
local SimpleShortcuts = {
	[Enum.KeyCode.E] = ToggleErasing
}

UserInputService.InputEnded:Connect(function(io, gp)
	if gp or History.inStroke() then
		return
	end

	if SimpleShortcuts[io.KeyCode] then
		SimpleShortcuts[io.KeyCode]()
	end
end)

RunService.RenderStepped:Connect(function()
	if UserInputService:GetLastInputType().Name:match("Gamepad") then
		return
	end

	local image = layers[curr_layer].image
	local label = layers[curr_layer].label

	local p = if usePressure and pressure > 0 then pressure else 1
	local rawPos = UserInputService:GetMouseLocation() - MainWindow.AbsolutePosition - GuiService:GetGuiInset()
	local isHover, posX, posY = image:GetRelativeMousePosition(label)
	local input = Vector3.new(posX, posY, p)
	UserInputService.MouseIconEnabled = not isHover
	Preview.Visible = DrawWindow.GuiState == Enum.GuiState.Hover or isHover
	Preview.Position = UDim2.fromOffset(rawPos.X, rawPos.Y)
	Preview.Size = if isDrawing
		then UDim2.fromOffset(p * stroke_width * zoom_percent, p * stroke_width * zoom_percent)
		else UDim2.fromOffset(stroke_width * zoom_percent, stroke_width * zoom_percent)
	
	if not History.inStroke() and isDrawing and table.find(PlayerGui:GetGuiObjectsAtPosition(rawPos.X, rawPos.Y), DrawWindow) then
		local tool = GetModifierTool()
		if tool then
			local raw_input = Vector3.new(rawPos.X, rawPos.Y, p)
			if last_input ~= nil then
				tool(raw_input)
			end
			last_input = raw_input
			return
		end
	end

	if not isDrawing
		or not isHover
		or (usePressure and p == 0)
	then
		if History.inStroke() then
			History.pushUndoClear(History.finishCircleStroke())
			History.Dump(false)
		end

		last_input = nil
		return
	end

	if input == last_input then
		return
	end
	
	local color = if erasing then eraser_color else stroke_color

	if History.inStroke() then
		History.extendCircleStroke(input)
	else		
		History.startCircleStroke(curr_layer, image.buffer, RESOLUTION, input, color, stroke_width)
	end

	image:Circle(input.X, input.Y, math.round(stroke_width * pressure), color)

	if last_input ~= nil then
		local distance = ((input - last_input) * Vector3.new(1, 1)).Magnitude
		local interp_steps = math.round(distance / 2)
		for step = 1, interp_steps do
			local interp = last_input:Lerp(input, step / interp_steps)
			image:Circle(math.round(interp.X), math.round(interp.Y), math.round(stroke_width * interp.Z), color)
			-- Whoops, this doesn't work as I'd hoped since OGSL doesn't do any alpha blending for us
			--PixelBrush.draw(image, interp.X, interp.Y, interp.Z, stroke_width, color)
		end
	end

	image:Render()

	last_input = input
end)
