use crate::{engine::{Engine, Surface}, settings::Settings};
use tiny_skia::{Color, Paint, PathBuilder, Pixmap, Stroke, Transform};

fn paint(r:u8,g:u8,b:u8,a:u8) -> Paint<'static> {
    let mut p=Paint::default(); p.set_color_rgba8(r,g,b,a); p
}
fn circle(p:&mut Pixmap,x:f32,y:f32,r:f32,color:&Paint) {
    if let Some(path)=PathBuilder::from_circle(x,y,r.max(0.1)) { p.fill_path(&path,color,tiny_skia::FillRule::Winding,Transform::identity(),None); }
}
fn rect(p:&mut Pixmap,x:f32,y:f32,w:f32,h:f32,color:&Paint) {
    if let Some(r)=tiny_skia::Rect::from_xywh(x,y,w,h) { p.fill_rect(r,color,Transform::identity(),None); }
}
fn pile(p:&mut Pixmap,s:&Surface,ox:f32,oy:f32) {
    if !s.pile.iter().any(|h| *h>0.15) { return; }
    for (a,b) in [(s.rect.x,s.rect.right())] {
        let left=a.max(ox); let right=b.min(ox+p.width() as f32);
        if right<=left { continue; }
        let mut path=PathBuilder::new(); path.move_to(left-ox,s.rect.y-oy);
        path.line_to(left-ox,s.rect.y-oy-s.height(left));
        for (i,h) in s.pile.iter().enumerate() {
            let x=s.rect.x+i as f32/(s.pile.len()-1) as f32*s.rect.w;
            if x>left && x<right { path.line_to(x-ox,s.rect.y-oy-h); }
        }
        path.line_to(right-ox,s.rect.y-oy-s.height(right));
        path.line_to(right-ox,s.rect.y-oy); path.close();
        if let Some(path)=path.finish() { p.fill_path(&path,&paint(225,243,255,245),tiny_skia::FillRule::Winding,Transform::identity(),None); }
    }
}
pub fn clear_window(p:&mut Pixmap,bounds:crate::engine::Rect,ox:f32,oy:f32){
    if let Some(r)=tiny_skia::Rect::from_xywh(bounds.x-ox,bounds.y-oy,bounds.w,bounds.h){
        let mut clear=Paint::default();clear.blend_mode=tiny_skia::BlendMode::Clear;
        p.fill_rect(r,&clear,Transform::identity(),None);
    }
}
pub fn draw(p:&mut Pixmap,e:&Engine,s:&Settings) {
    draw_with_front(p,e,s,None);
}
pub fn draw_with_front(p:&mut Pixmap,e:&Engine,s:&Settings,front:Option<crate::engine::Rect>) {
    p.fill(Color::TRANSPARENT);
    let ox=e.bounds.x; let oy=e.bounds.y;
    // Compose back to front: each real window erases the snow of windows behind it,
    // including the part of a snow cap extending above its supporting edge.
    // Only the thin bands holding accumulated snow can contain pixels at this
    // stage. Clearing entire application windows was wasting most of a frame.
    let bands:Vec<_>=e.surfaces.values().filter_map(|v|{
        if !(if v.taskbar{s.taskbar}else{s.windows}){return None;}
        let height=v.pile.iter().copied().fold(0.0_f32,f32::max);
        if height<=0.15{return None;}
        Some(crate::engine::Rect{x:v.rect.x,y:v.rect.y-height.ceil()-1.0,w:v.rect.w,h:height.ceil()+2.0})
    }).collect();
    for (id,bounds) in e.window_stack.iter().rev() {
        for band in &bands{if let Some(overlap)=bounds.intersection(*band){clear_window(p,overlap,ox,oy);}}
        if let Some(v)=e.surfaces.get(id) { if if v.taskbar {s.taskbar} else {s.windows} { pile(p,v,ox,oy); } }
    }
    if let Some(front)=front{clear_window(p,front,ox,oy);}
    for f in &e.flakes {
        let x=f.x-ox; let y=f.y-oy; let r=f.size;
        let color=paint(239,249,255,(f.alpha*255.0) as u8);
        match s.style {
            0 => {
                let mut path=PathBuilder::new();
                for i in 0..3 { let a=i as f32*std::f32::consts::PI/3.0+f.phase*0.2;
                    let (dx,dy)=(a.cos()*r,a.sin()*r); path.move_to(x-dx,y-dy); path.line_to(x+dx,y+dy);
                    for sign in [-1.0,1.0] { let (tx,ty)=(x+dx*0.65*sign,y+dy*0.65*sign);
                        for side in [-0.8_f32,0.8] { path.move_to(tx,ty); path.line_to(tx-(a+side).cos()*r*0.3*sign,ty-(a+side).sin()*r*0.3*sign); }
                    }
                }
                if let Some(path)=path.finish() { p.stroke_path(&path,&color,&Stroke{width:1.1,..Stroke::default()},Transform::identity(),None); }
            },
            1 => { circle(p,x,y,r,&paint(220,240,255,(f.alpha*35.0) as u8)); circle(p,x,y,r*0.55,&paint(234,248,255,(f.alpha*135.0) as u8)); circle(p,x,y,r*0.28,&color); },
            2 => { let mut path=PathBuilder::new(); path.move_to(x,y); path.line_to(x+s.wind*4.0,y+r*2.0);
                if let Some(path)=path.finish(){p.stroke_path(&path,&color,&Stroke{width:1.5,..Stroke::default()},Transform::identity(),None);}
            },
            _ => { let a=(0.5+0.5*(f.phase*3.0).sin())*f.alpha; let color=paint(210,240,255,(a*255.0) as u8);
                rect(p,x-r,y-0.6,r*2.0,1.2,&color); rect(p,x-0.6,y-r,1.2,r*2.0,&color); circle(p,x,y,1.5,&color); }
        }
    }
    for c in &e.clumps { circle(p,c.x-ox,c.y-oy,c.size,&paint(232,246,255,(c.life.min(1.0)*230.0) as u8)); }
    for b in &e.balls {
        let (x,y)=(b.x-ox,b.y-oy); circle(p,x,y,b.r+1.0,&paint(146,192,220,255));
        circle(p,x,y,b.r,&paint(219,239,252,255)); circle(p,x-b.r*0.15,y-b.r*0.2,b.r*0.77,&paint(239,249,255,255));
    }
    if e.snowman && e.balls.len()==3 {
        let b=&e.balls[2]; let (x,y)=(b.x-ox,b.y-oy); let coal=paint(20,37,52,255);
        circle(p,x-4.0,y-3.0,2.0,&coal); circle(p,x+4.0,y-3.0,2.0,&coal);
        let mut nose=PathBuilder::new(); nose.move_to(x,y); nose.line_to(x+13.0,y+3.0); nose.line_to(x,y+5.0); nose.close();
        if let Some(path)=nose.finish(){p.fill_path(&path,&paint(255,139,60,255),tiny_skia::FillRule::Winding,Transform::identity(),None);}
        rect(p,x-b.r*0.8,y-b.r-3.0,b.r*1.6,5.0,&coal); rect(p,x-b.r*0.55,y-b.r-18.0,b.r*1.1,17.0,&coal);
        let mid=&e.balls[1]; rect(p,mid.x-ox-mid.r*0.65,mid.y-oy-mid.r,mid.r*1.3,7.0,&paint(222,65,87,255));
        for i in 0..3 {circle(p,mid.x-ox,mid.y-oy-5.0+i as f32*9.0,2.2,&coal);}
    }
    if let Some(v)=&e.plow {
        let (x,y)=(v.x-ox,v.y-oy);
        let dark=paint(24,43,62,255); let blue=paint(61,157,228,255);
        circle(p,x+12.0,y-5.0,8.0,&dark); circle(p,x+40.0,y-5.0,8.0,&dark);
        rect(p,x,y-29.0,48.0,20.0,&blue); rect(p,x+11.0,y-49.0,25.0,23.0,&blue);
        rect(p,x+15.0,y-45.0,17.0,14.0,&paint(182,225,250,255));
        rect(p,x+48.0,y-26.0,8.0,26.0,&paint(246,175,59,255));
        circle(p,x+24.0,y-52.0,3.0,&paint(255,189,76,255));
    }
}

#[cfg(test)]
mod tests {
    use super::*;
    use crate::engine::{Rect,Snapshot};
    fn scene(front:Rect)->Engine{
        let mut e=Engine::new(Rect{x:0.0,y:0.0,w:600.0,h:400.0});
        e.refresh(&[
            Snapshot{id:1,rect:front,taskbar:false,accumulates:false},
            Snapshot{id:2,rect:Rect{x:0.0,y:100.0,w:500.0,h:250.0},taskbar:false,accumulates:true},
        ]);
        e.surfaces.get_mut(&2).unwrap().pile.fill(20.0);e
    }
    fn alpha(p:&Pixmap,x:u32,y:u32)->u8{p.pixel(x,y).unwrap().alpha()}
    #[test]fn foreground_window_covers_rear_snow_cap(){
        let e=scene(Rect{x:100.0,y:50.0,w:200.0,h:200.0});let mut p=Pixmap::new(600,400).unwrap();
        draw(&mut p,&e,&Settings::default());
        assert_eq!(alpha(&p,150,90),0);assert!(alpha(&p,50,90)>0);
        assert!(!e.surfaces.contains_key(&1));
    }
    #[test]fn occlusion_clips_full_cap_height_not_just_baseline(){
        let e=scene(Rect{x:100.0,y:70.0,w:200.0,h:20.0});let mut p=Pixmap::new(600,400).unwrap();
        draw(&mut p,&e,&Settings::default());
        assert_eq!(alpha(&p,150,85),0);assert!(alpha(&p,150,95)>0);
    }
    #[test]fn rear_cap_returns_when_foreground_window_closes(){
        let mut e=scene(Rect{x:100.0,y:50.0,w:200.0,h:200.0});
        e.refresh(&[Snapshot{id:2,rect:Rect{x:0.0,y:100.0,w:500.0,h:250.0},taskbar:false,accumulates:true}]);
        let mut p=Pixmap::new(600,400).unwrap();draw(&mut p,&e,&Settings::default());assert!(alpha(&p,150,90)>0);
    }
    #[test]fn optimized_occlusion_matches_full_window_compositing(){
        let mut e=scene(Rect{x:100.0,y:50.0,w:200.0,h:200.0});
        e.refresh(&[
            Snapshot{id:1,rect:crate::engine::Rect{x:73.0,y:52.0,w:280.0,h:190.0},taskbar:false,accumulates:false},
            Snapshot{id:3,rect:crate::engine::Rect{x:210.0,y:140.0,w:340.0,h:220.0},taskbar:false,accumulates:true},
            Snapshot{id:2,rect:crate::engine::Rect{x:0.0,y:100.0,w:500.0,h:250.0},taskbar:false,accumulates:true},
        ]);
        for v in e.surfaces.values_mut(){for(i,h)in v.pile.iter_mut().enumerate(){*h=(i%17) as f32*1.07;}}
        let mut actual=Pixmap::new(600,400).unwrap();draw(&mut actual,&e,&Settings::default());
        let mut reference=Pixmap::new(600,400).unwrap();
        for(id,r)in e.window_stack.iter().rev(){clear_window(&mut reference,*r,0.0,0.0);if let Some(v)=e.surfaces.get(id){pile(&mut reference,v,0.0,0.0);}}
        assert_eq!(actual.data(),reference.data());
    }
    #[test]fn foreground_settings_hide_stale_snow_before_scanner_catches_up(){
        let e=scene(Rect{x:100.0,y:50.0,w:200.0,h:200.0});
        let mut p=Pixmap::new(600,400).unwrap();
        // A restored foreground window has not appeared in the cached stack yet.
        draw_with_front(&mut p,&e,&Settings::default(),Some(Rect{x:0.0,y:70.0,w:500.0,h:200.0}));
        assert_eq!(alpha(&p,50,90),0);
    }
}
