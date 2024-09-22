# :construction_worker_man: Jobs
A simple and hackable job system for Odin.

Latest tested Odin version: `dev-2023-12-nightly:31b1aef4`

> [!NOTE]
> I've been working on a new version of this job system which is a complete rewrite for my new project.
> It has many advantages when dealing with batching and the implementation itself is way simpler and more flexible.
> I just haven't got around to fully polishing it and releasing it here.
> 
> The current version will be eventually deprecated but still available on V1 branch.

## Overview

The design is inspired by fiber-based job systems, most notably the one used at Naughty Dog.
(see [Parallelizing the Naughty Dog Engine](https://www.gdcvault.com/play/1022186/Parallelizing-the-Naughty-Dog-Engine)).

BUT This scheduler doesn't use fibers! The queued jobs are just executed directly on the waiting thread.
From an API perspective, this is basically the same as fibers.
It might require more stack space in your worker threads, but there is no need to allocate stacks for fibers.

Also there is no chance of ending up on another thread after using `wait`, so you can use TLS
and OS-provided synchronization primitives like Mutexes and Semaphores.

### Features:
- dispatching and waiting for jobs to finish
- nested jobs
- utilities for batch processing of slices/arrays
- full control over the thread processing loop
- support for Windows, Linux and Drawin

### Notes:
- the jobs are queued on a linked list (FILO queue)
- individual jobs are allocated with `context.temp_allocator` (or manually)
- jobs are intended to finish within one frame, but you can make long running tasks with a custom allocator.

## A simple hello world program
```odin
main :: proc() {
    jobs.initialize()

    g: jobs.Group
    jobs.dispatch(.Medium, jobs.make_job(&g, hello_job))
    jobs.wait(&g)

    jobs.shutdown()
}

hello_job :: proc(_: rawptr) {
    fmt.println("Hello from thread", jobs.current_thread_index())
}

```

## Examples
See the [examples](examples/) directory for all examples.

All examples:
- [hello](examples/hello/hello.odin) - a very basic introduction to jobs
- [simple](examples/simple/simple.odin) - simple overview with most of the features
- [boids](examples/boids/boids.odin) - boids simulation with Raylib
- [background](examples/background/background.odin) - long-running tasks over multiple frames
- [efficient_spinning](examples/efficient_spinning/efficient_spinning.odin) - using a custom thread proc to sleep whenever no jobs are available to save power

![boids](misc/boids.png)
![boids](misc/boids_spall.png)

## TODO
- improve the examples (boids are especially wonky)
- use atomic linked list instead of spinlocks
- Per-job debug labels
- Profiler integration (with `core:prof/spall` by default)

## Contributing
All contributions are welcome!
