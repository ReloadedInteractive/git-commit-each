--!strict

local fs = require("@lune/fs")
local process = require("@lune/process")
local stdio = require("@lune/stdio")

local changedFiles: { string }
local result = process.spawn("git", {"diff", "--name-status", "--diff-filter=MA"}, {shell=true})
if result.ok then
	changedFiles = result.stdout:split("\n")
	changedFiles[#changedFiles] = nil
	result = process.spawn("git", {"diff", "--cached", "--name-status", "--diff-filter=MA"})
	if result.ok then
		local cachedFiles = result.stdout:split("\n")
		cachedFiles[#cachedFiles] = nil
		for _, v in cachedFiles do
			table.insert(changedFiles, v)
		end
	else
		error(result.stderr)
	end
else
	error(result.stderr)
end

if changedFiles then
	for i, v in changedFiles do
		if type(v) ~= "string" then
			continue
		end
		local splited = v:split("\t")
		local status = splited[1]
		if status ~= "M" and status ~= "A" then
			continue
		end
		local file = splited[2]
		stdio.write(stdio.color("reset"))
		stdio.write(`File: `)
		stdio.write(stdio.color("cyan"))
		stdio.write(file)
		stdio.write(stdio.color("reset"))
		stdio.write("\nStatus: ")
		if status == "A" then
			stdio.write(stdio.color("green"))
			stdio.write("ADDED")
		elseif status == "M" then
			stdio.write(stdio.color("yellow"))
			stdio.write("MODIFIED")
		end
		stdio.write("\n")
		local message = stdio.prompt("text", "commit message:")
		result = process.spawn("git", {"commit", "-m", message, file})
		if result.ok then
			stdio.write("\n")
		else
			error(result.stderr)
		end
	end
end
