# CBT config collector demo. All targets run against localhost only.
PERL ?= perl

.PHONY: help deps sim-start sim-stop collect collect-ssh test lab-ssh-start lab-ssh-stop lab-docker-start lab-docker-stop clean

help:
	@echo "make deps              install Perl modules (cpanm)"
	@echo "make sim-start         start the Telnet device simulator (127.0.0.1:2301-2303)"
	@echo "make collect           collect configs from the simulator into output/ (Telnet)"
	@echo "make collect-ssh       collect over SSH from lab/ssh + lab/docker (conf/devices.local-ssh.conf)"
	@echo "                       secrets via env: CBT_PASSWORD, CBT_ENABLE_PASSWORD, CBT_SSH_KEY, CBT_LAB_KNOWN_HOSTS (lab defaults)"
	@echo "make test              run the test suite (starts its own simulator; SSH tests run if the labs are up)"
	@echo "make lab-ssh-start     private sshd lab, key auth   (127.0.0.1:2201-2203)"
	@echo "make lab-docker-start  Docker sshd lab, password+key (127.0.0.1:2401-2403)"
	@echo "make sim-stop | lab-ssh-stop | lab-docker-stop | clean"

deps:
	cpanm --installdeps .

sim-start:
	@mkdir -p .run
	$(PERL) sim/bs-sim.pl --daemon --pidfile .run/sim.pid
	@sleep 1

sim-stop:
	@if [ -f .run/sim.pid ]; then kill `cat .run/sim.pid` && rm -f .run/sim.pid && echo "bs-sim: stopped"; fi

collect:
	$(PERL) bin/cbt-collect -i conf/devices.local.conf

# Lab defaults; override by exporting the variables.
collect-ssh: export CBT_PASSWORD ?= cbt-pass
collect-ssh: export CBT_ENABLE_PASSWORD ?= cbt-enable
collect-ssh: export CBT_SSH_KEY ?= $(CURDIR)/lab/.state/cbt_id_ed25519
collect-ssh: export CBT_LAB_KNOWN_HOSTS ?= $(CURDIR)/lab/.state/known_hosts
collect-ssh:
	$(PERL) bin/cbt-collect -i conf/devices.local-ssh.conf

test:
	prove -lr t

lab-ssh-start:
	lab/ssh/start.sh

lab-ssh-stop:
	lab/ssh/stop.sh

lab-docker-start:
	lab/docker/start.sh

lab-docker-stop:
	lab/docker/stop.sh

clean:
	rm -rf output log
