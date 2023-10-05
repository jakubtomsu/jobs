package jobs

import "core:intrinsics"
import "core:sync"

Group :: struct {
	atomic_counter: u64,
}

Job_Proc :: #type proc(arg: rawptr)
Thread_Init_Proc :: #type proc(arg: rawptr)

Job :: struct {
	procedure: Job_Proc,
	arg:       rawptr,
	Group:   ^Group,
	_next:      ^Job,
}

Priority :: enum u8 {
	MEDIUM = 0,
	LOW,
	HIGH,
}

_state: struct {
	running:          bool,
	job_lists:   [Priority]Job_List,
	threads:          []Thread_Handle,
	thread_init_proc: Thread_Init_Proc,
	thread_init_arg:  rawptr,
	thread_init_counter: int,
}

Job_List :: struct {
	head: ^Job,
	mutex: sync.Atomic_Mutex,
}

@(thread_local)
_thread_state: struct {
	index: int,
}

make_job_typed :: proc(Group: ^Group, arg: ^$T, p: proc(arg: ^T)) -> Job {
	assert(Group != nil)
	assert(p != nil)
	return {
		procedure = cast(proc(a: rawptr))p,
		arg = rawptr(arg),
		Group = Group,
	}
}

make_job_raw :: proc(Group: ^Group, arg: rawptr, p: proc(arg: rawptr)) -> Job {
	assert(Group != nil)
	assert(p != nil)
	return {
		procedure = p,
		arg = arg,
		Group = Group,
	}
}

make_job_noarg :: proc(Group: ^Group, p: proc(arg: rawptr)) -> Job {
	assert(Group != nil)
	assert(p != nil)
	return {
		procedure = p,
		Group = Group,
	}
}

make_job :: proc {
	make_job_typed,
	make_job_raw,
	make_job_noarg,
}

run :: proc(jobs: []Job, priority: Priority = .MEDIUM) {
	_jobs := make([]Job, len(jobs), context.temp_allocator)
	copy(_jobs, jobs)
	for &job, i in _jobs {
		assert(job.Group != nil)
		intrinsics.atomic_add(&job.Group.atomic_counter, 1)
		if i < len(_jobs) - 1 {
			job._next = &_jobs[i + 1]
		}
	}

	sync.atomic_mutex_lock(&_state.job_lists[priority].mutex)
	_jobs[len(_jobs) - 1]._next = _state.job_lists[priority].head
	_state.job_lists[priority].head = &_jobs[0]
	sync.atomic_mutex_unlock(&_state.job_lists[priority].mutex)
}

wait :: proc(Group: ^Group) {
	for intrinsics.atomic_load(&Group.atomic_counter) > 0 {
		_run_queued_job()
	}
}

num_threads :: proc() -> int {
	return 1 + len(_state.threads)
}

current_thread_index :: proc() -> int {
	return _thread_state.index
}

@(private)
run_worker_thread :: proc(arg: rawptr) {
	_thread_state.index = intrinsics.atomic_add(&_state.thread_init_counter, 1)

	if _state.thread_init_proc != nil {
		_state.thread_init_proc(_state.thread_init_arg)
	}

	for _state.running {
		_run_queued_job()
	}
}

_run_queued_job :: proc() {
	block: for priority in Priority {
		if _state.job_lists[priority].head == nil {
			continue
		}

		for i in 0 ..< 4 {
			if sync.atomic_mutex_try_lock(&_state.job_lists[priority].mutex) {
				if job := _state.job_lists[priority].head; job != nil {
					_state.job_lists[priority].head = job._next
					sync.atomic_mutex_unlock(&_state.job_lists[priority].mutex)
		
					assert(job.Group != nil)
					assert(job.procedure != nil)

					job.procedure(job.arg)
					intrinsics.atomic_sub(&job.Group.atomic_counter, 1)
					break block
				}
				sync.atomic_mutex_unlock(&_state.job_lists[priority].mutex)
			}
		}
	}
}

initialize :: proc(
	num_worker_threads := -1,
	set_thread_affinity := false,
	thread_init_proc: proc(arg: rawptr) = nil,
	thread_init_arg: rawptr = nil,
) {
	if set_thread_affinity {
		_set_thread_affinity(_get_current_thread(), 1)
	}

	_state = {
		thread_init_proc = thread_init_proc,
		thread_init_arg = thread_init_arg,
		thread_init_counter = 1,
		running = true
	}

	// Main thread TLS
	_thread_state = {
		index = 0,
	}

	// Worker threads
	{
		num_hw_threads := _get_num_hardware_threads()
		num_threads := num_worker_threads < 0 ? (num_hw_threads - 1) : num_worker_threads

		if num_threads > 0 {
			_state.threads = make([]Thread_Handle, num_threads)

			for i in 0 ..< num_threads {
				thread := _create_worker_thread(nil)
				_state.threads[i] = thread

				if set_thread_affinity {
					_set_thread_affinity(thread, 1 << uint((i + 1) %% num_hw_threads))
				}
			}
		}
	}
}

shutdown :: proc() {
	_state.running = false
	if len(_state.threads) > 0 {
		_wait_for_threads_to_finish(_state.threads[:])
	}
	delete(_state.threads)
}