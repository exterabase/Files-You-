use serde_json::{json, Value};
use std::ffi::{CStr, CString};
use std::fs;
use std::io::{BufRead, BufReader, Read, Write};
use std::net::{TcpListener, TcpStream};
use std::os::raw::c_char;
use std::path::{Path, PathBuf};
use std::sync::atomic::{AtomicBool, Ordering};
use std::sync::{Arc, Mutex};
use std::time::{Duration, UNIX_EPOCH};
use std::collections::HashMap;
use std::hash::{Hash, Hasher};
use std::collections::hash_map::DefaultHasher;

fn cs(p: *const c_char) -> String {
    if p.is_null() { return String::new(); }
    unsafe { CStr::from_ptr(p).to_string_lossy().into_owned() }
}
fn out(s: String) -> *mut c_char {
    CString::new(s.replace('\0', "")).unwrap().into_raw()
}
#[no_mangle]
pub extern "C" fn fy_free(p: *mut c_char) {
    if !p.is_null() { unsafe { drop(CString::from_raw(p)) } }
}

fn ent(p: &Path) -> Option<Value> {
    let m = fs::metadata(p).ok()?;
    let mod_ = m.modified().ok().and_then(|t| t.duration_since(UNIX_EPOCH).ok()).map(|d| d.as_secs()).unwrap_or(0);
    Some(json!({"p": p.to_string_lossy(), "n": p.file_name()?.to_string_lossy(), "d": m.is_dir(), "s": if m.is_dir() {0} else {m.len()}, "m": mod_}))
}
fn hidden(p: &Path) -> bool {
    p.file_name().map(|n| n.to_string_lossy().starts_with('.')).unwrap_or(false)
}

#[no_mangle]
pub extern "C" fn fy_storage(path: *const c_char) -> *mut c_char {
    let path = CString::new(cs(path)).unwrap();
    let mut s: libc::statvfs = unsafe { std::mem::zeroed() };
    let r = unsafe { libc::statvfs(path.as_ptr(), &mut s) };
    if r != 0 { return out(json!({"total":0,"free":0}).to_string()); }
    let bs = s.f_frsize as u64;
    out(json!({"total": s.f_blocks as u64 * bs, "free": s.f_bavail as u64 * bs}).to_string())
}

#[no_mangle]
pub extern "C" fn fy_list(path: *const c_char, show_hidden: i32) -> *mut c_char {
    let mut v = vec![];
    if let Ok(rd) = fs::read_dir(cs(path)) {
        for e in rd.flatten() {
            let p = e.path();
            if show_hidden == 0 && hidden(&p) { continue; }
            if let Some(j) = ent(&p) { v.push(j); }
        }
    }
    out(Value::Array(v).to_string())
}

fn walk(root: &str, show_hidden: bool, mut f: impl FnMut(&Path, &fs::Metadata) -> bool) {
    let mut st = vec![PathBuf::from(root)];
    while let Some(d) = st.pop() {
        let Ok(rd) = fs::read_dir(&d) else { continue };
        for e in rd.flatten() {
            let p = e.path();
            if !show_hidden && hidden(&p) { continue; }
            let Ok(m) = fs::symlink_metadata(&p) else { continue };
            if m.is_dir() { st.push(p.clone()); }
            if !f(&p, &m) { return; }
        }
    }
}

#[no_mangle]
pub extern "C" fn fy_search(root: *const c_char, query: *const c_char, exts: *const c_char, show_hidden: i32, limit: i32) -> *mut c_char {
    let q = cs(query).to_lowercase();
    let ex: Vec<String> = cs(exts).split(',').filter(|s| !s.is_empty()).map(|s| s.to_lowercase()).collect();
    let mut v = vec![];
    walk(&cs(root), show_hidden != 0, |p, m| {
        let ok_ext = if ex.is_empty() { true } else { !m.is_dir() && p.extension().map(|e| ex.contains(&e.to_string_lossy().to_lowercase())).unwrap_or(false) };
        let ok_q = q.is_empty() || p.to_string_lossy().to_lowercase().contains(&q);
        let ok_kind = !(q.is_empty() && m.is_dir());
        if ok_ext && ok_q && ok_kind { if let Some(j) = ent(p) { v.push(j); } }
        (v.len() as i32) < limit
    });
    out(Value::Array(v).to_string())
}

#[no_mangle]
pub extern "C" fn fy_scan(root: *const c_char) -> *mut c_char {
    let (mut ph, mut au, mut vi) = (0u64, 0u64, 0u64);
    walk(&cs(root), false, |p, m| {
        if m.is_file() {
            let e = p.extension().map(|e| e.to_string_lossy().to_lowercase()).unwrap_or_default();
            match e.as_str() {
                "jpg" | "jpeg" | "png" | "gif" | "webp" | "heic" | "bmp" => ph += m.len(),
                "mp3" | "wav" | "flac" | "m4a" | "ogg" | "aac" | "opus" => au += m.len(),
                "mp4" | "mkv" | "avi" | "mov" | "webm" | "3gp" => vi += m.len(),
                _ => {}
            }
        }
        true
    });
    out(json!({"photo": ph, "audio": au, "video": vi}).to_string())
}

fn file_fingerprint(p: &Path, size: u64) -> u64 {
    let mut hasher = DefaultHasher::new();
    size.hash(&mut hasher);
    p.extension().map(|e| e.to_string_lossy().to_lowercase()).unwrap_or_default().hash(&mut hasher);
    hasher.finish()
}

#[no_mangle]
pub extern "C" fn fy_analyze_quick(root: *const c_char) -> *mut c_char {
    let root = cs(root);
    let mut photo = 0u64;
    let mut audio = 0u64;
    let mut video = 0u64;
    let mut documents = 0u64;
    let mut apps = 0u64;
    let mut other = 0u64;
    let mut folders = HashMap::<String, u64>::new();
    walk(&root, false, |p, m| {
        if m.is_dir() { return true; }
        if !m.is_file() { return true; }
        let size = m.len();
        let ext = p.extension().map(|e| e.to_string_lossy().to_lowercase()).unwrap_or_default();
        match ext.as_str() {
            "jpg"|"jpeg"|"png"|"gif"|"webp"|"heic"|"heif"|"bmp"|"avif" => photo += size,
            "mp3"|"wav"|"flac"|"m4a"|"ogg"|"aac"|"opus"|"amr"|"wma" => audio += size,
            "mp4"|"mkv"|"avi"|"mov"|"webm"|"3gp"|"m4v" => video += size,
            "pdf"|"doc"|"docx"|"xls"|"xlsx"|"ppt"|"pptx"|"txt"|"md"|"odt"|"rtf"|"csv"|"json"|"xml"|"html"|"htm" => documents += size,
            "apk"|"xapk"|"apks"|"obb"|"aab" => apps += size,
            _ => other += size,
        }
        let rel = p.strip_prefix(&root).unwrap_or(p).to_string_lossy().replace('\\', "/");
        let top = rel.split('/').next().unwrap_or("").to_string();
        if !top.is_empty() { *folders.entry(top).or_insert(0) += size; }
        true
    });
    let mut folder_rows: Vec<Value> = folders.into_iter().map(|(name,size)| json!({"name":name,"size":size})).collect();
    folder_rows.sort_by(|a,b| b["size"].as_u64().unwrap_or(0).cmp(&a["size"].as_u64().unwrap_or(0)));
    out(json!({
        "categories":{"photo":photo,"audio":audio,"video":video,"documents":documents,"apps":apps,"other":other},
        "folders":folder_rows.into_iter().take(40).collect::<Vec<_>>(),
        "large":[],"recent":[],"empty":[],"duplicates":[],"trash":[]
    }).to_string())
}

#[no_mangle]
pub extern "C" fn fy_analyze(root: *const c_char) -> *mut c_char {
    let root = cs(root);
    let mut photo = 0u64;
    let mut audio = 0u64;
    let mut video = 0u64;
    let mut documents = 0u64;
    let mut apps = 0u64;
    let mut other = 0u64;
    let mut large = Vec::<Value>::new();
    let mut recent = Vec::<Value>::new();
    let mut empty = Vec::<Value>::new();
    let mut trash = Vec::<Value>::new();
    let mut folders = Vec::<(String, u64, String)>::new();
    let mut fingerprints = HashMap::<u64, Vec<Value>>::new();
    let mut now = 0u64;
    if let Ok(t) = std::time::SystemTime::now().duration_since(UNIX_EPOCH) { now = t.as_secs(); }
    let mut folder_sums = HashMap::<String, u64>::new();

    walk(&root, false, |p, m| {
        if m.is_dir() {
            if let Ok(rd) = fs::read_dir(p) {
                if rd.count() == 0 {
                    if let Some(j) = ent(p) { empty.push(j); }
                }
            }
            return true;
        }
        if !m.is_file() { return true; }
        let size = m.len();
        let ext = p.extension().map(|e| e.to_string_lossy().to_lowercase()).unwrap_or_default();
        match ext.as_str() {
            "jpg"|"jpeg"|"png"|"gif"|"webp"|"heic"|"heif"|"bmp"|"avif" => photo += size,
            "mp3"|"wav"|"flac"|"m4a"|"ogg"|"aac"|"opus"|"amr"|"wma" => audio += size,
            "mp4"|"mkv"|"avi"|"mov"|"webm"|"3gp"|"m4v" => video += size,
            "pdf"|"doc"|"docx"|"xls"|"xlsx"|"ppt"|"pptx"|"txt"|"md"|"odt"|"rtf"|"csv"|"json"|"xml"|"html"|"htm" => documents += size,
            "apk"|"xapk"|"apks"|"obb"|"aab" => apps += size,
            _ => other += size,
        }
        if size >= 100 * 1024 * 1024 {
            if let Some(j) = ent(p) { large.push(j); }
        }
        let mod_ = m.modified().ok().and_then(|t| t.duration_since(UNIX_EPOCH).ok()).map(|d| d.as_secs()).unwrap_or(0);
        if now > mod_ && now - mod_ <= 14 * 86400 {
            if let Some(j) = ent(p) { recent.push(j); }
        }
        let rel = p.strip_prefix(&root).unwrap_or(p).to_string_lossy().replace('\\', "/");
        if rel.starts_with(".FilesYouTrash/") {
            if let Some(j) = ent(p) { trash.push(j); }
        }
        let top = rel.split('/').next().unwrap_or("").to_string();
        if !top.is_empty() { *folder_sums.entry(top).or_insert(0) += size; }
        if size > 0 {
            let fp = file_fingerprint(p, size);
            if let Some(j) = ent(p) { fingerprints.entry(fp).or_default().push(j); }
        }
        true
    });

    large.sort_by(|a,b| b["s"].as_u64().unwrap_or(0).cmp(&a["s"].as_u64().unwrap_or(0)));
    recent.sort_by(|a,b| b["m"].as_u64().unwrap_or(0).cmp(&a["m"].as_u64().unwrap_or(0)));
    for (name, size) in folder_sums { folders.push((name, size, format!("{size}"))); }
    folders.sort_by(|a,b| b.1.cmp(&a.1));
    let folder_json: Vec<Value> = folders.into_iter().take(40).map(|(name,size,_)| json!({"name":name,"size":size})).collect();
    let duplicates: Vec<Value> = fingerprints.into_values().filter(|v| v.len() > 1).take(100).map(|v| json!({"files":v})).collect();
    let categories = json!({"photo":photo,"audio":audio,"video":video,"documents":documents,"apps":apps,"other":other});
    out(json!({
        "categories":categories,
        "large":large.into_iter().take(200).collect::<Vec<_>>(),
        "recent":recent.into_iter().take(200).collect::<Vec<_>>(),
        "empty":empty.into_iter().take(200).collect::<Vec<_>>(),
        "duplicates":duplicates,
        "trash":trash.into_iter().take(200).collect::<Vec<_>>(),
        "folders":folder_json
    }).to_string())
}

// ---------------- minimal FTP server ----------------
static STOP: Mutex<Option<Arc<AtomicBool>>> = Mutex::new(None);

fn vres(cwd: &[String], arg: &str) -> Vec<String> {
    let mut v: Vec<String> = if arg.starts_with('/') { vec![] } else { cwd.to_vec() };
    for part in arg.split('/') {
        match part { "" | "." => {}, ".." => { v.pop(); }, x => v.push(x.to_string()) }
    }
    v
}
fn real(root: &Path, v: &[String]) -> PathBuf {
    let mut p = root.to_path_buf();
    for x in v { p.push(x); }
    p
}
fn send(s: &mut TcpStream, m: &str) { let _ = s.write_all(format!("{}\r\n", m).as_bytes()); }

fn client(mut s: TcpStream, root: PathBuf, user: String, pass: String, show_hidden: bool, stop: Arc<AtomicBool>) {
    let _ = s.set_read_timeout(Some(Duration::from_secs(300)));
    let mut r = BufReader::new(s.try_clone().unwrap());
    let (mut cwd, mut got_user, mut auth) = (Vec::<String>::new(), false, false);
    let mut pasv: Option<TcpListener> = None;
    let mut rnfr: Option<PathBuf> = None;
    send(&mut s, "220 Files You FTP");
    let mut line = String::new();
    loop {
        line.clear();
        if r.read_line(&mut line).unwrap_or(0) == 0 || stop.load(Ordering::Relaxed) { break; }
        let l = line.trim_end().to_string();
        let (cmd, arg) = match l.split_once(' ') { Some((c, a)) => (c.to_uppercase(), a.to_string()), None => (l.to_uppercase(), String::new()) };
        if cmd == "USER" { got_user = arg == user; send(&mut s, "331 Password required"); continue; }
        if cmd == "PASS" { auth = got_user && arg == pass; send(&mut s, if auth { "230 OK" } else { "530 Login incorrect" }); continue; }
        if cmd == "QUIT" { send(&mut s, "221 Bye"); break; }
        if !auth { send(&mut s, "530 Please login"); continue; }
        match cmd.as_str() {
            "SYST" => send(&mut s, "215 UNIX Type: L8"),
            "FEAT" => send(&mut s, "211-Features:\r\n SIZE\r\n UTF8\r\n211 End"),
            "OPTS" | "TYPE" | "NOOP" | "MODE" | "STRU" => send(&mut s, "200 OK"),
            "PWD" | "XPWD" => send(&mut s, &format!("257 \"/{}\"", cwd.join("/"))),
            "CWD" | "XCWD" | "CDUP" => {
                let n = vres(&cwd, if cmd == "CDUP" { ".." } else { &arg });
                if real(&root, &n).is_dir() { cwd = n; send(&mut s, "250 OK"); } else { send(&mut s, "550 No such directory"); }
            }
            "PASV" => {
                match TcpListener::bind("0.0.0.0:0") {
                    Ok(l) => {
                        let port = l.local_addr().unwrap().port();
                        let ip = match s.local_addr().unwrap().ip() { std::net::IpAddr::V4(v) => v.octets(), _ => [127, 0, 0, 1] };
                        send(&mut s, &format!("227 Entering Passive Mode ({},{},{},{},{},{})", ip[0], ip[1], ip[2], ip[3], port >> 8, port & 255));
                        pasv = Some(l);
                    }
                    Err(_) => send(&mut s, "425 Cannot open passive port"),
                }
            }
            "LIST" | "NLST" | "RETR" | "STOR" => {
                let Some(l) = pasv.take() else { send(&mut s, "425 Use PASV first"); continue };
                let a = arg.split(' ').filter(|x| !x.starts_with('-')).collect::<Vec<_>>().join(" ");
                let target = real(&root, &vres(&cwd, &a));
                send(&mut s, "150 Opening data connection");
                let Ok((mut d, _)) = l.accept() else { send(&mut s, "425 Failed"); continue };
                let ok = match cmd.as_str() {
                    "LIST" | "NLST" => {
                        let mut txt = String::new();
                        let dir = if target.is_dir() { target.clone() } else { target.parent().unwrap_or(&root).to_path_buf() };
                        if let Ok(rd) = fs::read_dir(dir) {
                            for e in rd.flatten() {
                                let p = e.path();
                                if !show_hidden && hidden(&p) { continue; }
                                let Ok(m) = fs::metadata(&p) else { continue };
                                let n = p.file_name().unwrap().to_string_lossy().to_string();
                                if cmd == "NLST" { txt += &format!("{}\r\n", n); }
                                else { txt += &format!("{}rw-r--r-- 1 user group {} Jan  1 00:00 {}\r\n", if m.is_dir() { "d" } else { "-" }, m.len(), n); }
                            }
                        }
                        d.write_all(txt.as_bytes()).is_ok()
                    }
                    "RETR" => match fs::File::open(&target) { Ok(mut f) => std::io::copy(&mut f, &mut d).is_ok(), Err(_) => false },
                    _ => match fs::File::create(&target) { Ok(mut f) => std::io::copy(&mut d, &mut f).is_ok(), Err(_) => false },
                };
                drop(d);
                send(&mut s, if ok { "226 Done" } else { "550 Failed" });
            }
            "SIZE" => match fs::metadata(real(&root, &vres(&cwd, &arg))) { Ok(m) => send(&mut s, &format!("213 {}", m.len())), Err(_) => send(&mut s, "550 No file") },
            "DELE" => send(&mut s, if fs::remove_file(real(&root, &vres(&cwd, &arg))).is_ok() { "250 Deleted" } else { "550 Failed" }),
            "RMD" | "XRMD" => send(&mut s, if fs::remove_dir_all(real(&root, &vres(&cwd, &arg))).is_ok() { "250 Removed" } else { "550 Failed" }),
            "MKD" | "XMKD" => send(&mut s, if fs::create_dir_all(real(&root, &vres(&cwd, &arg))).is_ok() { "257 Created" } else { "550 Failed" }),
            "RNFR" => { rnfr = Some(real(&root, &vres(&cwd, &arg))); send(&mut s, "350 Ready for RNTO"); }
            "RNTO" => {
                let ok = rnfr.take().map(|f| fs::rename(f, real(&root, &vres(&cwd, &arg))).is_ok()).unwrap_or(false);
                send(&mut s, if ok { "250 Renamed" } else { "550 Failed" });
            }
            _ => send(&mut s, "502 Not implemented"),
        }
    }
    let mut _x = Vec::new();
    let _ = r.read_to_end(&mut _x);
}

#[no_mangle]
pub extern "C" fn fy_ftp_start(root: *const c_char, port: i32, user: *const c_char, pass: *const c_char, show_hidden: i32) -> i32 {
    fy_ftp_stop();
    let Ok(l) = TcpListener::bind(("0.0.0.0", port as u16)) else { return -1 };
    let _ = l.set_nonblocking(true);
    let stop = Arc::new(AtomicBool::new(false));
    *STOP.lock().unwrap() = Some(stop.clone());
    let (root, user, pass) = (PathBuf::from(cs(root)), cs(user), cs(pass));
    std::thread::spawn(move || {
        while !stop.load(Ordering::Relaxed) {
            match l.accept() {
                Ok((s, _)) => {
                    let _ = s.set_nonblocking(false);
                    let (r, u, p, st) = (root.clone(), user.clone(), pass.clone(), stop.clone());
                    std::thread::spawn(move || client(s, r, u, p, show_hidden != 0, st));
                }
                Err(_) => std::thread::sleep(Duration::from_millis(150)),
            }
        }
    });
    0
}
#[no_mangle]
pub extern "C" fn fy_ftp_stop() {
    if let Some(s) = STOP.lock().unwrap().take() { s.store(true, Ordering::Relaxed); }
}
