PROJ_NAME=omniscient
TARGET_ARCH=aarch64-unknown-linux-gnu
ROOTNAME=target/$(TARGET_ARCH)/release/$(PROJ_NAME)
ROOTNAME_DEBUG=target/$(TARGET_ARCH)/debug/$(PROJ_NAME)

build:
	cargo build

run:
	cargo run

cross-build:
	cargo build --target $(TARGET_ARCH)

release:
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
	systemfd --no-pid -s http::3000 -- cargo watch -w src/ -x run
