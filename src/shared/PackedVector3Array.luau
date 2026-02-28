--!native
--!optimize 2

--- Note that indexing begins at 0
local packed = {}
packed.__index = packed

export type PackedVector3Array = setmetatable<{ _buffer: buffer }, typeof(packed)>

function packed.fromTable(t: {Vector3}) : PackedVector3Array
	local buf = buffer.create(#t * 24)
	local offset = 0
	for _, v in t do
		buffer.writef64(buf, offset, v.X)
		buffer.writef64(buf, offset + 8, v.Y)
		buffer.writef64(buf, offset + 16, v.Z)

		offset += 24
	end

	return setmetatable({ _buffer = buf }, packed)
end

--- Strongly references and wraps a given buffer as a Vector3 array.
--- Returns nil if `src` is not a valid size (not divisble by 24).
function packed.fromBuffer(src: buffer) : PackedVector3Array?
	local len = buffer.len(src)
	if len % 24 ~= 0 then
		return nil
	end

	return setmetatable({ _buffer = src }, packed)
end

--- Creates a **copy** of the given buffer and wraps it with this type.
--- Returns nil if `src` is not a valid size.
function packed.fromBufferCopy(src: buffer) : PackedVector3Array?
	local len = buffer.len(src)
	if len % 24 ~= 0 then
		return nil
	end

	local buf = buffer.create(len)
	buffer.copy(buf, 0, src)

	return setmetatable({ _buffer = buf }, packed) 
end


function packed.Len(self: PackedVector3Array) : number
	return buffer.len(self._buffer) / 24
end

function packed.Get(self: PackedVector3Array, i: number) : Vector3?
	if i < 0 or i >= packed.Len(self) then
		return
	end

	local offset = i * 24
	return Vector3.new(
		buffer.readf64(self._buffer, offset),
		buffer.readf64(self._buffer, offset + 8),
		buffer.readf64(self._buffer, offset + 16)
	)
end

function packed.Set(self: PackedVector3Array, i: number, v: Vector3)
	if i < 0 or i >= packed.Len(self) then
		return
	end

	local offset = i * 24
	return Vector3.new(
		buffer.writef64(self._buffer, offset, v.X),
		buffer.writef64(self._buffer, offset + 8, v.Y),
		buffer.writef64(self._buffer, offset + 16, v.Z)
	)
end

function packed.Clear(self: PackedVector3Array)
	buffer.fill(self._buffer, 0, 0)
end

--- Returns a **copy** of the given range of the array.
--- `i` defaults to 0, `j` defaults to `PackedVector3Array:Len()`
function packed.Slice(self: PackedVector3Array, i: number?, j: number?) : PackedVector3Array
	local max = self:Len()
	i = if i == nil then 0 else i
	j = if j == nil then max else math.max(i, math.min(j, max))

	local len = (i - j) * 24
	local slice = buffer.create(len)
	buffer.copy(slice, 0, self._buffer, i * 24, len)

	return setmetatable({ _buffer = buffer }, packed)
end

--- For explicitly guaranteeing that at least the underlying buffer is freed if the array wrapper is leaked.
--- It is an error to use a PackedVector3Array that has already been explicitly freed.
function packed.Free(self: PackedVector3Array)
	self._buffer = nil
end

local function packedNext(p: PackedVector3Array, lastKey: number?) : (number?, Vector3)
	local key = if lastKey == nil then 0 else lastKey + 1
	if key >= p:Len() then
		return nil
	end
	return key, p:Get(key)
end
function packed.__iter(self)
	return packedNext, self
end

return packed
