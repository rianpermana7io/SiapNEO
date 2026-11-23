#!/usr/bin/env python3
"""
Wireless Debugging CLI untuk iPhone Rian (iOS 16.2) via Wi-Fi (TCP Lockdown + Heartbeat).
Tidak memerlukan kabel USB selama PC dan iPhone berada di jaringan Wi-Fi yang sama.
"""
import argparse
import asyncio
import datetime
import os
import plistlib
import sys
from pathlib import Path

from pymobiledevice3.bonjour import browse_mobdev2
from pymobiledevice3.lockdown import create_using_tcp
from pymobiledevice3.services.afc import AfcService
from pymobiledevice3.services.dvt.instruments.device_info import DeviceInfo
from pymobiledevice3.services.dvt.instruments.dvt_provider import DvtProvider
from pymobiledevice3.services.dvt.instruments.process_control import ProcessControl
from pymobiledevice3.services.dvt.instruments.screenshot import Screenshot
from pymobiledevice3.services.heartbeat import HeartbeatService
from pymobiledevice3.services.installation_proxy import InstallationProxyService
from pymobiledevice3.services.os_trace import OsTraceService

DEFAULT_UDID = "00008120-000659803410201E"
CACHE_DIR = Path.home() / ".pymobiledevice3"
IP_CACHE_FILE = CACHE_DIR / "last_wifi_ip.txt"


def load_pair_record(udid: str) -> dict:
    candidates = [
        CACHE_DIR / f"{udid}.plist",
        Path(r"C:\ProgramData\Apple\Lockdown") / f"{udid}.plist",
    ]
    for p in candidates:
        if p.exists():
            return plistlib.loads(p.read_bytes())
    raise FileNotFoundError(
        f"Pair record {udid}.plist tidak ditemukan. Colok USB sekali lalu jalankan:\n"
        f"  python -m pymobiledevice3 lockdown save-pair-record \"{CACHE_DIR / (udid + '.plist')}\""
    )


async def resolve_ip(explicit_ip: str | None, pair_record: dict) -> str:
    if explicit_ip:
        return explicit_ip

    target_mac = (pair_record.get("WiFiMACAddress") or "").lower()
    try:
        answers = await browse_mobdev2(timeout=2.5)
        for ans in answers:
            mac = ans.instance.split("@", 1)[0].lower() if "@" in ans.instance else ""
            if (not target_mac or mac == target_mac) and ans.addresses:
                for addr in ans.addresses:
                    ip = addr.full_ip
                    if "." in ip and not ip.startswith("169.254."):
                        CACHE_DIR.mkdir(parents=True, exist_ok=True)
                        IP_CACHE_FILE.write_text(ip, encoding="utf-8")
                        return ip
    except Exception:
        pass

    if IP_CACHE_FILE.exists():
        cached = IP_CACHE_FILE.read_text(encoding="utf-8").strip()
        if cached:
            return cached

    raise RuntimeError("iPhone tidak ditemukan di Wi-Fi. Pastikan Wi-Fi sama dan layar iPhone sempat dinyalakan.")


async def connect_wifi(udid: str, ip: str | None):
    pr = load_pair_record(udid)
    host = await resolve_ip(ip, pr)
    ld = await create_using_tcp(hostname=host, identifier=udid, pair_record=pr)
    hb_task = asyncio.create_task(HeartbeatService(ld).start())
    await asyncio.sleep(0.35)
    return ld, hb_task, host


async def run_cmd(args):
    ld, hb_task, host = await connect_wifi(args.udid, args.ip)
    try:
        if args.cmd == "status":
            name = await ld.get_value(key="DeviceName")
            ver = await ld.get_value(key="ProductVersion")
            batt = await ld.get_value(domain="com.apple.mobile.battery", key="BatteryCurrentCapacity")
            wifi_on = await ld.get_value(domain="com.apple.mobile.wireless_lockdown", key="EnableWifiConnections")
            dev_mode = await ld.get_developer_mode_status()
            print(f"Status     : TERHUBUNG (WI-FI WIRELESS DEBUGGING)")
            print(f"Perangkat  : {name} ({ld.product_type})")
            print(f"iOS        : {ver} | Developer Mode: {dev_mode}")
            print(f"IP Wi-Fi   : {host}:62078")
            print(f"Baterai    : {batt}%")
            print(f"Wi-Fi Sync : {wifi_on}")

        elif args.cmd == "ls":
            remote_dir = args.path or "/Downloads"
            async with AfcService(ld) as afc:
                items = await afc.listdir(remote_dir)
                print(f"Isi {remote_dir} ({len(items)} item) via Wi-Fi {host}:")
                for item in sorted(items):
                    print(" ", item)

        elif args.cmd == "push":
            local = Path(args.file)
            if not local.exists():
                raise FileNotFoundError(f"File tidak ditemukan: {local}")
            remote_dir = (args.remote_dir or "/Downloads").rstrip("/")
            remote_path = f"{remote_dir}/{local.name}"
            print(f"Mengirim {local.name} ({local.stat().st_size:,} bytes) -> {remote_path} via Wi-Fi {host}...")
            async with AfcService(ld) as afc:
                await afc.push(str(local), remote_path)
            print("BERHASIL dikirim via Wi-Fi!")

        elif args.cmd == "apps":
            flt = (args.filter or "").lower()
            async with InstallationProxyService(ld) as inst:
                apps = await inst.get_apps(application_type="Any")
                matched = []
                for bid, info in sorted(apps.items()):
                    name = info.get("CFBundleDisplayName") or info.get("CFBundleName") or ""
                    ver = info.get("CFBundleShortVersionString") or ""
                    if not flt or flt in bid.lower() or flt in name.lower():
                        matched.append((bid, name, ver))
                print(f"Aplikasi terpasang via Wi-Fi {host} ({len(matched)} cocok dari {len(apps)}):")
                for bid, name, ver in matched:
                    print(f"  {bid}  |  {name} ({ver})")

        elif args.cmd == "procs":
            flt = (args.filter or "").lower()
            async with DvtProvider(ld) as dvt:
                async with DeviceInfo(dvt) as di:
                    procs = await di.proclist()
                    matched = [p for p in procs if not flt or flt in (p.get("name") or "").lower()]
                    print(f"Proses aktif via Wi-Fi {host} ({len(matched)} dari {len(procs)}):")
                    for p in matched:
                        print(f"  PID {p.get('pid'):>6}  {p.get('name')}")

        elif args.cmd == "launch":
            bundle_id = args.bundle_id or "com.kemenkeu.bcpriok.siapneo.ios"
            async with DvtProvider(ld) as dvt:
                async with ProcessControl(dvt) as pc:
                    pid = await pc.launch(bundle_id)
                    print(f"Berhasil membuka {bundle_id} via Wi-Fi {host} (PID: {pid})")

        elif args.cmd == "screenshot":
            out = Path(args.out) if args.out else Path.home() / "Downloads" / f"iphone_wifi_{datetime.datetime.now().strftime('%Y%m%d_%H%M%S')}.png"
            async with DvtProvider(ld) as dvt:
                async with Screenshot(dvt) as sc:
                    png = await sc.get_screenshot()
                    out.write_bytes(png)
                    print(f"Screenshot Wi-Fi disimpan ke: {out} ({len(png):,} bytes)")

        elif args.cmd == "syslog":
            flt = (args.filter or "SIAPNeo").lower()
            print(f"Streaming syslog Wi-Fi {host} (filter='{flt}', Ctrl+C untuk berhenti)...")
            async with OsTraceService(ld) as ost:
                async for entry in ost.syslog():
                    msg = entry.message or ""
                    proc = entry.filename or ""
                    if not flt or flt in msg.lower() or flt in proc.lower():
                        print(f"[{entry.timestamp}] {proc}: {msg}")
    finally:
        hb_task.cancel()
        try:
            await hb_task
        except asyncio.CancelledError:
            pass
        await ld.close()


def main():
    parser = argparse.ArgumentParser(description="Wireless iPhone Debugging CLI (Wi-Fi TCP + Heartbeat)")
    parser.add_argument("--udid", default=DEFAULT_UDID)
    parser.add_argument("--ip", default=None, help="IP iPhone opsional (otomatis cari via Bonjour/cache)")
    sub = parser.add_subparsers(dest="cmd", required=True)

    sub.add_parser("status", help="Cek status koneksi Wi-Fi debugging iPhone")

    p_ls = sub.add_parser("ls", help="Daftar file di iPhone via Wi-Fi AFC")
    p_ls.add_argument("path", nargs="?", default="/Downloads")

    p_push = sub.add_parser("push", help="Kirim file/IPA ke iPhone via Wi-Fi")
    p_push.add_argument("file")
    p_push.add_argument("remote_dir", nargs="?", default="/Downloads")

    p_apps = sub.add_parser("apps", help="Daftar aplikasi terpasang")
    p_apps.add_argument("filter", nargs="?", default="")

    p_procs = sub.add_parser("procs", help="Daftar proses aktif (DVT)")
    p_procs.add_argument("filter", nargs="?", default="")

    p_launch = sub.add_parser("launch", help="Jalankan aplikasi via Wi-Fi (DVT)")
    p_launch.add_argument("bundle_id", nargs="?", default="com.kemenkeu.bcpriok.siapneo.ios")

    p_sc = sub.add_parser("screenshot", help="Ambil screenshot layar iPhone via Wi-Fi")
    p_sc.add_argument("out", nargs="?", default=None)

    p_log = sub.add_parser("syslog", help="Stream live syslog via Wi-Fi")
    p_log.add_argument("filter", nargs="?", default="SIAPNeo")

    args = parser.parse_args()
    try:
        asyncio.run(run_cmd(args))
    except KeyboardInterrupt:
        pass


if __name__ == "__main__":
    main()
