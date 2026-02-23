[![Build Status](https://api.travis-ci.org/fluffle/sp0rkle.svg)](https://travis-ci.org/fluffle/sp0rkle)

Getting started, from scratch:

1.  Install some dependencies.

	```bash
	sudo apt-get install build-essential bison
	sudo apt-get install git
	```

2.  Install Go.

	Install go https://golang.org/doc/install

	```bash
	# consider putting these in ~/.bashrc too...
	export GOROOT="$HOME/go"
	export GOPATH="$HOME/gocode"
	export PATH="$PATH:$GOROOT/bin:$GOPATH/bin"

	# ... and creating the GOPATH directory structure.
	# (read `go help gopath` for details of this)
	mkdir -p $GOPATH/{src,pkg,bin}
	```

3.  Use the `go` tool to get dependencies.

	```bash
	go mod download
	```
4.  Clone sp0rkle's code from github.

	```bash
	cd $GOPATH/src/github.com/fluffle

	# Note: in order to submit patches more easily, you might want to get a github
	# account, fork the bot, and clone from your own writeable version.

	# If you do that, clone with:
	git clone git@github.com:<username>/sp0rkle.git
	# and then add my repository as an alternative remote to pull from:
	cd sp0rkle
	git remote add -f -m master fluffle http://github.com/fluffle/sp0rkle.git

	# Otherwise, just clone from my repository:
	git clone http://github.com/fluffle/sp0rkle.git
	```

5.  Import a recent database backup of BoltDB.

	```bash
	# sp0rkle uses BoltDB, simply place your backup file as sp0rkle.boltdb
	gunzip < sp0rkle.boltdb.YYYY-MM-DD.HH:MM.gz > sp0rkle.boltdb
	```

	If you don't know where to get a DB backup from, you possibly
	shouldn't be submitting patches :-)

6.  Code, build, commit, push :)

	```bash
	git checkout -b myfeature
	while coding in $GOPATH/src/github.com/fluffle/sp0rkle/sp0rkle:
	  vim <stuff>:wq
	  go build
	  # Run local build for testing ...
	  ./sp0rkle --servers irc.pl0rt.org[:port]  [--nick=mybot] [--channels='#test']
	  ^C

	git add <stuff>
	git commit -m "Some useful message about the edit to <stuff>."

	# If you cloned from your own repo, push the new branch with:
	git push origin myfeature
	# ... then send me a pull request on github :-)
	```

	Here's a more in depth description of a good workflow to use with github:
	https://gist.github.com/Chaser324/ce0505fbed06b947d962
