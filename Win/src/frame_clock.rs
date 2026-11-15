use std::{ptr::null,sync::{Arc,atomic::{AtomicBool,Ordering}},thread::JoinHandle};
use windows_sys::Win32::{Foundation::*,System::Threading::*,UI::WindowsAndMessaging::*};
pub struct FrameClock{stop:HANDLE,pending:Arc<AtomicBool>,worker:Option<JoinHandle<()>>}
impl FrameClock{
    pub unsafe fn new(hwnd:HWND,fps:u32)->std::io::Result<Self>{
        // High-resolution waitable timers exist on recent Windows 10/11.
        // Retry with ordinary flags on older compatible Windows builds.
        let mut timer=CreateWaitableTimerExW(null(),null(),2,TIMER_ALL_ACCESS);
        if timer.is_null(){timer=CreateWaitableTimerExW(null(),null(),0,TIMER_ALL_ACCESS);}
        if timer.is_null(){return Err(std::io::Error::last_os_error());}
        let stop=CreateEventW(null(),1,0,null());
        if stop.is_null(){CloseHandle(timer);return Err(std::io::Error::last_os_error());}
        let due=-10_000_i64;
        if SetWaitableTimer(timer,&due,(1000/fps.clamp(20,60)) as i32,None,std::ptr::null(),0)==0{CloseHandle(timer);CloseHandle(stop);return Err(std::io::Error::last_os_error());}
        let pending=Arc::new(AtomicBool::new(false));let queued=pending.clone();
        let(timer_id,stop_id,window_id)=(timer as usize,stop as usize,hwnd as usize);
        let worker=std::thread::Builder::new().name("snow-frame-clock".into()).spawn(move||{
            let handles=[stop_id as HANDLE,timer_id as HANDLE];
            loop{
                if WaitForMultipleObjects(2,handles.as_ptr(),0,INFINITE)!=WAIT_OBJECT_0+1{break;}
                if !queued.swap(true,Ordering::AcqRel) && PostMessageW(window_id as HWND,WM_APP+2,0,0)==0{queued.store(false,Ordering::Release);}
            }
            CancelWaitableTimer(timer_id as HANDLE);CloseHandle(timer_id as HANDLE);
        });
        match worker{Ok(worker)=>Ok(Self{stop,pending,worker:Some(worker)}),Err(e)=>{CloseHandle(timer);CloseHandle(stop);Err(e)}}
    }
    pub fn frame_finished(&self){self.pending.store(false,Ordering::Release);}
}
impl Drop for FrameClock{fn drop(&mut self){unsafe{SetEvent(self.stop);if let Some(worker)=self.worker.take(){let _=worker.join();}CloseHandle(self.stop);}}}
