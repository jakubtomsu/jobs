package jobs_example_simple

import jobs "../.."
import "core:fmt"
import "core:time"


main :: proc() {
    jobs.initialize(
        num_worker_threads = -1,
        set_thread_affinity = true,
        thread_init_proc = proc(_: rawptr) {fmt.println("Hello from thread", jobs.current_thread_index())},
    )

    // sleep for a moment so all threads have time to init
    time.sleep(time.Second)

    {
        section("simple")

        g: jobs.Group

        f: f32 = 1
        a: int
        for i in 0 ..< 10 {
            jobs.dispatch(
                .Medium,
                jobs.make_job(&g, &f, proc(x: ^f32) {x^ = x^ * 2;fmt.println(x^)}),
                jobs.make_job(&g, &a, proc(a: rawptr) {fmt.println(a)}),
                jobs.make_job(&g, proc(_: rawptr) {fmt.println("Hey")}),
            )
        }
        jobs.wait(&g)
    }

    {
        section("batches")

        data := make([]int, 50)
        for &x, i in data do x = i

        g: jobs.Group
        jobs.dispatch_batches(&g, data, 5, p = proc(b: ^jobs.Batch(int)) {
            fmt.printf("    %i: %v\n", b.index, b.data)
        })
        jobs.wait(&g)
    }

    {
        section("batches fixed")

        data := make([]int, 50)
        for &x, i in data do x = i

        g: jobs.Group
        jobs.dispatch_batches_fixed(&g, data, 5, p = proc(b: ^jobs.Batch(int)) {
            fmt.printf("    %i: %v\n", b.index, b.data)
        })
        jobs.wait(&g)
    }

    {
        Ball :: struct {
            pos: [3]f32,
            vel: [3]f32,
            rad: f32,
            damping: f32,
            bounce_factor: f32,
            some_data: [4]i32,
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
        for i in 0..<10 {
            jobs.dispatch(.Low, jobs.make_job(&g, proc(_: rawptr) {fmt.println("Low"); time.sleep(time.Millisecond * 100)}))
            jobs.dispatch(.Medium, jobs.make_job(&g, proc(_: rawptr) {fmt.println("Medium"); time.sleep(time.Millisecond * 100)}))
            jobs.dispatch(.High, jobs.make_job(&g, proc(_: rawptr) {fmt.println("High"); time.sleep(time.Millisecond * 100)}))
        }

        jobs.wait(&g)
    }

    fmt.println(jobs.num_threads())

    jobs.shutdown()
}

_end_section :: proc(name: string, start: time.Tick) {
    fmt.printf("%s: %v microseconds\n", name, time.duration_microseconds(time.tick_since(start)))
}

@(deferred_in_out = _end_section)
section :: proc(name: string) -> time.Tick {
    fmt.println(name)
    return time.tick_now()
}