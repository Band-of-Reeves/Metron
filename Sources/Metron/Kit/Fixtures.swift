import Foundation

/// Canned readings for glances whose real source cannot be reached from a
/// headless run.
///
/// This exists for `--measure`, which checks that a popover ends up as tall as
/// the panel inside it. That check is only worth anything against a *loaded*
/// panel: an empty one is short, matches trivially, and reports success. The
/// KatechonOS glance reads a NAS over ssh, so on any machine that cannot reach
/// it the panel stayed empty and the check passed without measuring anything —
/// which is the exact failure mode the rest of `verify.sh` was built to catch.
///
/// These are embedded as source rather than bundled as resources so that
/// `--measure` needs nothing beside the binary, on a CI runner included.
enum Fixtures {

    /// A plausible KatechonOS reading: a healthy pool, cells at a range of
    /// fullness, one socket-activated unit, and a bootc pair. Deliberately
    /// exercises the branches the panel draws differently — an unbounded cell
    /// with no quota, a stopped cell, and a service that is `listening` rather
    /// than `active`.
    static let katechon = """
    {
      "katechon_version": "0.9.4",
      "hostname": "katechon",
      "kernel": "6.11.4-200.fc41.x86_64",
      "generated_at": "2026-08-31T12:00:00Z",
      "bootc": {
        "readable": true,
        "booted": "ghcr.io/katechon/os:0.9.4",
        "rollback": "ghcr.io/katechon/os:0.9.3"
      },
      "storage": {
        "pool_name": "tank",
        "pool": {
          "name": "tank",
          "health": "ONLINE",
          "size": "29.1T",
          "allocated": "11.4T",
          "free": "17.7T"
        }
      },
      "cells": [
        { "name": "media",    "used": "6.71T", "quota": "12T",  "available": "5.29T", "state": "running", "grants": 3 },
        { "name": "backups",  "used": "2.902T","quota": "4T",   "available": "1.098T","state": "running", "grants": 1 },
        { "name": "archive",  "used": "1.42T", "quota": "none", "available": "-",     "state": "running", "grants": 0 },
        { "name": "scratch",  "used": "312G",  "quota": "500G", "available": "188G",  "state": "stopped", "grants": 0 }
      ],
      "services": [
        { "unit": "katechon-ui-serve.service", "state": "active" },
        { "unit": "katechon-api.socket",       "state": "listening" },
        { "unit": "zfs-scrub.service",         "state": "active" },
        { "unit": "smbd.service",              "state": "active" }
      ]
    }
    """

    /// The fixture for a glance id, if one exists.
    static func json(for id: String) -> Data? {
        switch id {
        case "katechon": return Data(katechon.utf8)
        default:         return nil
        }
    }
}
