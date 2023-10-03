package main

import fj ".."
import "core:fmt"

main :: proc() {
	fmt.println("Hey")

	fj.initialize(num_worker_threads = -1)

	fmt.println("Hey2")

	c: fj.Counter
	fj.run_jobs(&c)

	fj.shutdown()
}
