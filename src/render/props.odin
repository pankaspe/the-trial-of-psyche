// How each prop looks: one row per kind, the same keys as level.PROPS.
// An oriented prop (level.PROPS' `dir`) turns every piece of its row toward
// its direction: the meshes named here are then the +x ones.
package render

import "../level"

Prop_Piece :: struct {
	mesh:     Mesh_Id,
	material: Material,
}

Prop_Look :: struct {
	body:  Prop_Piece,
	extra: Maybe(Prop_Piece), // a second piece in its own material
}

PROP_LOOK := [level.Prop_Kind]Prop_Look {
	.Rail            = {body = {.Rail_PX, .Marble}},
	.Wall            = {body = {.Wall_PX, .Masonry}},
	.Wall_Half       = {body = {.Wall_Half_PX, .Masonry}},
	.Wall_Battlement = {body = {.Battlement_PX, .Masonry}},
	.Fence           = {body = {.Fence_PX, .Bronze}},
	.Rope            = {body = {.Rope_PX, .Wood}},
	.Log             = {body = {.Log_PX, .Wood}},
	.Lip             = {body = {.Lip_PX, .Rock}},
	.Pillar          = {body = {.Pillar, .Marble}},
	.Plinth          = {body = {.Plinth, .Marble}},
	.Cypress         = {body = {.Cypress, .Foliage}},
	.Urn             = {body = {.Urn, .Bronze}},
	.Brazier         = {body = {.Brazier, .Bronze}},
	.Bed             = {body = {.Bed_PX, .Bronze}},
	.Statue          = {body = {.Statue_PX, .Marble}},
	.Spruce          = {body = {.Spruce, .Foliage}, extra = Prop_Piece{.Spruce_Trunk, .Wood}},
	.Plane           = {body = {.Plane, .Foliage}, extra = Prop_Piece{.Plane_Trunk, .Wood}},
	.Heap            = {body = {.Heap, .Seeds}},
	.Arch            = {body = {.Arch_PX, .Masonry}},
	.Vase            = {body = {.Vase_PX, .Bronze}},
	.Reeds           = {body = {.Reeds_PX, .Foliage}},
	.Sconce          = {body = {.Sconce_PX, .Bronze}, extra = Prop_Piece{.Candle_PX, .Psyche}}, // the candle, in wax
	.Pine            = {body = {.Pine_PX, .Foliage}, extra = Prop_Piece{.Trunk_PX, .Wood}},
	.Boulder         = {body = {.Boulder_PX, .Rock}},
	.Shrub           = {body = {.Shrub_PX, .Foliage}},
	.Cairn           = {body = {.Cairn_PX, .Rock}},
	.Rose            = {body = {.Rose_PX, .Foliage}, extra = Prop_Piece{.Rose_Bloom_PX, .Blossom}},
	.Myrtle          = {body = {.Myrtle_PX, .Foliage}, extra = Prop_Piece{.Myrtle_Pot_PX, .Bronze}},
	.Fire            = {body = {.Fire_Stones, .Rock}, extra = Prop_Piece{.Fire_Logs, .Wood}},
}
