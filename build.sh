#!/usr/bin/env bash
set -e

PROJECT_DIR=$(pwd)
PROJECT_NAME="omniscient"
TARGET="aarch64-unknown-linux-gnu"
REMOTE_HOST="pi70@raspberrypi70.local"
REMOTE_DIR="~/${PROJECT_NAME}"

GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m' 

echo -e "${YELLOW}Building Docker image...${NC}"
docker build -t aarch64-rust-build -f pi.Dockerfile .

echo -e "${YELLOW}Running cross-compilation...${NC}"
docker run --rm -v "${PROJECT_DIR}":/app aarch64-rust-build cargo build --target ${TARGET} --release

if [ $? -eq 0 ]; then
    echo -e "${GREEN}Build successful!${NC}"
    echo -e "Binary location: ${PROJECT_DIR}/target/${TARGET}/release/${PROJECT_NAME}"
    
    read -p "Deploy to remote target? (y/n): " deploy
    if [ "$deploy" == "y" ]; then
        echo -e "${YELLOW}Deploying to remote target...${NC}"
        rsync -az "${PROJECT_DIR}/target/${TARGET}/release/${PROJECT_NAME}" "${REMOTE_HOST}:${REMOTE_DIR}/"
        read -p "Restart service? (y/n): " restart
        if [ "$restart" == "y" ]; then
            ssh "${REMOTE_HOST}" "sudo systemctl restart omniscient.service"
            echo -e "${GREEN}Service restarted!${NC}"
        fi
    fi
else
    echo -e "${RED}Build failed!${NC}"
    exit 1
fi
