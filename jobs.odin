// Jobs
// A simple job system for Odin.
//
// The design is inspired by fiber-based job systems, most notably the one used at Naughty Dog
// (see https://www.gdcvault.com/play/1022186/Parallelizing-the-Naughty-Dog-Engine)
//
// BUT! This job system doesn't use any fibers at all.
// Instead of using fibers, this job system just directly runs queued job
// in the waiting thread. From an API perspective, this is the same as fibers.
// It might require more stack space in your worker threads, but there is no
// need to allocate stacks for fibers.
//
// Features:
// - dispatching and waiting for jobs to finish
// - nested jobs
// - utilities for batch processing of slices/arrays
// - full control over the thread processing loop
//
// Notes:
// - the jobs are queued on a linked list (FILO queue)
// - the individual jobs are allocated with context.temp_allocator (or manually allocated)
package jobs

import "core:intrinsics"
import "core:log"
import "core:math"
import "core:sync"
import "core:mem"

Group :: struct {
    atomic_counter: u64,
}

Job_Proc :: #type proc(arg: rawptr)
Thread_Proc :: #type proc(arg: rawptr)

Job :: struct {
    procedure: Job_Proc,
    arg:       rawptr,
    group:     ^Group,
    _next:     ^Job,
}

Priority :: enum u8 {
    Medium = 0,
    Low,
    High,
}

_state: struct {
    running:        bool,
    job_lists:      [Priority]Job_List,
    threads:        []Thread_Handle,
    thread_proc:    Thread_Proc,
    thread_arg:     rawptr,
    thread_counter: int,
	allocator:      ^mem.Allocator,
}

Job_List :: struct {
    head:  ^Job,
    mutex: sync.Atomic_Mutex,
}

@(thread_local)
_thread_state: struct {
    index: int,
}


num_threads :: proc() -> int {
    return 1 + len(_state.threads)
}

current_thread_index :: proc() -> int {
    return _thread_state.index
}

current_thread_id :: proc() -> u32 {
    return _current_thread_id()
}

is_running :: proc() -> bool {
    return _state.running
}

make_job_typed :: proc(group: ^Group, arg: ^$T, p: proc(arg: ^T)) -> Job {
    assert(group != nil)
    assert(p != nil)
    return {procedure = cast(proc(a: rawptr))p, arg = rawptr(arg), group = group}
}

make_job_raw :: proc(group: ^Group, arg: rawptr, p: proc(arg: rawptr)) -> Job {
    assert(group != nil)
    assert(p != nil)
    return {procedure = p, arg = arg, group = group}
}

make_job_noarg :: proc(group: ^Group, p: proc(arg: rawptr)) -> Job {
    assert(group != nil)
    assert(p != nil)
    return {procedure = p, group = group}
}

make_job :: proc {
    make_job_typed,
    make_job_raw,
    make_job_noarg,
}

Batch :: struct($T: typeid) {
    data:   []T,
    index:  i32,
    offset: i32,
}

// Process slice in a fixed number of batches.
dispatch_batches :: proc(
    group: ^Group,
    data: []$T,
    num_batches := 0,
    priority: Priority = .Medium,
    p: proc(batch: ^Batch(T)),
) {
    num_batches := num_batches

    if len(data) <= 0 {
        return
    }

    if num_batches <= 0 {
        num_batches = num_threads()
    }

    dispatch_batches_fixed(
        group = group,
        data = data,
        batch_size = div_ceil(len(data), num_batches),
        priority = priority,
        p = p,
    )
}

// Process slice in batches of fixed size.
// Note: batch_size is the _maximum_ batch size.
dispatch_batches_fixed :: proc(
    group: ^Group,
    data: []$T,
    batch_size := 1,
    priority: Priority = .Medium,
    p: proc(batch: ^Batch(T)),
) {
    assert(p != nil)
    assert(batch_size > 0)
    assert(group != nil)

    if len(data) <= 0 {
        return // nothing to process
    }

    num_batches := div_ceil(len(data), batch_size)

    jobs := make_slice([]Job, num_batches, _state.allocator)
    batches := make_slice([]Batch(T), num_batches, _state.allocator)

    for &batch, i in batches {
        offset := i * batch_size
        batch = {
            index  = i32(i),
            offset = i32(offset),
            data   = data[offset:min(offset + batch_size, len(data))],
        }
    }

    for &job, i in jobs {
        job = {
            procedure = Job_Proc(p),
            group     = group,
            arg       = &batches[i],
        }
    }

    dispatch_jobs(priority, jobs)
}

@(private)
div_ceil :: proc(a, b: int) -> int {
    return (a + b - 1) / b
}

dispatch :: proc(priority: Priority = .Medium, jobs: ..Job) {
    _jobs := make([]Job, len(jobs), _state.allocator^)
    copy(_jobs, jobs)
    dispatch_jobs(priority, _jobs)
}

// Push jobs to the queue for the given priority.
dispatch_jobs :: proc(priority: Priority, jobs: []Job) {
    for &job, i in jobs {
        assert(job.group != nil)
        intrinsics.atomic_add(&job.group.atomic_counter, 1)
        if i < len(jobs) - 1 {
            job._next = &jobs[i + 1]
        }
    }

    sync.atomic_mutex_lock(&_state.job_lists[priority].mutex)
    jobs[len(jobs) - 1]._next = _state.job_lists[priority].head
    _state.job_lists[priority].head = &jobs[0]
    sync.atomic_mutex_unlock(&_state.job_lists[priority].mutex)
}

// Block the current thread until all jobs in the group are finished.
// Other queued jobs are executed while waiting.
wait :: proc(group: ^Group) {
    for !group_is_finished(group) {
        _run_queued_jobs()
    }
    group^ = {}
}

// Check if all jobs in the group are finished.
@(require_results)
group_is_finished :: #force_inline proc(group: ^Group) -> bool {
    return intrinsics.atomic_load(&group.atomic_counter) <= 0
}

@(private)
run_worker_thread :: proc(arg: rawptr) {
    _thread_state.index = intrinsics.atomic_add(&_state.thread_counter, 1)

    if _state.thread_proc != nil {
        _state.thread_proc(_state.thread_arg)
    }
}

default_thread_proc :: proc(_: rawptr) {
    for _state.running {
        if !_run_queued_jobs() {
            intrinsics.cpu_relax()
        }
    }
}

_run_queued_jobs :: proc() -> (result: bool) {
    ORDERED_PRIORITIES :: [len(Priority)]Priority{.High, .Medium, .Low}

    block: for priority in ORDERED_PRIORITIES {
        if _state.job_lists[priority].head == nil {
            continue
        }

        if sync.atomic_mutex_try_lock(&_state.job_lists[priority].mutex) {
            if job := _state.job_lists[priority].head; job != nil {
                _state.job_lists[priority].head = job._next
                sync.atomic_mutex_unlock(&_state.job_lists[priority].mutex)

                assert(job.group != nil)
                assert(job.procedure != nil)

                job.procedure(job.arg)
                intrinsics.atomic_sub(&job.group.atomic_counter, 1)
                result = true
                break block
            }
            sync.atomic_mutex_unlock(&_state.job_lists[priority].mutex)
        }
    }

    return
}

// Spawns all threads.
initialize :: proc(
    num_worker_threads := -1,
    set_thread_affinity := false,
    thread_proc := default_thread_proc,
    thread_arg: rawptr = nil,
    create_suspended_threads := false,
	allocator_param : ^mem.Allocator,
) {
    if set_thread_affinity {
        _set_thread_affinity(_current_thread(), 1)
    }

    _state = {
        thread_proc    = thread_proc,
        thread_arg     = thread_arg,
        thread_counter = 1,
        running        = true,
		allocator = allocator_param,
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
                thread := _create_worker_thread(nil, create_suspended_threads)
                _state.threads[i] = thread

                if set_thread_affinity {
                    _set_thread_affinity(thread, 1 << uint((i + 1) %% num_hw_threads))
                }
            }
        }
    }
}

// Stop all threads and wait for them to finish.
shutdown :: proc() {
    _state.running = false
    if len(_state.threads) > 0 {
        _wait_for_threads_to_finish(_state.threads[:])
    }
    delete(_state.threads)
}
