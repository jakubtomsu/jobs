package jobs_examples_efficient_spinning

import jobs "../.."
import "core:fmt"
import "core:sys/windows"
import "core:time"

counter: int

main :: proc() {
    when ODIN_OS == .Windows {
        windows.timeBeginPeriod(1)
    }

    jobs.initialize(thread_proc = proc(_: rawptr) {
            for jobs.is_running() {
                if !jobs.try_execute_queued_job() {
                    time.sleep(2 * time.Millisecond)
                }
            }
        })

    frame: int
    for {
        frame += 1
        fmt.println("frame:", frame, "counter:", counter)

        // Arbitrary per-frame work
        g: jobs.Group
        for i in 0 ..< 50 {
            jobs.dispatch(.Medium, jobs.make_job(&g, proc(_: rawptr) {
                    for i in 0 ..< 1000 {
                        counter += 1
                    }
                }))
        }
        jobs.wait(&g)
    }
}
