PROJ_NAME=omniscient
TARGET_ARCH=aarch64-unknown-linux-gnu
ROOTNAME=target/$(TARGET_ARCH)/release/$(PROJ_NAME)
ROOTNAME_DEBUG=target/$(TARGET_ARCH)/debug/$(PROJ_NAME)
REMOTE_HOST=pi70@raspberrypi70.local
REMOTE_DIR=~/omniscient
SSH_OPTS=-o ControlMaster=auto -o ControlPath=/tmp/ssh-control-%r@%h:%p -o ControlPersist=yes

build:
	cargo build

run:
	cargo build && cargo run

cross-build:
	PKG_CONFIG_ALLOW_CROSS=1 \
	PKG_CONFIG_PATH=$(AARCH64_PKG_CONFIG_PATH) \
	PKG_CONFIG_LIBDIR=$(AARCH64_PKG_CONFIG_LIBDIR) \
	CARGO_TARGET_AARCH64_UNKNOWN_LINUX_GNU_LINKER=$(AARCH64_CC) \
	RUSTFLAGS="$(AARCH64_RUSTFLAGS)" \
	cargo build --target $(TARGET_ARCH)

release:
	PKG_CONFIG_ALLOW_CROSS=1 \
	PKG_CONFIG_PATH=$(AARCH64_PKG_CONFIG_PATH) \
	PKG_CONFIG_LIBDIR=$(AARCH64_PKG_CONFIG_LIBDIR) \
	CARGO_TARGET_AARCH64_UNKNOWN_LINUX_GNU_LINKER=$(AARCH64_CC) \
	RUSTFLAGS="$(AARCH64_RUSTFLAGS)" \
	cargo build --release --target $(TARGET_ARCH)

qemu: cross-build
	qemu-aarch64 -L /usr/aarch64-linux-gnu $(ROOTNAME_DEBUG)

qemu-release: release
	qemu-aarch64 -L /usr/aarch64-linux-gnu $(ROOTNAME)

clean: 
	cargo clean

remote: release
	rsync -az $(ROOTNAME) $(REMOTE_HOST):$(REMOTE_DIR)/

update-assets:
	rsync -az --mkpath src/assets/ $(REMOTE_HOST):$(REMOTE_DIR)/assets/

ssh-open:
	ssh -M $(SSH_OPTS) $(REMOTE_HOST) "connected"

install-services: ssh-open
	rsync -az omniscient.service omniloop.service omniloop.sh $(REMOTE_HOST):$(REMOTE_DIR)/
	ssh $(SSH_OPTS) $(REMOTE_HOST) "\
		sudo chmod +x $(REMOTE_DIR)/omniloop.sh && \
		sudo cp $(REMOTE_DIR)/omniscient.service /etc/systemd/system/ && \
		sudo cp $(REMOTE_DIR)/omniloop.service /etc/systemd/system/ && \
		sudo systemctl daemon-reload"

enable-services: ssh-open
	ssh $(SSH_OPTS) $(REMOTE_HOST) "\
		sudo systemctl enable omniloop.service && \
		sudo systemctl enable omniscient.service"

start-services: ssh-open
	ssh $(SSH_OPTS) $(REMOTE_HOST) "\
		sudo systemctl start omniloop.service && \
		sudo systemctl start omniscient.service"

restart-services: ssh-open
	ssh $(SSH_OPTS) $(REMOTE_HOST) "\
		sudo systemctl restart omniloop.service && \
		sudo systemctl restart omniscient.service"

stop-services: ssh-open
	ssh $(SSH_OPTS) $(REMOTE_HOST) "\
		sudo systemctl stop omniscient.service && \
		sudo systemctl stop omniloop.service"

service-status: ssh-open
	ssh $(SSH_OPTS) $(REMOTE_HOST) "\
		sudo systemctl status omniloop.service && \
		sudo systemctl status omniscient.service"

deploy: remote install-services enable-services restart-services
	@echo "Deployment complete! Use 'make service-status' to check service status."

watch:
	systemfd --no-pid -s http::3001 -- cargo watch -w src/ -x run

ssh-close:
	ssh -O exit $(REMOTE_HOST) 2>/dev/null || true

.PHONY: build run cross-build release qemu qemu-release clean remote watch \
	ssh-open ssh-close install-services enable-services start-services \
	restart-services stop-services service-status deploy update-assets
