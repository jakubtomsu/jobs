package fiberjob

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

Thread_Handle :: windows.HANDLE
Fiber_Handle :: windows.LPVOID

_get_num_hardware_threads :: proc() -> int {
	info: SYSTEM_INFO
	GetNativeSystemInfo(&info)
	return int(info.dwNumberOfProcessors)
}

_create_worker_thread :: proc(param: rawptr) -> Thread_Handle {
	handle := windows.CreateThread(nil, 0, _thread_start_routine, param, 0, nil)

	if handle == nil {
		panic("Failed to create thread.")
	}

	return handle


	_thread_start_routine :: proc "stdcall" (param: windows.LPVOID) -> windows.DWORD {
		// HACK
		context = runtime.default_context()
		run_worker_thread(param)
		return 0
	}
}

_set_thread_affinity :: proc(handle: Thread_Handle, affinity: uint) {
	if SetThreadAffinityMask(handle, affinity) == 0 {
		panic("Failed to set thread affinity.")
	}
}

_create_worker_fiber :: proc(stack_size: uint, arg: rawptr) -> Fiber_Handle {
	result := windows.CreateFiber(stack_size, _fiber_start_routine, arg)

	if result == nil {
		panic("Failed to create worker fiber.")
	}

	return result

	_fiber_start_routine :: proc "stdcall" (arg: windows.LPVOID) {
		// HACK
		context = runtime.default_context()
		run_worker_fiber(arg)
	}
}

_switch_to_fiber :: proc(handle: Fiber_Handle) {
	windows.SwitchToFiber(handle)
}

// Pseudo-handle!
_get_current_thread :: proc() -> Thread_Handle {
	return windows.GetCurrentThread()
}

_convert_current_thread_to_fiber :: proc() {
	if windows.ConvertThreadToFiber(nil) == nil {
		panic("Failed to convert current thread to fiber.")
	}
}

_wait_for_threads_to_finish :: proc(threads: []Thread_Handle) {
	if windows.WaitForMultipleObjects(
		   windows.DWORD(len(threads)),
		   &threads[0],
		   true,
		   windows.INFINITE,
	   ) !=
	   windows.WAIT_FAILED {
		panic("Failed to wait for threads to finish.")
	}
}
