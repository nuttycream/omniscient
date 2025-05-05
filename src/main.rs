mod sound;

use std::{
    env,
    error::Error,
    net::SocketAddr,
    ops::ControlFlow,
    thread::{self, sleep},
    time::Duration,
    vec,
};

use axum::{
    Router,
    extract::{
        WebSocketUpgrade,
        ws::{Message, WebSocket},
    },
    http::header,
    response::{Html, IntoResponse, Response},
    routing::{any, get},
};
use futures::{SinkExt, StreamExt};
use listenfd::ListenFd;
use rand::Rng;
use serde::{Deserialize, Serialize};
use shared_memory::{Shmem, ShmemConf};
use sound::{get_sounds, play_chicken};
use std::mem::size_of;
use tokio::{
    net::TcpListener,
    sync::{mpsc, watch},
    task,
};

//https://github.com/elast0ny/shared_memory/blob/master/examples

#[repr(C)]
#[derive(Debug, Clone, Copy)]
struct Shared {
    ver: i32,
    direction: i32,
    motor_power: [i32; 3],
    bot_mode: i32,

    obstacle: i32,

    go_left: i32,
    go_right: i32,
    sensor_mode: i32,

    sensors: [i32; 4],
}

#[derive(Serialize, Deserialize)]
struct SocketMsg {
    direction: String,
    motors: [i32; 3],
    bot_mode: i32,
    curr_action: String,
    obstacle: i32,
    sensors: [i32; 4],
}

// goofy ahh sounds
// randomly play mc
// chicken sfx
struct Sounds {
    sounds: Vec<String>,
}

impl Sounds {
    fn new() -> Self {
        // multiple asset paths
        // because ynaut
        let asset_paths = vec![
            "src/assets",
            "assets",
            "../assets",
            "./assets",
        ];

        let mut sounds = vec![];
        for path in asset_paths {
            sounds = get_sounds(path);
        }

        Sounds { sounds }
    }

    fn play_rand(&self) {
        let sounds = self.sounds.clone();
        thread::spawn(move || {
            if let Err(e) = play_chicken(&sounds) {
                println!("{e}");
            }
        });
    }
}

// should this be open
// the entire time web server
// is running?
fn open_shared_mem() -> Result<Shmem, Box<dyn Error>> {
    let mem = ShmemConf::new()
        .os_id("omnigod")
        .size(size_of::<Shared>())
        .open()?;

    Ok(mem)
}

fn read_shared_mem(mem: &Shmem) -> Shared {
    let ptr = mem.as_ptr() as *const Shared;
    // unsafe { read_volatile(ptr) }
    unsafe { ptr.read() }
}

#[tokio::main]
async fn main() -> Result<(), Box<dyn Error>> {
    let port = env::args()
        .nth(1)
        .and_then(|arg| arg.parse::<i32>().ok())
        .unwrap_or(3001);
    let addr = format!("0.0.0.0:{port}");

    let chicken = Sounds::new();

    // temp so that i dont ehear the damn chicken
    let chicken = Sounds { sounds: vec![] };

    thread::spawn(move || {
        loop {
            let mut rng = rand::rng();
            chicken.play_rand();
            let wait_time = rng.random_range(5..=20);
            for _ in 0..wait_time {
                thread::sleep(Duration::from_millis(500));
            }
        }
    });

    let app = Router::new()
        .route("/", get(serve_html))
        .route("/style.css", get(serve_css))
        .route("/script.js", get(serve_js))
        .route("/ws", any(handle_websocket));

    let mut listenfd = ListenFd::from_env();
    let listener = match listenfd.take_tcp_listener(0)? {
        Some(listener) => {
            listener.set_nonblocking(true)?;
            TcpListener::from_std(listener)?
        }
        None => TcpListener::bind(addr).await?,
    };

    let shutdown = async {
        tokio::signal::ctrl_c()
            .await
            .expect("failed to get C-c signhandle");
    };

    println!("listening on {}", listener.local_addr()?);
    axum::serve(
        listener,
        app.into_make_service_with_connect_info::<SocketAddr>(),
    )
    .with_graceful_shutdown(shutdown)
    .await?;

    Ok(())
}

async fn handle_websocket(
    ws: WebSocketUpgrade,
) -> Response {
    ws.on_upgrade(handle_socket)
}

async fn handle_socket(socket: WebSocket) {
    println!("ws connection opened");
    let (mut sender, mut receiver) = socket.split();

    let (tx, mut rx) = mpsc::channel(100);

    let (shutdown_tx, shutdown_rx) = watch::channel(false);

    // C-c to the shutdown channel
    let shut_rx_clone = shutdown_rx.clone();
    tokio::spawn(async move {
        tokio::signal::ctrl_c().await.ok();
        let _ = shutdown_tx.send(true);
        println!("Shutdown signal sent");
    });

    // since shmem doesnt use Send
    // we have to spawn a blocking thread
    // shouldnt be that much of an issue for this
    // project tbh
    let read_task = task::spawn_blocking(move || {
        let shutdown_rx = shut_rx_clone;
        let mut mem_available = false;
        let mut mem = None;
        let mut last_ver = -1;

        loop {
            if *shutdown_rx.borrow() {
                println!("blocking thread got shutdown");
                break;
            }

            // periodically checks if shared mem can be read
            // 5 sec default
            if !mem_available {
                match open_shared_mem() {
                    Ok(opened_mem) => {
                        println!("opened shared mem");
                        mem = Some(opened_mem);
                        mem_available = true;
                    }
                    Err(e) => {
                        println!(
                            "waiting for shared memory: {e}"
                        );
                        sleep(Duration::from_secs(5));
                        continue;
                    }
                }
            }
            if mem_available {
                // unwrap should be safe here
                // because we set mem
                let shared_mem = mem.as_ref().unwrap();

                let shared_result =
                    std::panic::catch_unwind(|| {
                        read_shared_mem(shared_mem)
                    });

                if let Ok(shared) = shared_result {
                    if shared.ver != last_ver {
                        last_ver = shared.ver;

                        let direction_text =
                            match shared.direction {
                                0 => "FORWARD",
                                1 => "BACKWARD",
                                2 => "STRAFE_LEFT",
                                3 => "STRAFE_RIGHT",
                                _ => "STOPPED",
                            }
                            .to_string();

                        let msg = SocketMsg {
                            direction: direction_text
                                .clone(),
                            motors: shared.motor_power,
                            bot_mode: shared.bot_mode,
                            curr_action: direction_text,
                            obstacle: shared.obstacle,
                            sensors: shared.sensors,
                        };

                        let json =
                            serde_json::to_string(&msg)
                                .unwrap_or_default();
                        if tx.blocking_send(json).is_err() {
                            return;
                        }
                    }
                } else {
                    println!(
                        "shared mem gone trying to reopen"
                    );
                    mem_available = false;
                    mem = None;
                    sleep(Duration::from_secs(1));
                }
            }

            sleep(Duration::from_millis(100));
        }
    });

    // relay messages from channel to websocket
    let mut send_task = tokio::spawn(async move {
        while let Some(msg) = rx.recv().await {
            if sender
                .send(Message::Text(msg.into()))
                .await
                .is_err()
            {
                break;
            }
        }
    });

    let mut recv_task = tokio::spawn(async move {
        while let Some(Ok(msg)) = receiver.next().await {
            if process_message(msg).is_break() {
                break;
            }
        }
    });

    tokio::select! {
        // task to read from shared mem
        _ = read_task => {
            println!("read task completed");
            send_task.abort();
            recv_task.abort();
        },
        rv_a = (&mut send_task) => {
            match rv_a {
                Ok(_) => println!("messages sent"),
                Err(a) => println!("Error sending messages {a:?}")
            }
            recv_task.abort();
        },
        rv_b = (&mut recv_task) => {
            match rv_b {
                Ok(_) => println!("received messages"),
                Err(b) => println!("Error receiving messages {b:?}")
            }
            send_task.abort();
        }
    }

    println!("ws connection closed");
}

fn process_message(msg: Message) -> ControlFlow<(), ()> {
    match msg {
        Message::Close(close_frame) => {
            if let Some(cf) = close_frame {
                println!(
                    "close with code {} with reason `{}`",
                    cf.code, cf.reason
                );
            } else {
                println!(
                    "sent close msg without closeframe"
                );
            }
            ControlFlow::Break(())
        }
        _ => ControlFlow::Continue(()),
    }
}

async fn serve_html() -> Html<&'static str> {
    let html = include_str!("./assets/index.html");
    Html(html)
}

async fn serve_css() -> impl IntoResponse {
    let css = include_str!("./assets/style.css");
    ([(header::CONTENT_TYPE, "text/css")], css)
}

async fn serve_js() -> impl IntoResponse {
    let js = include_str!("./assets/script.js");
    ([(header::CONTENT_TYPE, "application/javascript")], js)
}
