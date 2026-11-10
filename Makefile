INPUT ?= input.glo

default:
	mkdir -p bin
	odin build src -out:bin/glsr -debug
	./bin/glsr input/$(INPUT)

clean:
	rm -r bin