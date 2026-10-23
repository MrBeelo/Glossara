package glsr

import "core:fmt"
import "base:runtime"

// Απλός διερμηνευτής της ΓΛΩΣΣΑΣ.

main :: proc() {
	tokens := tokenize("hellope <- NOT >= (-4.5356)*7")
	for token in tokens do fmt.printf("%v\n", token)
}

error :: proc(stage: enum{LEXER, PARSER}, pos: int, message: string, args: ..any, loc := #caller_location) -> ! {
	p := context.assertion_failure_proc
	if p == nil do p = runtime.default_assertion_failure_proc

	stage_str := string(fmt.ctprintf("%v", stage))
	format := string(fmt.ctprintf(message, ..args))
	final := string(fmt.ctprintf("%s (pos: %d)", format, pos))
	p(stage_str, final, loc)
}