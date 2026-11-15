use crate::settings::Settings;
use std::collections::HashMap;

#[derive(Clone, Copy, Debug, Default, PartialEq)]
pub struct Rect { pub x: f32, pub y: f32, pub w: f32, pub h: f32 }
impl Rect {
    pub fn right(self) -> f32 { self.x + self.w }
    pub fn bottom(self) -> f32 { self.y + self.h }
    pub fn contains_x(self, x: f32) -> bool { x >= self.x && x <= self.right() }
    pub fn intersects(self, b: Self) -> bool { self.x < b.right() && b.x < self.right() && self.y < b.bottom() && b.y < self.bottom() }
    pub fn intersection(self,b:Self)->Option<Self>{
        let(x,y)=(self.x.max(b.x),self.y.max(b.y));let(w,h)=(self.right().min(b.right())-x,self.bottom().min(b.bottom())-y);
        if w>0.0 && h>0.0{Some(Self{x,y,w,h})}else{None}
    }
}
#[derive(Clone, Debug)]
pub struct Snapshot { pub id: isize, pub rect: Rect, pub taskbar: bool, pub accumulates: bool }
#[derive(Clone, Debug)]
pub struct Surface { pub rect: Rect, pub pile: Vec<f32>, pub exposed: Vec<(f32, f32)>, pub taskbar: bool }
impl Surface {
    pub fn new(rect: Rect, taskbar: bool) -> Self {
        Self { rect, pile: vec![0.0; ((rect.w / 7.0) as usize + 1).max(3)], exposed: vec![(rect.x, rect.right())], taskbar }
    }
    pub fn height(&self, x: f32) -> f32 {
        let t = ((x - self.rect.x) / self.rect.w.max(1.0) * (self.pile.len() - 1) as f32).clamp(0.0, (self.pile.len() - 1) as f32);
        let i = t as usize; let j = (i + 1).min(self.pile.len() - 1);
        self.pile[i] + (self.pile[j] - self.pile[i]) * t.fract()
    }
    fn deposit(&mut self, x: f32, amount: f32) {
        let c = (((x - self.rect.x) / self.rect.w.max(1.0)) * (self.pile.len() - 1) as f32) as isize;
        for d in -2_isize..=2 { let i = c + d; if i >= 0 && (i as usize) < self.pile.len() {
            let weight = match d.abs() { 0 => 1.0, 1 => 0.56, _ => 0.22 };
            self.pile[i as usize] = (self.pile[i as usize] + amount * weight).min(if self.taskbar { 38.0 } else { 30.0 });
        }}
    }
    pub fn exposed_at(&self, x: f32) -> bool { self.exposed.iter().any(|&(a,b)| x >= a && x <= b) }
}
pub fn exposed_ranges(rect: Rect, front: &[Rect]) -> Vec<(f32, f32)> {
    let mut ranges = vec![(rect.x, rect.right())];
    for r in front {
        if r.y > rect.y || r.bottom() <= rect.y { continue; }
        let mut next = Vec::new();
        for (a,b) in ranges {
            if r.right() <= a || r.x >= b { next.push((a,b)); }
            else { if r.x > a { next.push((a,r.x)); } if r.right() < b { next.push((r.right(),b)); } }
        }
        ranges = next;
    } ranges
}
#[derive(Clone, Debug)]
pub struct Flake { pub x: f32, pub y: f32, pub speed: f32, pub size: f32, pub phase: f32, pub alpha: f32 }
#[derive(Clone, Debug)]
pub struct Clump { pub x: f32, pub y: f32, pub vx: f32, pub vy: f32, pub size: f32, pub life: f32 }
#[derive(Clone, Debug)]
pub struct Ball { pub x: f32, pub y: f32, pub r: f32, pub vx: f32, pub vy: f32, pub stable: bool }
#[derive(Clone, Debug)]
pub struct Plow { pub x: f32, pub y: f32, pub end: f32, pub id: isize }
pub struct Engine {
    pub bounds: Rect,
    pub flakes: Vec<Flake>, pub clumps: Vec<Clump>, pub surfaces: HashMap<isize, Surface>,
    pub window_stack: Vec<(isize,Rect)>,
    pub balls: Vec<Ball>, pub snowman: bool, pub plow: Option<Plow>,
    pub time: f32, style:usize, seed: u64, drag: Option<usize>, previous_mouse: (f32,f32),
}
impl Engine {
    pub fn new(bounds: Rect) -> Self {
        Self { bounds, flakes: vec![], clumps: vec![], surfaces: HashMap::new(),
            window_stack: vec![], balls: vec![], snowman: false, plow: None, time: 0.0, style:0, seed: 0x548af92c,
            drag: None, previous_mouse: (0.0,0.0) }
    }
    fn random(&mut self) -> f32 {
        self.seed ^= self.seed << 13; self.seed ^= self.seed >> 7; self.seed ^= self.seed << 17;
        (self.seed >> 40) as f32 / ((1_u32 << 24) - 1) as f32
    }
    fn new_flake(&mut self, s: &Settings, scattered: bool) -> Flake {
        let (speed, size) = match s.style { 1 => (32.0,7.0), 2 => (145.0,3.0), 3 => (52.0,3.0), _ => (62.0,5.0) };
        Flake { x: self.bounds.x + self.random() * self.bounds.w,
            y: if scattered { self.bounds.y + self.random() * self.bounds.h } else { self.bounds.y - self.random() * 90.0 },
            speed: speed * (0.7 + self.random() * 0.6), size: size * (0.7 + self.random() * 0.6),
            phase: self.random() * 6.28, alpha: 0.55 + self.random() * 0.4 }
    }
    pub fn clear(&mut self) {
        for s in self.surfaces.values_mut() { s.pile.fill(0.0); }
        self.balls.clear(); self.clumps.clear(); self.snowman = false; self.plow = None; self.drag = None;
    }
    pub fn settings_changed(&mut self, s: &Settings) {
        if !s.enabled || self.style!=s.style { self.flakes.clear(); }
        self.style=s.style;
        if !s.enabled || !s.snowman { self.drag = None; }
        for v in self.surfaces.values_mut() { if (v.taskbar && !s.taskbar) || (!v.taskbar && !s.windows) { v.pile.fill(0.0); } }
        if !s.taskbar { self.plow = None; self.balls.clear(); self.drag=None; self.snowman=false; }
    }
    pub fn refresh(&mut self, windows: &[Snapshot]) {
        let mut front = Vec::new();
        self.window_stack.clear();
        let mut next = HashMap::new();
        for w in windows {
            if !w.rect.intersects(self.bounds) { continue; }
            if w.taskbar && w.rect.intersection(self.bounds).is_none_or(|r| r.h<w.rect.h.min(12.0) || r.w<w.rect.w.min(12.0)){continue;}
            self.window_stack.push((w.id,w.rect));
            if !w.accumulates { front.push(w.rect); continue; }
            let old = self.surfaces.remove(&w.id);
            let mut surface = if let Some(mut old) = old {
                let moved = (old.rect.x-w.rect.x).abs() + (old.rect.y-w.rect.y).abs() > 3.0;
                let resized = (old.rect.w-w.rect.w).abs() > 3.0;
                if moved || resized { self.release(&old); old = Surface::new(w.rect, w.taskbar); }
                old.rect = w.rect; old
            } else { Surface::new(w.rect, w.taskbar) };
            surface.exposed = exposed_ranges(w.rect, &front);
            front.push(w.rect); next.insert(w.id, surface);
        }
        let removed: Vec<Surface> = self.surfaces.drain().map(|(_,s)| s).collect();
        for s in removed { self.release(&s); }
        self.surfaces = next;
        if self.plow.as_ref().is_some_and(|p| !self.surfaces.contains_key(&p.id)) { self.plow = None; }
    }
    fn release(&mut self, s: &Surface) {
        for (i,h) in s.pile.iter().enumerate().step_by(3) {
            if *h > 0.5 && self.clumps.len() < 110 {
                let vx = self.random() * 90.0 - 45.0;
                self.clumps.push(Clump { x: s.rect.x + i as f32 / (s.pile.len()-1) as f32 * s.rect.w,
                    y: s.rect.y - h, vx, vy: -20.0, size: 3.5, life: 5.0 });
            }
        }
    }
    pub fn summon_plow(&mut self, s: &Settings) {
        if !s.enabled || !s.taskbar || self.plow.is_some() { return; }
        if let Some((&id,bar)) = self.surfaces.iter().find(|(_,v)| v.taskbar) {
            self.plow = Some(Plow { x: bar.rect.x - 110.0, y: bar.rect.y, end: bar.rect.right()+100.0, id });
        }
    }
    // Highest crossed surface in screen coordinates. Windows below the flake cannot catch it prematurely.
    fn landing(&self, x: f32, old_y: f32, new_y: f32, radius: f32, s: &Settings) -> Option<(isize,f32)> {
        let mut best: Option<(isize,f32)> = None;
        for (&id,v) in &self.surfaces {
            if !(if v.taskbar { s.taskbar } else { s.windows }) || !v.rect.contains_x(x) || !v.exposed_at(x) { continue; }
            let y = v.rect.y - v.height(x) - radius;
            if old_y <= y && new_y >= y && best.is_none_or(|b| y < b.1) { best = Some((id,y)); }
        }
        best
    }
    pub fn step(&mut self, dt: f32, s: &Settings, mouse: (f32,f32)) {
        if !s.enabled { return; }
        let dt = dt.clamp(0.0,0.05); self.time += dt;
        let cap = match s.style { 2 => 220, _ => 150 };
        let wanted = ((self.bounds.w*self.bounds.h/9000.0*s.intensity) as usize).clamp(18,cap);
        while self.flakes.len() < wanted { let f = self.new_flake(s,true); self.flakes.push(f); }
        self.flakes.truncate(wanted);
        for i in 0..self.flakes.len() {
            let f = &mut self.flakes[i]; let old_y = f.y; f.phase += dt;
            let mut vx = s.wind*86.0 + (f.phase*1.3).sin()*15.0;
            let mut vy = f.speed;
            if s.cursor {
                let dx = f.x-mouse.0; let dy = f.y-mouse.1; let d = dx.hypot(dy);
                if d > 2.0 && d < 100.0 { let force = (100.0-d)*3.0; vx += dx/d*force; vy += dy/d*force; }
            }
            f.x += vx*dt; f.y += vy*dt;
            if f.x < self.bounds.x-40.0 { f.x = self.bounds.right()+30.0; }
            if f.x > self.bounds.right()+40.0 { f.x = self.bounds.x-30.0; }
            let (x,y,r) = (f.x,f.y,f.size);
            if let Some((id,_)) = self.landing(x,old_y,y,r*0.4,s) {
                let amount = r*0.35;
                if let Some(surface) = self.surfaces.get_mut(&id) { surface.deposit(x,amount); }
                self.flakes[i] = self.new_flake(s,false);
            } else if y > self.bounds.bottom()+40.0 { self.flakes[i] = self.new_flake(s,false); }
        }
        for c in &mut self.clumps { c.vy += 260.0*dt; c.x += c.vx*dt; c.y += c.vy*dt; c.life -= dt; }
        self.clumps.retain(|c| c.life > 0.0 && c.y < self.bounds.bottom()+50.0);
        if let Some(mut p) = self.plow.take() {
            p.x += 210.0*dt;
            if let Some(v) = self.surfaces.get_mut(&p.id) {
                for i in 0..v.pile.len() {
                    let x = v.rect.x + i as f32/(v.pile.len()-1) as f32*v.rect.w;
                    if x >= p.x+28.0 && x < p.x+58.0 && v.pile[i] > 0.2 {
                        if self.clumps.len() < 110 { self.clumps.push(Clump { x, y: p.y-12.0, vx: 95.0, vy: -95.0, size: 3.0, life: 1.1 }); }
                        v.pile[i] = 0.0;
                    }
                }
            }
            if p.x < p.end { self.plow = Some(p); }
        }
        self.update_balls(dt,s);
    }
    pub fn pointer(&mut self, mouse: (f32,f32), pressed: bool, was_pressed: bool, s: &Settings) {
        if !s.snowman || !s.enabled || !s.taskbar { self.drag = None; return; }
        if pressed && !was_pressed {
            self.previous_mouse = mouse;
            let hit = self.balls.iter().position(|b| (b.x-mouse.0).hypot(b.y-mouse.1) < b.r+8.0);
            if self.snowman && hit.is_some() {
                self.snowman = false;
                for (i,b) in self.balls.iter_mut().enumerate() { b.vx = (i as f32-1.0)*95.0; b.vy = -100.0; b.stable = false; }
                self.drag = None;
            } else if let Some(i) = hit { self.drag = Some(i); }
            else if self.balls.len() < 3 && self.surfaces.values().any(|v| {
                v.taskbar && s.taskbar && v.height(mouse.0)>0.4 && v.exposed_at(mouse.0) && v.rect.contains_x(mouse.0) && (mouse.1-(v.rect.y-v.height(mouse.0))).abs() < 36.0
            }) {
                self.balls.push(Ball { x: mouse.0, y: mouse.1, r: 9.0, vx: 0.0, vy: 0.0, stable: false }); self.drag = Some(self.balls.len()-1);
            }
        }
        if let Some(i) = self.drag {
            if pressed {
                let movement = (mouse.0-self.previous_mouse.0).hypot(mouse.1-self.previous_mouse.1);
                let b = &mut self.balls[i]; b.x = mouse.0; b.y = mouse.1; b.vx=0.0; b.vy=0.0; b.stable = false;
                let max = [44.0,33.0,24.0][i.min(2)];
                for v in self.surfaces.values_mut() {
                    if !v.taskbar || !s.taskbar || !v.rect.contains_x(mouse.0) || !v.exposed_at(mouse.0) { continue; }
                    if movement>0.01 && (mouse.1-(v.rect.y-v.height(mouse.0))).abs() < 50.0 {
                        if v.height(mouse.0)>0.4 { b.r = (b.r+movement.min(80.0)*0.065).min(max); }
                        let count=v.pile.len();
                        for (j,h) in v.pile.iter_mut().enumerate() {
                            let x = v.rect.x + j as f32/(count-1) as f32*v.rect.w;
                            if (x-mouse.0).abs() < b.r { *h = (*h-0.5).max(0.0); }
                        }
                    }
                }
            } else { self.balls[i].vy = 10.0; self.drag = None; }
        }
        self.previous_mouse = mouse;
    }
    fn update_balls(&mut self, dt: f32, s: &Settings) {
        if self.snowman && self.balls.len()!=3{self.snowman=false;}
        if self.snowman {
            let base=&self.balls[0];
            if let Some(bar)=self.surfaces.values().find(|v| v.taskbar && s.taskbar && v.rect.contains_x(base.x) && v.exposed_at(base.x)) {
                let dy=bar.rect.y-bar.height(base.x)-base.r-base.y;
                for ball in &mut self.balls { ball.y+=dy; }
            } else { self.balls.clear(); self.snowman=false; self.drag=None; }
            return;
        }
        for i in 0..self.balls.len() {
            if self.drag == Some(i) { continue; }
            let b = &self.balls[i]; let mut floor = f32::INFINITY;
            for v in self.surfaces.values() {
                if v.taskbar && s.taskbar && v.rect.contains_x(b.x) && v.exposed_at(b.x) && v.rect.y >= b.y+b.r-8.0 {
                    floor = floor.min(v.rect.y-v.height(b.x)-b.r);
                }
            }
            for (j,other) in self.balls.iter().enumerate() {
                if i != j && other.stable && other.y > b.y {
                    let dx = (other.x-b.x).abs(); let sum = other.r+b.r-2.0;
                    if dx < sum*0.72 { floor = floor.min(other.y-(sum*sum-dx*dx).sqrt()); }
                }
            }
            let b = &mut self.balls[i]; b.vy += dt*320.0; b.x += b.vx*dt; b.y += b.vy*dt;
            if b.y >= floor { b.y = floor; b.vy = 0.0; b.vx *= 0.9; b.stable = b.vx.abs() < 6.0; } else { b.stable = false; }
        }
        // Balls that miss the taskbar fall out of the effect; the desktop edge is not a floor.
        if self.drag.is_none() { self.balls.retain(|b| b.y-b.r < self.bounds.bottom()+50.0); }
        if self.balls.len() == 3 && self.drag.is_none() && self.balls.iter().all(|b| b.stable && b.r >= 14.0) {
            let min = self.balls.iter().map(|b| b.x).fold(f32::INFINITY,f32::min);
            let max = self.balls.iter().map(|b| b.x).fold(f32::NEG_INFINITY,f32::max);
            if max-min < 70.0 {
                self.balls.sort_by(|a,b| b.r.total_cmp(&a.r));
                let x = self.balls[0].x;
                for i in 1..3 { self.balls[i].x = x; self.balls[i].y = self.balls[i-1].y-self.balls[i-1].r-self.balls[i].r+3.0; }
                self.snowman = true;
            }
        }
    }
}

#[cfg(test)]
mod tests {
    use super::*;
    fn bounds() -> Rect { Rect { x:-1920.0,y:0.0,w:1920.0,h:1080.0 } }
    #[test] fn occlusion_splits_top_edge() {
        let r = Rect{x:0.0,y:100.0,w:200.0,h:200.0};
        assert_eq!(exposed_ranges(r,&[Rect{x:50.0,y:50.0,w:50.0,h:100.0}]),vec![(0.0,50.0),(100.0,200.0)]);
    }
    #[test] fn nearest_crossed_surface_wins() {
        let mut e=Engine::new(bounds()); let s=Settings::default();
        e.surfaces.insert(1,Surface::new(Rect{x:-1000.0,y:400.0,w:400.0,h:200.0},false));
        e.surfaces.insert(2,Surface::new(Rect{x:-1000.0,y:200.0,w:400.0,h:100.0},false));
        assert_eq!(e.landing(-900.0,0.0,600.0,0.0,&s),Some((2,200.0)));
    }
    #[test] fn clear_cancels_drag_and_plow() {
        let mut e=Engine::new(bounds()); e.drag=Some(0); e.snowman=true; e.clear();
        assert!(e.drag.is_none() && e.plow.is_none() && !e.snowman);
    }
    #[test] fn disabled_surfaces_cannot_catch_snow() {
        let mut e=Engine::new(bounds()); let s=Settings{windows:false,..Settings::default()};
        e.surfaces.insert(1,Surface::new(Rect{x:-1000.0,y:200.0,w:400.0,h:100.0},false));
        assert_eq!(e.landing(-900.0,0.0,600.0,0.0,&s),None);
    }
    #[test] fn long_simulation_stays_bounded() {
        let mut e=Engine::new(bounds()); let s=Settings::default();
        for _ in 0..10000 { e.step(1.0/36.0,&s,(-5000.0,-5000.0)); }
        assert!(e.flakes.len() <= 150 && e.clumps.len() <= 110);
        assert!(e.flakes.iter().all(|f| f.x.is_finite() && f.y.is_finite()));
    }
    #[test] fn desktop_bottom_never_catches_snow() {
        let e=Engine::new(bounds());
        assert_eq!(e.landing(-900.0,1000.0,1200.0,3.0,&Settings::default()),None);
    }
    #[test] fn balls_can_only_be_started_on_taskbar_top() {
        let mut e=Engine::new(bounds());let s=Settings::default();
        e.surfaces.insert(1,Surface::new(Rect{x:-1000.0,y:400.0,w:400.0,h:200.0},false));
        e.surfaces.insert(2,Surface::new(Rect{x:-1920.0,y:1040.0,w:1920.0,h:40.0},true));
        e.pointer((-900.0,400.0),true,false,&s);
        assert!(e.balls.is_empty());
        e.surfaces.get_mut(&2).unwrap().pile.fill(5.0);
        e.pointer((-900.0,1040.0),true,false,&s);
        assert_eq!(e.balls.len(),1);assert_eq!(e.balls[0].r,9.0);
    }
    #[test] fn balls_do_not_settle_on_windows_or_desktop_edge() {
        let mut e=Engine::new(bounds());let s=Settings::default();
        e.surfaces.insert(1,Surface::new(Rect{x:-1000.0,y:400.0,w:400.0,h:200.0},false));
        e.balls.push(Ball{x:-900.0,y:350.0,r:20.0,vx:0.0,vy:0.0,stable:false});
        for _ in 0..400{e.update_balls(0.02,&s);}
        assert!(e.balls.is_empty());
    }
    #[test] fn disabling_taskbar_clears_balls_and_snowman() {
        let mut e=Engine::new(bounds());
        e.balls.push(Ball{x:-900.0,y:1000.0,r:20.0,vx:0.0,vy:0.0,stable:true});e.snowman=true;
        let s=Settings{taskbar:false,..Settings::default()};e.settings_changed(&s);
        assert!(e.balls.is_empty() && !e.snowman && e.drag.is_none());
    }
    #[test] fn balls_still_settle_above_taskbar() {
        let mut e=Engine::new(bounds());let s=Settings::default();
        e.surfaces.insert(2,Surface::new(Rect{x:-1920.0,y:1040.0,w:1920.0,h:40.0},true));
        e.balls.push(Ball{x:-900.0,y:900.0,r:20.0,vx:0.0,vy:0.0,stable:false});
        for _ in 0..200{e.update_balls(0.02,&s);}
        assert_eq!(e.balls.len(),1);assert_eq!(e.balls[0].y,1020.0);assert!(e.balls[0].stable);
    }
    #[test]fn empty_taskbar_cannot_create_a_ball(){
        let mut e=Engine::new(bounds());let s=Settings::default();
        e.surfaces.insert(2,Surface::new(Rect{x:-1920.0,y:1040.0,w:1920.0,h:40.0},true));
        e.pointer((-900.0,1040.0),true,false,&s);assert!(e.balls.is_empty());
    }
    #[test]fn changing_style_replaces_old_particles(){
        let mut e=Engine::new(bounds());let mut s=Settings::default();e.step(0.02,&s,(1e6,1e6));
        assert!(!e.flakes.is_empty());s.style=2;e.settings_changed(&s);assert!(e.flakes.is_empty());
        e.step(0.02,&s,(1e6,1e6));assert!(e.flakes.iter().all(|f|f.speed>=100.0));
    }
    #[test]fn auto_hidden_taskbar_is_not_a_surface(){
        let mut e=Engine::new(bounds());
        e.refresh(&[Snapshot{id:2,rect:Rect{x:-1920.0,y:1078.0,w:1920.0,h:40.0},taskbar:true,accumulates:true}]);
        assert!(e.surfaces.is_empty());
    }
    #[test]fn malformed_snowman_state_does_not_panic(){
        let mut e=Engine::new(bounds());e.snowman=true;e.update_balls(0.02,&Settings::default());assert!(!e.snowman);
    }
    #[test]fn holding_mouse_still_does_not_consume_snow(){
        let mut e=Engine::new(bounds());let s=Settings::default();
        let mut bar=Surface::new(Rect{x:-1920.0,y:1040.0,w:1920.0,h:40.0},true);bar.pile.fill(8.0);e.surfaces.insert(2,bar);
        let before=e.surfaces[&2].pile.clone();
        e.pointer((-900.0,1032.0),true,false,&s);
        for _ in 0..100{e.pointer((-900.0,1032.0),true,true,&s);}
        assert_eq!(e.surfaces[&2].pile,before);assert_eq!(e.balls[0].r,9.0);
    }
}
