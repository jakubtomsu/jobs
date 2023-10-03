package fiberjob

import "core:fmt"

MAX_THREADS :: 128
NUM_FIBERS :: 128

Counter :: struct {
	atomic_counter: u16,
	waiting_jobs:   ^Waiting_Job,
}

Job_Proc :: #type proc(arg: rawptr)

Job :: struct {
	p:        Job_Proc,
	arg:      rawptr,
	priority: Priority,
	label:    string,
}

Priority :: enum u8 {
	MEDIUM = 0,
	LOW,
	HIGH,
}

Waiting_Job :: struct {
	next_waiting_job: ^Waiting_Job,
}

_state: struct {
	running: bool,
	queues:  [Priority]Job,
	fibers:  [NUM_FIBERS]Fiber_Handle,
}

run_jobs :: proc(counter: ^Counter, job: Job_Proc) {

}

wait :: proc(counter: ^Counter) {

}

// current_fiber_index :: proc() -> int {

// }

// current_job_index :: proc() {

// }

// current_thread_index :: proc() {

// }

@(private)
run_worker_thread :: proc(arg: rawptr) {

}

@(private)
run_worker_fiber :: proc(arg: rawptr) {
	i := 0
	for _state.running {
		fmt.println("Hello", i)
		i += 1
	}
}

initialize :: proc(
	num_worker_threads := -1,
	set_thread_affinity := false,
	fiber_stack_size := 1024 * 1024,
) {
	for i in 0 ..< NUM_FIBERS {
		_state.fibers[i] = _create_worker_fiber(uint(fiber_stack_size), nil)
	}
}

shutdown :: proc() {

}


wait_to_finish_all :: proc() {

}
