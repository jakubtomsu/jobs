package jobs_example_background

import common ".."
import jobs "../.."
import "core:fmt"

frame: int
counter: int

main :: proc() {
    jobs.initialize(num_worker_threads = 1)
    common._profiler_init()

    g: jobs.Group

    // For this to work without stalling the main thread we need more than 1 thread.
    assert(jobs.num_threads() > 1)

    // Dispatch long-lived job on any thread other than the main thread.
    // Warning: you are responsible for freeing the memory.
    // That's why all short-lived jobs should just use context.temp_allocator
    bg_jobs := jobs.dispatch(
        .Medium,
        jobs.make_job(&g, background_job, ignored_threads = jobs.Ignored_Threads{jobs.MAIN_THREAD_INDEX}),
        allocator = context.allocator,
    )

    for !jobs.group_is_finished(&g) {
        free_all(context.temp_allocator)
        fmt.printf("Frame %i\n", frame)
        frame += 1

        short_g: jobs.Group
        for i in 0 ..< 5 {
            jobs.dispatch(.Low, jobs.make_job(&short_g, proc(_: rawptr) {
                    fmt.println("  short job")
                }))
        }

        jobs.wait(&short_g)
    }

    fmt.println("Background job finished!")
    fmt.println("Counter:", counter)
    fmt.println("Frame:", frame)

    delete(bg_jobs)

    common._profiler_shutdown()
    jobs.shutdown()
}

background_job :: proc(_: rawptr) {
    for frame < 100 {
        fmt.println("waiting for frame 100")
    }

    g: jobs.Group
    for i in 0 ..< 5 {
        jobs.dispatch(.High, jobs.make_job(&g, proc(_: rawptr) {
                fmt.println("  background child job")
            }))
    }

    N :: 1_000_000
    fmt.println("Count to", N)
    for i in 0 ..< N {
        counter += 1
    }

    jobs.wait(&g)
}
