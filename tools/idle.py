#!/usr/bin/env python3
"""Samples a running process over an idle interval (validation only).

Usage: idle.py PID SECONDS
Prints the process's CPU ticks (utime + stime, all threads) used during
the interval, each thread's voluntary and involuntary context switches
during it (a sleeping thread that wakes counts a voluntary switch), and
the process's VmRSS and VmHWM at the end.
"""
import os
import sys
import time


def cpu(pid):
    with open(f'/proc/{pid}/stat') as f:
        parts = f.read().rsplit(')', 1)[1].split()
    return int(parts[11]) + int(parts[12])


def threads(pid):
    out = {}
    for tid in os.listdir(f'/proc/{pid}/task'):
        try:
            name = open(f'/proc/{pid}/task/{tid}/comm').read().strip()
            vol = inv = 0
            for line in open(f'/proc/{pid}/task/{tid}/status'):
                if line.startswith('voluntary_ctxt_switches'):
                    vol = int(line.split()[1])
                elif line.startswith('nonvoluntary_ctxt_switches'):
                    inv = int(line.split()[1])
            out[tid] = (name, vol, inv)
        except FileNotFoundError:
            pass
    return out


def memory(pid):
    vals = {}
    for line in open(f'/proc/{pid}/status'):
        if line.startswith(('VmRSS', 'VmHWM')):
            k, v = line.split(':')
            vals[k] = int(v.split()[0])
    return vals


def main():
    pid, secs = int(sys.argv[1]), float(sys.argv[2])
    c0, t0 = cpu(pid), threads(pid)
    time.sleep(secs)
    c1, t1 = cpu(pid), threads(pid)
    mem = memory(pid)
    print(f'idle {secs:.0f} s: {c1 - c0} CPU ticks (10 ms each); '
          f'VmRSS {mem["VmRSS"] / 1024:.1f} MiB, VmHWM {mem["VmHWM"] / 1024:.1f} MiB')
    main_tid = str(pid)
    for tid, (name, vol, inv) in sorted(t1.items(), key=lambda kv: int(kv[0])):
        n0 = t0.get(tid, (name, 0, 0))
        dv, di = vol - n0[1], inv - n0[2]
        tag = ' (main)' if tid == main_tid else ''
        print(f'  thread {tid}{tag} {name}: {dv} voluntary, {di} involuntary switches'
              f' ({(dv + di) / secs:.1f}/s)')


if __name__ == '__main__':
    main()
