INPUT ?= input.glo

default:
	mkdir -p bin
	odin build src -out:bin/glsr
	./bin/glsr input/$(INPUT)