package main

import fj ".."
import "core:fmt"

main :: proc() {
	fmt.println("Hey")

	fj.initialize(num_worker_threads = -1)

	fmt.println("Hey2")

	for i in 0..<300 do fmt.print(".")
	fmt.println()

	g: fj.Group

	f: f32 = 1
	a: int
	for i in 0..<10 do fj.run({
		fj.make_job(&g, &f, proc(x: ^f32) {x ^= x^ * 2; fmt.println(x^)}),
		fj.make_job(&g, &a, proc(a: rawptr) {fmt.println(a)}),
		fj.make_job(&g, proc(rawptr) {fmt.println("Hey")})
	}
	)

	fj.wait(&g)

	fmt.println(fj.num_threads())

	fj.shutdown()
}
