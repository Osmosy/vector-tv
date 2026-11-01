#!/usr/bin/env python3
"""Быстрый профиль телевизора в сети: порт на мосту, порты ТВ, часы, TCP-отклик.

    python3 tv-probe.py 192.168.1.61                 # профиль
    python3 tv-probe.py 192.168.1.61 --watch 12      # следить за uptime (перезагрузки)

Keenetic (мост, за которым сидит ТВ) опрашивается по RCI с Basic auth; креды берутся
из netrc-файла, путь — переменная KN_NETRC (по умолчанию ~/.config/keenetic.netrc).
Без netrc проверка порта моста пропускается, остальное работает.
"""
import argparse
import json
import os
import re
import socket
import subprocess
import time
import urllib.error
import urllib.request

PORTS = (80, 443, 8001, 8002, 55000, 7676, 9090, 9197, 52235)


def rci(host, path, netrc):
    if not netrc or not os.path.exists(netrc):
        return {}
    out = subprocess.run(["curl", "-sS", "-m", "8", "--netrc-file", netrc,
                          f"http://{host}/rci/{path}"], capture_output=True, text=True).stdout
    try:
        return json.loads(out)
    except Exception:
        return {}


def tcp(ip, port, n=5, timeout=3.0):
    ok, times = 0, []
    for _ in range(n):
        s = socket.socket()
        s.settimeout(timeout)
        t0 = time.time()
        try:
            s.connect((ip, port))
            ok += 1
            times.append((time.time() - t0) * 1000)
        except OSError:
            pass
        finally:
            s.close()
        time.sleep(0.15)
    return ok, (round(min(times), 1), round(sum(times) / len(times), 1), round(max(times), 1)) if times else None


def tv_clock(ip):
    """Date из ответа. У старых Samsung это 1970-01-01 + время работы, а не реальное время."""
    try:
        with urllib.request.urlopen(f"http://{ip}/", timeout=4) as r:
            return r.headers.get("Date")
    except urllib.error.HTTPError as e:
        return e.headers.get("Date")
    except Exception:
        return None


def uptime(date_str):
    m = re.search(r"1970 (\d\d):(\d\d):(\d\d)", date_str or "")
    return int(m.group(1)) * 3600 + int(m.group(2)) * 60 + int(m.group(3)) if m else None


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("ip")
    ap.add_argument("--bridge", default=os.environ.get("KN_BRIDGE", ""), help="IP моста Keenetic")
    ap.add_argument("--netrc", default=os.environ.get("KN_NETRC", os.path.expanduser("~/.config/keenetic.netrc")))
    ap.add_argument("--watch", type=int, default=0, help="замеров по 15 с")
    a = ap.parse_args()

    if a.bridge:
        d = rci(a.bridge, "show/interface/FastEthernet0", a.netrc)
        print(f"мост {a.bridge}: кабельный порт link={d.get('link')} speed={d.get('speed')}")

    d = tv_clock(a.ip)
    u = uptime(d)
    print(f"часы ТВ: {d}  ({'uptime %d мин %02d с' % (u // 60, u % 60) if u else 'реальное время или нет ответа'})")

    print("TCP-отклик:")
    for p in PORTS:
        ok, st = tcp(a.ip, p)
        if ok:
            print(f"  {p:<6} открыт   успешно {ok}/5  min/avg/max = {st} мс")
    closed = [p for p in PORTS if tcp(a.ip, p, n=1)[0] == 0]
    print(f"  закрыты: {', '.join(map(str, closed)) or '—'}")

    if a.watch:
        print(f"\nнаблюдение {a.watch} × 15 с")
        prev, resets, miss = None, 0, 0
        for i in range(a.watch):
            u = uptime(tv_clock(a.ip))
            if u is None:
                miss += 1
                print(f"  {time.strftime('%H:%M:%S')}  нет ответа")
            else:
                mark = ""
                if prev is not None and u < prev:
                    resets += 1
                    mark = "  ← СБРОС uptime (перезагрузка)"
                print(f"  {time.strftime('%H:%M:%S')}  uptime {u // 60}м{u % 60:02d}с{mark}")
                prev = u
            time.sleep(15)
        print(f"итог: перезагрузок {resets}, неответов {miss} из {a.watch}")


if __name__ == "__main__":
    main()
