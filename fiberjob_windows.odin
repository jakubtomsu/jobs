package fiberjob

import "core:sys/windows"

_get_num_hardware_threads :: proc() -> int {
    info: windows.SYSTEM_INFO
    windows.GetNativeSystemInfo(&info)
    return int(info.dwNumberOfProcessors);
}

_create_worker_thread :: proc(param: rawptr) {
    handle = windows.CreateThread(nil, 0, _worker_thread_start_routine, param)
}
