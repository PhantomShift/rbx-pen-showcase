
local editor = {}
editor.__index = editor

type CurveEditorData = {
	Parent: GuiObject,
	Points: {Path2DControlPoint},
	Handles: { [Path2DControlPoint]: Frame },
	Left: Path2DControlPoint,
	Right: Path2DControlPoint,
	Path: Path2D,
	
	Lock: Path2DControlPoint?,
	_conn: {RBXScriptConnection}
}

type CurveEditor = setmetatable<CurveEditorData, typeof(editor)>
type Path2DProperty = keyof<Path2D>

editor.MIN_SELECT_DISTANCE = 32

local HandleTemplate = Instance.new("Frame")
HandleTemplate.Size = UDim2.fromOffset(8, 8)
HandleTemplate.BackgroundTransparency = 1
HandleTemplate.AnchorPoint = Vector2.new(0.5, 0.5)
local HandleCorner = Instance.new("UICorner")
HandleCorner.CornerRadius = UDim.new(1)
HandleCorner.Parent = HandleTemplate
local HandleStroke = Instance.new("UIStroke")
HandleStroke.Thickness = 4
HandleStroke.Color = Color3.new(0.67, 0.67, 0.67)
HandleStroke.Parent = HandleTemplate

-- local Inactive = Color3.new(0.67, 0.67, 0.67)
-- local Active = Color3.new(0.9, 0.9, 0.9)

function editor.new(parent: GuiObject, path_properties: {[Path2DProperty]: any}? ) : CurveEditor
	assert(parent:IsA("GuiObject"), "editor must be parented to a GuiObject")
	local left = Path2DControlPoint.new(UDim2.fromScale(0, 1))
	local right = Path2DControlPoint.new(UDim2.fromScale(1, 0))
	local path = Instance.new("Path2D")
	if path_properties ~= nil then
		for name, property in path_properties do
			path[name] = property
		end
	end
	path.Parent = parent
	local self = {
		Parent = parent,
		Points = {left, right},
		Handles = {},
		Left = left,
		Right = right,
		Path = path,
		
		_conn = {},
	}
	
	setmetatable(self, editor)
	
	self:_init()
	
	return self
end

function editor._pushConn(self: CurveEditor, connection: RBXScriptConnection)
	table.insert(self._conn, connection)
end

function editor._init(self: CurveEditor)
	self:_addHandle(self.Left)
	self:_addHandle(self.Right)
	self.Path:SetControlPoints(self.Points)
	
	local parent: GuiObject = self.Parent
	self:_pushConn(
		parent.InputBegan:Connect(function(io: InputObject)
			if self.Lock then
				return
			end
			
			if io.UserInputType ~= Enum.UserInputType.MouseButton1 then
				return
			end
			
			local pos = self:_mouseRelUnit(Vector2.new(io.Position.X, io.Position.Y))
			local point = self:GetNearestPoint(pos)
			if point == nil then
				point = Path2DControlPoint.new(UDim2.fromScale(pos.X, pos.Y))
				local insert = 2
				while insert <= #self.Points - 1 and self.Points[insert] and self.Points[insert].Position.X.Scale < pos.X do
					insert += 1
				end
				table.insert(self.Points, insert, point)
				self.Path:SetControlPoints(self.Points)
				self:_addHandle(point)
			end
			self.Lock = point
		end)
	)
	
	self:_pushConn(
		parent.InputChanged:Connect(function(io: InputObject)
			if io.UserInputType ~= Enum.UserInputType.MouseMovement then
				return
			end
			if self.Lock == nil then
				return
			end
			
			local pos = self:_mouseRelUnit(Vector2.new(io.Position.X, io.Position.Y))
			local i = table.find(self.Points, self.Lock)
			assert(i, "lock should be a valid control point")
			local clamp_x do
				if self.Lock == self.Left then
					clamp_x = 0
				elseif self.Lock == self.Right then
					clamp_x = 1
				else
					clamp_x = math.clamp(pos.X, self.Points[i-1].Position.X.Scale, self.Points[i+1].Position.X.Scale)
				end
			end
			
			
			self.Lock.Position = UDim2.fromScale(clamp_x, pos.Y)
			self.Path:UpdateControlPoint(table.find(self.Points, self.Lock), self.Lock)
			self.Handles[self.Lock].Position = self.Lock.Position
		end)
	)
	
	self:_pushConn(
		parent.InputEnded:Connect(function(io: InputObject)
			if io.UserInputType == Enum.UserInputType.MouseButton1 then
				if self.Lock then
					self.Lock = nil
				end
				return
			end
			if io.UserInputType == Enum.UserInputType.MouseButton2 then
				if self.Lock then
					return
				end
				
				local pos = self:_mouseRelUnit(Vector2.new(io.Position.X, io.Position.Y))
				local point = self:GetNearestPoint(pos)
				if point == nil or point == self.Left or point == self.Right then
					return
				end
				
				local i = table.find(self.Points, point)
				table.remove(self.Points, i)
				self.Handles[point]:Destroy()
				self.Path:SetControlPoints(self.Points)
			end
		end)
	)
end

function editor._mouseRelUnit(self: CurveEditor, raw: Vector2) : Vector2
	return (raw - self.Parent.AbsolutePosition) / self.Parent.AbsoluteSize
end

function editor._addHandle(self: CurveEditor, point: Path2DControlPoint)
	if self.Handles[point] ~= nil then
		return
	end
	
	local handle = HandleTemplate:Clone()
	handle.Position = point.Position
	self.Handles[point] = handle
	handle.Parent = self.Parent
end

function editor.GetNearestPoint(self: CurveEditor, pos: Vector2) : Path2DControlPoint?
	local size = self.Parent.AbsoluteSize.Magnitude
	local nearest: Path2DControlPoint?
	local nd = math.huge
	local d
	for _, point in self.Points do
		d = (pos - Vector2.new(point.Position.X.Scale, point.Position.Y.Scale)).Magnitude * size
		if d < nd then
			nearest = point
			nd = d
		end
	end
	
	if nearest and nd < self.MIN_SELECT_DISTANCE then
		return nearest
	end
	
	return nil
end

local clamp = math.clamp
function editor.GetCurveY(self: CurveEditor, x: number) : number
	return clamp(1 - self.Path:GetPositionOnCurve(x).Y.Scale, 0, 1)
end

function editor.Reset(self: CurveEditor)
	self.Lock = nil
	for _, point in self.Points do
		self.Handles[point]:Destroy()
		self.Handles[point] = nil
	end
	table.clear(self.Points)
	self.Left = Path2DControlPoint.new(UDim2.fromScale(0, 1))
	self.Right = Path2DControlPoint.new(UDim2.fromScale(1, 0))
	self.Points = {self.Left, self.Right}
	self.Path:SetControlPoints(self.Points)
	self:_addHandle(self.Left)
	self:_addHandle(self.Right)
end

return editor
