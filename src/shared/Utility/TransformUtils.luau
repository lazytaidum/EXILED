local TransformUtils = {}

local function cloneVectorTable(vectorTable)
	return {
		X = vectorTable.X or 0,
		Y = vectorTable.Y or 0,
		Z = vectorTable.Z or 0,
	}
end

function TransformUtils.CloneTransform(transform)
	transform = transform or {}

	return {
		Position = cloneVectorTable(transform.Position or {}),
		Rotation = cloneVectorTable(transform.Rotation or {}),
	}
end

function TransformUtils.CloneTransformMap(transformMap)
	local clonedMap = {}

	for name, transform in pairs(transformMap or {}) do
		clonedMap[name] = TransformUtils.CloneTransform(transform)
	end

	return clonedMap
end

function TransformUtils.ToCFrame(transform)
	transform = transform or {}

	local position = transform.Position or {}
	local rotation = transform.Rotation or {}

	return CFrame.new(position.X or 0, position.Y or 0, position.Z or 0)
		* CFrame.Angles(
			math.rad(rotation.X or 0),
			math.rad(rotation.Y or 0),
			math.rad(rotation.Z or 0)
		)
end

function TransformUtils.SetAxis(transform, axisGroup, axisName, value)
	transform[axisGroup] = transform[axisGroup] or {}
	transform[axisGroup][axisName] = value
end

function TransformUtils.AdjustAxis(transform, axisGroup, axisName, delta)
	transform[axisGroup] = transform[axisGroup] or {}
	transform[axisGroup][axisName] = (transform[axisGroup][axisName] or 0) + delta
end

function TransformUtils.FormatNumber(value)
	local rounded = math.round((value or 0) * 1000) / 1000
	if rounded == -0 then
		rounded = 0
	end

	local text = string.format("%.3f", rounded)
	text = string.gsub(text, "0+$", "")
	text = string.gsub(text, "%.$", "")

	if text == "" then
		return "0"
	end

	return text
end

function TransformUtils.FormatTransform(transform, indent)
	indent = indent or "\t"

	local position = transform.Position or {}
	local rotation = transform.Rotation or {}

	return string.format(
		"{\n%sPosition = { X = %s, Y = %s, Z = %s },\n%sRotation = { X = %s, Y = %s, Z = %s },\n}",
		indent,
		TransformUtils.FormatNumber(position.X),
		TransformUtils.FormatNumber(position.Y),
		TransformUtils.FormatNumber(position.Z),
		indent,
		TransformUtils.FormatNumber(rotation.X),
		TransformUtils.FormatNumber(rotation.Y),
		TransformUtils.FormatNumber(rotation.Z)
	)
end

function TransformUtils.FormatTransformMap(transformMap, indent)
	indent = indent or "\t"

	local names = {}
	for name in pairs(transformMap or {}) do
		table.insert(names, name)
	end
	table.sort(names)

	local lines = { "{" }

	for _, name in ipairs(names) do
		table.insert(
			lines,
			string.format("%s%s = %s,", indent, name, TransformUtils.FormatTransform(transformMap[name], indent .. "\t"))
		)
	end

	table.insert(lines, "}")

	return table.concat(lines, "\n")
end

return TransformUtils
