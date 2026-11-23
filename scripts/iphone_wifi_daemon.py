#!/usr/bin/env python3
"""
Auto-Connect / Auto-Disconnect Wireless Debugging Daemon untuk iPhone Rian (iOS 16.2).
- Jika iPhone berada di subnet Wi-Fi yang sama dengan PC ini:
    Otomatis membuka sesi Wi-Fi Lockdown + Heartbeat (Marco/Polo) sehingga wireless debugging langsung aktif.
- Jika iPhone tidak lagi di jaringan yang sama (pindah 4G/5G, Wi-Fi lain, atau tidak terjangkau):
    Otomatis memutus Heartbeat & Lockdown session dan mematikan debugging hingga kembali ke jaringan yang sama.
- Menyediakan status lokal di http://127.0.0.1:8765/ (dan JSON di /api/status) serta file status ~/.pymobiledevice3/wifi_debug_state.json.
"""
import asyncio
import datetime
import ipaddress
import json
import os
import plistlib
import socket
import subprocess
import sys
import threading
import time
from http.server import BaseHTTPRequestHandler, HTTPServer
from pathlib import Path

from pymobiledevice3.bonjour import browse_mobdev2
from pymobiledevice3.lockdown import create_using_tcp
from pymobiledevice3.services.heartbeat import HeartbeatService

DEFAULT_UDID = "00008120-000659803410201E"
CACHE_DIR = Path.home() / ".pymobiledevice3"
IP_CACHE_FILE = CACHE_DIR / "last_wifi_ip.txt"
STATE_FILE = CACHE_DIR / "wifi_debug_state.json"
PID_FILE = CACHE_DIR / "wifi_debug_daemon.pid"
LOG_FILE = CACHE_DIR / "wifi_debug_daemon.log"
HTTP_PORT = 8765
POLL_INTERVAL_SEC = 8
FAIL_THRESHOLD = 2  # putus otomatis setelah 2x cek gagal (~16 detik di luar jaringan)


def now_wib() -> str:
    tz = datetime.timezone(datetime.timedelta(hours=7))
    return datetime.datetime.now(tz).strftime("%Y-%m-%d %H:%M:%S WIB")


def log(msg: str):
    line = f"[{now_wib()}] {msg}"
    if sys.stdout is not None:
        try:
            print(line, flush=True)
        except Exception:
            pass
    try:
        CACHE_DIR.mkdir(parents=True, exist_ok=True)
        with open(LOG_FILE, "a", encoding="utf-8") as f:
            f.write(line + "\n")
    except Exception:
        pass


def get_local_ipv4_networks() -> list[ipaddress.IPv4Network]:
    """Ambil subnet jaringan lokal PC ini (mendukung Wi-Fi rumah /24 maupun LAN kantor lintas VLAN /16 seperti 172.16.x.x)."""
    nets: list[ipaddress.IPv4Network] = []
    raw_ips: list[str] = []
    try:
        hostname = socket.gethostname()
        _, _, ips = socket.gethostbyname_ex(hostname)
        raw_ips.extend(ips)
    except Exception:
        pass
    try:
        s = socket.socket(socket.AF_INET, socket.SOCK_DGRAM)
        s.connect(("8.8.8.8", 80))
        primary_ip = s.getsockname()[0]
        s.close()
        if primary_ip not in raw_ips:
            raw_ips.insert(0, primary_ip)
    except Exception:
        pass

    for ip in raw_ips:
        if ip.startswith("127.") or ip.startswith("169.254."):
            continue
        try:
            addr = ipaddress.IPv4Address(ip)
        except ValueError:
            continue
        # Jaringan kantor 172.16-31.x.x sering beda VLAN antar lantai (/16), Wi-Fi rumah 192.168.x.x pakai /24
        if addr in ipaddress.IPv4Network("172.16.0.0/12"):
            net = ipaddress.IPv4Network(f"{ip}/16", strict=False)
        else:
            net = ipaddress.IPv4Network(f"{ip}/24", strict=False)
        if net not in nets:
            nets.append(net)
    return nets


def is_same_network(target_ip: str) -> bool:
    try:
        addr = ipaddress.IPv4Address(target_ip)
    except ValueError:
        return False
    nets = get_local_ipv4_networks()
    if not nets:
        return False
    return any(addr in net for net in nets)


def tcp_probe(ip: str, port: int = 62078, timeout: float = 2.0) -> bool:
    s = socket.socket(socket.AF_INET, socket.SOCK_STREAM)
    s.settimeout(timeout)
    try:
        s.connect((ip, port))
        return True
    except Exception:
        return False
    finally:
        s.close()


def load_pair_record(udid: str) -> dict:
    for p in [CACHE_DIR / f"{udid}.plist", Path(r"C:\ProgramData\Apple\Lockdown") / f"{udid}.plist"]:
        if p.exists():
            return plistlib.loads(p.read_bytes())
    raise FileNotFoundError(f"Pair record {udid}.plist tidak ditemukan.")


def send_windows_toast(title: str, body: str):
    """Tampilkan notifikasi ringan Windows saat status koneksi berubah (non-blocking)."""
    try:
        ps = (
            "[Windows.UI.Notifications.ToastNotificationManager, Windows.UI.Notifications, ContentType = WindowsRuntime] > $null;"
            "$tpl = [Windows.UI.Notifications.ToastNotificationManager]::GetTemplateContent([Windows.UI.Notifications.ToastTemplateType]::ToastText02);"
            f"$tpl.GetElementsByTagName('text')[0].AppendChild($tpl.CreateTextNode('{title.replace(chr(39), '')}')) > $null;"
            f"$tpl.GetElementsByTagName('text')[1].AppendChild($tpl.CreateTextNode('{body.replace(chr(39), '')}')) > $null;"
            "$toast = [Windows.UI.Notifications.ToastNotification]::new($tpl);"
            "[Windows.UI.Notifications.ToastNotificationManager]::CreateToastNotifier('SIAP NEO iPhone Wireless Debug').Show($toast)"
        )
        subprocess.Popen(
            ["powershell", "-NoProfile", "-WindowStyle", "Hidden", "-Command", ps],
            stdout=subprocess.DEVNULL,
            stderr=subprocess.DEVNULL,
            creationflags=getattr(subprocess, "CREATE_NO_WINDOW", 0),
        )
    except Exception:
        pass


class WifiDebugDaemon:
    def __init__(self, udid: str):
        self.udid = udid
        self.pair_record = load_pair_record(udid)
        self.target_mac = (self.pair_record.get("WiFiMACAddress") or "").lower()
        self.lockdown = None
        self.hb_task: asyncio.Task | None = None
        self.connected_ip: str | None = None
        self.fail_count = 0
        self.state = {
            "status": "STARTING",
            "debugging_active": False,
            "device_name": "iPhone Rian",
            "udid": udid,
            "ios_version": "",
            "ip": None,
            "pc_subnets": [],
            "battery": None,
            "same_network": False,
            "last_change": now_wib(),
            "last_check": now_wib(),
            "message": "Inisialisasi pemantau jaringan Wi-Fi...",
        }
        self._save_state()

    def _save_state(self):
        try:
            CACHE_DIR.mkdir(parents=True, exist_ok=True)
            STATE_FILE.write_text(json.dumps(self.state, indent=2), encoding="utf-8")
        except Exception:
            pass

    async def discover_same_network_ip(self) -> str | None:
        # 1. Coba IP yang sedang terkoneksi / cache lebih dulu jika masih satu subnet
        candidates: list[str] = []
        if self.connected_ip:
            candidates.append(self.connected_ip)
        if IP_CACHE_FILE.exists():
            cached = IP_CACHE_FILE.read_text(encoding="utf-8").strip()
            if cached and cached not in candidates:
                candidates.append(cached)

        for ip in candidates:
            if is_same_network(ip) and await asyncio.to_thread(tcp_probe, ip, 62078, 1.8):
                return ip

        # 2. Scan Bonjour mobdev2 di jaringan lokal (jika IP iPhone berubah dari DHCP)
        try:
            answers = await browse_mobdev2(timeout=2.5)
            for ans in answers:
                mac = ans.instance.split("@", 1)[0].lower() if "@" in ans.instance else ""
                if (not self.target_mac or mac == self.target_mac) and ans.addresses:
                    for addr in ans.addresses:
                        ip = addr.full_ip
                        if "." in ip and not ip.startswith("169.254.") and is_same_network(ip):
                            if await asyncio.to_thread(tcp_probe, ip, 62078, 1.8):
                                CACHE_DIR.mkdir(parents=True, exist_ok=True)
                                IP_CACHE_FILE.write_text(ip, encoding="utf-8")
                                return ip
        except Exception:
            pass

        return None

    async def disconnect_debugging(self, reason: str):
        was_connected = self.state.get("debugging_active", False)
        if self.hb_task is not None:
            self.hb_task.cancel()
            try:
                await self.hb_task
            except (asyncio.CancelledError, Exception):
                pass
            self.hb_task = None
        if self.lockdown is not None:
            try:
                await self.lockdown.close()
            except Exception:
                pass
            self.lockdown = None

        self.connected_ip = None
        self.state.update({
            "status": "DISCONNECTED",
            "debugging_active": False,
            "ip": None,
            "same_network": False,
            "last_check": now_wib(),
            "message": reason,
        })
        if was_connected:
            self.state["last_change"] = now_wib()
            log(f"OFFLINE -> Debugging OTOMATIS DIMATIKAN ({reason})")
            send_windows_toast("iPhone Wireless Debug: NONAKTIF", reason)
        self._save_state()

    async def connect_debugging(self, ip: str):
        # Tutup sesi lama jika ada
        if self.hb_task is not None or self.lockdown is not None:
            await self.disconnect_debugging("Menyambungkan ulang...")

        ld = await create_using_tcp(hostname=ip, identifier=self.udid, pair_record=self.pair_record)
        hb_task = asyncio.create_task(HeartbeatService(ld).start())
        await asyncio.sleep(0.4)
        if hb_task.done():
            exc = hb_task.exception()
            await ld.close()
            raise RuntimeError(f"Heartbeat gagal: {exc}")

        name = await ld.get_value(key="DeviceName") or "iPhone Rian"
        ver = await ld.get_value(key="ProductVersion") or ""
        batt = await ld.get_value(domain="com.apple.mobile.battery", key="BatteryCurrentCapacity")

        self.lockdown = ld
        self.hb_task = hb_task
        self.connected_ip = ip
        self.fail_count = 0
        CACHE_DIR.mkdir(parents=True, exist_ok=True)
        IP_CACHE_FILE.write_text(ip, encoding="utf-8")

        self.state.update({
            "status": "CONNECTED",
            "debugging_active": True,
            "device_name": str(name),
            "ios_version": str(ver),
            "ip": ip,
            "battery": batt,
            "same_network": True,
            "last_change": now_wib(),
            "last_check": now_wib(),
            "message": f"Terhubung otomatis di jaringan Wi-Fi yang sama ({ip}:62078)",
        })
        self._save_state()
        log(f"ONLINE -> Debugging OTOMATIS AKTIF untuk {name} (iOS {ver}, {ip}, baterai {batt}%)")
        send_windows_toast("iPhone Wireless Debug: AKTIF", f"{name} terhubung di Wi-Fi ({ip}) • Baterai {batt}%")

    async def run_forever(self):
        log("Memulai Auto Wi-Fi Debugging Daemon (iPhone Rian)...")
        while True:
            subnets = [str(n) for n in get_local_ipv4_networks()]
            self.state["pc_subnets"] = subnets
            self.state["last_check"] = now_wib()

            # Cek kondisi sesi aktif saat ini
            if self.lockdown is not None and self.hb_task is not None:
                hb_dead = self.hb_task.done()
                still_same_net = bool(self.connected_ip and is_same_network(self.connected_ip))
                reachable = False
                if still_same_net and not hb_dead and self.connected_ip:
                    reachable = await asyncio.to_thread(tcp_probe, self.connected_ip, 62078, 1.8)

                if hb_dead or not still_same_net or not reachable:
                    self.fail_count += 1
                    if not still_same_net:
                        await self.disconnect_debugging("PC/iPhone berpindah jaringan — debugging otomatis dimatikan")
                    elif self.fail_count >= FAIL_THRESHOLD or hb_dead:
                        await self.disconnect_debugging("iPhone tidak lagi terjangkau di jaringan Wi-Fi ini")
                else:
                    self.fail_count = 0
                    try:
                        batt = await self.lockdown.get_value(domain="com.apple.mobile.battery", key="BatteryCurrentCapacity")
                        self.state["battery"] = batt
                    except Exception:
                        pass
                    self._save_state()
            else:
                # Belum terhubung -> cek apakah iPhone muncul di jaringan yang sama
                ip = await self.discover_same_network_ip()
                if ip:
                    try:
                        await self.connect_debugging(ip)
                    except Exception as e:
                        log(f"Gagal auto-connect ke {ip}: {e}")
                        await self.disconnect_debugging(f"Menunggu iPhone siap di jaringan ({e})")
                else:
                    if self.state["status"] != "DISCONNECTED":
                        await self.disconnect_debugging("iPhone tidak berada di jaringan Wi-Fi yang sama dengan PC")
                    else:
                        self._save_state()

            await asyncio.sleep(POLL_INTERVAL_SEC)


def start_http_server(daemon: WifiDebugDaemon):
    class Handler(BaseHTTPRequestHandler):
        def log_message(self, format, *args):
            return

        def do_GET(self):
            if self.path == "/api/status":
                body = json.dumps(daemon.state, indent=2).encode("utf-8")
                self.send_response(200)
                self.send_header("Content-Type", "application/json; charset=utf-8")
                self.send_header("Cache-Control", "no-store")
                self.end_headers()
                self.wfile.write(body)
                return

            st = daemon.state
            is_on = st.get("debugging_active", False)
            badge_bg = "#10B981" if is_on else "#EF4444"
            badge_txt = "TERHUBUNG (DEBUGGING AKTIF)" if is_on else "TIDAK DI JARINGAN (DEBUGGING MATI)"
            html = f"""<!doctype html>
<html lang="id"><head><meta charset="utf-8"><meta http-equiv="refresh" content="5">
<title>iPhone Auto Wireless Debugging</title>
<style>
body{{font-family:system-ui,-apple-system,sans-serif;background:#0A1118;color:#F8FAFC;display:flex;justify-content:center;padding:32px}}
.card{{background:#121E2A;border:1px solid #24374A;border-radius:16px;padding:24px;max-width:480px;width:100%}}
.badge{{display:inline-block;padding:6px 12px;border-radius:999px;font-weight:700;font-size:12px;background:{badge_bg};color:#081018}}
.row{{display:flex;justify-content:space-between;padding:8px 0;border-bottom:1px solid #1E2E3F;font-size:14px}}
.lbl{{color:#94A3B8}} .val{{font-weight:600;color:#F8FAFC}}
</style></head><body><div class="card">
<h2 style="margin:0 0 10px">iPhone Auto Wireless Debugging</h2>
<div class="badge">{badge_txt}</div>
<div style="margin-top:16px">
<div class="row"><span class="lbl">Perangkat</span><span class="val">{st.get('device_name')} (iOS {st.get('ios_version') or '16.2'})</span></div>
<div class="row"><span class="lbl">IP Wi-Fi iPhone</span><span class="val">{st.get('ip') or '-'}</span></div>
<div class="row"><span class="lbl">Subnet PC</span><span class="val">{', '.join(st.get('pc_subnets') or []) or '-'}</span></div>
<div class="row"><span class="lbl">Baterai iPhone</span><span class="val">{(str(st.get('battery')) + '%') if st.get('battery') is not None else '-'}</span></div>
<div class="row"><span class="lbl">Status</span><span class="val">{st.get('message')}</span></div>
<div class="row"><span class="lbl">Dicek Terakhir</span><span class="val">{st.get('last_check')}</span></div>
</div></div></body></html>""".encode("utf-8")
            self.send_response(200)
            self.send_header("Content-Type", "text/html; charset=utf-8")
            self.end_headers()
            self.wfile.write(html)

    try:
        srv = HTTPServer(("127.0.0.1", HTTP_PORT), Handler)
        t = threading.Thread(target=srv.serve_forever, daemon=True)
        t.start()
        log(f"Status panel lokal aktif di http://127.0.0.1:{HTTP_PORT}/")
    except OSError as e:
        log(f"Port status {HTTP_PORT} sudah dipakai ({e}), lanjut tanpa HTTP panel.")


def main():
    CACHE_DIR.mkdir(parents=True, exist_ok=True)
    PID_FILE.write_text(str(os.getpid()), encoding="utf-8")
    try:
        daemon = WifiDebugDaemon(DEFAULT_UDID)
        start_http_server(daemon)
        asyncio.run(daemon.run_forever())
    except KeyboardInterrupt:
        log("Daemon dihentikan oleh user.")
    except Exception as e:
        import traceback
        log(f"FATAL ERROR: {e}\n{traceback.format_exc()}")
    finally:
        try:
            PID_FILE.unlink(missing_ok=True)
        except Exception:
            pass


if __name__ == "__main__":
    main()
