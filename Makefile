# CBT config collector demo. All targets run against localhost only.
PERL ?= perl

.PHONY: help deps sim-start sim-stop collect collect-ssh collect-docker demo test lab-ssh-start lab-ssh-stop lab-docker-start lab-docker-stop clean

help:
	@echo "make deps              install Perl modules (cpanm)"
	@echo "make sim-start         start the Telnet device simulator (127.0.0.1:2301-2303)"
	@echo "make collect           collect configs from the simulator into output/ (Telnet)"
	@echo "make collect-ssh       collect over SSH from lab/ssh (key auth)"
	@echo "make collect-docker    collect over SSH from lab/docker (password + key auth)"
	@echo "make demo              Telnet vs SSH side by side in tmux (scripts/demo_telnet_vs_ssh.sh)"
	@echo "make test              run the test suite (starts its own simulator)"
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

collect-ssh:
	$(PERL) bin/cbt-collect -i conf/devices.local-ssh.conf

# Lab-only secrets, passed the same way as in production: through the environment.
collect-docker:
	CBT_PASSWORD=cbt-pass CBT_ENABLE_PASSWORD=cbt-enable $(PERL) bin/cbt-collect -i conf/devices.local-docker.conf

demo:
	scripts/demo_telnet_vs_ssh.sh

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
