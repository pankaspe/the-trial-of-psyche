// The biomes: the places a level can be, one row each. `biome NAME` in a
// level gives its defaults (the lines written in the file always win): the
// light, the day and evening of a level with sundials, the look at the foot
// of a level that goes down, the world under it in a level that turns over,
// what its basins are made of and filled with. Its props, weighted, are what
// the place is decorated with: level_check warns of a prop foreign to it.
package level

Biome :: enum u8 {
	Palace, // the palace of voices
	Crag, // a mountain crag of bare rock
	Forest, // a forest of rock pillars and firs
	River, // a wide river among the firs
	Temple, // a temple among the ranges
	Venus, // the house of Venus above the clouds
	Pasture, // the Sun's pastures by a river
	Styx, // the crag of the Styx and its gorge
	Tower, // the high tower over the mouth of the underworld
	Taenarus, // the land of the dead: ash, black rock, the dark water
	Dis, // Proserpina's kingdom, under the land of the dead
}

Biome_Info :: struct {
	name:   string, // in the level files
	light:  Setting,
	day:    Maybe([2]Setting), // a level with sundials: its day and its evening
	below:  Maybe(Setting), // a level that goes down: the look at its foot
	upside: Maybe(Biome), // a level with pomegranates: the world under it
	rim:    Rim, // a basin's
	fluid:  Fluid,
	fish:   u8, // how many fish swim in its water: 0 none (a swamp has none) .. 3 many
	props:  [Prop_Kind]u8, // how often each prop is found there: 0 never .. 3 everywhere
}

BIOMES := [Biome]Biome_Info {
	.Palace = {
		name = "palace",
		fish = 1,
		light = .Night,
		props = #partial {.Sconce = 3, .Rail = 3, .Wall_Battlement = 2, .Vase = 1, .Pillar = 1, .Cypress = 1, .Urn = 1, .Arch = 1, .Brazier = 1, .Statue = 1, .Bed = 1},
	},
	.Crag = {
		name = "crag",
		fish = 1,
		light = .Crag_Day,
		rim = .Rock,
		props = #partial {.Shrub = 3, .Cairn = 2, .Pine = 2, .Lip = 2, .Boulder = 2, .Brazier = 1},
	},
	.Forest = {
		name = "forest",
		light = .Forest_Night,
		rim = .Earth,
		fluid = .Swamp,
		props = #partial {.Spruce = 3, .Rope = 2, .Log = 2, .Shrub = 2, .Cypress = 1, .Cairn = 1},
	},
	.River = {
		name = "river",
		fish = 3,
		light = .River_Dawn,
		rim = .Rock,
		props = #partial {.Spruce = 3, .Reeds = 2, .Rope = 2, .Boulder = 1, .Shrub = 1},
	},
	.Temple = {
		name = "temple",
		fish = 1,
		light = .Temple_Dusk,
		props = #partial {.Rail = 3, .Pillar = 3, .Statue = 1, .Urn = 1, .Brazier = 1},
	},
	.Venus = {
		name = "venus",
		fish = 2,
		light = .Venus_Day,
		day = [2]Setting{.Venus_Day, .Venus_Evening},
		props = #partial {.Rail = 3, .Rope = 3, .Rose = 1, .Myrtle = 1, .Statue = 1, .Urn = 1, .Heap = 1, .Sconce = 1},
	},
	.Pasture = {
		name = "pasture",
		fish = 2,
		light = .Pasture_Day,
		day = [2]Setting{.Pasture_Day, .Pasture_Evening},
		rim = .Earth,
		props = #partial {.Rope = 3, .Shrub = 2, .Reeds = 2, .Fence = 2},
	},
	.Styx = {
		name = "styx",
		light = .Styx_Night,
		day = [2]Setting{.Styx_Day, .Styx_Evening},
		rim = .Rock,
		props = #partial {.Lip = 3, .Rope = 2, .Shrub = 2, .Cairn = 2, .Pine = 1, .Boulder = 1},
	},
	.Tower = {
		name = "tower",
		light = .Tower_Dusk,
		below = .Taenarus,
		rim = .Rock,
		props = #partial {.Sconce = 3, .Wall_Battlement = 2, .Lip = 2},
	},
	.Taenarus = {
		name = "taenarus",
		light = .Taenarus,
		upside = .Dis,
		rim = .Rock,
		props = #partial {.Lip = 3, .Boulder = 2, .Shrub = 1, .Cairn = 1, .Pine = 1, .Fire = 1},
	},
	.Dis = {
		name = "dis",
		light = .Dis,
		props = #partial {.Rail = 3, .Pillar = 3, .Sconce = 2, .Arch = 1, .Urn = 1, .Cypress = 1},
	},
}
