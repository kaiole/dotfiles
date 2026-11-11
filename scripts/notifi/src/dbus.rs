//! The notification daemon, asked over the session bus. gdbus and dunstctl
//! take 5 ms a call to start; speaking the bus's wire format here takes
//! 0.2 ms for the connection and less for each call on it.
//!
//! Only what these calls need is here: method calls whose arguments are
//! strings and 32-bit numbers, and their replies.

use std::env;
use std::io::{Read, Write};
use std::os::linux::net::SocketAddrExt;
use std::os::unix::net::{SocketAddr, UnixStream};
use std::time::Duration;

const TIMEOUT: Duration = Duration::from_secs(3);
/// More than any reply read here; a longer message is not one of them.
const LONGEST: usize = 1 << 20;

const BUS: [&str; 3] = [
    "org.freedesktop.DBus",
    "/org/freedesktop/DBus",
    "org.freedesktop.DBus",
];
const NOTIFICATIONS: &str = "org.freedesktop.Notifications";
const NOTIFICATIONS_PATH: &str = "/org/freedesktop/Notifications";
/// What dunstctl calls.
const DUNST: &str = "org.dunstproject.cmd0";

fn pad(bytes: &mut Vec<u8>, boundary: usize) {
    bytes.resize(bytes.len().next_multiple_of(boundary), 0);
}

fn number(bytes: &[u8], at: usize) -> Option<u32> {
    let bytes = bytes.get(at..at.checked_add(4)?)?;
    Some(u32::from_le_bytes(bytes.try_into().ok()?))
}

/// The arguments of a call, in the bus's encoding.
#[derive(Default)]
struct Arguments {
    signature: String,
    body: Vec<u8>,
}

impl Arguments {
    fn text(mut self, text: &str) -> Self {
        self.signature.push('s');
        pad(&mut self.body, 4);
        self.body.extend((text.len() as u32).to_le_bytes());
        self.body.extend(text.as_bytes());
        self.body.push(0);
        self
    }

    fn number(mut self, number: u32) -> Self {
        self.signature.push('u');
        pad(&mut self.body, 4);
        self.body.extend(number.to_le_bytes());
        self
    }
}

/// A method call: a fixed header, the header fields, each a code and a
/// value with its type, and the arguments.
fn call(serial: u32, to: [&str; 3], method: &str, arguments: &Arguments) -> Vec<u8> {
    let [destination, path, interface] = to;
    // Flag 2: the bus must not start a daemon to answer this. A key bind
    // waits for the answer, and no daemon means nothing is on screen.
    let mut message = vec![b'l', 1, 2, 1];
    message.extend((arguments.body.len() as u32).to_le_bytes());
    message.extend(serial.to_le_bytes());
    message.extend([0; 4]); // the length of the fields, known below
    let fields = [
        (1, b'o', path),
        (2, b's', interface),
        (3, b's', method),
        (6, b's', destination),
        (8, b'g', &arguments.signature),
    ];
    for (code, kind, value) in fields {
        if value.is_empty() {
            continue;
        }
        pad(&mut message, 8);
        message.extend([code, 1, kind, 0]);
        if kind == b'g' {
            message.push(value.len() as u8);
        } else {
            message.extend((value.len() as u32).to_le_bytes());
        }
        message.extend(value.as_bytes());
        message.push(0);
    }
    let length = (message.len() - 16) as u32;
    message[12..16].copy_from_slice(&length.to_le_bytes());
    pad(&mut message, 8);
    message.extend(&arguments.body);
    message
}

/// The serial of the call that a message with these header fields answers.
fn answered(fields: &[u8]) -> Option<u32> {
    let mut at = 0;
    while at + 4 <= fields.len() {
        let (code, kind) = (fields[at], fields[at + 2]);
        at += 4;
        match kind {
            b'u' if code == 5 => return number(fields, at),
            b'u' => at += 4,
            b's' | b'o' => at += 4 + number(fields, at)? as usize + 1,
            b'g' => at += 1 + *fields.get(at)? as usize + 1,
            _ => return None,
        }
        at = at.next_multiple_of(8);
    }
    None
}

fn socket() -> Option<UnixStream> {
    let Ok(addresses) = env::var("DBUS_SESSION_BUS_ADDRESS") else {
        let runtime = env::var_os("XDG_RUNTIME_DIR")?;
        return UnixStream::connect(std::path::Path::new(&runtime).join("bus")).ok();
    };
    for address in addresses.split(';') {
        let Some(keys) = address.strip_prefix("unix:") else {
            continue;
        };
        for key in keys.split(',') {
            let stream = if let Some(path) = key.strip_prefix("path=") {
                UnixStream::connect(path)
            } else if let Some(name) = key.strip_prefix("abstract=") {
                SocketAddr::from_abstract_name(name)
                    .and_then(|address| UnixStream::connect_addr(&address))
            } else {
                continue;
            };
            if let Ok(stream) = stream {
                return Some(stream);
            }
        }
    }
    None
}

/// A connection to the session bus.
struct Bus {
    stream: UnixStream,
    /// Read from the stream and not used yet.
    unread: Vec<u8>,
    serial: u32,
}

impl Bus {
    fn connect() -> Option<Bus> {
        let mut stream = socket()?;
        stream.set_read_timeout(Some(TIMEOUT)).ok()?;
        stream.set_write_timeout(Some(TIMEOUT)).ok()?;
        // Who this is, by the uid the socket already tells the bus, and the
        // Hello every connection starts with, sent without waiting for the
        // bus to accept the first.
        let uid = unsafe { libc::getuid() }.to_string();
        let uid: String = uid.bytes().map(|digit| format!("{digit:02x}")).collect();
        let mut hello = format!("\0AUTH EXTERNAL {uid}\r\nBEGIN\r\n").into_bytes();
        hello.extend(call(1, BUS, "Hello", &Arguments::default()));
        stream.write_all(&hello).ok()?;
        let mut bus = Bus {
            stream,
            unread: Vec::new(),
            serial: 1,
        };
        let mut accepted = Vec::new();
        while !accepted.ends_with(b"\r\n") {
            accepted.extend(bus.take(1)?);
        }
        accepted.starts_with(b"OK").then_some(bus)
    }

    /// The next `count` bytes from the bus.
    fn take(&mut self, count: usize) -> Option<Vec<u8>> {
        let mut chunk = [0; 4096];
        while self.unread.len() < count {
            match self.stream.read(&mut chunk) {
                Ok(read) if read > 0 => self.unread.extend(&chunk[..read]),
                Ok(_) => return None,
                Err(error) if error.kind() == std::io::ErrorKind::Interrupted => {}
                Err(_) => return None,
            }
        }
        Some(self.unread.drain(..count).collect())
    }

    /// Calls a method and returns what it returned, encoded; None if it
    /// failed.
    fn call(&mut self, to: [&str; 3], method: &str, arguments: Arguments) -> Option<Vec<u8>> {
        self.serial += 1;
        let message = call(self.serial, to, method, &arguments);
        self.stream.write_all(&message).ok()?;
        loop {
            // Other messages come too: the reply to Hello, and a signal that
            // says this connection has its name.
            let header = self.take(16)?;
            let (body, fields) = (number(&header, 4)?, number(&header, 12)?);
            let (body, fields) = (body as usize, fields as usize);
            if header[0] != b'l' || body > LONGEST || fields > LONGEST {
                return None;
            }
            let padded = self.take(fields.next_multiple_of(8))?;
            let body = self.take(body)?;
            if answered(&padded[..fields]) == Some(self.serial) {
                // 2 is a method's return, 3 an error.
                return (header[1] == 2).then_some(body);
            }
        }
    }
}

/// The notification daemon. Connects when first asked.
#[derive(Default)]
pub struct Daemon {
    bus: Option<Option<Bus>>,
    owner: Option<Option<String>>,
}

impl Daemon {
    fn call(&mut self, to: [&str; 3], method: &str, arguments: Arguments) -> Option<Vec<u8>> {
        let bus = self.bus.get_or_insert_with(Bus::connect).as_mut()?;
        bus.call(to, method, arguments)
    }

    /// The bus name of the running daemon, which a later one will not have.
    pub fn owner(&mut self) -> Option<&str> {
        if self.owner.is_none() {
            let arguments = Arguments::default().text(NOTIFICATIONS);
            let owner = self.call(BUS, "GetNameOwner", arguments).and_then(|reply| {
                let name = reply.get(4..4 + number(&reply, 0)? as usize)?;
                Some(String::from_utf8_lossy(name).into_owned())
            });
            self.owner = Some(owner);
        }
        self.owner.as_ref()?.as_deref()
    }

    pub fn close(&mut self, id: u32) {
        let to = [NOTIFICATIONS, NOTIFICATIONS_PATH, NOTIFICATIONS];
        self.call(to, "CloseNotification", Arguments::default().number(id));
    }

    /// How many notifications dunst has on screen: 0 if it is not running.
    pub fn displayed(&mut self) -> u32 {
        let to = [
            NOTIFICATIONS,
            NOTIFICATIONS_PATH,
            "org.freedesktop.DBus.Properties",
        ];
        let property = Arguments::default().text(DUNST).text("displayedLength");
        // A variant: the signature of what it holds, then that.
        self.call(to, "Get", property)
            .filter(|reply| reply.starts_with(&[1, b'u', 0]))
            .and_then(|reply| number(&reply, 4))
            .unwrap_or(0)
    }

    /// Runs the action of the notification on top, as `dunstctl action`.
    pub fn act(&mut self) {
        let to = [NOTIFICATIONS, NOTIFICATIONS_PATH, DUNST];
        self.call(to, "NotificationAction", Arguments::default().number(0));
    }
}
