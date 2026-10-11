package main

import "base:runtime"
import "core:sync"
import "core:thread"

import "content"
import "game"
import "palace"

// The dead ends of each level (game.search_dead_ends), searched on a worker
// thread: a big level takes seconds in a debug build, and the game must not
// stop for it. The level plays meanwhile; she is told once the answer comes.
// Each level is searched once per session (a level read from a file, for
// shots, each time it loads).
Dead_Ends :: struct {
	known:   [content.LEVEL_COUNT]Maybe([]palace.State), // in the heap, for the session
	worker:  ^thread.Thread,
	job:     Dead_End_Job,
	pending: Maybe(Dead_End_Job), // asked for while the worker was busy
}

Dead_End_Job :: struct {
	index:  int,
	source: string,
	keep:   bool, // a level slot's own text: remembered for the session
	result: []palace.State,
	done:   bool, // set by the worker (atomic)
}

// A level has loaded: its dead ends now, or once searched.
want_dead_ends :: proc(app: ^App, index: int, source: string) {
	d := &app.dead_ends
	keep := source == content.LEVELS[index].source
	if dead, ok := d.known[index].?; ok && keep {
		game.know_dead_ends(&app.game, dead)
		return
	}
	job := Dead_End_Job{index = index, source = source, keep = keep}
	if d.worker != nil {
		d.pending = job
		return
	}
	start_dead_end_job(d, job)
}

@(private = "file")
start_dead_end_job :: proc(d: ^Dead_Ends, job: Dead_End_Job) {
	d.job = job
	d.worker = thread.create_and_start_with_poly_data(&d.job, proc(job: ^Dead_End_Job) {
		job.result = game.search_dead_ends(job.source, runtime.heap_allocator())
		sync.atomic_store(&job.done, true)
	})
}

// Each frame: an answer from the worker goes to the level playing, if it is
// the one searched; then the next job.
poll_dead_ends :: proc(app: ^App) {
	d := &app.dead_ends
	if d.worker == nil || !sync.atomic_load(&d.job.done) {
		return
	}
	thread.join(d.worker)
	thread.destroy(d.worker)
	d.worker = nil
	job := d.job
	g := &app.game
	if g.level_index == job.index && (!job.keep || d.known[job.index] == nil) {
		game.know_dead_ends(g, job.result)
	}
	if job.keep && d.known[job.index] == nil {
		d.known[job.index] = job.result
	} else {
		delete(job.result, runtime.heap_allocator())
	}
	if next, ok := d.pending.?; ok {
		d.pending = nil
		if dead, known := d.known[next.index].?; known && next.keep {
			if g.level_index == next.index {
				game.know_dead_ends(g, dead)
			}
		} else {
			start_dead_end_job(d, next)
		}
	}
}

// At the end: the worker waited for, the answers freed.
drop_dead_ends :: proc(d: ^Dead_Ends) {
	if d.worker != nil {
		thread.join(d.worker)
		thread.destroy(d.worker)
		delete(d.job.result, runtime.heap_allocator())
	}
	for &k in d.known {
		if dead, ok := k.?; ok {
			delete(dead, runtime.heap_allocator())
		}
		k = nil
	}
}
