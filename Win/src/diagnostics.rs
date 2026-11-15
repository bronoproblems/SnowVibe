//! Short, offscreen CPU benchmark. No visible overlay or changes to user settings.
use crate::{engine::Engine,native,render,settings::Settings};
use std::{io,time::{Instant,Duration},fs::File};
pub struct Metrics{file:File,since:Instant,frames:u64,simulation:f64,render:f64,present:f64}
impl Metrics{
    pub fn new(path:&str)->io::Result<Self>{Ok(Self{file:File::create(path)?,since:Instant::now(),frames:0,simulation:0.0,render:0.0,present:0.0})}
    pub fn frame(&mut self,simulation:f64,render:f64,present:f64){self.frames+=1;self.simulation+=simulation;self.render+=render;self.present+=present;}
    pub fn report(&mut self,engines:impl Iterator<Item=(usize,usize,f32,f32)>,tray:bool)->io::Result<()>{
        if self.since.elapsed()<Duration::from_secs(1){return Ok(());}
        use std::io::Write;
        let monitors:Vec<_>=engines.collect();let n=self.frames.max(1) as f64;
        writeln!(self.file,"{}",serde_json::json!({"fps":self.frames as f64/self.since.elapsed().as_secs_f64(),"simulation_ms":self.simulation*1000.0/n,"render_ms":self.render*1000.0/n,"present_ms":self.present*1000.0/n,"monitors_surface_taskbar_snow":monitors,"tray_available":tray}))?;
        self.file.flush()?;self.since=Instant::now();self.frames=0;self.simulation=0.0;self.render=0.0;self.present=0.0;Ok(())
    }
}
pub fn benchmark(path:&str)->io::Result<()>{
    let monitors=unsafe{native::monitors()};let windows=unsafe{native::snapshots()};
    let mut reports=vec![];
    for bounds in monitors{
        let mut scenarios=vec![];
        for accumulated in [false,true]{
            let mut e=Engine::new(bounds);e.refresh(&windows);
            if accumulated{for surface in e.surfaces.values_mut(){surface.pile.fill(15.0);}}
            let mut p=tiny_skia::Pixmap::new(bounds.w as u32,bounds.h as u32).unwrap();let mut bgra=vec![0_u8;p.data().len()];
            let settings=Settings::default();let(mut simulate,mut draw,mut copy)=(0.0,0.0,0.0);
            for frame in 0..24{
                let t=Instant::now();e.step(1.0/36.0,&settings,(-100000.0,-100000.0));let a=t.elapsed().as_secs_f64();
                let t=Instant::now();render::draw(&mut p,&e,&settings);let b=t.elapsed().as_secs_f64();
                let t=Instant::now();for(src,dst)in p.data().chunks_exact(4).zip(bgra.chunks_exact_mut(4)){dst[0]=src[2];dst[1]=src[1];dst[2]=src[0];dst[3]=src[3];}let c=t.elapsed().as_secs_f64();
                std::hint::black_box(&bgra);
                if frame>=4{simulate+=a;draw+=b;copy+=c;}
            }
            scenarios.push(serde_json::json!({"accumulated":accumulated,"simulation_ms":simulate*50.0,"render_ms":draw*50.0,"copy_ms":copy*50.0,"cpu_total_ms":(simulate+draw+copy)*50.0}));
        }
        reports.push(serde_json::json!({"width":bounds.w,"height":bounds.h,"frame_bytes":bounds.w as u64*bounds.h as u64*4,"scenarios":scenarios}));
    }
    let window_report:Vec<_>=windows.iter().map(|w|serde_json::json!({"class":unsafe{native::class_name(w.id as _)},"id":w.id,"x":w.rect.x,"y":w.rect.y,"w":w.rect.w,"h":w.rect.h,"taskbar":w.taskbar,"accumulates":w.accumulates})).collect();
    std::fs::write(path,serde_json::to_vec_pretty(&serde_json::json!({"version":env!("CARGO_PKG_VERSION"),"window_count":windows.len(),"windows":window_report,"monitors":reports,"note":"CPU-only, 20 measured frames after warmup. Excludes UpdateLayeredWindow, DWM, GPU and interactive input. Artificial snow piles; not an end-to-end FPS measurement."}))?)
}
