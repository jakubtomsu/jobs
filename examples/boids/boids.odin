package jobs_example_boids

import common ".."
import jobs "../.."
import "core:fmt"
import "core:math/linalg"
import "core:math/rand"
import "core:runtime"
import "core:time"
import rl "vendor:raylib"

WINDOW_X :: CHUNKS_X * CHUNK_SIZE
WINDOW_Y :: CHUNKS_Y * CHUNK_SIZE

SEPARATION :: 200
ALIGNMENT :: 10

Run_Mode :: enum {
    Singlethreaded,
    Multithreaded,
}

Boid :: struct {
    pos:   [2]f32,
    vel:   [2]f32,
    force: [2]f32,
    rad:   f32,
}

CHUNK_MAX_BOIDS :: 64

CHUNKS_X :: 32
CHUNKS_Y :: 24

CHUNK_SIZE :: 30

Chunk :: struct {
    boids:     [CHUNK_MAX_BOIDS]u32,
    num_boids: u8,
}

Profile_Section :: enum {
    Frame,
    Update,
    Draw,
    Chunks_Pre_Update,
    Boids_Update,
    Chunks_Update,
}

_state: struct {
    run_mode:         Run_Mode,
    boids:            [dynamic]Boid,
    chunks:           [CHUNKS_X][CHUNKS_Y]Chunk,
    profile_sections: [Profile_Section]time.Duration,
}

chunk_is_in_bounds :: #force_inline proc(p: [2]int) -> bool {
    return p.x >= 0 && p.x < CHUNKS_X && p.y >= 0 && p.y < CHUNKS_Y
}

_end_section :: proc(section: Profile_Section, start: time.Tick) {
    _state.profile_sections[section] = time.tick_since(start)
    common.profile_end()
}

@(deferred_in_out = _end_section)
section :: proc(section: Profile_Section) -> time.Tick {
    common.profile_begin(fmt.tprint(section))
    return time.tick_now()
}

main :: proc() {
    rl.InitWindow(WINDOW_X, WINDOW_Y, "Boids - press X to change run mode")
    jobs.initialize(set_thread_affinity = true)
    common._profiler_init()

    for !rl.WindowShouldClose() {
        section(.Frame)

        free_all(context.temp_allocator)
        // Update
        {
            section(.Update)

            delta := rl.GetFrameTime()

            if rl.IsKeyPressed(.X) {
                _state.run_mode = Run_Mode((int(_state.run_mode) + 1) %% len(Run_Mode))
            }

            target := cast([2]f32)rl.GetMousePosition()

            if rl.IsMouseButtonPressed(.LEFT) {
                for _ in 0 ..< 1000 {
                    append(
                        &_state.boids,
                        Boid{
                            pos = target + {rand.float32_range(-100, 100), rand.float32_range(-100, 100)},
                            rad = 1,
                        },
                    )
                }
            }

            switch _state.run_mode {
            case .Singlethreaded:
                {
                    section(.Chunks_Pre_Update)
                    for x in 0 ..< CHUNKS_X {
                        for y in 0 ..< CHUNKS_Y {
                            chunk_pre_update(&_state.chunks[x][y])
                        }
                    }
                }

                {
                    section(.Boids_Update)
                    boids_update(_state.boids[:], 0, target, delta)
                }

                {
                    section(.Chunks_Update)
                    for x in 0 ..< CHUNKS_X {
                        for y in 0 ..< CHUNKS_Y {
                            chunk_update(&_state.chunks[x][y], {x, y}, delta)
                        }
                    }
                }

            case .Multithreaded:
                g: jobs.Group

                {
                    section(.Chunks_Pre_Update)

                    job_arr := new([CHUNKS_X]jobs.Job, context.temp_allocator)
                    for &job, i in job_arr {
                        job = jobs.make_job(&g, &_state.chunks[i], proc(chunks: ^[CHUNKS_Y]Chunk) {
                            common.profile_scope("Batch")

                            for &ch in chunks {
                                chunk_pre_update(&ch)
                            }
                        })
                    }

                    jobs.dispatch_jobs(.High, job_arr[:])

                    jobs.wait(&g)
                }

                {
                    section(.Boids_Update)

                    jobs.dispatch_batches(
                        &g,
                        data = _state.boids[:],
                        num_batches = -1,
                        priority = .High,
                        p = proc(b: ^jobs.Batch(Boid)) {
                            common.profile_scope("Batch")

                            boids_update(
                                b.data,
                                int(b.offset),
                                cast([2]f32)rl.GetMousePosition(),
                                rl.GetFrameTime(),
                            )
                        },
                    )

                    jobs.wait(&g)
                }

                {
                    section(.Chunks_Update)

                    Job :: struct {
                        job:       jobs.Job,
                        chunk_pos: [2]u16,
                    }
                    job_arr := make_soa(#soa[]Job, CHUNKS_X * CHUNKS_Y, context.temp_allocator)

                    for x in 0 ..< CHUNKS_X {
                        for y in 0 ..< CHUNKS_Y {
                            job := &job_arr[x + CHUNKS_X * y]
                            job^ = {
                                chunk_pos = {u16(x), u16(y)},
                                job = jobs.make_job(&g, &job.chunk_pos, proc(chunk_pos: ^[2]u16) {
                                    common.profile_scope("Batch")

                                    chunk_update(
                                        &_state.chunks[chunk_pos.x][chunk_pos.y],
                                        {int(chunk_pos.x), int(chunk_pos.y)},
                                        rl.GetFrameTime(),
                                    )
                                }),
                            }
                        }
                    }

                    job_slice, _ := soa_unzip(job_arr)
                    jobs.dispatch_jobs(.High, job_slice)

                    jobs.wait(&g)
                }
            }
        }


        // Draw
        {
            section(.Draw)

            rl.BeginDrawing()
            rl.ClearBackground(rl.BLACK)

            for x in 0 ..< CHUNKS_X {
                for y in 0 ..< CHUNKS_Y {
                    num := _state.chunks[x][y].num_boids
                    if num > 0 {
                        col: rl.Color = num > (CHUNK_MAX_BOIDS * 0.5) ? rl.ORANGE : {255, 150, 0, 40}
                        if num > CHUNK_MAX_BOIDS - 2 do col = rl.RED
                        rl.DrawRectangleV({f32(x), f32(y)} * CHUNK_SIZE, CHUNK_SIZE, col)
                    }
                }
            }

            for x in 1 ..< CHUNKS_X {
                rl.DrawLineV({f32(x) * CHUNK_SIZE, 0}, {f32(x) * CHUNK_SIZE, WINDOW_Y}, {255, 255, 255, 50})
            }

            for y in 1 ..< CHUNKS_Y {
                rl.DrawLineV({0, f32(y) * CHUNK_SIZE}, {WINDOW_X, f32(y) * CHUNK_SIZE}, {255, 255, 255, 50})
            }

            for b, i in _state.boids {
                rl.DrawRectangleV(rl.Vector2(b.pos - b.rad), rl.Vector2(b.rad * 2), rl.WHITE)
            }

            rl.DrawFPS(2, 2)

            rl.DrawText(fmt.ctprintf("Num boids: %i", len(_state.boids)), 2, 22, 20, rl.ORANGE)
            rl.DrawText(fmt.ctprintf("Run mode: %v", _state.run_mode), 2, 44, 20, rl.RED)
            rl.DrawText(fmt.ctprintf("Num threads: %i", jobs.num_threads()), 2, 66, 20, rl.RED)

            for sec, i in Profile_Section {
                rl.DrawText(
                    fmt.ctprintf(
                        "%v: %-4.3f ms",
                        sec,
                        f32(time.duration_milliseconds(_state.profile_sections[sec])),
                    ),
                    2,
                    88 + 22 * i32(i),
                    20,
                    rl.GRAY,
                )
            }

            rl.EndDrawing()
        }
    }

    common._profiler_shutdown()
    jobs.shutdown()
    rl.CloseWindow()
}

chunk_pre_update :: proc(chunk: ^Chunk) {
    chunk.num_boids = 0
}

boids_update :: proc(boids: []Boid, offset: int, target: [2]f32, delta: f32) {
    for &b, i in boids {
        b.vel += b.force * delta
        b.force = 0
        b.vel += linalg.normalize(target - b.pos) * 2
        // damping
        b.vel /= 1.0 + delta * 3

        b.pos += b.vel * delta

        chunk_pos: [2]int = {int(b.pos.x / CHUNK_SIZE), int(b.pos.y / CHUNK_SIZE)}

        if !chunk_is_in_bounds(chunk_pos) {
            continue
        }

        chunk := &_state.chunks[chunk_pos.x][chunk_pos.y]

        // Let's say we don't care what happens when too many boids are on one chunk.
        chunk.boids[chunk.num_boids] = u32(offset + i)
        chunk.num_boids = (chunk.num_boids + 1) % CHUNK_MAX_BOIDS
    }
}

// Probably way slower than it could be!!
chunk_update :: proc(chunk: ^Chunk, chunk_pos: [2]int, delta: f32) {
    boids := chunk.boids[:chunk.num_boids]
    for boid_index in boids {
        boid := &_state.boids[boid_index]

        for nx in -1 ..< 1 {
            for ny in -1 ..< 1 {
                n_pos: [2]int = {chunk_pos.x + nx, chunk_pos.y + ny}

                if !chunk_is_in_bounds(n_pos) {
                    continue
                }

                n_chunk := _state.chunks[n_pos.x][n_pos.y]
                n_boids := chunk.boids[:chunk.num_boids]
                for n_boid_index in n_boids {
                    n_boid := _state.boids[n_boid_index]

                    MAX_DIST :: CHUNK_SIZE

                    dist := linalg.length(boid.pos - n_boid.pos)

                    if dist < 0.05 || dist > MAX_DIST {
                        continue
                    }

                    dist = 1.0 - dist / MAX_DIST

                    force: [2]f32

                    force += linalg.normalize(boid.pos - n_boid.pos) * dist * SEPARATION
                    force += boid.vel * dist * ALIGNMENT

                    boid.force += force * delta
                }
            }
        }
    }
}
