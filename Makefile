PROJ_NAME=omniscient
TARGET_ARCH=aarch64-unknown-linux-gnu
ROOTNAME=target/$(TARGET_ARCH)/release/$(PROJ_NAME)
ROOTNAME_DEBUG=target/$(TARGET_ARCH)/debug/$(PROJ_NAME)
REMOTE_HOST=pi70@raspberrypi70.local
REMOTE_DIR=~/omniscient

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

watch:
	systemfd --no-pid -s http::3001 -- cargo watch -w src/ -x run

install-service:
	rsync -az omniscient.service $(REMOTE_HOST):$(REMOTE_DIR)/
	ssh $(REMOTE_HOST) "sudo cp $(REMOTE_DIR)/omniscient.service /etc/systemd/system/ && sudo systemctl daemon-reload"

enable-service:
	ssh $(REMOTE_HOST) "sudo systemctl enable omniscient.service"

start-service:
	ssh $(REMOTE_HOST) "sudo systemctl start omniscient.service"

restart-service:
	ssh $(REMOTE_HOST) "sudo systemctl restart omniscient.service"

deploy: remote install-service restart-service

update-assets:
	rsync -az --mkpath src/assets/ $(REMOTE_HOST):$(REMOTE_DIR)/assets/
