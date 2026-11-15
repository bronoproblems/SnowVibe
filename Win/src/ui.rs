use crate::{native::wide,settings::Settings,ui_art::{self,Canvas,BG,CARD}};
use std::{cell::RefCell,rc::Rc,mem::{zeroed,size_of},ptr::{null,null_mut}};
use windows_sys::Win32::{Foundation::*,Graphics::{Gdi::*,Dwm::*},System::LibraryLoader::*,UI::{WindowsAndMessaging::*,Controls::*,HiDpi::*,Shell::*,Input::KeyboardAndMouse::*}};

#[derive(Clone,Copy)]enum Kind{Switch,Check,Segment(usize),Slider,Action(u16),Close,Minimize}
struct Control{kind:Kind,scale:f32,font:HFONT,model:Rc<RefCell<Settings>>,text:String}
pub struct Ui{construction_error:Option<String>,pub hwnd:HWND,pub controls:Vec<(u16,HWND)>,fonts:Vec<HFONT>,scale:f32,model:Rc<RefCell<Settings>>,background:Vec<u8>,width:i32,height:i32}
unsafe fn font(size:f32,weight:i32,scale:f32)->HFONT{
    CreateFontW(-(size*scale).round() as i32,0,0,0,weight,0,0,0,DEFAULT_CHARSET as u32,OUT_DEFAULT_PRECIS as u32,CLIP_DEFAULT_PRECIS as u32,CLEARTYPE_QUALITY as u32,DEFAULT_PITCH as u32,wide("Segoe UI").as_ptr())
}
unsafe fn blit(dc:HDC,bytes:&[u8],w:i32,h:i32){
    let mut info:BITMAPINFO=zeroed();info.bmiHeader=BITMAPINFOHEADER{biSize:size_of::<BITMAPINFOHEADER>() as u32,biWidth:w,biHeight:-h,biPlanes:1,biBitCount:32,biCompression:BI_RGB,..zeroed()};
    StretchDIBits(dc,0,0,w,h,0,0,w,h,bytes.as_ptr() as _,&info,DIB_RGB_COLORS,SRCCOPY);
}
unsafe fn text(dc:HDC,font:HFONT,s:f32,label:&str,x:f32,y:f32,w:f32,h:f32,color:[u8;3],flags:u32){
    SelectObject(dc,font);SetBkMode(dc,TRANSPARENT as i32);SetTextColor(dc,color[0] as u32|((color[1] as u32)<<8)|((color[2] as u32)<<16));
    let mut r=RECT{left:(x*s).round() as i32,top:(y*s).round() as i32,right:((x+w)*s).round() as i32,bottom:((y+h)*s).round() as i32};
    let t=wide(label);DrawTextW(dc,t.as_ptr(),(t.len()-1) as i32,&mut r,flags|DT_NOPREFIX);
}
unsafe extern "system" fn control_proc(h:HWND,m:u32,w:WPARAM,l:LPARAM,_id:usize,data:usize)->LRESULT{
    if m==WM_NCDESTROY{RemoveWindowSubclass(h,Some(control_proc),1);drop(Box::from_raw(data as *mut Control));return DefSubclassProc(h,m,w,l);}
    let c=&*(data as *const Control);
    if m==WM_ERASEBKGND{return 1;}
    if m==WM_PAINT{
        let mut ps:PAINTSTRUCT=zeroed();let dc=BeginPaint(h,&mut ps);let mut r:RECT=zeroed();GetClientRect(h,&mut r);
        let(w,hgt)=(r.right.max(1),r.bottom.max(1));let s=c.scale;let(lw,lh)=(w as f32/s,hgt as f32/s);
        let card=matches!(c.kind,Kind::Check|Kind::Slider|Kind::Segment(_));let mut a=Canvas::new(w as u32,hgt as u32,s,if card{CARD}else{BG});
        let checked=SendMessageW(h,BM_GETCHECK,0,0)==BST_CHECKED as isize;let pressed=SendMessageW(h,BM_GETSTATE,0,0)&BST_PUSHED as isize!=0;
        match c.kind{
            Kind::Switch=>{a.round(0.0,1.0,lw,24.0,12.0,[84,84,84]);a.round(if checked{lw-33.0}else{2.0},3.0,31.0,20.0,10.0,[230,230,230]);},
            Kind::Check=>{a.round(0.0,4.0,15.0,15.0,4.0,if checked{[86,86,86]}else{[65,65,65]});if checked{a.line(3.0,11.0,6.3,14.5,[235,235,235],2.0);a.line(6.3,14.5,12.0,7.0,[235,235,235],2.0);}},
            Kind::Segment(index)=>{a.round(0.0,0.0,lw,24.0,6.0,[62,62,62]);if index>0{a.round(0.0,0.0,6.0,24.0,0.0,[62,62,62]);}if index<3{a.round(lw-6.0,0.0,6.0,24.0,0.0,[62,62,62]);}if c.model.borrow().style==index{a.round(0.0,0.0,lw,24.0,6.0,[85,85,85]);}else if index<3{a.line(lw-0.5,5.0,lw-0.5,19.0,[105,105,105],0.7);}},
            Kind::Slider=>{let mut channel:RECT=zeroed();let mut thumb:RECT=zeroed();SendMessageW(h,TBM_GETCHANNELRECT,0,&mut channel as *mut _ as isize);SendMessageW(h,TBM_GETTHUMBRECT,0,&mut thumb as *mut _ as isize);let x=(thumb.left+thumb.right) as f32/2.0/s;
                a.round(channel.left as f32/s,lh/2.0-3.0,(channel.right-channel.left) as f32/s,6.0,3.0,[88,88,88]);a.round(x-10.0,lh/2.0-8.0,20.0,16.0,8.0,[222,222,222]);},
            Kind::Action(id)=>{a.round(0.0,0.0,lw,24.0,5.0,if pressed{[88,88,88]}else if id==13{[45,126,225]}else{[72,72,72]});ui_art::icon(&mut a,if id==12{5}else{6},20.0,12.0,[224,224,224]);},
            Kind::Close|Kind::Minimize=>{
                let(x,y)=(lw/2.0,lh/2.0);a.circle(x,y,6.0,if matches!(c.kind,Kind::Close){[255,95,87]}else{[255,189,46]});
                if matches!(c.kind,Kind::Close){a.line(x-2.0,y-2.0,x+2.0,y+2.0,[94,22,21],1.1);a.line(x-2.0,y+2.0,x+2.0,y-2.0,[94,22,21],1.1);}
                else{a.line(x-3.0,y,x+3.0,y,[105,68,9],1.1);}
            }
        }
        blit(dc,&a.bgra(),w,hgt);
        match c.kind{
            Kind::Check=>text(dc,c.font,s,&c.text,22.0,0.0,lw-22.0,23.0,[224,224,224],DT_SINGLELINE|DT_VCENTER),
            Kind::Segment(_)=>text(dc,c.font,s,&c.text,0.0,0.0,lw,24.0,[222,222,222],DT_SINGLELINE|DT_VCENTER|DT_CENTER),
            Kind::Action(_)=>text(dc,c.font,s,&c.text,32.0,0.0,lw-36.0,24.0,[238,238,238],DT_SINGLELINE|DT_VCENTER|DT_CENTER),_=>{}
        }
        if GetFocus()==h && !matches!(c.kind,Kind::Close|Kind::Minimize) && SendMessageW(h,WM_QUERYUISTATE,0,0)&UISF_HIDEFOCUS as isize==0{let pen=CreatePen(PS_DOT,1,0x00E4B25E);let oldp=SelectObject(dc,pen);let oldb=SelectObject(dc,GetStockObject(NULL_BRUSH));RoundRect(dc,1,1,w-1,hgt-1,6,6);SelectObject(dc,oldp);SelectObject(dc,oldb);DeleteObject(pen);}
        EndPaint(h,&ps);return 0;
    }
    if m==WM_SETFOCUS||m==WM_KILLFOCUS||m==WM_ENABLE{InvalidateRect(h,null(),0);}
    let result=DefSubclassProc(h,m,w,l);if m==BM_SETCHECK||m==TBM_SETPOS||m==WM_KEYUP||m==WM_LBUTTONUP{InvalidateRect(h,null(),0);}result
}
impl Ui{
    pub unsafe fn new()->Result<Self,String>{
        let mut work:RECT=zeroed();SystemParametersInfoW(SPI_GETWORKAREA,0,&mut work as *mut _ as _,0);
        let scale=(GetDpiForSystem() as f32/96.0).min((work.bottom-work.top-32) as f32/810.0).min((work.right-work.left-32) as f32/580.0).max(0.5);
        let(width,height)=((580.0*scale).round() as i32,(810.0*scale).round() as i32);
        let h=CreateWindowExW(WS_EX_APPWINDOW,wide("SnowVibeSettings").as_ptr(),wide("SnowVibe").as_ptr(),WS_POPUP|WS_SYSMENU|WS_MINIMIZEBOX|WS_CLIPCHILDREN,work.left+(work.right-work.left-width)/2,work.top+(work.bottom-work.top-height)/2,width,height,null_mut(),null_mut(),GetModuleHandleW(null()),null());
        if h.is_null(){return Err("Не удалось создать настройки".into());}let dark=1_i32;DwmSetWindowAttribute(h,20,&dark as *const _ as _,4);
        let policy=DWMNCRP_DISABLED;DwmSetWindowAttribute(h,DWMWA_NCRENDERING_POLICY as u32,&policy as *const _ as _,4);
        SetWindowRgn(h,CreateRoundRectRgn(0,0,width+1,height+1,(16.0*scale) as i32,(16.0*scale) as i32),1);
        let fonts=vec![font(13.0,600,scale),font(27.0,700,scale),font(13.0,500,scale),font(11.5,500,scale),font(10.5,400,scale)];
        let mut ui=Self{construction_error:None,hwnd:h,controls:vec![],fonts,scale,model:Rc::new(RefCell::new(Settings::default())),background:ui_art::background(scale,width as u32,height as u32).bgra(),width,height};
        ui.control("BUTTON","Закрыть настройки",16,BS_PUSHBUTTON as u32,8.0,3.0,14.0,14.0,Kind::Close);
        ui.control("BUTTON","Свернуть",15,BS_PUSHBUTTON as u32,26.0,3.0,14.0,14.0,Kind::Minimize);
        ui.control("BUTTON","Включить снег",1,BS_AUTOCHECKBOX as u32,498.0,36.0,54.0,26.0,Kind::Switch);
        for(i,label)in ["Снежинки","Пушистый","Метель","Искры"].iter().enumerate(){ui.control("BUTTON",label,20+i as u16,BS_PUSHBUTTON as u32,[44.0,177.0,312.0,426.0][i],267.0,[133.0,135.0,114.0,110.0][i],24.0,Kind::Segment(i));}
        ui.slider(3,"Интенсивность",32.0,322.0,516.0,26.0,15,100);ui.slider(4,"Плавность",32.0,374.0,516.0,26.0,20,60);ui.slider(5,"Ветер",51.0,424.0,478.0,26.0,0,200);
        for(id,label,y)in [(6,"На верхушках окон",515.0),(7,"На верхней части панели задач",540.0),(9,"Снег разлетается от курсора",590.0),(10,"Катать снежные шары на панели задач",615.0)]{ui.control("BUTTON",label,id,BS_AUTOCHECKBOX as u32,44.0,y,492.0,24.0,Kind::Check);}
        ui.control("BUTTON","Очистить весь снег",12,BS_PUSHBUTTON as u32,28.0,687.0,257.0,24.0,Kind::Action(12));ui.control("BUTTON","Запустить снегоуборщик",13,BS_PUSHBUTTON as u32,295.0,687.0,257.0,24.0,Kind::Action(13));
        if let Some(error)=ui.construction_error.take(){return Err(error);}
        AppendMenuW(GetSystemMenu(h,0),MF_SEPARATOR,0,null());AppendMenuW(GetSystemMenu(h,0),MF_STRING,0x110,wide("Выйти из SnowVibe").as_ptr());Ok(ui)
    }
    unsafe fn control(&mut self,class:&str,label:&str,id:u16,style:u32,x:f32,y:f32,w:f32,h:f32,kind:Kind)->HWND{
        let s=self.scale;let handle=CreateWindowExW(0,wide(class).as_ptr(),wide(label).as_ptr(),WS_CHILD|WS_VISIBLE|WS_TABSTOP|style,(x*s).round() as i32,(y*s).round() as i32,(w*s).round() as i32,(h*s).round() as i32,self.hwnd,id as usize as _,GetModuleHandleW(null()),null());
        if handle.is_null(){self.construction_error=Some(format!("Create control {id}: {}",GetLastError()));return handle;}
        SendMessageW(handle,WM_SETFONT,self.fonts[0] as usize,0);let data=Box::new(Control{kind,scale:s,font:self.fonts[0],model:self.model.clone(),text:label.to_owned()});let data=Box::into_raw(data);if SetWindowSubclass(handle,Some(control_proc),1,data as usize)==0{drop(Box::from_raw(data));self.construction_error=Some(format!("Subclass control {id} failed"));}
        self.controls.push((id,handle));handle
    }
    unsafe fn slider(&mut self,id:u16,label:&str,x:f32,y:f32,w:f32,h:f32,min:i32,max:i32){let hwnd=self.control("msctls_trackbar32",label,id,TBS_HORZ|TBS_NOTICKS,x,y,w,h,Kind::Slider);SendMessageW(hwnd,TBM_SETRANGEMIN,0,min as isize);SendMessageW(hwnd,TBM_SETRANGEMAX,1,max as isize);}
    pub fn get(&self,id:u16)->HWND{self.controls.iter().find(|(i,_)|*i==id).unwrap().1}
    pub unsafe fn sync(&self,s:&Settings){
        *self.model.borrow_mut()=s.clone();for(id,on)in [(1,s.enabled),(6,s.windows),(7,s.taskbar),(9,s.cursor),(10,s.snowman)]{SendMessageW(self.get(id),BM_SETCHECK,usize::from(on),0);}
        for(id,n)in [(3,(s.intensity*100.0).round() as isize),(4,s.fps as isize),(5,(s.wind*100.0+100.0).round() as isize)]{SendMessageW(self.get(id),TBM_SETPOS,1,n);}self.invalidate();
    }
    pub unsafe fn read(&self,s:&mut Settings){
        let checked=|id|SendMessageW(self.get(id),BM_GETCHECK,0,0)==BST_CHECKED as isize;
        s.enabled=checked(1);s.windows=checked(6);s.taskbar=checked(7);s.cursor=checked(9);s.snowman=checked(10);
        s.intensity=SendMessageW(self.get(3),WM_USER,0,0) as f32/100.0;s.fps=SendMessageW(self.get(4),WM_USER,0,0) as u32;s.wind=(SendMessageW(self.get(5),WM_USER,0,0) as f32-100.0)/100.0;s.normalize();*self.model.borrow_mut()=s.clone();self.invalidate();
    }
    unsafe fn invalidate(&self){InvalidateRect(self.hwnd,null(),0);for(_,h)in &self.controls{InvalidateRect(*h,null(),0);}}
    pub unsafe fn show(&self){ShowWindow(self.hwnd,SW_RESTORE);SetForegroundWindow(self.hwnd);}
    pub unsafe fn hit_test(&self,l:LPARAM)->LRESULT{
        let mut p=POINT{x:(l as i16) as i32,y:((l>>16) as i16) as i32};ScreenToClient(self.hwnd,&mut p);
        if (p.y as f32)/self.scale<84.0 && ChildWindowFromPoint(self.hwnd,p)==self.hwnd{HTCAPTION as isize}else{HTCLIENT as isize}
    }
    pub unsafe fn paint(&self){
        let mut ps:PAINTSTRUCT=zeroed();let dc=BeginPaint(self.hwnd,&mut ps);let mem=CreateCompatibleDC(dc);let bitmap=CreateCompatibleBitmap(dc,self.width,self.height);let old=SelectObject(mem,bitmap);blit(mem,&self.background,self.width,self.height);
        let s=self.scale;let white=[243,243,243];let secondary=[130,130,130];text(mem,self.fonts[1],s,"SnowVibe",76.0,23.0,360.0,36.0,white,DT_SINGLELINE);text(mem,self.fonts[0],s,"Живой зимний эффект",76.0,57.0,360.0,21.0,secondary,DT_SINGLELINE);
        for(label,y)in [("Вид снега",240.0),("Интенсивность",298.0),("Плавность",351.0),("Ветер",401.0),("Где копить снег",492.0),("Физика и игра",567.0)]{text(mem,self.fonts[0],s,label,69.0,y,380.0,22.0,white,DT_SINGLELINE|DT_VCENTER);}
        let model=self.model.borrow();text(mem,self.fonts[0],s,&format!("{}%",(model.intensity*100.0).round() as i32),440.0,298.0,96.0,22.0,secondary,DT_SINGLELINE|DT_VCENTER|DT_RIGHT);text(mem,self.fonts[0],s,&format!("{} FPS",model.fps),440.0,351.0,96.0,22.0,secondary,DT_SINGLELINE|DT_VCENTER|DT_RIGHT);
        for(x,label)in [(44.0,"←"),(524.0,"→")]{text(mem,self.fonts[2],s,label,x,426.0,14.0,22.0,secondary,DT_SINGLELINE|DT_VCENTER);}
        text(mem,self.fonts[3],s,"Зажми Alt и тяни по снегу на верхней части панели задач. Отпусти кнопку — шар упадёт. Три шара соберут снеговика; Alt + нажатие разломит его.",42.0,730.0,496.0,42.0,secondary,DT_CENTER|DT_WORDBREAK);
        text(mem,self.fonts[4],s,"Не читает содержимое окон · клики проходят сквозь снег",28.0,773.0,524.0,20.0,[105,105,105],DT_CENTER|DT_SINGLELINE);
        BitBlt(dc,0,0,self.width,self.height,mem,0,0,SRCCOPY);SelectObject(mem,old);DeleteObject(bitmap);DeleteDC(mem);EndPaint(self.hwnd,&ps);
    }
}
impl Drop for Ui{fn drop(&mut self){unsafe{DestroyWindow(self.hwnd);for f in &self.fonts{DeleteObject(*f);}}}}
