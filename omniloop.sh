#!/bin/bash

# LOL IGNORE THIS JANK
# THIS IS THE ONLY WAY I FOUND OUT
# THAT WORKS

#!/bin/bash
while true; do
  if [ -e /dev/shm/omnigod ]; then
    chmod a+rw /dev/shm/omnigod 2>/dev/null
  fi
  sleep 0.5
done
