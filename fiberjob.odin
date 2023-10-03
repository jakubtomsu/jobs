package fiberjob

import "core:fmt"
import "core:intrinsics"
import "core:sync"

MAX_THREADS :: 128
NUM_FIBERS :: 128

Counter :: struct {
	atomic_counter: u64,
	waiting_fiber:  int,
}

Job_Proc :: #type proc(arg: rawptr)
Thread_Init_Proc :: #type proc(arg: rawptr)

Job :: struct {
	procedure: Job_Proc,
	arg:       rawptr,
	label:     string,
	counter:   ^Counter,
	next:      ^Job,
}

Priority :: enum u8 {
	MEDIUM = 0,
	LOW,
	HIGH,
}

Job_Queue :: struct {
	jobs:  [1024]Job,
	len:   u64,
	mutex: sync.Atomic_Mutex,
}

_state: struct {
	running:          bool,
	queues:           [Priority]Job_Queue,
	threads:          []Thread_Handle,
	fibers:           [NUM_FIBERS]Fiber,
	idle_fibers:      ^Fiber,
	continue_fibers:  ^Fiber,
	job_head:         ^Job,
	thread_init_proc: Thread_Init_Proc,
	thread_init_arg:  rawptr,
}

Fiber :: struct {
	handle:  Fiber_Handle,
	counter: ^Counter,
	next:    ^Fiber,
}

// `jobs` need to live for the whole frame!
run_jobs :: proc(jobs: []Job, priority: Priority = .MEDIUM) {
	for &job, i in jobs[:len(jobs) - 1] {
		job.next = &jobs[i + 1]
	}

	_atomic_linked_list_push_front(&_state.job_head, &jobs[len(jobs) - 1].next, &jobs[0])

	// intrinsics.atomic_add(counter, Counter(len(jobs)))
	// sync.atomic_mutex_lock(&_state.queues[priority].mutex)
	// copy(_state.queues[priority].jobs[_state.queues[priority].len:], jobs)
	// sync.atomic_mutex_unlock(&_state.queues[priority].mutex)
}

wait :: proc(counter: ^Counter) {
	if intrinsics.atomic_load(counter) <= 0 {
		return
	}

	// counter.waiting_fiber = ...
}

_atomic_linked_list_push_front :: proc(head, next: ^$T, node: T) {
	for {
		if _, ok := intrinsics.atomic_compare_exchange_weak(head, next^, node); ok {
			return
		} else {
			next^ = head^.next
		}
	}
}

// current_fiber_index :: proc() -> int {

// }

// current_job_index :: proc() {

// }

// current_thread_index :: proc() {

// }

@(private)
run_worker_thread :: proc(arg: rawptr) {
	_convert_current_thread_to_fiber()

	fmt.println("Hello from thread!")

	for &fiber in _state.fibers {
		_switch_to_fiber(fiber.handle)
	}
}

@(private)
run_worker_fiber :: proc(arg: rawptr) {
	fmt.println("Hello from fiber!")

	for _state.running {
		fmt.println("Fiber Iter")

		for &queue, priority in _state.queues {
			if queue.len > 1 {
				if sync.atomic_mutex_try_lock(&queue.mutex) {
					job := queue.jobs[queue.len]
					queue.len -= 1
					sync.atomic_mutex_unlock(&queue.mutex)

					job.procedure(job.arg)

					if intrinsics.atomic_sub(job.counter, 1) == 0 {
						// switch to job.counter.waiting_fiber
					}
				}
			}
		}
	}
}

initialize :: proc(
	num_worker_threads := -1,
	set_thread_affinity := false,
	fiber_stack_size := 1024 * 1024,
	thread_init_proc: proc(arg: rawptr) = nil,
	thread_init_arg: rawptr = nil,
) {
	for i in 0 ..< NUM_FIBERS {
		_state.fibers[i] = {
			handle = _create_worker_fiber(uint(fiber_stack_size), nil),
		}
	}

	if set_thread_affinity {
		_set_thread_affinity(_get_current_thread(), 1)
	}

	_state.running = true

	// Worker threads
	{
		num_hw_threads := _get_num_hardware_threads()
		num_threads := num_worker_threads < 0 ? (num_hw_threads - 1) : num_worker_threads

		if num_threads > 0 {
			threads := make([]Thread_Handle, num_threads)

			for i in 0 ..< num_threads {
				thread := _create_worker_thread(nil)
				threads[i] = thread

				if set_thread_affinity {
					_set_thread_affinity(thread, 1 << uint((i + 1) %% num_hw_threads))
				}
			}
		}
	}
}

shutdown :: proc() {
	if len(_state.threads) > 0 {
		_wait_for_threads_to_finish(_state.threads[:])
	}
}


wait_to_finish_all :: proc() {

}
