//! The Wayland side: a full-width layer-shell strip on the focused output
//! with exclusive keyboard focus, drawn in software into shm buffers.
//!
//! The first frame is drawn in the first configure event, with every
//! thumbnail already loaded, so it's complete when it appears. Scale comes
//! from Hyprland: the buffer is in device pixels and a viewport maps it to
//! the logical size.

use std::thread::{self, JoinHandle};

use smithay_client_toolkit::{
    compositor::{CompositorHandler, CompositorState, FrameCallbackData},
    delegate_registry,
    dispatch2::Dispatch2,
    output::{OutputHandler, OutputState},
    reexports::{
        calloop::{EventLoop, LoopHandle},
        calloop_wayland_source::WaylandSource,
        client::{
            Connection, Proxy, QueueHandle,
            globals::registry_queue_init,
            protocol::{wl_keyboard, wl_output, wl_pointer, wl_seat, wl_shm, wl_surface},
        },
        protocols::wp::{
            cursor_shape::v1::client::wp_cursor_shape_device_v1::{Shape, WpCursorShapeDeviceV1},
            viewporter::client::{wp_viewport::WpViewport, wp_viewporter::WpViewporter},
        },
    },
    registry::{ProvidesRegistryState, RegistryState},
    registry_handlers,
    seat::{
        Capability, SeatHandler, SeatState,
        keyboard::{KeyEvent, KeyboardHandler, Keysym, Modifiers, RawModifiers},
        pointer::{PointerEvent, PointerEventKind, PointerHandler, cursor_shape::CursorShapeManager},
    },
    shell::{
        WaylandSurface,
        wlr_layer::{
            Anchor, KeyboardInteractivity, Layer, LayerShell, LayerShellHandler, LayerSurface,
            LayerSurfaceConfigure,
        },
    },
    shm::{Shm, ShmHandler, slot::SlotPool},
};

use crate::{
    Content, Result,
    draw::{self, Canvas, Colors, Frame, Layout},
    picker::Picker,
    text::Font,
    thumbs, trace,
};

const BTN_LEFT: u32 = 0x110;
/// Scroll distance, in surface pixels, that moves the selection one tile
/// on a touchpad.
const SCROLL_STEP: f64 = 15.0;

pub enum Outcome {
    Cancel,
    Apply(usize),
}

pub struct Inputs {
    pub scale: f64,
    /// Expected buffer width: the monitor's width in pixels.
    pub width: u32,
    pub font: Font,
    pub colors: Colors,
    pub content: JoinHandle<Result<Content>>,
    /// Exit as soon as the first frame is on screen.
    pub bench: bool,
}

pub fn run(inputs: Inputs) -> Result<(Outcome, Content)> {
    let conn = Connection::connect_to_env()?;
    let (globals, queue) = registry_queue_init(&conn)?;
    let qh = queue.handle();
    let compositor = CompositorState::bind(&globals, &qh)?;
    let layer_shell = LayerShell::bind(&globals, &qh)?;
    let shm = Shm::bind(&globals, &qh)?;
    let viewporter: WpViewporter = globals.bind(&qh, 1..=1, NoEvents)?;
    let cursor_shapes = CursorShapeManager::bind(&globals, &qh).ok();

    let layout = Layout::new(inputs.width, inputs.scale, inputs.font.line_height);
    let surface = compositor.create_surface(&qh);
    let viewport = viewporter.get_viewport(&surface, &qh, NoEvents);
    // No output: Hyprland puts the surface on the focused monitor.
    let layer = layer_shell.create_layer_surface(&qh, surface, Layer::Overlay, Some("wall_select"), None);
    layer.set_anchor(Anchor::LEFT | Anchor::RIGHT);
    layer.set_size(0, logical(layout.height, inputs.scale));
    layer.set_keyboard_interactivity(KeyboardInteractivity::Exclusive);
    layer.commit();
    conn.flush()?;
    trace::mark("surface requested");

    // The compositor answers the commit while the thumbnails load.
    let content = inputs.content.join().map_err(|_| "thumbnail loader panicked")??;
    trace::mark("thumbnails loaded");

    let pool = SlotPool::new((layout.width * layout.height * 4) as usize, &shm)?;
    let mut event_loop: EventLoop<App> = EventLoop::try_new()?;
    WaylandSource::new(conn.clone(), queue)
        .insert(event_loop.handle())
        .map_err(|e| e.error)?;

    let picker = Picker::new(content.walls.iter().map(|w| w.label.as_str()), content.selected);
    let mut app = App {
        registry: RegistryState::new(&globals),
        seat: SeatState::new(&globals, &qh),
        outputs: OutputState::new(&globals, &qh),
        shm,
        qh: qh.clone(),
        loop_handle: event_loop.handle(),
        layer,
        viewport,
        pool,
        cursor_shapes,
        shape_device: None,
        cursor: None,
        enter_serial: 0,
        keyboard: None,
        pointer: None,
        modifiers: Modifiers::default(),
        scroll: 0.0,
        scale: inputs.scale,
        font: inputs.font,
        colors: inputs.colors,
        layout,
        buffer: None,
        content,
        picker,
        bench: inputs.bench,
        drawn: false,
        outcome: None,
    };
    while app.outcome.is_none() {
        event_loop.dispatch(None, &mut app)?;
    }

    // Unmap right away: applying may wait for awww-daemon to start.
    app.layer.wl_surface().attach(None, 0, 0);
    app.layer.commit();
    conn.flush()?;
    let outcome = app.outcome.take().unwrap_or(Ok(Outcome::Cancel))?;
    Ok((outcome, app.content))
}

fn logical(px: u32, scale: f64) -> u32 {
    (f64::from(px) / scale).ceil() as u32
}

struct App {
    registry: RegistryState,
    seat: SeatState,
    outputs: OutputState,
    shm: Shm,
    qh: QueueHandle<App>,
    loop_handle: LoopHandle<'static, App>,
    layer: LayerSurface,
    viewport: WpViewport,
    pool: SlotPool,
    cursor_shapes: Option<CursorShapeManager>,
    shape_device: Option<WpCursorShapeDeviceV1>,
    cursor: Option<Shape>,
    enter_serial: u32,
    keyboard: Option<wl_keyboard::WlKeyboard>,
    pointer: Option<wl_pointer::WlPointer>,
    modifiers: Modifiers,
    /// Touchpad scroll not yet turned into steps.
    scroll: f64,
    scale: f64,
    font: Font,
    colors: Colors,
    layout: Layout,
    /// Buffer size in pixels, once configured.
    buffer: Option<(u32, u32)>,
    content: Content,
    picker: Picker,
    bench: bool,
    drawn: bool,
    outcome: Option<Result<Outcome>>,
}

impl App {
    fn draw(&mut self) {
        let Some((w, h)) = self.buffer else { return };
        let (buffer, buf) =
            match self.pool.create_buffer(w as i32, h as i32, w as i32 * 4, wl_shm::Format::Xrgb8888) {
                Ok(b) => b,
                Err(e) => return self.fail(e.into()),
            };
        let (page, selected) = self.picker.page();
        let frame = Frame { walls: &self.content.walls, page, selected };
        let mut canvas = Canvas { buf, width: w, height: h };
        draw::frame(&mut canvas, &self.layout, &self.colors, &self.font, &frame);

        let surface = self.layer.wl_surface();
        surface.damage_buffer(0, 0, w as i32, h as i32);
        if !self.drawn {
            surface.frame(&self.qh, FrameCallbackData(surface.clone()));
        }
        if let Err(e) = buffer.attach_to(surface) {
            return self.fail(e.into());
        }
        self.layer.commit();

        if !self.drawn {
            self.drawn = true;
            trace::mark("first frame committed");
            let paths: Vec<_> = self.content.walls.iter().map(|w| w.path.clone()).collect();
            thread::spawn(move || thumbs::prune(&paths));
        }
    }

    fn fail(&mut self, e: Box<dyn std::error::Error + Send + Sync>) {
        self.outcome = Some(Err(e));
    }

    fn apply(&mut self) {
        if let Some(i) = self.picker.selected() {
            self.outcome = Some(Ok(Outcome::Apply(i)));
        }
    }

    /// Runs `f` on the picker and redraws.
    fn update(&mut self, f: impl FnOnce(&mut Picker)) {
        f(&mut self.picker);
        self.draw();
    }

    fn key(&mut self, event: KeyEvent) {
        let ctrl = self.modifiers.ctrl;
        match event.keysym {
            Keysym::Escape => self.outcome = Some(Ok(Outcome::Cancel)),
            Keysym::c | Keysym::g | Keysym::bracketleft if ctrl => {
                self.outcome = Some(Ok(Outcome::Cancel));
            }
            Keysym::Return | Keysym::KP_Enter => self.apply(),
            Keysym::j | Keysym::m if ctrl => self.apply(),
            Keysym::Left | Keysym::Up | Keysym::ISO_Left_Tab | Keysym::KP_Left | Keysym::KP_Up => {
                self.update(|p| p.step(-1));
            }
            Keysym::p if ctrl => self.update(|p| p.step(-1)),
            Keysym::Right | Keysym::Down | Keysym::Tab | Keysym::KP_Right | Keysym::KP_Down => {
                self.update(|p| p.step(1));
            }
            Keysym::n if ctrl => self.update(|p| p.step(1)),
            Keysym::Page_Up | Keysym::KP_Page_Up => self.update(|p| p.page_step(-1)),
            Keysym::Page_Down | Keysym::KP_Page_Down => self.update(|p| p.page_step(1)),
            Keysym::Home | Keysym::KP_Home => self.update(Picker::first),
            Keysym::End | Keysym::KP_End => self.update(Picker::last),
            Keysym::BackSpace => self.update(Picker::pop),
            Keysym::u if ctrl => self.update(Picker::clear),
            _ => {
                let text = event.utf8.filter(|s| !s.chars().any(char::is_control));
                if let Some(text) = text.filter(|_| !ctrl && !self.modifiers.alt) {
                    self.update(|p| p.push(&text));
                }
            }
        }
    }

    fn set_cursor(&mut self, shape: Shape) {
        if self.cursor != Some(shape)
            && let Some(device) = &self.shape_device
        {
            device.set_shape(self.enter_serial, shape);
            self.cursor = Some(shape);
        }
    }
}

impl LayerShellHandler for App {
    fn closed(&mut self, _: &Connection, _: &QueueHandle<Self>, _: &LayerSurface) {
        self.outcome = Some(Ok(Outcome::Cancel));
    }

    fn configure(
        &mut self,
        _: &Connection,
        _: &QueueHandle<Self>,
        _: &LayerSurface,
        configure: LayerSurfaceConfigure,
        _: u32,
    ) {
        let (w, h) = configure.new_size;
        let width = if w == 0 { self.layout.width } else { (f64::from(w) * self.scale).round() as u32 };
        let layout = Layout::new(width, self.scale, self.font.line_height);
        if layout.icon != self.content.icon {
            // The surface landed somewhere other than the monitor Hyprland
            // reported as focused.
            let paths = self.content.walls.drain(..).map(|w| w.path).collect();
            self.content.walls = thumbs::load(paths, layout.icon);
            self.content.icon = layout.icon;
        }
        let height = logical(layout.height, self.scale);
        self.layout = layout;
        if h != height {
            self.layer.set_size(0, height);
            self.layer.commit();
            return;
        }
        let w = if w == 0 { logical(width, self.scale) } else { w };
        self.viewport.set_destination(w as i32, h as i32);
        self.buffer = Some((width, (f64::from(h) * self.scale).round() as u32));
        trace::mark("configured");
        self.draw();
    }
}

impl CompositorHandler for App {
    fn frame(&mut self, _: &Connection, _: &QueueHandle<Self>, _: &wl_surface::WlSurface, _: u32) {
        trace::mark("first frame shown (frame callback)");
        if self.bench {
            self.outcome = Some(Ok(Outcome::Cancel));
        }
    }

    fn scale_factor_changed(&mut self, _: &Connection, _: &QueueHandle<Self>, _: &wl_surface::WlSurface, _: i32) {}
    fn transform_changed(
        &mut self,
        _: &Connection,
        _: &QueueHandle<Self>,
        _: &wl_surface::WlSurface,
        _: wl_output::Transform,
    ) {
    }
    fn surface_enter(&mut self, _: &Connection, _: &QueueHandle<Self>, _: &wl_surface::WlSurface, _: &wl_output::WlOutput) {}
    fn surface_leave(&mut self, _: &Connection, _: &QueueHandle<Self>, _: &wl_surface::WlSurface, _: &wl_output::WlOutput) {}
}

impl KeyboardHandler for App {
    fn press_key(&mut self, _: &Connection, _: &QueueHandle<Self>, _: &wl_keyboard::WlKeyboard, _: u32, event: KeyEvent) {
        self.key(event);
    }

    fn repeat_key(&mut self, _: &Connection, _: &QueueHandle<Self>, _: &wl_keyboard::WlKeyboard, _: u32, event: KeyEvent) {
        self.key(event);
    }

    fn update_modifiers(
        &mut self,
        _: &Connection,
        _: &QueueHandle<Self>,
        _: &wl_keyboard::WlKeyboard,
        _: u32,
        modifiers: Modifiers,
        _: RawModifiers,
        _: u32,
    ) {
        self.modifiers = modifiers;
    }

    fn enter(
        &mut self,
        _: &Connection,
        _: &QueueHandle<Self>,
        _: &wl_keyboard::WlKeyboard,
        _: &wl_surface::WlSurface,
        _: u32,
        _: &[u32],
        _: &[Keysym],
    ) {
    }
    fn leave(&mut self, _: &Connection, _: &QueueHandle<Self>, _: &wl_keyboard::WlKeyboard, _: &wl_surface::WlSurface, _: u32) {}
    fn release_key(&mut self, _: &Connection, _: &QueueHandle<Self>, _: &wl_keyboard::WlKeyboard, _: u32, _: KeyEvent) {}
}

impl PointerHandler for App {
    fn pointer_frame(
        &mut self,
        _: &Connection,
        _: &QueueHandle<Self>,
        _: &wl_pointer::WlPointer,
        events: &[PointerEvent],
    ) {
        for event in events {
            if &event.surface != self.layer.wl_surface() {
                continue;
            }
            let (x, y) = event.position;
            let col = self.layout.hit(x * self.scale, y * self.scale);
            let over_tile = col.is_some_and(|c| c < self.picker.page().0.len());
            match event.kind {
                PointerEventKind::Enter { serial } => {
                    self.enter_serial = serial;
                    self.cursor = None;
                }
                // Like rofi's hover-select, only movement selects, so
                // opening the picker under the pointer keeps the preselection.
                PointerEventKind::Motion { .. } => {
                    if let Some(col) = col
                        && self.picker.select_column(col)
                    {
                        self.draw();
                    }
                }
                PointerEventKind::Press { button: BTN_LEFT, .. } if over_tile => {
                    if let Some(col) = col {
                        self.picker.select_column(col);
                    }
                    self.apply();
                }
                PointerEventKind::Axis { horizontal, vertical, .. } => {
                    // value120 is wheel clicks in 1/120ths; touchpads send
                    // only pixel distances.
                    let clicks = vertical.value120 + horizontal.value120;
                    self.scroll += if clicks != 0 {
                        f64::from(clicks) / 120.0 * SCROLL_STEP
                    } else {
                        vertical.absolute + horizontal.absolute
                    };
                    let n = (self.scroll / SCROLL_STEP).trunc();
                    if n != 0.0 {
                        self.scroll -= n * SCROLL_STEP;
                        self.update(|p| p.step(n as isize));
                    }
                }
                _ => {}
            }
            self.set_cursor(if over_tile { Shape::Pointer } else { Shape::Default });
        }
    }
}

impl SeatHandler for App {
    fn seat_state(&mut self) -> &mut SeatState {
        &mut self.seat
    }

    fn new_capability(&mut self, _: &Connection, qh: &QueueHandle<Self>, seat: wl_seat::WlSeat, capability: Capability) {
        match capability {
            Capability::Keyboard if self.keyboard.is_none() => {
                let repeat = Box::new(|app: &mut App, _: &wl_keyboard::WlKeyboard, event| app.key(event));
                match self.seat.get_keyboard_with_repeat(qh, &seat, None, self.loop_handle.clone(), repeat) {
                    Ok(keyboard) => self.keyboard = Some(keyboard),
                    Err(e) => self.fail(e.into()),
                }
            }
            Capability::Pointer if self.pointer.is_none() => {
                if let Ok(pointer) = self.seat.get_pointer(qh, &seat) {
                    self.shape_device = self.cursor_shapes.as_ref().map(|m| m.get_shape_device(&pointer, qh));
                    self.pointer = Some(pointer);
                }
            }
            _ => {}
        }
    }

    fn remove_capability(&mut self, _: &Connection, _: &QueueHandle<Self>, _: wl_seat::WlSeat, capability: Capability) {
        match capability {
            Capability::Keyboard => {
                if let Some(k) = self.keyboard.take() {
                    k.release();
                }
            }
            Capability::Pointer => {
                if let Some(d) = self.shape_device.take() {
                    d.destroy();
                }
                if let Some(p) = self.pointer.take() {
                    p.release();
                }
            }
            _ => {}
        }
    }

    fn new_seat(&mut self, _: &Connection, _: &QueueHandle<Self>, _: wl_seat::WlSeat) {}
    fn remove_seat(&mut self, _: &Connection, _: &QueueHandle<Self>, _: wl_seat::WlSeat) {}
}

impl OutputHandler for App {
    fn output_state(&mut self) -> &mut OutputState {
        &mut self.outputs
    }

    fn new_output(&mut self, _: &Connection, _: &QueueHandle<Self>, _: wl_output::WlOutput) {}
    fn update_output(&mut self, _: &Connection, _: &QueueHandle<Self>, _: wl_output::WlOutput) {}
    fn output_destroyed(&mut self, _: &Connection, _: &QueueHandle<Self>, _: wl_output::WlOutput) {}
}

impl ShmHandler for App {
    fn shm_state(&mut self) -> &mut Shm {
        &mut self.shm
    }
}

impl ProvidesRegistryState for App {
    fn registry(&mut self) -> &mut RegistryState {
        &mut self.registry
    }
    registry_handlers![OutputState, SeatState];
}

/// User data for the viewporter objects, which have no events.
struct NoEvents;

impl<I: Proxy> Dispatch2<I, App> for NoEvents {
    fn event(&self, _: &mut App, _: &I, _: I::Event, _: &Connection, _: &QueueHandle<App>) {}
}

delegate_registry!(App);
smithay_client_toolkit::delegate_dispatch2!(App);
