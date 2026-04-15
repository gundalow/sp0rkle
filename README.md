Getting started, from scratch:

1.  Install some dependencies.

	```bash
	sudo apt-get install build-essential bison
	sudo apt-get install git bzr
	```

2.  Install Go.

	Install go https://golang.org/doc/install

3.  Use the `go` tool to build and install.

	```bash
	go build ./...
	```

4.  Clone sp0rkle's code from github.

	```bash
	git clone https://github.com/fluffle/sp0rkle.git
	```

5.  Code, build, commit, push :)

	```bash
	git checkout -b myfeature
	# edit files
	go build
	# Run local build for testing ...
	./sp0rkle --boltdb sp0rkle.boltdb --servers irc.pl0rt.org[:port] [--nick=mybot] [--channels='#test']
	```
