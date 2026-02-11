# Meshtastic Integration

This guide explains how to integrate your Meshtastic LoRa mesh network with Harbor Scale. By using the **Harbor Lighthouse** agent, you can turn a computer (Raspberry Pi, Laptop, or Server) connected to a Meshtastic device into a telemetry gateway.
![Image](https://i.imgur.com/DLqunXx.jpeg)
Unlike previous methods that required manual Python scripts, Lighthouse now handles this natively via the `mesh_engine` driver. It acts as a gateway, reporting battery levels, environmental metrics, and signal statistics for **every node** in your mesh, regardless of whether the gateway is connected via USB or Wi-Fi.

## Prerequisites

Before starting, ensure you have:

* A **Meshtastic device** (e.g., LoRa ESP32, T-Beam, Rak WisBlock) connected via USB to your host computer **OR** connected to your local network via Wi-Fi.
* **Harbor Lighthouse** installed on the host computer. (See [Installation Guide](https://docs.harborscale.com/docs/lighthouse)).
* A **Harbor Scale account** (Cloud) or a self-hosted instance.

## Architecture

The integration works by using the Lighthouse `exec` collector combined with a specialized binary called `mesh_engine`.

1. **The Mesh Engine** connects to your node via Serial (USB) or TCP (Wi-Fi).
2. It decodes packets from the mesh (JSON).
3. **Lighthouse** manages the engine, ensures it stays running, and securely ships the data to Harbor Scale.

---

## Setup Guide

### Step 1: Install the Mesh Engine

First, you need to download the driver that allows Lighthouse to communicate with LoRa hardware.

**🐧 Linux / 🍎 macOS / 🥧 Raspberry Pi**

```bash
curl -sL get.harborscale.com/meshtastic | sudo bash
```

**🪟 Windows (PowerShell)**

```powershell
iwr get.harborscale.com/meshtastic | iex
```

### Step 2: Add the Monitor

Use the `lighthouse` command to configure the gateway. This will register the agent to start the `mesh_engine` automatically.

**For Harbor Scale Cloud:**

```bash
lighthouse --add \
  --name "meshtastic-gateway" \
  --harbor-id "YOUR_HARBOR_ID" \
  --key "YOUR_API_KEY" \
  --source exec \
  --param command="mesh_engine --ttl 3600"

```

**For Self-Hosted / OSS:**

```bash
lighthouse --add \
  --name "meshtastic-gateway" \
  --endpoint "http://YOUR_IP:8000" \
  --key "YOUR_OSS_KEY" \
  --source exec \
  --param command="mesh_engine --ttl 3600"

```

> **Note:** The default command attempts to auto-detect a USB device. To specify a TCP address or a specific COM port, see **Configuration Options** below.

---

## Configuration Options

You can customize how the engine behaves by modifying the `--param command="..."` string when adding the monitor.

### 🔌 Option A: USB / Serial Connection (Default)

By default, the engine attempts to auto-detect the Meshtastic device. If you have multiple devices or auto-detection fails, force a specific port using `--port`.

* **Linux/Mac:** `mesh_engine --port /dev/ttyUSB0`
* **Windows:** `mesh_engine --port COM3`

**Example:**

```bash
--param command="mesh_engine --port /dev/ttyUSB0 --ttl 3600"
```

### 📡 Option B: Wi-Fi / TCP Connection (New)

If your Meshtastic node is connected to Wi-Fi, you can pull telemetry over the network without a USB cable. Use the `--host` flag to specify the IP address or hostname.

* **Format:** `mesh_engine --host <IP_ADDRESS>`

**Example:**

```bash
--param command="mesh_engine --host 192.168.1.50 --ttl 3600"
```

> **Note:** The `--host` flag takes precedence over `--port`. If both are provided, the engine will attempt a TCP connection.

### Adjusting Node TTL

The `--ttl` (Time To Live) flag determines how long a node remains "active" in the report if no new packets are received. The default is `3600` seconds (1 hour).

* To report nodes only if heard within the last 10 minutes: `--ttl 600`

---

## Troubleshooting

### Common Issues

* **Permission Denied (Linux USB):**
Ensure the user running Lighthouse has permission to access serial ports. You may need to add the user to the `dialout` group:
```bash
sudo usermod -a -G dialout $USER
```


*Restart the computer after running this command.*
* **Device Not Found (USB):**
1. Check your USB cable (ensure it is a data cable, not just power).
2. Verify the device shows up in `/dev/` (Linux/Mac) or Device Manager (Windows).
3. Try explicitly setting the `--port` flag.


* **Connection Failed (TCP/Wi-Fi):**
1. Ensure the computer running Lighthouse is on the same network as the Meshtastic device.
2. Verify you can `ping` the device IP from the host computer.
3. Ensure the Meshtastic device has Wi-Fi enabled and is successfully connected to the access point.


* **No Data in Dashboard:**
Run the logs command to see what the engine is doing:
```bash
lighthouse --logs "meshtastic-gateway"
```


You should see JSON output representing the nodes in your mesh.
