use crate::engine::Snapshot;
use std::sync::{mpsc,Arc,Mutex};

/// A single worker for the lifetime of the app, with at most one pending scan.
/// Dropping the sender closes the worker; no new threads are created per timer tick.
pub struct WindowScanner{
    request:mpsc::SyncSender<()>,
    cache:Arc<Mutex<Arc<Vec<Snapshot>>>>,
}
impl WindowScanner{
    pub fn new()->std::io::Result<Self>{
        let(tx,rx)=mpsc::sync_channel(1);
        let cache=Arc::new(Mutex::new(Arc::new(Vec::new())));let output=cache.clone();
        std::thread::Builder::new().name("snow-window-scan".into()).spawn(move||{
            while rx.recv().is_ok(){
                let fresh=unsafe{crate::native::snapshots()};
                if let Ok(mut cache)=output.lock(){*cache=Arc::new(fresh);}
            }
        })?;
        Ok(Self{request:tx,cache})
    }
    pub fn request(&self){let _=self.request.try_send(());}
    pub fn snapshots(&self)->Arc<Vec<Snapshot>>{
        self.cache.lock().map(|v|v.clone()).unwrap_or_else(|_|Arc::new(Vec::new()))
    }
}
