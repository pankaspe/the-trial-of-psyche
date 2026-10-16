// The catalogue of props: one row per kind, everything the loader, the rules
// and the checks know of it. How each looks is render's PROP_LOOK, keyed the
// same way. A new prop: a kind here, its row in PROPS and in PROP_LOOK, and
// its shape (render/shapes.odin).
package level

Prop_Kind :: enum u8 {
	// edge props: close one side of the cell they stand in
	Rail,
	Wall,
	Wall_Half,
	Wall_Battlement,
	Fence,
	Rope, // the hand ropes of a rope bridge, along one side
	Log, // a fallen trunk lying along one side
	Lip, // a low lip of rock along one side: the parapet of a crag's ledge
	// blocking props: nobody can stand in their cell
	Pillar,
	Plinth,
	Cypress,
	Urn,
	Brazier,
	Bed,
	Statue, // a marble woman on a plinth, calling with her arm raised toward `dir`
	Spruce, // a tall fir of the forest
	Heap, // a mound of mixed seeds (Venus's task)
	// decoration only
	Arch,
	Vase, // small, in one corner of the cell: px (+x,+y), py (-x,+y), mx (-x,-y), my (+x,-y)
	Reeds, // a clump of reeds in one corner of the cell (as the vase)
	Sconce, // a candle on the side `dir` of the block at (x,y,z): lit where the setting lights them
	// the mountain: blocking
	Pine, // a wind-bent pine
	Boulder, // a heap of fallen rocks
	// the mountain: decoration only, in one corner of the cell (as the vase)
	Shrub, // a low bush
	Cairn, // a few stones piled up by passers-by
	// the house of Venus: decoration only, in one corner of the cell (as the vase)
	Rose, // a rose bush in flower
	Myrtle, // a small myrtle, Venus's tree, in a pot
	Fire, // a fire in a ring of stones: it burns in any setting and lights the stones around it
}

// How a prop holds its cell.
Prop_Fill :: enum u8 {
	None, // decoration only: walked through
	Side, // closes side `dir` of its cell
	Cell, // nobody can stand in its cell
}

// Whether a prop takes a direction (`prop name x y z [dir]`).
Prop_Dir :: enum u8 {
	None, // drawn one way only
	Optional, // turned toward `dir` when one is given (+x otherwise)
	Needed,
}

// What a prop stands on (the checks: what it must not hang off).
Prop_Rest :: enum u8 {
	Floor, // the stone under its cell
	Wall, // side `dir` of the block in its own cell
	Posts, // the posts of a rope bridge: it hangs between them, never on a stone
}

// The flame a prop carries.
Prop_Flame :: enum u8 {
	None,
	Candle, // lit where the setting lights the candles
	Fire, // burns in any setting, lights the stones further, is heard near
}

Prop_Info :: struct {
	name:  string, // in the level files
	fill:  Prop_Fill,
	dir:   Prop_Dir,
	rest:  Prop_Rest,
	flame: Prop_Flame,
}

PROPS := [Prop_Kind]Prop_Info {
	.Rail            = {name = "rail", fill = .Side, dir = .Needed},
	.Wall            = {name = "wall", fill = .Side, dir = .Needed},
	.Wall_Half       = {name = "wallHalf", fill = .Side, dir = .Needed},
	.Wall_Battlement = {name = "wallBattlement", fill = .Side, dir = .Needed},
	.Fence           = {name = "fence", fill = .Side, dir = .Needed},
	.Rope            = {name = "rope", fill = .Side, dir = .Needed, rest = .Posts},
	.Log             = {name = "log", fill = .Side, dir = .Needed},
	.Lip             = {name = "lip", fill = .Side, dir = .Needed},
	.Pillar          = {name = "pillar", fill = .Cell},
	.Plinth          = {name = "plinth", fill = .Cell},
	.Cypress         = {name = "cypress", fill = .Cell},
	.Urn             = {name = "urn", fill = .Cell},
	.Brazier         = {name = "brazier", fill = .Cell},
	.Bed             = {name = "bed", fill = .Cell, dir = .Optional},
	.Statue          = {name = "statue", fill = .Cell, dir = .Needed},
	.Spruce          = {name = "spruce", fill = .Cell},
	.Heap            = {name = "heap", fill = .Cell},
	.Arch            = {name = "arch", dir = .Optional},
	.Vase            = {name = "vase", dir = .Needed},
	.Reeds           = {name = "reeds", dir = .Needed},
	.Sconce          = {name = "sconce", dir = .Needed, rest = .Wall, flame = .Candle},
	.Pine            = {name = "pine", fill = .Cell, dir = .Optional},
	.Boulder         = {name = "boulder", fill = .Cell, dir = .Optional},
	.Shrub           = {name = "shrub", dir = .Needed},
	.Cairn           = {name = "cairn", dir = .Needed},
	.Rose            = {name = "rose", dir = .Needed},
	.Myrtle          = {name = "myrtle", dir = .Needed},
	.Fire            = {name = "fire", fill = .Cell, flame = .Fire},
}
