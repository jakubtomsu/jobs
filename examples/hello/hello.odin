package jobs_example_hello

import jobs "../.."
import "core:fmt"

main :: proc() {
    // Initialize the job system. Uses all CPU cores by default.
    jobs.initialize()

    //
    // One simple job
    //

    // A job group allows you to wait for some jobs to finish.
    g: jobs.Group

    // Dispatch adds the job to a queue for the given priority
    jobs.dispatch(.Medium, jobs.make_job(&g, hello_job))

    // Wait for the job to finish. This blocks the current thread and
    // runs queued jobs until all jobs in the job group are finished.
    jobs.wait(&g)

    //
    // Nested job with arguments
    //

    fmt.println("Many hellos:")

    // This is a variable with arguments passed into the `many_hello_job`.
    // Be careful aboiut the lifetime of job arguments!
    // Most of the time it's ok to use a variable stored on the stack, but more
    // complex tasks might require you to use some allocator.
    many_hello_arg := Many_Hello_Args{10}

    jobs.dispatch(.Medium, jobs.make_job(&g, &many_hello_arg, many_hello_job))

    // This automatically also waits for the nested jobs.
    jobs.wait(&g)

    // Shutdown the job system. This will stop all worker threads.
    jobs.shutdown()
}

hello_job :: proc(_: rawptr) {
    fmt.println("Hello from thread", jobs.current_thread_index())
}

// Job args can be a pointer to any data, but using structs to pack all of the argument is better for consistency
Many_Hello_Args :: struct {
    num: int,
}

many_hello_job :: proc(arg: ^Many_Hello_Args) {
    // Jobs can be nested
    g: jobs.Group

    for i in 0 ..< arg.num {
        jobs.dispatch(.High, jobs.make_job(&g, hello_job))
    }

    jobs.wait(&g)

    fmt.println("Done!")
}

// The program prints something like this:
//
// Hello from thread 3
// Many hellos:
// Hello from thread 0
// Hello from thread 0
// Hello from thread 0
// Hello from thread 5
// Hello from thread 6
// Hello from thread 7
// Hello from thread 2
// Hello from thread 1
// Hello from thread 3
// Hello from thread 4
// Done!
