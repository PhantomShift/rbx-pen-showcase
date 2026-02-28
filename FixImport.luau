-- Hopefully a temporary fix, binary serialization for StyleRules is broken.
-- Doing this seems to fix the issue, though it's definitely hacky at best.

local fs = require("@lune/fs")
local proc = require("@lune/process")

assert(#proc.args == 1, "expected exactly one argument")

local path = proc.args[1]

assert(fs.isFile(path) and path:match("%.rbxlx$"), "expected an rbxlx file")

local contents = fs.readFile(path)
local fixed = contents:gsub(
    `<BinaryString name="PropertiesSerialize"></BinaryString>`,
    `<BinaryString name="PropertiesSerialize">AAAAAA==</BinaryString>`
)

fs.writeFile(path, fixed)
