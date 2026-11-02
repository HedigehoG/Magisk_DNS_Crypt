# Magisk DNS Crypt 🛡️

[🇷🇺 Читать на русском](README_RU.md)

Magisk / KernelSU / APatch module for encrypted DNS traffic powered by **dnsproxy** (DoH). 
Transparently redirects all device DNS traffic via `iptables` to a secure local resolver (`127.0.0.1:5353`).

---

### ✨ Features
* **Anti-Spoofing & Leak Protection:** All port 53 (UDP/TCP) traffic is routed through encrypted DoH.
* **Fail-Safe Startup:** `iptables` rules are only applied if the local resolver responds successfully (prevents internet loss on startup errors).
* **Flexible Configuration:** Supports Cloudflare, Google, Comss, or any custom DoH upstream.
* **Censorship / Middlebox Bypass:** Option to disable HTTP/3 (QUIC) to prevent UDP 443 handshake drops on restricted networks.

---

### 📦 Installation
1. Download the latest ZIP from **[Releases](../../releases)**.
2. Flash via **Magisk**, **KernelSU**, or **APatch**.
3. Reboot device.

---

### ⚙️ Configuration

Config file location:
`/sdcard/Download/MyDoH_Config.txt`

Options available:
* Upstream DNS provider selection (Cloudflare / Google / Comss / Custom URL).
* `USE_HTTP3=0` — Disable HTTP/3 (Recommended if UDP 443 is blocked/throttled).
* `USE_HTTP3=1` — Enable HTTP/3 (QUIC).

> **Note:** After editing the config, restart the module using the **Action** button in your root manager or reboot the device.

---

### 🔍 Verification
Check your DNS encryption status at:
* [1.1.1.1/help](https://1.1.1.1/help) (Check `Using DNS over HTTPS (DoH)`)
* [browserleaks.com/dns](https://browserleaks.com/dns)
