# CBT config collector demo. All targets run against localhost only.
PERL ?= perl

.PHONY: help deps sim-start sim-stop collect collect-ssh collect-docker test lab-ssh-start lab-ssh-stop lab-docker-start lab-docker-stop clean

help:
	@echo "make deps              install Perl modules (cpanm)"
	@echo "make sim-start         start the Telnet device simulator (127.0.0.1:2301-2303)"
	@echo "make collect           collect configs from the simulator into output/"
	@echo "make collect-ssh       collect over SSH from lab/ssh (public key)"
	@echo "make collect-docker    collect over SSH from lab/docker (password + public key)"
	@echo "make test              run the test suite (starts its own simulator; SSH tests need a running lab)"
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

# Lab-only secrets, passed through the environment (the inventories do not contain them).
LAB_SSH_ENV = CBT_SSH_KEY_FILE=lab/.state/cbt_id_ed25519 CBT_SSH_KNOWN_HOSTS=lab/.state/known_hosts

collect-ssh:
	$(LAB_SSH_ENV) $(PERL) bin/cbt-collect -i conf/devices.local-ssh.conf

collect-docker:
	$(LAB_SSH_ENV) CBT_PASSWORD=cbt-pass CBT_ENABLE_PASSWORD=cbt-enable \
	  $(PERL) bin/cbt-collect -i conf/devices.local-docker.conf

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
