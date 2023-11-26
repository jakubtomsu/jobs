// +build windows
package jobs

import "core:os"
import "core:runtime"
import "core:sys/windows"

foreign import kernel32 "system:Kernel32.lib"

SYSTEM_INFO :: struct {
    using _:                     struct #raw_union {
        dwOemId: windows.DWORD,
        using _: struct #raw_union {
            wProcessorArchitecture: windows.WORD,
            wReserved:              windows.WORD,
        },
    },
    dwPageSize:                  windows.DWORD,
    lpMinimumApplicationAddress: windows.LPVOID,
    lpMaximumApplicationAddress: windows.LPVOID,
    dwActiveProcessorMask:       windows.DWORD_PTR,
    dwNumberOfProcessors:        windows.DWORD,
    dwProcessorType:             windows.DWORD,
    dwAllocationGranularity:     windows.DWORD,
    wProcessorLevel:             windows.WORD,
    wProcessorRevision:          windows.WORD,
}

@(default_calling_convention = "stdcall")
foreign kernel32 {
    GetNativeSystemInfo :: proc(lpSystemInfo: ^SYSTEM_INFO) ---
    SetThreadAffinityMask :: proc(hThread: windows.HANDLE, dwThreadAffinityMask: windows.DWORD_PTR) -> windows.DWORD_PTR ---
}

_Thread :: windows.HANDLE

_get_num_hardware_threads :: proc() -> int {
    info: SYSTEM_INFO
    GetNativeSystemInfo(&info)
    return int(info.dwNumberOfProcessors)
}


_create_worker_thread :: proc() -> _Thread {
    handle := windows.CreateThread(nil, 0, _thread_start_routine, nil, 0, nil)

    if handle == nil {
        panic("Failed to create thread.")
    }

    return handle

    _thread_start_routine :: proc "stdcall" (param: windows.LPVOID) -> windows.DWORD {
        // HACK
        context = runtime.default_context()
        run_worker_thread()
        return 0
    }
}

_current_thread_id :: proc() -> u64 {
    return u64(windows.GetCurrentThreadId())
}

_wait_for_threads_to_finish :: proc(threads: []Thread) {
    if windows.WaitForMultipleObjects(windows.DWORD(len(threads)), &threads[0], true, windows.INFINITE) ==
       windows.WAIT_FAILED {
        panic("Failed to wait for threads to finish.")
    }
}
