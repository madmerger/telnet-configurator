# CBT config collector demo. All targets run against localhost only.
PERL ?= perl

.PHONY: help deps sim-start sim-stop collect collect-ssh collect-docker test lab-ssh-start lab-ssh-stop lab-docker-start lab-docker-stop clean web-api web-dev web-build test-py

help:
	@echo "make deps              install Perl modules (cpanm)"
	@echo "make sim-start         start the Telnet device simulator (127.0.0.1:2301-2303)"
	@echo "make collect           collect configs from the simulator into output/"
	@echo "make collect-ssh       collect over SSH from lab/ssh (public key)"
	@echo "make collect-docker    collect over SSH from lab/docker (password + public key)"
	@echo "make test              run the test suite (starts its own simulator; SSH tests need a running lab)"
	@echo "make lab-ssh-start     private sshd lab, key auth   (127.0.0.1:2201-2203)"
	@echo "make lab-docker-start  Docker sshd lab, password+key (127.0.0.1:2401-2403)"
	@echo "make web-api           Python backend (http://127.0.0.1:8000, serves web/dist when built)"
	@echo "make web-dev           React dev server (http://127.0.0.1:5173, proxies /api to web-api)"
	@echo "make web-build         build the React app into web/dist"
	@echo "make test-py           run the Python backend tests"
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

PYTHON ?= python3
WEB_PORT ?= 8000

web-api:
	$(LAB_SSH_ENV) PYTHONPATH=backend $(PYTHON) -m cbt serve --port $(WEB_PORT)

web-dev:
	cd web && npm install && npm run dev

web-build:
	cd web && npm install && npm run build

test-py:
	cd backend && $(PYTHON) -m unittest discover -s tests -v

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
