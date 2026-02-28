--!native
--!optimize 2

local utils = {}

local function position(width: number, pos: Vector2) : number
	return ((pos.Y * width) + pos.X) * 4
end

utils.position = position

function utils.ReadRectangle(src: buffer, src_res: Vector2, top_left: Vector2, bot_right: Vector2) : buffer?
	local size = buffer.len(src)
	local rect_size = bot_right - top_left
	
end

function utils.WriteRectangle(dest: buffer, dest_res: Vector2, source: buffer, top_left: Vector2, bot_right: Vector2)
	local dest_width = dest_res.X
	local buf_width = (bot_right.X - top_left.Y) * 4
	local rows = bot_right.Y - top_left.X
	local src_offset
	for y_s = 0, rows - 1 do
		src_offset = y_s * buf_width
		buffer.copy(source, position(dest_width, top_left + Vector2.new(y_s)), source, src_offset, buf_width)
	end
end

return utils