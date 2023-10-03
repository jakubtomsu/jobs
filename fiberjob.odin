package fiberjob

Counter :: struct {
    atomic_counter: u16,
    waiting_jobs: ^Waiting_Job,
}

Job_Proc :: #type proc(arg: rawptr)

Job :: strut {
    proc: Job_Proc,
    arg: rawptr,
    priority: Priority,
    label: string,
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
    queues: [Priority]Job,
}

initialize :: proc(num_worker_threads := -1, set_thread_affinity := false) {

}

shutdown :: proc() {

}

run_jobs :: proc(counter: ^Counter, job: Job_Proc) {

}

wait :: proc(counter: ^Counter) {

}

current_fiber_index :: proc() -> int {

}

current_job_index :: proc() {

}

current_thread_index :: proc() {

}


