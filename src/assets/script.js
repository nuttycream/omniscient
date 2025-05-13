let socket = null;

// https://developer.mozilla.org/en-US/docs/Web/API/WebSocket
// https://developer.mozilla.org/en-US/docs/Web/API/WebSockets_API/Writing_WebSocket_client_applications
function connect() {
    const protocol = window.location.protocol === 'https:' ? 'wss:' : 'ws:';
    const ws_url = `${protocol}//${window.location.host}/ws`;

    socket = new WebSocket(ws_url);

    socket.addEventListener('open', (_) => {
        console.log('Connected to WebSocket server');
    });
    
    socket.addEventListener('message', (event) => {
        const message = event.data;
        process_msg(message);
    });
    
    socket.addEventListener('close', (_) => {
        console.log('Disconnected from WebSocket server');
        // attempt to reconnect after a delay
        setTimeout(() => connect(), 5000);
    });
    
    socket.addEventListener('error', (event) => {
        console.error('WebSocket error:', event);
        socket.close();
    });
}

function process_msg(msg) {
    try {
        const data = JSON.parse(msg);

        if (data.shared_mem !== undefined) {
            document.getElementById('mem').textContent = data.shared_mem;
        }

        if (data.bot_mode !== undefined) {
            document.getElementById('bot-mode').textContent = data.bot_mode;
        }

        if (data.direction !== undefined) {
            document.getElementById('direction').textContent = data.direction;
        }

        if (data.sensor_mode !== undefined) {
            document.getElementById('sensor-mode').textContent = data.sensor_mode;
        }

        if (data.curr_action !== undefined) {
            document.getElementById('curr-action').textContent = data.curr_action;
        }

        if (data.obstacle !== undefined) {
            if (data.obstacle === 0) {
                document.getElementById('obstacle').classList.remove('found');
            } else {
                document.getElementById('obstacle').classList.add('found');
            }
        }

        if (data.obstacle_mode !== undefined) {
            document.getElementById('obstacle-mode').textContent = data.obstacle_mode;
        }
        
        if (data.motors !== undefined) {
            update_wheels(data.motors);
        }

        if (data.sensors !== undefined) {
            update_sensors(data.sensors);
        }

    } catch (error) {
        console.error('error:', error);
    }
}

function update_wheels(motors) {
    document.querySelector('#wheel-left .wheel-power').textContent = `${motors[0]}%`;
    document.querySelector('#wheel-right .wheel-power').textContent = `${motors[1]}%`;
    document.querySelector('#wheel-bottom .wheel-power').textContent = `${motors[2]}%`;
}

function update_sensors(sensors) {
    const frontSensors = document.querySelectorAll('.front-line-sensor');
    
    for (let i = 0; i < frontSensors.length && i < sensors.length; i++) {
        if (sensors[i] === 1) {
            frontSensors[i].classList.add('sensor-active');
            frontSensors[i].classList.remove('sensor-inactive');
        } else {
            frontSensors[i].classList.add('sensor-inactive');
            frontSensors[i].classList.remove('sensor-active');
        }
    }
}

document.addEventListener('DOMContentLoaded', () => {
    connect();
    
    document.querySelector('button')
        .addEventListener('click', toggle_sound);
});

async function toggle_sound() {
    const sound = await fetch("/toggle-sound").then((res) => res.json());
    document.getElementById("sound").innerText = sound.status;
}

