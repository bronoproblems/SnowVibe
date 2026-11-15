use crate::engine::{Rect, Snapshot};
use std::{mem::{size_of, zeroed}, ptr::{null, null_mut}};
use windows_sys::Win32::{Foundation::*, Graphics::{Gdi::*, Dwm::*},
    System::{LibraryLoader::*, Threading::*}, UI::{WindowsAndMessaging::*, Shell::*}};

pub fn wide(s:&str)->Vec<u16>{s.encode_utf16().chain(Some(0)).collect()}
pub fn rect(r:RECT)->Rect{Rect{x:r.left as f32,y:r.top as f32,w:(r.right-r.left) as f32,h:(r.bottom-r.top) as f32}}
pub unsafe fn class_name(hwnd:HWND)->String{
    let mut text=[0_u16;256]; let n=GetClassNameW(hwnd,text.as_mut_ptr(),256); String::from_utf16_lossy(&text[..n.max(0) as usize])
}
pub unsafe fn snapshots()->Vec<Snapshot>{
    unsafe extern "system" fn visit(hwnd:HWND,param:LPARAM)->i32{
        let out=&mut *(param as *mut Vec<Snapshot>);
        if IsWindowVisible(hwnd)==0 || IsIconic(hwnd)!=0 {return 1;}
        let mut pid=0; GetWindowThreadProcessId(hwnd,&mut pid);
        let name=class_name(hwnd);
        if name=="SnowVibeOverlay"{return 1;}
        let taskbar=name=="Shell_TrayWnd" || name=="Shell_SecondaryTrayWnd";
        if ["Progman","WorkerW","tooltips_class32","MultitaskingViewFrame"].contains(&name.as_str()){return 1;}
        let ex=GetWindowLongPtrW(hwnd,GWL_EXSTYLE) as u32;
        if !taskbar && ex&WS_EX_TRANSPARENT!=0{return 1;}
        if !taskbar && ex&WS_EX_LAYERED!=0{let(mut alpha,mut flags)=(255_u8,0_u32);if GetLayeredWindowAttributes(hwnd,null_mut(),&mut alpha,&mut flags)!=0 && flags&LWA_ALPHA!=0 && alpha==0{return 1;}}
        let accumulates=pid!=GetCurrentProcessId() && (taskbar || (ex&WS_EX_TOOLWINDOW==0 && ex&WS_EX_NOACTIVATE==0));
        let mut cloaked=0_u32;
        DwmGetWindowAttribute(hwnd,DWMWA_CLOAKED as u32,&mut cloaked as *mut _ as _,4);
        if cloaked!=0{return 1;}
        let mut r:RECT=zeroed();
        if DwmGetWindowAttribute(hwnd,DWMWA_EXTENDED_FRAME_BOUNDS as u32,&mut r as *mut _ as _,size_of::<RECT>() as u32)<0 {
            if GetWindowRect(hwnd,&mut r)==0{return 1;}
        }
        let r=rect(r);
        if r.w>0.0 && r.h>0.0 && r.w.is_finite() && r.h.is_finite() {
            let accumulates=accumulates && r.w>=(if taskbar{24.0}else{120.0}) && r.h>=(if taskbar{24.0}else{55.0});
            out.push(Snapshot{id:hwnd as isize,rect:r,taskbar,accumulates});
        } 1
    }
    let mut out=Vec::new(); EnumWindows(Some(visit),&mut out as *mut _ as isize); out
}
pub unsafe fn monitors()->Vec<Rect>{
    unsafe extern "system" fn visit(_m:HMONITOR,_dc:HDC,r:*mut RECT,p:LPARAM)->i32{
        (&mut *(p as *mut Vec<Rect>)).push(rect(*r));1
    }
    let mut out=vec![]; EnumDisplayMonitors(null_mut(),null(),Some(visit),&mut out as *mut _ as isize);out
}
pub unsafe fn fullscreen(bounds:Rect)->bool{
    let h=GetForegroundWindow(); if h.is_null(){return false;}
    let name=class_name(h); if ["Progman","WorkerW","Shell_TrayWnd","Shell_SecondaryTrayWnd"].contains(&name.as_str()){return false;}
    let mut pid=0;GetWindowThreadProcessId(h,&mut pid);if pid==GetCurrentProcessId(){return false;}
    let mut r:RECT=zeroed();if GetWindowRect(h,&mut r)==0{return false;}
    let r=rect(r);
    r.x<=bounds.x && r.y<=bounds.y && r.right()>=bounds.right() && r.bottom()>=bounds.bottom()
        && GetWindowLongPtrW(h,GWL_STYLE) as u32 & WS_CAPTION == 0
}
pub unsafe fn register(name:&str,proc:WNDPROC)->Result<(),String>{
    let name=wide(name);
    let wc=WNDCLASSW{lpfnWndProc:proc,hInstance:GetModuleHandleW(null()),lpszClassName:name.as_ptr(),
        hCursor:LoadCursorW(null_mut(),IDC_ARROW),..zeroed()};
    if RegisterClassW(&wc)==0{Err(format!("RegisterClassW: {}",GetLastError()))}else{Ok(())}
}
unsafe extern "system" fn overlay_proc(h:HWND,m:u32,w:WPARAM,l:LPARAM)->LRESULT{
    match m{WM_NCHITTEST=>HTTRANSPARENT as isize,WM_MOUSEACTIVATE=>MA_NOACTIVATE as isize,_=>DefWindowProcW(h,m,w,l)}
}
pub struct Layer{
    pub hwnd:HWND,dc:HDC,bitmap:HBITMAP,old:HGDIOBJ,bits:*mut u8,pub pixmap:tiny_skia::Pixmap,pub bounds:Rect,pub visible:bool,
}
impl Layer{
    pub unsafe fn register()->Result<(),String>{register("SnowVibeOverlay",Some(overlay_proc))}
    pub unsafe fn new(bounds:Rect)->Result<Self,String>{
        let width=bounds.w as u32;let height=bounds.h as u32;
        let pixmap=tiny_skia::Pixmap::new(width,height).ok_or("Недостаточно памяти для монитора")?;
        let h=CreateWindowExW(WS_EX_LAYERED|WS_EX_TRANSPARENT|WS_EX_TOOLWINDOW|WS_EX_NOACTIVATE|WS_EX_TOPMOST,
            wide("SnowVibeOverlay").as_ptr(),wide("SnowVibe — снег").as_ptr(),WS_POPUP,
            bounds.x as i32,bounds.y as i32,width as i32,height as i32,null_mut(),null_mut(),GetModuleHandleW(null()),null());
        if h.is_null(){return Err(format!("CreateWindowExW: {}",GetLastError()));}
        let dc=CreateCompatibleDC(null_mut());if dc.is_null(){DestroyWindow(h);return Err("CreateCompatibleDC".into());}
        let mut info:BITMAPINFO=zeroed();info.bmiHeader=BITMAPINFOHEADER{biSize:size_of::<BITMAPINFOHEADER>() as u32,
            biWidth:width as i32,biHeight:-(height as i32),biPlanes:1,biBitCount:32,biCompression:BI_RGB,..zeroed()};
        let mut bits=null_mut();let bitmap=CreateDIBSection(dc,&info,DIB_RGB_COLORS,&mut bits,null_mut(),0);
        if bitmap.is_null(){DeleteDC(dc);DestroyWindow(h);return Err("CreateDIBSection".into());}
        let old=SelectObject(dc,bitmap);
        if old.is_null() || old as isize == -1{DeleteObject(bitmap);DeleteDC(dc);DestroyWindow(h);return Err("SelectObject failed".into());}
        Ok(Self{hwnd:h,dc,bitmap,old,bits:bits as _,pixmap,bounds,visible:false})
    }
    pub unsafe fn present(&mut self)->Result<(),String>{
        let out=std::slice::from_raw_parts_mut(self.bits,self.pixmap.data().len());
        for (src,dst) in self.pixmap.data().chunks_exact(4).zip(out.chunks_exact_mut(4)){
            dst[0]=src[2];dst[1]=src[1];dst[2]=src[0];dst[3]=src[3];
        }
        let pos=POINT{x:self.bounds.x as i32,y:self.bounds.y as i32};
        let size=SIZE{cx:self.bounds.w as i32,cy:self.bounds.h as i32};let src=POINT{x:0,y:0};
        let blend=BLENDFUNCTION{BlendOp:AC_SRC_OVER as u8,BlendFlags:0,SourceConstantAlpha:255,AlphaFormat:AC_SRC_ALPHA as u8};
        if UpdateLayeredWindow(self.hwnd,null_mut(),&pos,&size,self.dc,&src,0,&blend,ULW_ALPHA)==0{
            return Err(format!("UpdateLayeredWindow: {}",GetLastError()));
        }
        if !self.visible{ShowWindow(self.hwnd,SW_SHOWNOACTIVATE);self.visible=true;}
        Ok(())
    }
    pub unsafe fn hide(&mut self){if self.visible{ShowWindow(self.hwnd,SW_HIDE);self.visible=false;}}
}
impl Drop for Layer{fn drop(&mut self){unsafe{SelectObject(self.dc,self.old);DeleteObject(self.bitmap);DeleteDC(self.dc);DestroyWindow(self.hwnd);}}}

pub struct Tray{data:NOTIFYICONDATAW,icon:HICON,pub available:bool}
impl Tray{
    pub unsafe fn new(hwnd:HWND)->Result<Self,String>{
        // A real alpha icon; no external asset or dependency at runtime.
        let mut p=tiny_skia::Pixmap::new(32,32).unwrap();
        let mut paint=tiny_skia::Paint::default();paint.set_color_rgba8(208,239,255,255);
        let mut b=tiny_skia::PathBuilder::new();
        for i in 0..3{let a=i as f32*std::f32::consts::PI/3.0;let(x,y)=(a.cos()*13.0,a.sin()*13.0);
            b.move_to(16.0-x,16.0-y);b.line_to(16.0+x,16.0+y);}
        p.stroke_path(&b.finish().unwrap(),&paint,&tiny_skia::Stroke{width:2.0,..Default::default()},tiny_skia::Transform::identity(),None);
        let mut bgra=p.data().to_vec();for c in bgra.chunks_exact_mut(4){c.swap(0,2);}
        let color=CreateBitmap(32,32,1,32,bgra.as_ptr() as _);
        let mask=CreateBitmap(32,32,1,1,[0_u8;128].as_ptr() as _);
        let ii=ICONINFO{fIcon:1,xHotspot:0,yHotspot:0,hbmMask:mask,hbmColor:color};
        let icon=CreateIconIndirect(&ii);DeleteObject(color);DeleteObject(mask);
        if icon.is_null(){return Err("CreateIconIndirect".into());}
        let mut data:NOTIFYICONDATAW=zeroed();data.cbSize=size_of::<NOTIFYICONDATAW>() as u32;
        data.hWnd=hwnd;data.uID=1;data.uFlags=NIF_ICON|NIF_MESSAGE|NIF_TIP;data.uCallbackMessage=WM_APP+1;data.hIcon=icon;
        let tip=wide("SnowVibe — настройки снега");data.szTip[..tip.len()].copy_from_slice(&tip);
        let available=Shell_NotifyIconW(NIM_ADD,&data)!=0;
        Ok(Self{data,icon,available})
    }
    pub unsafe fn restore(&mut self){self.available=Shell_NotifyIconW(NIM_ADD,&self.data)!=0 || Shell_NotifyIconW(NIM_MODIFY,&self.data)!=0;}
    pub unsafe fn menu(&self,enabled:bool,pause_fullscreen:bool)->u16{
        let menu=CreatePopupMenu();
        AppendMenuW(menu,MF_STRING,100,wide("Открыть SnowVibe…").as_ptr());
        AppendMenuW(menu,MF_STRING,101,wide(if enabled{"Выключить снег"}else{"Включить снег"}).as_ptr());
        AppendMenuW(menu,MF_SEPARATOR,0,null());
        AppendMenuW(menu,MF_STRING,102,wide("Очистить весь снег").as_ptr());
        AppendMenuW(menu,MF_STRING,103,wide("Запустить снегоуборщик").as_ptr());
        AppendMenuW(menu,MF_STRING|if pause_fullscreen{MF_CHECKED}else{0},105,wide("Пауза в полноэкранных приложениях").as_ptr());
        AppendMenuW(menu,MF_SEPARATOR,0,null());AppendMenuW(menu,MF_STRING,104,wide("Выйти").as_ptr());
        let mut p=POINT{x:0,y:0};GetCursorPos(&mut p);SetForegroundWindow(self.data.hWnd);
        let command=TrackPopupMenu(menu,TPM_RIGHTBUTTON|TPM_RETURNCMD,p.x,p.y,0,self.data.hWnd,null());
        PostMessageW(self.data.hWnd,WM_NULL,0,0);DestroyMenu(menu);command as u16
    }
}
impl Drop for Tray{fn drop(&mut self){unsafe{Shell_NotifyIconW(NIM_DELETE,&self.data);DestroyIcon(self.icon);}}}
