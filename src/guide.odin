package main

import "base:runtime"
import "core:sync"
import "core:thread"

import "game"
import "palace"

// The guide (an aid): asked with the light on Psyche (Tab, the pad's North),
// the way from where she stands to the goal is searched on a worker thread
// (a big level takes a while), then its first stretch is shown.
Guide_Search :: struct {
	worker: ^thread.Thread,
	job:    Guide_Job,
}

Guide_Job :: struct {
	index:   int,
	diorama: int,
	source:  string, // the diorama's text
	from:    palace.State,
	result:  []palace.Plan_Step,
	done:    bool, // set by the worker (atomic)
}

// Asked: searched if the game has the aid, she stands still and no search runs.
ask_guide :: proc(app: ^App) {
	g := &app.game
	gs := &app.guide
	if .Guide not_in app.prog.aids || gs.worker != nil || !g.active || g.phase != .Play || !game.idle(g) {
		return
	}
	gs.job = {index = g.level_index, diorama = g.diorama, source = app.diorama_text, from = game.state_now(g)}
	gs.worker = thread.create_and_start_with_poly_data(&gs.job, proc(job: ^Guide_Job) {
		job.result = game.search_guide(job.source, job.from, runtime.heap_allocator())
		sync.atomic_store(&job.done, true)
	})
}

// Each frame: a way found goes to the level playing, if it is the one
// searched and she has not moved since (game.show_guide).
poll_guide :: proc(app: ^App) {
	gs := &app.guide
	if gs.worker == nil || !sync.atomic_load(&gs.job.done) {
		return
	}
	g := &app.game
	if g.level_index == gs.job.index && g.diorama == gs.job.diorama {
		game.show_guide(g, gs.job.from, gs.job.result)
	}
	drop_guide(gs)
}

// The worker waited for and its answer freed (also at the end).
drop_guide :: proc(gs: ^Guide_Search) {
	if gs.worker == nil {
		return
	}
	thread.join(gs.worker)
	thread.destroy(gs.worker)
	gs.worker = nil
	delete(gs.job.result, runtime.heap_allocator())
	gs.job.result = nil
}
