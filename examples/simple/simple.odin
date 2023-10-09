package jobs_example_simple

import common ".."
import jobs "../.."
import "core:fmt"
import "core:math/rand"
import "core:time"

main :: proc() {

    jobs.initialize(num_worker_threads = -1, set_thread_affinity = false, thread_proc = proc(_: rawptr) {
            fmt.println("Hello from thread", jobs.current_thread_index())
            for jobs.is_running() {
                jobs._run_queued_jobs()
            }
        })

    common._profiler_init()

    // sleep for a moment so all threads have time to init
    time.sleep(time.Second)

    {
        section("simple")

        g: jobs.Group

        f: f32 = 1
        a: int
        for i in 0 ..< 10 {
            jobs.dispatch(.Medium, jobs.make_job(&g, &f, proc(x: ^f32) {
                    common.profile_scope("A")
                    x^ = x^ * 2
                    fmt.println(x^)
                }), jobs.make_job(&g, &a, proc(a: rawptr) {
                    common.profile_scope("B")
                    fmt.println(a)
                }), jobs.make_job(&g, proc(_: rawptr) {
                    common.profile_scope("C")
                    fmt.println("Hey")
                }))
        }
        jobs.wait(&g)
    }

    {
        section("batches")

        data := make([]int, 50)
        for &x, i in data do x = i

        g: jobs.Group
        jobs.dispatch_batches(&g, data, 7, p = proc(b: ^jobs.Batch(int)) {
                common.profile_scope("Batch")
                fmt.printf("    %i: %i + %v (len %i)\n", b.index, b.offset, b.data, len(b.data))
            })
        jobs.wait(&g)
    }

    {
        section("batches fixed")

        data := make([]int, 50)
        for &x, i in data do x = i

        g: jobs.Group
        jobs.dispatch_batches_fixed(&g, data, 7, p = proc(b: ^jobs.Batch(int)) {
                common.profile_scope("Batch")
                fmt.printf("    %i: %i + %v (len %i)\n", b.index, b.offset, b.data, len(b.data))
            })
        jobs.wait(&g)
    }

    {
        section("balls")

        Ball :: struct {
            pos:           [3]f32,
            vel:           [3]f32,
            rad:           f32,
            damping:       f32,
            bounce_factor: f32,
            some_data:     [4]i32,
        }

        // hehe balls
        balls := make([]Ball, 100000)

        {
            section("balls: singlethreaded")
            update_balls(balls)
        }

        for batch_size in ([]int{1, 10, 100, 500, 1000, 5000, 10000}) {
            section(fmt.tprintf("balls: batches of size %i", batch_size))
            g: jobs.Group
            jobs.dispatch_batches_fixed(&g, balls, batch_size = batch_size, p = proc(b: ^jobs.Batch(Ball)) {
                    common.profile_scope("Batch")
                    update_balls(b.data)
                })
            jobs.wait(&g)
        }

        update_balls :: proc(balls: []Ball) {
            for &b in balls {
                b.vel.y -= 9.81
                b.vel /= 1.0 + b.damping
                b.pos += b.vel
                if b.pos.y - b.rad < 0.0 {
                    b.pos.y = b.rad
                    b.vel.y = abs(b.vel.y)
                    b.vel *= b.bounce_factor
                }

                // random stuff
                for &d in b.some_data {
                    d *= d + 1
                    if d > 100 {
                        d -= 50
                    }
                }
            }
        }
    }

    {
        section("priorities")

        g: jobs.Group
        {
            common.profile_scope("dispatch")
            for i in 0 ..< 100 {
                jobs.dispatch(.Low, jobs.make_job(&g, proc(_: rawptr) {
                        common.profile_scope("Low")
                        fmt.println("Low")
                        time.sleep(time.Microsecond * time.Duration(100 + rand.int31_max(100)))
                    }))
                jobs.dispatch(.Medium, jobs.make_job(&g, proc(_: rawptr) {
                        common.profile_scope("Medium")
                        fmt.println("Medium")
                        time.sleep(time.Microsecond * time.Duration(100 + rand.int31_max(100)))
                    }))
                jobs.dispatch(.High, jobs.make_job(&g, proc(_: rawptr) {
                        common.profile_scope("High")
                        fmt.println("High")
                        time.sleep(time.Microsecond * time.Duration(100 + rand.int31_max(100)))
                    }))
            }
        }

        jobs.wait(&g)
    }

    {
        // Measure how much useful code is executed
        section("overhead")

        Foo :: struct {
            a, b, c: [3]f32,
            data:    [8]u64,
        }

        // hehe foos
        foos := make([]Foo, 100000)

        start: time.Tick
        st_duration: time.Duration
        {
            start = section("foos: singlethreaded")
            update_foos(foos)
            st_duration = time.tick_since(start)
        }

        for batch_size in ([]int{1, 10, 100, 1000, 10000}) {
            start = section(fmt.tprintf("foos: batches of size %i", batch_size))
            g: jobs.Group
            jobs.dispatch_batches_fixed(&g, foos, batch_size = batch_size, p = proc(b: ^jobs.Batch(Foo)) {
                    common.profile_scope("Batch")
                    update_foos(b.data)
                })
            jobs.wait(&g)
            dur := time.tick_since(start)
            faster := time.duration_microseconds(st_duration) / time.duration_microseconds(dur)
            fmt.println("  ", faster, " x faster (target = ", jobs.num_threads(), " x)", sep = "")

        }

        update_foos :: proc(foos: []Foo) {
            for &x in foos {
                // do random crap
                x.a *= 2
                x.b += x.a
                x.c = x.a.zzy * x.b.zxy
                x.a += x.c * x.c * 2
                for &d, i in x.data {
                    d += 2
                    d *= 2
                    d ~= 0xffaaffaa
                    d += u64(i % 2 == 0 ? x.a.z : x.b[i % 3])
                }
            }
        }
    }

    {
        section("nested")

        g: jobs.Group
        g2: jobs.Group

        for i in 0 ..< 5 {
            jobs.dispatch(.Medium, jobs.make_job(&g, proc(_: rawptr) {
                    common.profile_scope("A")

                    time.sleep(time.Millisecond * 200)
                    g: jobs.Group

                    for i in 0 ..< 5 {
                        jobs.dispatch(.Low, jobs.make_job(&g, proc(_: rawptr) {
                                common.profile_scope("A2")
                                time.sleep(time.Millisecond * 300)
                            }))
                    }

                    jobs.wait(&g)
                }))

            jobs.dispatch(.Medium, jobs.make_job(&g, &g2, proc(g: ^jobs.Group) {
                    common.profile_scope("B")
                    time.sleep(time.Millisecond * 500)

                    jobs.dispatch(.High, jobs.make_job(g, proc(_: rawptr) {
                            common.profile_scope("B2")
                            time.sleep(100)
                        }))
                }))
        }

        jobs.wait(&g)

        jobs.dispatch(.Medium, jobs.make_job(&g, &g2, proc(g: ^jobs.Group) {
                common.profile_scope("Wait job")
                jobs.wait(g)
                time.sleep(time.Second)
                fmt.println("done")
            }))

        jobs.wait(&g)
    }

    fmt.println("num_threads", jobs.num_threads())

    common._profiler_shutdown()

    jobs.shutdown()
}

_end_section :: proc(name: string, start: time.Tick) {
    fmt.printf("%s: %v microseconds\n", name, time.duration_microseconds(time.tick_since(start)))
    common.profile_end()
}

@(deferred_in_out = _end_section)
section :: proc(name: string) -> time.Tick {
    fmt.println(name)
    common.profile_begin(fmt.tprintf("Section %s", name))
    return time.tick_now()
}
