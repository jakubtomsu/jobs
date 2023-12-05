// Generic platform backend using 'core:' libs

// +build linux, darwin
package jobs

import "core:os"
import "core:thread"

_Thread :: ^thread.Thread

_get_num_hardware_threads :: proc() -> int {
    return os.processor_core_count()
}

_create_worker_thread :: proc() -> _Thread {
    return thread.create_and_start(run_worker_thread)
}

_current_thread_id :: proc() -> u64 {
    return u64(os.current_thread_id())
}

_wait_for_threads_to_finish :: proc(threads: []Thread) {
    thread.join_multiple(..threads)
}
