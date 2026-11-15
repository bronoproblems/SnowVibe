#![cfg_attr(not(debug_assertions), windows_subsystem = "windows")]
mod settings;
mod engine;
mod render;
mod native;
mod ui;
mod ui_art;
mod diagnostics;
mod scanner;
mod frame_clock;
use engine::Engine;
use native::{wide,Layer,Tray};
use settings::Settings;
use ui::Ui;
use std::{cell::RefCell,mem::{zeroed,size_of},ptr::{null,null_mut},time::{Duration,Instant}};
use windows_sys::Win32::{Foundation::*,Graphics::Gdi::*,System::Threading::*,
    UI::{WindowsAndMessaging::*,Controls::*,Input::KeyboardAndMouse::*,HiDpi::*}};

struct Desktop{layer:Layer,engine:Engine,paused:bool}
struct App{
    ui:Ui,tray:Tray,settings:Settings,desktops:Vec<Desktop>,last:Instant,
    scanner:Option<scanner::WindowScanner>,
    timer_resolution:Option<frame_clock::FrameClock>,timer_interval:u32,
    metrics:Option<diagnostics::Metrics>,last_tray_retry:Instant,
    dirty:bool,pressed:bool,rebuild:bool,taskbar_message:u32,smoke_end:Option<Instant>,save_error:bool,
}
thread_local!{static APP:RefCell<Option<App>>=const{RefCell::new(None)};}
unsafe fn message(text:&str){MessageBoxW(null_mut(),wide(text).as_ptr(),wide("SnowVibe").as_ptr(),MB_OK|MB_ICONERROR);}
impl App{
    unsafe fn new(smoke:bool,preview:bool)->Result<Self,String>{
        native::register("SnowVibeSettings",Some(window_proc))?;Layer::register()?;
        let ic=INITCOMMONCONTROLSEX{dwSize:size_of::<INITCOMMONCONTROLSEX>() as u32,dwICC:ICC_BAR_CLASSES};InitCommonControlsEx(&ic);
        let ui=Ui::new()?;
        if smoke && (GetWindowLongPtrW(ui.hwnd,GWL_EXSTYLE) as u32 & WS_EX_TOPMOST != 0 || GetWindowLongPtrW(ui.hwnd,GWL_STYLE) as u32 & WS_THICKFRAME != 0){return Err("Settings window must be fixed-size and not topmost".into());}
        let tray=Tray::new(ui.hwnd)?;let settings=Settings::load();ui.sync(&settings);
        let args:Vec<String>=std::env::args().collect();
        let metrics=if let Some(index)=args.iter().position(|a|a=="--metrics"){Some(diagnostics::Metrics::new(args.get(index+1).ok_or("Missing metrics path")?).map_err(|e|e.to_string())?)}else{None};
        let mut app=Self{ui,tray,settings,desktops:vec![],last:Instant::now(),timer_resolution:None,timer_interval:0,metrics,last_tray_retry:Instant::now(),scanner:if preview{None}else{Some(scanner::WindowScanner::new().map_err(|e|e.to_string())?)},dirty:false,pressed:false,rebuild:false,
            taskbar_message:RegisterWindowMessageW(wide("TaskbarCreated").as_ptr()),
            smoke_end:if smoke{Some(Instant::now()+Duration::from_secs(8))}else{None},save_error:false};
        if !preview{app.rebuild()?;app.scan();}app.timer();SetTimer(app.ui.hwnd,2,100,None);Ok(app)
    }
    unsafe fn timer(&mut self){
        let interval=if self.settings.enabled && self.desktops.iter().any(|d|!d.paused){self.settings.fps}else{0};
        if interval==self.timer_interval{return;}
        KillTimer(self.ui.hwnd,1);self.timer_resolution=None;self.last=Instant::now();self.timer_interval=interval;
        if interval>0{
            self.timer_resolution=frame_clock::FrameClock::new(self.ui.hwnd,interval).ok();
            if self.timer_resolution.is_none(){SetTimer(self.ui.hwnd,1,1000/interval,None);}
        }else{self.timer_resolution=None;for d in &mut self.desktops{d.layer.hide();}}
    }
    unsafe fn rebuild(&mut self)->Result<(),String>{
        let mut desktops=vec![];
        for b in native::monitors(){desktops.push(Desktop{layer:Layer::new(b)?,engine:Engine::new(b),paused:false});}
        self.desktops=desktops;self.pressed=false;self.rebuild=false;self.timer();Ok(())
    }
    fn scan(&self){if let Some(scanner)=&self.scanner{scanner.request();}}
    unsafe fn changed(&mut self){
        for d in &mut self.desktops{d.engine.settings_changed(&self.settings);}
        self.timer();self.dirty=true;self.save_error=false;
    }
    unsafe fn tick(&mut self)->Result<(),String>{
        if !self.settings.enabled{return Ok(());}
        let now=Instant::now();let dt=now.duration_since(self.last).as_secs_f32();self.last=now;
        let mut p=POINT{x:0,y:0};GetCursorPos(&mut p);let mouse=(p.x as f32,p.y as f32);
        let pressed=GetAsyncKeyState(VK_LBUTTON as i32)<0 && GetAsyncKeyState(VK_MENU as i32)<0;
        let front=if GetForegroundWindow()==self.ui.hwnd && IsWindowVisible(self.ui.hwnd)!=0 && IsIconic(self.ui.hwnd)==0{
            let mut r:RECT=zeroed();if GetWindowRect(self.ui.hwnd,&mut r)!=0{Some(native::rect(r))}else{None}
        }else{None};
        let(mut simulation,mut drawing,mut presenting)=(0.0,0.0,0.0);
        for d in &mut self.desktops{
            if d.paused{continue;}
            let inside=p.x as f32>=d.engine.bounds.x && (p.x as f32)<d.engine.bounds.right() && p.y as f32>=d.engine.bounds.y && (p.y as f32)<d.engine.bounds.bottom();
            let timer=Instant::now();
            d.engine.pointer(mouse,pressed && inside,self.pressed,&self.settings);
            d.engine.step(dt,&self.settings,mouse);
            simulation+=timer.elapsed().as_secs_f64();let timer=Instant::now();
            render::draw_with_front(&mut d.layer.pixmap,&d.engine,&self.settings,front);drawing+=timer.elapsed().as_secs_f64();let timer=Instant::now();d.layer.present()?;presenting+=timer.elapsed().as_secs_f64();
        }
        if let Some(metrics)=&mut self.metrics{metrics.frame(simulation,drawing,presenting);}
        self.pressed=pressed;Ok(())
    }
    unsafe fn housekeep(&mut self)->Result<(),String>{
        if self.smoke_end.is_some_and(|end|Instant::now()>=end){PostQuitMessage(0);return Ok(());}
        if self.rebuild{self.rebuild()?;}
        if !self.tray.available && self.last_tray_retry.elapsed()>=Duration::from_secs(5){self.tray.restore();self.last_tray_retry=Instant::now();}
        if let Some(metrics)=&mut self.metrics{metrics.report(self.desktops.iter().map(|d|(d.engine.surfaces.len(),d.engine.surfaces.values().filter(|s|s.taskbar).count(),d.engine.surfaces.values().flat_map(|s|s.pile.iter()).copied().sum(),d.engine.surfaces.values().filter(|s|s.taskbar).flat_map(|s|s.pile.iter()).copied().fold(0.0_f32,f32::max))),self.tray.available).map_err(|e|e.to_string())?;}
        if self.dirty && !self.save_error{
            if let Err(e)=self.settings.save(){self.save_error=true;message(&format!("Не удалось сохранить настройки: {e}"));}
            else{self.dirty=false;}
        }
        if self.settings.enabled && !self.desktops.is_empty(){
            if let Some(scanner)=&self.scanner{
                let windows=scanner.snapshots();
                for d in &mut self.desktops{
                    d.paused=self.settings.pause_fullscreen && native::fullscreen(d.engine.bounds);
                    if d.paused{d.layer.hide();}else{d.engine.refresh(&windows);}
                }
            }
            self.scan();self.timer();
        }Ok(())
    }
    unsafe fn command(&mut self,id:u16){
        match id{
            1|3..=10=>{self.ui.read(&mut self.settings);self.changed();},
            12|102=>{for d in &mut self.desktops{d.engine.clear();}},
            13|103=>{for d in &mut self.desktops{d.engine.summon_plow(&self.settings);}},
            100=>self.ui.show(),
            101=>{self.settings.enabled=!self.settings.enabled;self.ui.sync(&self.settings);self.changed();},
            14|104=>PostQuitMessage(0),
            15=>{ShowWindow(self.ui.hwnd,SW_MINIMIZE);},
            16=>{PostMessageW(self.ui.hwnd,WM_CLOSE,0,0);},
            20..=23=>{self.settings.style=(id-20) as usize;self.ui.sync(&self.settings);self.changed();},
            105=>{self.settings.pause_fullscreen=!self.settings.pause_fullscreen;self.changed();},_=>{}
        }
    }
}
unsafe extern "system" fn window_proc(h:HWND,m:u32,w:WPARAM,l:LPARAM)->LRESULT{
    if m==WM_CLOSE{
        let can_hide=APP.with(|c|c.try_borrow().ok().and_then(|a|a.as_ref().map(|a|a.tray.available)).unwrap_or(false));
        ShowWindow(h,if can_hide{SW_HIDE}else{SW_MINIMIZE});return 0;
    }
    if m==WM_NCCALCSIZE || m==WM_NCPAINT{return 0;}
    if m==WM_NCACTIVATE{return 1;}
    if m==WM_ERASEBKGND{return 1;}
    if m==WM_CTLCOLORSTATIC || m==WM_CTLCOLORBTN{
        SetTextColor(w as HDC,0x00FFF4E8);SetBkColor(w as HDC,0x0020140E);
        SetDCBrushColor(w as HDC,0x0020140E);return GetStockObject(DC_BRUSH) as isize;
    }
    let result=APP.with(|cell|{
        let Ok(mut slot)=cell.try_borrow_mut() else{return None;};let Some(app)=slot.as_mut() else{return None;};
        match m{
            m if m==WM_APP+2=>{let result=app.tick();if let Some(clock)=&app.timer_resolution{clock.frame_finished();}if let Err(e)=result{message(&e);PostQuitMessage(1);}Some(0)},
            WM_TIMER=>{
                let result=if w==1{app.tick()}else{app.housekeep()};
                if let Err(e)=result{message(&e);PostQuitMessage(1);}Some(0)
            },
            WM_COMMAND=>{app.command((w&0xffff) as u16);Some(0)},
            WM_HSCROLL=>{app.ui.read(&mut app.settings);app.changed();Some(0)},
            WM_PAINT=>{app.ui.paint();Some(0)},
            WM_NCHITTEST=>Some(app.ui.hit_test(l)),
            WM_SYSCOMMAND if w==0x110=>{PostQuitMessage(0);Some(0)},
            WM_DISPLAYCHANGE|WM_DPICHANGED=>{app.rebuild=true;Some(0)},
            _ if m==WM_APP+1=>{match l as u32{WM_LBUTTONUP|WM_LBUTTONDBLCLK=>app.ui.show(),WM_RBUTTONUP=>{let command=app.tray.menu(app.settings.enabled,app.settings.pause_fullscreen);app.command(command);},_=>{}}Some(0)},
            _ if m==app.taskbar_message=>{app.tray.restore();Some(0)},
            _=>None
        }
    });
    result.unwrap_or_else(||DefWindowProcW(h,m,w,l))
}
fn main(){unsafe{
    SetProcessDpiAwarenessContext(DPI_AWARENESS_CONTEXT_PER_MONITOR_AWARE_V2);
    let args:Vec<String>=std::env::args().collect();
    if args.get(1).is_some_and(|a|a=="--benchmark"){
        if let Some(path)=args.get(2){match diagnostics::benchmark(path){Ok(())=>{},Err(e)=>{message(&e.to_string());std::process::exit(1);}}}else{std::process::exit(2);}return;
    }
    let preview=std::env::args().any(|a|a=="--ui-preview");
    let smoke=std::env::args().any(|a|a=="--smoke-test");
    let mutex=CreateMutexW(null(),0,wide(&if smoke{format!("Local\\SnowVibe.Windows.Smoke.{}",GetCurrentProcessId())}else if preview{"Local\\SnowVibe.Windows.Preview".into()}else{"Local\\SnowVibe.Windows.v1".into()}).as_ptr());
    if mutex.is_null(){message("Не удалось создать блокировку приложения");return;}
    if GetLastError()==ERROR_ALREADY_EXISTS{
        let hwnd=FindWindowW(wide("SnowVibeSettings").as_ptr(),null());if !hwnd.is_null(){ShowWindow(hwnd,SW_RESTORE);SetForegroundWindow(hwnd);}CloseHandle(mutex);return;
    }
    match App::new(smoke,preview){
        Ok(app)=>{let hwnd=app.ui.hwnd;APP.with(|cell|*cell.borrow_mut()=Some(app));ShowWindow(hwnd,SW_SHOW);UpdateWindow(hwnd);
            let mut msg:MSG=zeroed();let exit_code;loop{
                let result=GetMessageW(&mut msg,null_mut(),0,0);if result<=0{exit_code=if result<0{1}else{msg.wParam as i32};break;}
                if IsDialogMessageW(hwnd,&msg)==0{TranslateMessage(&msg);DispatchMessageW(&msg);}
            }
            APP.with(|cell|{let mut slot=cell.borrow_mut();if let Some(app)=slot.as_mut(){
                KillTimer(app.ui.hwnd,1);KillTimer(app.ui.hwnd,2);
                if app.dirty{if let Err(e)=app.settings.save(){message(&format!("Не удалось сохранить настройки: {e}"));}}
            }slot.take();});
            CloseHandle(mutex);std::process::exit(exit_code);
        },Err(e)=>{message(&e);CloseHandle(mutex);std::process::exit(1); }
    }
}}
