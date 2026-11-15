//! Vector artwork translated from Mac/src/SettingsUI.swift at the same 580×880 logical size.
use tiny_skia::{Color,FillRule,GradientStop,LinearGradient,Paint,PathBuilder,Pixmap,Point,SpreadMode,Stroke,Transform};
pub const BG:[u8;3]=[56,56,56];
pub const CARD:[u8;3]=[43,43,43];
pub const CYAN:[u8;3]=[78,210,247];
pub struct Canvas{pub pixmap:Pixmap,pub scale:f32,clip:Option<tiny_skia::Mask>}
impl Canvas{
    pub fn new(w:u32,h:u32,scale:f32,bg:[u8;3])->Self{let mut p=Pixmap::new(w.max(1),h.max(1)).expect("UI bitmap");p.fill(Color::from_rgba8(bg[0],bg[1],bg[2],255));Self{pixmap:p,scale,clip:None}}
    pub fn fill(&mut self,path:&tiny_skia::Path,color:[u8;3],alpha:u8){let mut p=Paint::default();p.set_color_rgba8(color[0],color[1],color[2],alpha);self.pixmap.fill_path(path,&p,FillRule::Winding,Transform::from_scale(self.scale,self.scale),self.clip.as_ref());}
    pub fn stroke(&mut self,path:&tiny_skia::Path,color:[u8;3],width:f32){let mut p=Paint::default();p.set_color_rgba8(color[0],color[1],color[2],255);self.pixmap.stroke_path(path,&p,&Stroke{width,line_cap:tiny_skia::LineCap::Round,..Default::default()},Transform::from_scale(self.scale,self.scale),self.clip.as_ref());}
    pub fn round(&mut self,x:f32,y:f32,w:f32,h:f32,r:f32,color:[u8;3]){self.fill(&rounded(x,y,w,h,r),color,255);}
    pub fn circle(&mut self,x:f32,y:f32,r:f32,color:[u8;3]){self.fill(&PathBuilder::from_circle(x,y,r).unwrap(),color,255);}
    pub fn line(&mut self,x:f32,y:f32,x2:f32,y2:f32,color:[u8;3],width:f32){let mut p=PathBuilder::new();p.move_to(x,y);p.line_to(x2,y2);self.stroke(&p.finish().unwrap(),color,width);}
    pub fn bgra(&self)->Vec<u8>{let mut b=self.pixmap.data().to_vec();for p in b.chunks_exact_mut(4){p.swap(0,2);}b}
}
pub fn rounded(x:f32,y:f32,w:f32,h:f32,r:f32)->tiny_skia::Path{
    let r=r.min(w/2.0).min(h/2.0);let k=0.5522848*r;let mut p=PathBuilder::new();p.move_to(x+r,y);p.line_to(x+w-r,y);
    p.cubic_to(x+w-r+k,y,x+w,y+r-k,x+w,y+r);p.line_to(x+w,y+h-r);p.cubic_to(x+w,y+h-r+k,x+w-r+k,y+h,x+w-r,y+h);
    p.line_to(x+r,y+h);p.cubic_to(x+r-k,y+h,x,y+h-r+k,x,y+h-r);p.line_to(x,y+r);p.cubic_to(x,y+r-k,x+r-k,y,x+r,y);p.close();p.finish().unwrap()
}
pub fn snowflake(c:&mut Canvas,x:f32,y:f32,r:f32,color:[u8;3]){
    for i in 0..3{let a=i as f32*std::f32::consts::PI/3.0;let(dx,dy)=(a.cos()*r,a.sin()*r);c.line(x-dx,y-dy,x+dx,y+dy,color,1.5);
        for sign in [-1.0,1.0]{for side in [-0.8_f32,0.8]{let(tx,ty)=(x+dx*0.66*sign,y+dy*0.66*sign);c.line(tx,ty,tx-(a+side).cos()*r*0.30*sign,ty-(a+side).sin()*r*0.30*sign,color,1.3);}}}
}
pub fn icon(c:&mut Canvas,kind:u8,x:f32,y:f32,color:[u8;3]){
    match kind{
        0=>snowflake(c,x,y,6.0,color),
        1=>{c.circle(x-3.0,y,3.5,color);c.circle(x+1.0,y-2.0,4.5,color);c.circle(x+5.0,y,3.0,color);for dx in [-3.0,1.0,5.0]{c.line(x+dx,y+5.0,x+dx-1.0,y+7.0,color,1.0);}},
        2=>{c.stroke(&PathBuilder::from_circle(x,y,5.5).unwrap(),color,1.0);c.line(x,y,x+3.0,y-3.0,color,1.0);c.circle(x,y,1.0,color);},
        3=>{for(i,offset)in [0.0,4.0,8.0].iter().enumerate(){c.line(x-6.0,y-4.0+offset,x+if i==1{7.0}else{3.0},y-4.0+offset,color,1.0);}},
        4=>{for dy in [-4.0,0.0,4.0]{let mut p=PathBuilder::new();p.move_to(x-6.0,y+dy);p.line_to(x,y+dy+3.0);p.line_to(x+6.0,y+dy);c.stroke(&p.finish().unwrap(),color,1.5);}},
        5=>{c.line(x,y-6.0,x,y+6.0,color,1.4);c.line(x-4.0,y,x+4.0,y,color,1.4);c.circle(x-5.0,y-5.0,1.2,color);c.circle(x+5.0,y+5.0,1.0,color);},
        _=>{c.round(x-7.0,y-5.0,9.0,9.0,2.0,color);c.round(x+2.0,y-2.0,6.0,6.0,1.0,color);c.circle(x-4.0,y+5.0,2.0,color);c.circle(x+5.0,y+5.0,2.0,color);}
    }
}
pub fn background(scale:f32,width:u32,height:u32)->Canvas{
    let mut c=Canvas::new(width,height,scale,BG);snowflake(&mut c,46.0,49.0,12.0,CYAN);
    for y in [228.0,480.0]{let h=if y<300.0{240.0}else{187.0};c.round(28.0,y,524.0,h,16.0,[65,65,65]);c.round(28.7,y+0.7,522.6,h-1.4,15.3,CARD);}
    hero(&mut c);for(kind,y)in [(0,250.0),(1,308.0),(2,361.0),(3,411.0),(4,502.0),(5,577.0)]{icon(&mut c,kind,53.0,y,CYAN);}c
}
fn hero(c:&mut Canvas){
    let(x,y,w,h)=(28.0,86.0,524.0,130.0);let path=rounded(x,y,w,h,22.0);let mut p=Paint::default();
    p.shader=LinearGradient::new(Point::from_xy(x,y+h),Point::from_xy(x+w,y),vec![GradientStop::new(0.0,Color::from_rgba8(9,20,41,255)),GradientStop::new(1.0,Color::from_rgba8(26,71,115,255))],SpreadMode::Pad,Transform::identity()).unwrap();
    c.pixmap.fill_path(&path,&p,FillRule::Winding,Transform::from_scale(c.scale,c.scale),None);
    let mut clip=tiny_skia::Mask::new(c.pixmap.width(),c.pixmap.height()).unwrap();
    clip.fill_path(&path,FillRule::Winding,true,Transform::from_scale(c.scale,c.scale));c.clip=Some(clip);
    let sy=|v:f32|y+h-v;
    for i in 0..22{let px=((i*71+17)%524) as f32;let py=((i*47+23)%130) as f32;if px>8.0&&px<w-8.0{c.circle(x+px,sy(py),if i%5==0{1.0}else{0.5},[182,202,220]);}}
    let wx=x+24.0;let wy=sy(127.0);let ww=w*0.54;
    c.round(wx-2.0,wy+2.0,ww+4.0,80.0,12.0,[9,24,38]);c.round(wx,wy,ww,78.0,11.0,[62,80,94]);c.round(wx+1.0,wy+1.0,ww-2.0,76.0,10.0,[6,14,26]);
    c.round(wx+1.0,wy+1.0,ww-2.0,30.0,10.0,[23,33,48]);c.round(wx+1.0,wy+15.0,ww-2.0,8.0,0.0,[23,33,48]);
    for(i,color)in [[255,95,87],[255,189,46],[40,202,65]].iter().enumerate(){c.circle(wx+14.5+i as f32*14.0,sy(114.5),3.5,*color);}
    c.round(wx+17.0,sy(71.0),74.0,8.0,4.0,[28,39,53]);c.round(wx+17.0,sy(85.0),128.0,7.0,3.0,[19,63,83]);
    let left=wx+11.0;let right=wx+ww-11.0;let mut cap=PathBuilder::new();cap.move_to(left,sy(127.0));cap.cubic_to(left+28.0,sy(135.0),left+61.0,sy(129.0),left+92.0,sy(132.0));cap.cubic_to(left+145.0,sy(136.0),right-42.0,sy(128.0),right,sy(130.0));cap.line_to(right,sy(127.0));cap.close();c.fill(&cap.finish().unwrap(),[237,250,255],250);
    let dx=x+48.0;let dy=sy(46.0);let dw=w-82.0;c.round(dx,dy+1.0,dw,36.0,13.0,[123,147,166]);c.round(dx+1.0,dy+2.0,dw-2.0,33.0,12.0,[67,104,132]);
    let colors=[[10,132,255],[152,154,162],[190,87,237],[255,55,118],[255,69,58],[48,193,219],[94,92,230],[255,159,10]];
    for(i,color)in colors.iter().enumerate(){let ix=dx+18.0+i as f32*34.0;c.round(ix,sy(39.0),22.0,22.0,5.0,*color);c.circle(ix+6.5,sy(33.5),1.5,[190,210,230]);}
    let mut cap=PathBuilder::new();cap.move_to(dx+12.0,sy(46.0));cap.cubic_to(dx+105.0,sy(53.0),dx+dw/2.0-65.0,sy(47.0),dx+dw/2.0,sy(50.0));cap.cubic_to(dx+dw/2.0+70.0,sy(53.0),dx+dw-72.0,sy(46.0),dx+dw-12.0,sy(48.0));cap.line_to(dx+dw-12.0,sy(46.0));cap.close();c.fill(&cap.finish().unwrap(),[244,251,255],255);
    let sx=dx+dw-43.0;let by=60.0;for(dy,r)in [(0.0,15.0),(24.0,11.0),(43.0,8.5)]{c.circle(sx,sy(by+dy),r,[234,250,255]);}
    c.circle(sx-2.6,sy(by+46.2),1.2,[13,13,13]);c.circle(sx+2.6,sy(by+46.2),1.2,[13,13,13]);c.round(sx-7.5,sy(by+54.5),15.0,3.5,0.0,[230,36,46]);c.round(sx-5.5,sy(by+62.0),11.0,8.0,0.0,[230,36,46]);c.clip=None;
}
