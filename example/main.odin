package main

import jobs ".."
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
        fmt.println("\nSIMPLE\n")

        g: jobs.Group

        f: f32 = 1
        a: int
        for i in 0 ..< 10 {
            jobs.run(
                {
                    jobs.make_job(&g, &f, proc(x: ^f32) {x^ = x^ * 2;fmt.println(x^)}),
                    jobs.make_job(&g, &a, proc(a: rawptr) {fmt.println(a)}),
                    jobs.make_job(&g, proc(_: rawptr) {fmt.println("Hey")}),
                },
            )
        }
        jobs.wait(&g)
    }

    {
        fmt.println("\nBENCHMARK\n")

        start := time.tick_now()
        g: jobs.Group



        fmt.println(time.tick_since(start))
    }

    fmt.println(jobs.num_threads())

    jobs.shutdown()
}
