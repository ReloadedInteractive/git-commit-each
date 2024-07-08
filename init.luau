--!strict

local process = require("@lune/process")
local stdio = require("@lune/stdio")

local debugMode = table.find(process.args, "debug") ~= nil

local EMPTY_COMMIT_SKIP_MESSAGE = "Skipping. because the given commit message is empty"

local function panic(message: string): never
	if debugMode then
		error(message)
	else
		stdio.write(stdio.color("red"))
		stdio.write(message)
		stdio.write(stdio.color("reset"))
	end
	return process.exit(1)
end

local function log(...: string)
	if not debugMode then
		return
	end
	print(...)
end

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
		panic(result.stderr)
	end
else
	panic(result.stderr)
end

if changedFiles then
	local done: { [string]: string }
	local commitGroups: {
		[string]: {
			files: { string },
			message: string
		}
	}
	for _, v in changedFiles do
		if type(v) ~= "string" then
			continue
		end
		local splited = v:split("\t")
		local status = splited[1]
		if status ~= "M" and status ~= "A" then
			continue
		end
		local file = splited[2]
		if done and done[file] then
			print(`file {file} already has committed. skipping..`)
			continue
		end
		stdio.write(stdio.color("reset"))
		stdio.write(`File: `)
		stdio.write(stdio.color("cyan"))
		stdio.write(file)
		stdio.write(stdio.color("reset"))
		stdio.write("\tStatus: ")
		stdio.write(stdio.style("bold"))
		if status == "A" then
			stdio.write(stdio.color("green"))
			stdio.write("ADDED")
		elseif status == "M" then
			stdio.write(stdio.color("yellow"))
			stdio.write("MODIFIED")
		end
		stdio.write(stdio.style("reset"))
		stdio.write("\n")

		local function wroteCommit(message: string)
			stdio.write(stdio.color("black"))
			stdio.write(stdio.style("dim"))
			stdio.write(`\tConfirmed commit message: {message}\n\n`)
			stdio.write(stdio.style("reset"))
			stdio.write(stdio.color("reset"))
		end

		if commitGroups then
			local options = { "Create a new commit" }
			for name, _ in commitGroups do
				table.insert(options, name)
			end
			local choice = stdio.prompt("select", "You've created commit groups. Select a commit group or create a new commit.", options)
			if choice ~= 1 then
				local group = commitGroups[options[choice]]
				table.insert(group.files, file)
				wroteCommit(group.message)
				continue
			end
		end
		local message = stdio.prompt("text", "Enter a commit message:")
		local groupStart, groupEnd = message:find("@%w+")
		if groupStart and groupEnd and groupStart == 1 then
			local isEscaped = message:sub(groupStart - 1, groupStart - 1) == "@"
			if not isEscaped then
				local groupName = message:sub(groupStart + 1, groupEnd)
				message = message:sub(groupEnd + 1 + 1)
				if #message == 0 then
					print(EMPTY_COMMIT_SKIP_MESSAGE)
					continue
				end
				if not commitGroups then
					commitGroups = {}
				end
				local group = commitGroups[groupName]
				if group then
					table.insert(group.files, file)
				else
					group = {
						files = {
							file
						},
						message = message
					}
					commitGroups[groupName] = group
				end
				wroteCommit(message)
				continue
			end
		end
		if #message == 0 then
			print(EMPTY_COMMIT_SKIP_MESSAGE)
			continue
		end
		result = process.spawn("git", {"commit", "-m", message, file})
		if result.ok then
			if not done then
				done = {}
			end
			if done then
				done[file] = message
			end
			wroteCommit(message)
		else
			log(result.stdout)
			panic(result.stderr)
		end
	end
	local groupedFiles = {}
	if commitGroups then
		for name, group in commitGroups do
			result = process.spawn("git", {"commit", "-m", group.message, table.unpack(group.files)})
			if result.ok then
				if not done then
					done = {}
				end
				for _, file in group.files do
					--done[file] = group.message .. ` @CommitGroup({name})`
					done[file] = group.message
					groupedFiles[file] = name
				end
			else
				log(result.stdout)
				panic(result.stderr)
			end
		end
	end
	if done then
		stdio.write(`Successfully committed:\n`)
		for file, message in done do
			stdio.write(stdio.color("purple"))
			stdio.write(stdio.style("bold"))
			stdio.write(file)
			stdio.write(stdio.style("reset"))
			stdio.write(stdio.color("reset"))
			stdio.write(" - ")
			stdio.write(stdio.color("green"))
			stdio.write(`"{message}"`)
			local groupName = groupedFiles[file]
			if groupName then
				stdio.write(stdio.color("black"))
				stdio.write(" (group: "..groupName..")")
				stdio.write(stdio.color("reset"))
			end
			stdio.write("\n")
		end
	else
		panic("Nothing to commit!")
	end
end
