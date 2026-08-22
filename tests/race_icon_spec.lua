-- Race icon atlas slugs. Five playable races have an atlas slug that is not
-- just the lowercased UnitRace() file name; verified against the 12.1.0 atlas
-- list (build 69404).

local H = require("tests.helpers")

local function markup(raceFileName, gender)
    local w = H.newEnv({ "core/Core.lua" })
    return w.AI.RaceIconMarkup({ raceFileName = raceFileName, gender = gender or 2 })
end

test("races whose atlas slug matches the race file name", function()
    eq(markup("Human"), "|A:raceicon-human-male:14:14|a", "human")
    eq(markup("NightElf", 3), "|A:raceicon-nightelf-female:14:14|a", "night elf, female")
    eq(markup("DarkIronDwarf"), "|A:raceicon-darkirondwarf-male:14:14|a", "dark iron dwarf")
    eq(markup("Dracthyr"), "|A:raceicon-dracthyr-male:14:14|a", "dracthyr")
    eq(markup("Vulpera"), "|A:raceicon-vulpera-male:14:14|a", "vulpera")
end)

test("races whose atlas slug differs from the race file name", function()
    eq(markup("HighmountainTauren"), "|A:raceicon-highmountain-male:14:14|a", "highmountain tauren")
    eq(markup("LightforgedDraenei"), "|A:raceicon-lightforged-male:14:14|a", "lightforged draenei")
    eq(markup("ZandalariTroll"), "|A:raceicon-zandalari-male:14:14|a", "zandalari troll")
    eq(markup("EarthenDwarf"), "|A:raceicon-earthen-male:14:14|a", "earthen")
    eq(markup("Scourge"), "|A:raceicon-undead-male:14:14|a", "undead")
end)

test("no icon without a known race or gender", function()
    eq(markup("Human", 1), nil, "unknown gender")
    eq(markup(nil), nil, "no race")
    eq(H.newEnv({ "core/Core.lua" }).AI.RaceIconMarkup(nil), nil, "no character")
end)
