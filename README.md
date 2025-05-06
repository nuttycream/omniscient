# omniscient

A pair program for the OmniBot that uses IPC and WebSockets to give us near
real-time updates from our bot

![preview](https://i.imgur.com/GlJwatc.png)

## what does it do?

the premise of this web app, is to read from shared memory from the bot

```mermaid
flowchart TD
    subgraph omnibot["omnibot (C)"]
        botMain[main.c] --> motors[Motor Control]
        botMain --> sensors[Sensors]
    end
    
    subgraph sharedMem["Shared Memory"]
        shared[Shared Struct\nversion\ndirection\nmotor_power\nbot_mode\nobstacle\nline sensors]
    end
    
    subgraph omniscient["omniscient (Rust)"]
        direction TB
        webApp[Web Interface] --> sound[Sound System]
        webApp --> wsServer[WebSocket Server]
    end
    
    omnibot -->|writes| sharedMem
    omniscient -->|reads| sharedMem
    wsServer -->|updates| browser((Browser))
    
    classDef cCode fill:#5c8dbc,color:#fff,stroke:#000
    classDef rustCode fill:#dea584,color:#000,stroke:#000
    classDef sharedMemory fill:#f9e79f,color:#000,stroke:#000
    classDef external fill:#f9f9f9,color:#000,stroke:#000
    
    class omnibot cCode
    class omniscient rustCode
    class sharedMem sharedMemory
    class browser external
```

## shared memory structure

```c
typedef struct {
    // we'll check for version
    // number per update
    // seems jank but the other option
    // is to check for modified 0/1
    // but the rust code needs W perms
    // which i dont want
    int ver;
    int direction;
    int motor_power[3];
    // bot can be either
    // line following: 0
    // obstacle tracking/avoidance: 1
    // man control: 2
    int bot_mode;

    // osbtacle stuff
    int obstacle;

    // line following stuff
    int go_left;
    int go_right;
    int sensor_mode;

    int sensors[4];
} Shared;
```

## attribution

chicken sounds from:\
[minecraft wiki](https://minecraft.fandom.com/wiki/Category:Chicken_sounds)

docker image inspo:\
[friday](https://github.com/JonasRSV/Friday)
