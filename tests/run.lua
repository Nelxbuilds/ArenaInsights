-- Dependency-free test runner. From the repo root:
--   lua tests/run.lua           run all tests/*_spec.lua
--   lua tests/run.lua foo       run only spec files whose name contains "foo"
local filter = arg and arg[1]

local passed, failures = 0, {}
local currentFile = "?"

function _G.test(name, fn)
    local ok, err = pcall(fn)
    if ok then
        passed = passed + 1
        io.write(".")
    else
        io.write("F")
        failures[#failures + 1] = { file = currentFile, name = name, err = err }
    end
end

function _G.eq(got, want, label)
    if got ~= want then
        error(("%s: expected %s, got %s")
            :format(label or "value", tostring(want), tostring(got)), 2)
    end
end

function _G.ok(v, label)
    if not v then error((label or "condition") .. ": expected truthy, got " .. tostring(v), 2) end
end

local specs = {}
local p = io.popen('ls tests/*_spec.lua 2>/dev/null')
if p then
    for line in p:lines() do
        if not filter or line:find(filter, 1, true) then
            specs[#specs + 1] = line
        end
    end
    p:close()
end

if #specs == 0 then
    print("no spec files found (run from the repo root)")
    os.exit(1)
end

for _, file in ipairs(specs) do
    currentFile = file
    local chunk, err = loadfile(file)
    if not chunk then
        io.write("F")
        failures[#failures + 1] = { file = file, name = "(load)", err = err }
    else
        local okRun, runErr = pcall(chunk)
        if not okRun then
            io.write("F")
            failures[#failures + 1] = { file = file, name = "(run)", err = runErr }
        end
    end
end

print()
for _, f in ipairs(failures) do
    print(("FAIL %s :: %s\n     %s"):format(f.file, f.name, tostring(f.err)))
end
print(("%d passed, %d failed"):format(passed, #failures))
os.exit(#failures == 0 and 0 or 1)
