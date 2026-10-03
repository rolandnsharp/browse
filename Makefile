PREFIX ?= $(HOME)/.local

browse: browse.nim
	nim c -d:release --opt:size --hints:off -o:browse browse.nim

install: browse
	install -Dm755 browse $(PREFIX)/bin/browse

clean:
	rm -f browse

.PHONY: install clean
