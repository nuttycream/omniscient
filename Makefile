PROJ_NAME=omniscient
TARGET_ARCH=aarch64-unknown-linux-musl
ROOTNAME=target/$(TARGET_ARCH)/release/$(PROJ_NAME)
ROOTNAME_DEBUG=target/$(TARGET_ARCH)/debug/$(PROJ_NAME)
REMOTE_HOST=pi08@192.168.68.70
REMOTE_DIR=~/omniscient

build:
	cargo build

run:
	cargo run

cross-build:
	cargo build --target $(TARGET_ARCH)

release:
	cargo build --release --target $(TARGET_ARCH)

qemu: cross-build
	qemu-aarch64 -L /usr/aarch64-linux-musl $(ROOTNAME_DEBUG)

qemu-release: release
	qemu-aarch64 -L /usr/aarch64-linux-musl $(ROOTNAME)

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

