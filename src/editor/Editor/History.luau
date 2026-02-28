local ReplicatedStorage = game:GetService("ReplicatedStorage")

local PackedVector3Array = require(ReplicatedStorage.Shared.PackedVector3Array)

local MEGA = 1024 * 1024

export type Stroke = {
	__type: string,
	
	layer: number,
	resolution: Vector2,
	color: number,
	width: number,
	inputs: {Vector3}?,
	raw_init: buffer?,
	size: number,

	undo_offset: number,
	undo_len: number,
	undo_data: buffer,
	redo_data: PackedVector3Array.PackedVector3Array,
}

export type CircleStroke = {
	__type: "CircleStroke",
} & Stroke

export type LayerSwap = { __type: "LayerSwap", a: number, b: number }

export type FloodFill = {
	__type: "FloodFill",
	start: Vector2,
	color: number,
	global: boolean,
}

export type LayerModify = {
	__type: "LayerModify",
	layer: number,
	last_layer: number,
	modification: "Exists" | "Visible",
	status: boolean,
	
	size: number,
	saved: buffer?,
	saved_name: string?,
}

export type LayerClear = {
	__type: "LayerClear",
	layer: number,
	size: number,
	saved: buffer,
}

export type Command = LayerModify | LayerSwap | FloodFill | Stroke | LayerClear

local History = {}

History.undo_stack = {} :: {Command}
History.redo_stack = {} :: {Command}

History.MAX_ENTRIES = 128
History.MAX_MEMORY_MB = 512

History.undo_mem = 0
History.redo_mem = 0

local MemoryChanged = Instance.new("BindableEvent")
History.memoryChanged = MemoryChanged.Event

function History.getMemMB()
	return (History.undo_mem + History.redo_mem) / MEGA
end

function History.clearRedoStack()
	History.redo_mem = 0
	table.clear(History.redo_stack)
	MemoryChanged:Fire()
end

function History.pushUndo(command: Command)
	local adding = if command.size ~= nil then command.size else 0
	while (History.MAX_ENTRIES > 0 and #History.undo_stack >= History.MAX_ENTRIES) or (History.undo_mem + History.redo_mem + adding) / MEGA >= History.MAX_MEMORY_MB do
		History.freeUndo()
	end
	History.undo_mem += adding
	if adding > 0 then
		MemoryChanged:Fire()
	end
	table.insert(History.undo_stack, command)
end

function History.pushUndoClear(command: Command)
	History.pushUndo(command)
	History.clearRedoStack()
end

function History.popUndo() : Command?
	local command = table.remove(History.undo_stack, #History.undo_stack)
	if command == nil then
		return nil
	end
	
	return command
end

function History.pushRedo(command)
	table.insert(History.redo_stack, command)
end

function History.popRedo() : Command?
	local command = table.remove(History.redo_stack, #History.redo_stack)
	if command and command.size then
		History.redo_mem -= command.size
		if command.size > 0 then
			MemoryChanged:Fire()
		end
	end
	return command
end

function History.freeUndo()
	local command = table.remove(History.undo_stack, 1)
	if command.size then
		History.undo_mem -= command.size
		if command.size > 0 then
			MemoryChanged:Fire()
		end
	end
	command = nil
end

local currStroke: Stroke?
function inStroke()
	return currStroke ~= nil
end
History.inStroke = inStroke

--- Note that inputs are expected to be rounded already.
function History.startCircleStroke(layer: number, state: buffer, resolution: Vector2, input: Vector3, color: number, width: number)

	assert(not inStroke(), "Should not start new stroke if there is one ongoing")

	local len = buffer.len(state)
	local raw_init = buffer.create(len)
	buffer.copy(raw_init, 0, state)

	local stroke = {}
	stroke.__type = "CircleStroke"
	stroke.layer = layer
	stroke.resolution = resolution
	stroke.color = color
	stroke.width = width
	stroke.inputs = {input}
	stroke.raw_init = raw_init

	currStroke = stroke
end

function History.extendCircleStroke(input: Vector3)
	assert(currStroke, "Should not extend non-existent stroke")

	table.insert(currStroke.inputs, input)
end

function History.finishCircleStroke()
	assert(currStroke, "Should not finish non-existent stroke")
	local stroke = currStroke
	currStroke = nil

	local max = Vector2.new()
	local min = stroke.resolution

	local v2
	for _, input in stroke.inputs do
		v2 = Vector2.new(input.X, input.Y)
		max = Vector2.max(max,  v2)
		min = Vector2.min(min, v2)
	end

	min -= Vector2.new(stroke.width, stroke.width)
	max += Vector2.new(stroke.width, stroke.width)

	local bounds = Rect.new(min, max)
	if Vector2.max(bounds.Min, Vector2.zero)  == Vector2.zero and Vector2.min(bounds.Max, stroke.resolution) == stroke.resolution then
		stroke.undo_offset = 0
		stroke.undo_len = buffer.len(stroke.raw_init)
		stroke.undo_data = stroke.raw_init
	else
		local offset = math.max(0, (min.Y * stroke.resolution.Y + min.X) * 4)
		local finish = math.min(
			((stroke.resolution.Y - 1) * stroke.resolution.Y + stroke.resolution.X - 1) * 4,
			(max.Y * stroke.resolution.Y + max.X) * 4
		)
		local len = finish - offset
		local partial = buffer.create(len)
		buffer.copy(partial, 0, stroke.raw_init, offset, len)

		stroke.undo_offset = offset
		stroke.undo_len = (finish - offset)
		stroke.undo_data = partial
	end
	stroke.raw_init = nil
	stroke.redo_data = PackedVector3Array.fromTable(stroke.inputs)
	stroke.size = stroke.undo_len + stroke.redo_data:Len() * 24
	stroke.inputs = nil

	return stroke
end

function History.Dump(dump_stacks: boolean?)
	print("[History Info Start]")

	print(`Undo Items: {#History.undo_stack}`)
	print(`Redo Items: {#History.redo_stack}`)
	print((`Raw Redo Total Size: %.3fMB ({History.undo_mem + History.redo_mem}B)`):format(History.getMemMB()))

	if dump_stacks then
		for i, s: Command in History.undo_stack do
			print(`[Undo Stack {i}]`)
			print(s)
		end
		for i, s: Command in History.redo_stack do
			print(`[Redo Stack {i}]`)
			print(s)
		end
	end

	print("[History Info End]")
end

function History.LayerSwap(a: number, b: number) : LayerSwap
	return { __type = "LayerSwap", a = a, b = b }
end

function History.LayerClear(index: number, buf: buffer) : LayerClear
	local size = buffer.len(buf)
	local saved = buffer.create(size)
	buffer.copy(saved, 0, buf)
	return {
		__type = "LayerClear",
		layer = index,
		size = size,
		saved = saved,
	}
end

return History