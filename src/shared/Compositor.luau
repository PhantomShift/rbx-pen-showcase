--!native
--!optimize 2

local AssetService = game:GetService("AssetService")

local Compositor = {}
Compositor.MEMORY_LIMIT_MB = 512

type CacheEntry = { buffer: buffer, timestamp: number, accesses: number }
type CacheEntries = { [NumberRange]: CacheEntry }
-- invalidate: for range, entry in cache do if dirty >= range.min and dirty <= range.max then remove end

export type Compositor = {
	cache: CacheEntries,
	_scratch: EditableImage?,
}

local scratchUnder: EditableImage? = nil
local scratchOver: EditableImage? = nil

local function tryInit(size: Vector2)
	if scratchUnder and scratchOver then
		scratchUnder:Destroy()
		scratchOver:Destroy()
		scratchUnder = nil
		scratchOver = nil
	end
	local success, under, over = pcall(function()
		return AssetService:CreateEditableImage({Size = size}), AssetService:CreateEditableImage({Size = size})
	end)
	if success then
		scratchUnder = under
		scratchOver = over
	else
		warn(`Error creating scratch images: {under}`)
	end
	return success
end

-- For now, just super basic over implementation
function Compositor.cascadeOver(destination: buffer, layers: {buffer})
	local bytes = buffer.len(destination)
	local r_d, g_d, b_d, a_d : number
	local r_s, g_s, b_s, a_s : number
	local a_c, a_t : number
	
	for _, layer in layers do
		for offset = 0, bytes - 4, 4 do
			r_d = buffer.readu8(destination, offset)
			g_d = buffer.readu8(destination, offset + 1)
			b_d = buffer.readu8(destination, offset + 2)
			a_d = buffer.readu8(destination, offset + 3)
			
			r_s = buffer.readu8(layer, offset)
			g_s = buffer.readu8(layer, offset + 1)
			b_s = buffer.readu8(layer, offset + 2)
			a_s = buffer.readu8(layer, offset + 3)
			
			a_t = 255 - a_s
			a_c = (255 * a_s + a_d * a_t) / 255
			buffer.writeu8(destination, offset, (r_s * a_s + r_d * a_t) / 255)
			buffer.writeu8(destination, offset + 1, (g_s * a_s + g_d * a_t) / 255)
			buffer.writeu8(destination, offset + 2, (b_s * a_s + b_d * a_t) / 255)

			buffer.writeu8(destination, offset + 3, a_c)
			
		end
	end
	
	return true
end

--- Implementation backed by `EditableImage`s.
--- ~2x faster, but is susceptible to memory constraints since it requires **two** EditableImage instances.
function Compositor.cascadeOverFast(destination: buffer, layers: {buffer}, size: Vector2) : boolean
	if scratchUnder == nil or scratchUnder.Size ~= size then
		if not tryInit(size) then
			return false
		end
	end
	assert(scratchUnder and scratchOver)

	scratchUnder:WritePixelsBuffer(Vector2.zero, size, destination)
	for _, layer in layers do
		scratchOver:WritePixelsBuffer(Vector2.zero, size, layer)
		scratchUnder:DrawImage(Vector2.zero, scratchOver, Enum.ImageCombineType.BlendSourceOver)
	end
	buffer.copy(destination, 0, scratchUnder:ReadPixelsBuffer(Vector2.zero, size))
	
	return true
end

function Compositor.cascadeOverFastDirect(destination: EditableImage, background: buffer, layers: {buffer}, size: Vector2) : boolean
	if scratchUnder == nil or scratchUnder.Size ~= size then
		if not tryInit(size) then
			return false
		end
	end
    assert(scratchOver)
	
	destination:WritePixelsBuffer(Vector2.zero, size, background)
	for _, layer in layers do
		scratchOver:WritePixelsBuffer(Vector2.zero, size, layer)
		destination:DrawImage(Vector2.zero, scratchOver, Enum.ImageCombineType.BlendSourceOver)
	end

	return true
end


return Compositor