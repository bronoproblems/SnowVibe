use serde::{Deserialize, Serialize};
use std::{fs, io, path::{Path,PathBuf}};

#[derive(Clone, Debug, Serialize, Deserialize, PartialEq)]
#[serde(default)]
pub struct Settings {
    pub enabled: bool,
    pub style: usize,
    pub intensity: f32,
    pub wind: f32,
    pub fps: u32,
    pub windows: bool,
    pub taskbar: bool,
    pub cursor: bool,
    pub snowman: bool,
    pub pause_fullscreen: bool,
}
impl Default for Settings {
    fn default() -> Self {
        Self { enabled: true, style: 0, intensity: 0.58, wind: 0.08, fps: 36,
            windows: true, taskbar: true, cursor: true,
            snowman: true, pause_fullscreen: true }
    }
}
impl Settings {
    pub fn normalize(&mut self) {
        self.style = self.style.min(3);
        self.intensity = if self.intensity.is_finite() { self.intensity.clamp(0.15, 1.0) } else { 0.58 };
        self.wind = if self.wind.is_finite() { self.wind.clamp(-1.0, 1.0) } else { 0.08 };
        self.fps = self.fps.clamp(20, 60);
    }
    pub fn path() -> PathBuf {
        std::env::var_os("LOCALAPPDATA").map(PathBuf::from)
            .unwrap_or_else(std::env::temp_dir).join("SnowVibe").join("settings.json")
    }
    pub fn load() -> Self {
        let path=Self::path();
        if !path.exists() && !path.with_extension("bak").exists() {
            // Preserve preferences when upgrading from the previous product name.
            if let Some(root)=path.parent().and_then(Path::parent) {
                let legacy=root.join("SnowGarden").join("settings.json");
                if legacy.exists() || legacy.with_extension("bak").exists() {
                    return Self::load_at(&legacy);
                }
            }
        }
        Self::load_at(&path)
    }
    fn load_at(path:&Path)->Self {
        let parse=|p:&Path|fs::read(p).ok().and_then(|b|serde_json::from_slice::<Self>(&b).ok());
        let mut s=parse(path).or_else(||parse(&path.with_extension("bak"))).unwrap_or_default();
        s.normalize();s
    }
    pub fn save(&self) -> io::Result<()> { self.save_at(&Self::path()) }
    fn save_at(&self,path:&Path)->io::Result<()> {
        if let Some(parent)=path.parent(){fs::create_dir_all(parent)?;}
        let mut normalized=self.clone();normalized.normalize();
        let bytes=serde_json::to_vec_pretty(&normalized)?;
        let tmp=path.with_extension(format!("{}.tmp",std::process::id()));
        {
            use std::io::Write;
            let mut file=fs::File::create(&tmp)?;file.write_all(&bytes)?;file.sync_all()?;
        }
        // Never replace a good backup with a corrupt primary file.
        if fs::read(path).ok().is_some_and(|b|serde_json::from_slice::<Self>(&b).is_ok()){
            fs::copy(path,path.with_extension("bak"))?;
        }
        // MoveFileExW replaces atomically on Windows, unlike std::fs::rename there.
        use std::os::windows::ffi::OsStrExt;
        let a: Vec<u16> = tmp.as_os_str().encode_wide().chain(Some(0)).collect();
        let b: Vec<u16> = path.as_os_str().encode_wide().chain(Some(0)).collect();
        #[link(name = "kernel32")]
        unsafe extern "system" { fn MoveFileExW(a: *const u16, b: *const u16, flags: u32) -> i32; }
        if unsafe { MoveFileExW(a.as_ptr(), b.as_ptr(), 1 | 8) } == 0 { return Err(io::Error::last_os_error()); }
        Ok(())
    }
}

#[cfg(test)]
mod tests {
    use super::*;
    #[test] fn old_config_gets_new_defaults() {
        let s: Settings = serde_json::from_str(r#"{"fps":30,"wind":-0.5}"#).unwrap();
        assert!(s.pause_fullscreen && s.taskbar); assert_eq!(s.fps, 30);
    }
    #[test] fn untrusted_config_is_bounded() {
        let mut s = Settings { style: 50, fps: 0, intensity: f32::NAN, wind: 900.0, ..Settings::default() };
        s.normalize(); assert_eq!(s.style, 3); assert_eq!(s.fps, 20);
        assert_eq!(s.wind, 1.0); assert_eq!(s.intensity, 0.58);
    }
    #[test] fn old_ground_option_is_ignored_and_not_saved() {
        let s:Settings=serde_json::from_str(r#"{"ground":true,"fps":30}"#).unwrap();
        assert_eq!(s.fps,30);
        assert!(!serde_json::to_string(&s).unwrap().contains("ground"));
    }
    #[test]fn corrupted_settings_recover_from_backup_without_losing_it(){
        let root=PathBuf::from(env!("CARGO_MANIFEST_DIR")).join("build").join(format!("settings-test-{}",std::process::id()));fs::create_dir_all(&root).unwrap();
        let path=root.join("settings.json");let backup=path.with_extension("bak");
        fs::write(&path,b"broken json").unwrap();fs::write(&backup,br#"{"fps":29,"wind":-0.2}"#).unwrap();
        let mut recovered=Settings::load_at(&path);assert_eq!(recovered.fps,29);assert_eq!(recovered.wind,-0.2);
        recovered.fps=31;recovered.save_at(&path).unwrap();
        assert_eq!(Settings::load_at(&path).fps,31);
        assert_eq!(serde_json::from_slice::<Settings>(&fs::read(&backup).unwrap()).unwrap().fps,29);
        fs::remove_file(path).unwrap();fs::remove_file(backup).unwrap();fs::remove_dir(root).unwrap();
    }
}
