local ReplicatedStorage = game:GetService("ReplicatedStorage")

local OSGL = require(ReplicatedStorage.Packages.OSGL)

local Brush = {}

local OPAQUE_PERCENT = 0.9

function Brush.draw(obj: OSGL.Window, posX: number, posY: number, pressure: number, width: number, color: OSGL.Color)
	local outside = math.round(pressure * width)
	local inside = math.round(pressure * width * OPAQUE_PERCENT)
	local a = OSGL.color.a(color)
	local steps = outside - inside
	for i = outside, inside, -1 do
		local strength = (outside - i) / steps
		obj:Circle(math.round(posX), math.round(posY), i, OSGL.color.setA(color, math.round(strength * a)))
	end
end

return Brush
