
# Meshtastic Integration

This guide explains how to integrate your Meshtastic LoRa mesh network with Harbor Scale. By using the **Harbor Lighthouse** agent, you can turn a computer (Raspberry Pi, Laptop, or Server) connected to a Meshtastic device into a telemetry gateway.


![Image](https://i.imgur.com/DLqunXx.jpeg)



Unlike previous methods that required manual Python scripts, Lighthouse now handles this natively via the `mesh_engine` driver. It acts as a gateway, reporting battery levels, environmental metrics, and signal statistics for **every node** in your mesh, not just the connected device.

## Prerequisites

Before starting, ensure you have:

-   A **Meshtastic device** (e.g., LoRa ESP32, T-Beam, Rak WisBlock) connected via USB to your host computer.
-   **Harbor Lighthouse** installed on the host computer. (See [Installation Guide]([/docs/lighthouse/](https://docs.harborscale.com/docs/lighthouse))).
-   A **Harbor Scale account** (Cloud) or a self-hosted instance.

## Architecture

The integration works by using the Lighthouse `exec` collector combined with a specialized binary called `mesh_engine`.

1.  **The Mesh Engine** talks to your USB device over serial.
2.  It decodes packets from the mesh (JSON).
3.  **Lighthouse** manages the engine, ensures it stays running, and securely ships the data to Harbor Scale.

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

> **Note:** Replace `YOUR_HARBOR_ID`, `YOUR_API_KEY`, and `YOUR_OSS_KEY` with your actual credentials.

---

## Configuration Options

You can customize how the engine behaves by modifying the `--param command="..."` string.

### Setting a Specific Port

By default, the engine attempts to auto-detect the Meshtastic device. If you have multiple devices or auto-detection fails, force a specific port.

* **Linux/Mac:** `mesh_engine --port /dev/ttyUSB0`
* **Windows:** `mesh_engine --port COM3`

**Example Update:**

```bash
--param command="mesh_engine --port /dev/ttyUSB0 --ttl 3600"
```

### Adjusting Node TTL

The `--ttl` (Time To Live) flag determines how long a node remains "active" in the report if no new packets are received. The default is `3600` seconds (1 hour).

* To report nodes only if heard within the last 10 minutes: `--ttl 600`

---

## Troubleshooting

### Common Issues

* **Permission Denied (Linux):** Ensure the user running Lighthouse has permission to access serial ports. You may need to add the user to the `dialout` group:
```bash
sudo usermod -a -G dialout $USER
```


*Restart the computer after running this command.*
* **Device Not Found:**
1. Check your USB cable (ensure it is a data cable, not just power).
2. Verify the device shows up in `/dev/` (Linux/Mac) or Device Manager (Windows).
3. Try explicitly setting the `--port` flag as shown above.


* **No Data in Dashboard:**
Run the logs command to see what the engine is doing:
```bash
lighthouse --logs "meshtastic-gateway"
```

You should see JSON output representing the nodes in your mesh.

