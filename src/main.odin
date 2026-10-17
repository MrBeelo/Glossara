package glsr

import "core:fmt"

// Απλός διερμηνευτής της ΓΛΩΣΣΑΣ.

main :: proc() {
	tokens := lexer("hellope <- 3 MOD 6")
	fmt.printf("%v", tokens)
}

