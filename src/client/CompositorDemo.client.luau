local AssetService = game:GetService("AssetService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Compositor = require(ReplicatedStorage.Shared.Compositor)

local label = script.Parent.ImageLabel
local expectedLabel = script.Parent.ExpectedLabel

local WIDTH = 1024
local HEIGHT = 1024
local SIZE = Vector2.new(WIDTH, HEIGHT)

local dest = buffer.create(WIDTH * HEIGHT * 4)

local green = buffer.create(WIDTH * HEIGHT * 4)
local fg = buffer.create(WIDTH * HEIGHT * 4)
local bg = buffer.create(WIDTH * HEIGHT * 4)

local offset
for x = 0, WIDTH - 1 do
	for y = 0, HEIGHT - 1 do
		offset = ((y * WIDTH) + x) * 4
		buffer.writeu8(fg, offset + 0, (x + y) / 4 / 2)
		buffer.writeu8(fg, offset + 3, 127)
		buffer.writeu8(bg, offset + 2, ((WIDTH - x) + y) / 4 / 2)
		buffer.writeu8(bg, offset + 3, 127)
		buffer.writeu8(green, offset + 1, 255)
		buffer.writeu8(green, offset + 3, 85)
	end
end

local layers = {bg, fg, green}

local expected = AssetService:CreateEditableImage { Size = Vector2.new(WIDTH, HEIGHT) }
local edit = AssetService:CreateEditableImage { Size = Vector2.new(WIDTH, HEIGHT) }


buffer.fill(dest, 0, 0xFF)
local start = os.clock()
Compositor.cascadeOverFastDirect(expected, dest, layers, SIZE)
local delta = os.clock() - start
print(`{delta * 1000}ms ({delta * 1000 / #layers} ms per layer)`)

buffer.fill(dest, 0, 0xFF)
start = os.clock()
Compositor.cascadeOver(dest, layers)
edit:WritePixelsBuffer(Vector2.zero, Vector2.new(WIDTH, HEIGHT), dest)
delta = os.clock() - start
print(`{delta * 1000}ms ({delta * 1000 / #layers} ms per layer)`)
label.ImageContent = Content.fromObject(edit)
expectedLabel.ImageContent = Content.fromObject(expected)

--local total = 0
--local TRIALS = 8
--for i = 1, TRIALS do
--	start = os.clock()
--	Compositor.cascadeOver(dest, layers)
--	total += (os.clock() - start)
--	buffer.fill(dest, 0, 0xFF)
--end
--local t_ms = total * 1000
--print(`{t_ms / TRIALS}ms per stack ({t_ms / TRIALS / #layers}ms per layer)`)
