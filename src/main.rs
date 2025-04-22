use std::{
    env, error::Error, net::SocketAddr, ops::ControlFlow,
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
use shared_memory::{Shmem, ShmemConf};
use tokio::net::TcpListener;

//https://github.com/elast0ny/shared_memory/blob/master/examples

#[repr(C)]
#[derive(Debug, Clone, Copy)]
struct Shared {
    ver: i32,
    direction: i32,
    motor_power: [i32; 3],
}

// should this be open
// the entire time web server
// is running??
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
        .unwrap_or(3000);
    let addr = format!("0.0.0.0:{port}");

    let app = Router::new()
        .route("/", get(serve_html))
        .route("/style.css", get(serve_css))
        .route("/htmx.js", get(serve_js))
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

    let mut send_task = tokio::spawn(async move {
        if sender
            .send(Message::text("huwat"))
            .await
            .is_err()
        {}
    });

    let shared = match open_shared_mem() {
        Ok(mem) => {
            println!("opened shared mem");
            mem
        }
        Err(e) => {
            println!("failed to open shared mem: {}", e);
            return;
        }
    };

    let mut recv_task = tokio::spawn(async move {
        while let Some(Ok(msg)) = receiver.next().await {
            if process_message(msg).is_break() {
                break;
            }
        }
    });

    tokio::select! {
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
        Message::Text(t) => {
            println!("got a text message {}", t);
            ControlFlow::Continue(())
        }
        Message::Binary(_) => ControlFlow::Continue(()),
        Message::Ping(_) => ControlFlow::Continue(()),
        Message::Pong(_) => ControlFlow::Continue(()),
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
    let js = include_str!("./assets/htmx.js");
    ([(header::CONTENT_TYPE, "application/javascript")], js)
}
