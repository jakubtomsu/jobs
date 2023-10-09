package game

import jobs ".."

PROFILER_ENABLED :: #config(PROFILER_ENABLED, true)

import "core:prof/spall"

when PROFILER_ENABLED {
    @(private = "file")
    _profiler: struct {
        spall_ctx: spall.Context,
        buffers:   []Profiler_Buffer,
    }
}

Profiler_Buffer :: struct {
    buffer:  spall.Buffer,
    backing: []u8,
}

@(disabled = !PROFILER_ENABLED)
profile_begin :: proc(name := "", args := "", location := #caller_location) {
    when PROFILER_ENABLED {
        spall._buffer_begin(
            &_profiler.spall_ctx,
            &_profiler.buffers[jobs.current_thread_index()].buffer,
            name,
            args,
            location,
        )
    }
}

@(disabled = !PROFILER_ENABLED)
profile_end :: proc() {
    when PROFILER_ENABLED {
        spall._buffer_end(&_profiler.spall_ctx, &_profiler.buffers[jobs.current_thread_index()].buffer)
    }
}

@(disabled = !PROFILER_ENABLED, deferred_none = profile_end)
profile_scope :: proc(name := "", args := "", location := #caller_location) {
    profile_begin(name, args, location)
}

_profiler_init :: proc() {
    when PROFILER_ENABLED {
        _profiler.spall_ctx = spall.context_create("trace.spall")
        _profiler.buffers = make([]Profiler_Buffer, jobs.num_threads())
        for &buf, i in _profiler.buffers {
            buf.backing = make([]u8, spall.BUFFER_DEFAULT_SIZE)
            buf.buffer = spall.buffer_create(buf.backing, u32(i))
        }
    }
}

_profiler_shutdown :: proc() {
    when PROFILER_ENABLED {
        for &buf in _profiler.buffers {
            spall.buffer_destroy(&_profiler.spall_ctx, &buf.buffer)
            // delete(buf.backing)
        }
        spall.context_destroy(&_profiler.spall_ctx)
    }
}
