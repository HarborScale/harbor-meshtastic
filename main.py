import sys
import time
import json
import logging
import argparse
from datetime import datetime
import meshtastic.serial_interface
from meshtastic import portnums_pb2

# --- CONFIGURATION ---
# Silence the noisy Meshtastic library (it loves to print to stdout)
logging.basicConfig(level=logging.CRITICAL)

def log_err(msg):
    """Print to STDERR so Lighthouse logs capture it, but it doesn't break JSON parsing."""
    sys.stderr.write(f"[MeshEngine] {msg}\n")
    sys.stderr.flush()

def get_node_id(node):
    """Safely extract a human-readable name or ID."""
    user = node.get('user', {})
    return user.get('longName') or user.get('id') or "Unknown"

def is_stale(node, ttl_seconds):
    """
    Determines if a node is a 'Zombie' (dead battery/out of range).
    Checks 'lastHeard' against current time.
    """
    # Local node is never stale
    if node.get('isLocal'):
        return False

    last_heard = node.get('lastHeard')
    if not last_heard:
        return True # If we've never heard from it, ignore it

    # lastHeard is usually a unix timestamp
    now = time.time()
    age = now - last_heard

    if age > ttl_seconds:
        # log_err(f"Node {get_node_id(node)} is stale (Last heard {int(age)}s ago)")
        return True
    return False

def normalize_metrics(node_id, node):
    """
    Flattens the nested Meshtastic dictionary into a simple key-value map
    compatible with Lighthouse.
    """
    # 1. Base Identity
    data = {
        "ship_id": node_id,
        "is_local": 1 if node.get('isLocal') else 0,
        "snr": node.get('snr', 0)
    }

    # 2. Battery & Voltage (Device Metrics (Battery & System)
    if 'deviceMetrics' in node:
        dm = node['deviceMetrics']
        if 'batteryLevel' in dm: data['battery_level'] = dm['batteryLevel']
        if 'voltage' in dm: data['voltage'] = dm['voltage']
        if 'channelUtilization' in dm: data['channel_util'] = dm['channelUtilization']
        if 'airUtilTx' in dm: data['air_util_tx'] = dm['airUtilTx']
        if 'uptimeSeconds' in dm: data['uptime'] = dm['uptimeSeconds']

    # 2. Environment (Temp, Hum, Press, Light, Wind, Rain, Distance)
    if 'environmentMetrics' in node:
        em = node['environmentMetrics']
        # Standard
        if 'temperature' in em: data['temperature'] = em['temperature']
        if 'relativeHumidity' in em: data['humidity'] = em['relativeHumidity']
        if 'barometricPressure' in em: data['pressure'] = em['barometricPressure']

        # Gas / Air Quality (BME680)
        if 'gasResistance' in em: data['gas_resistance'] = em['gasResistance']
        if 'iaq' in em: data['iaq'] = em['iaq']

        # Light (OPT3001, VEML7700, LTR390)
        if 'lux' in em: data['lux'] = em['lux']
        if 'whiteLux' in em: data['white_lux'] = em['whiteLux']
        if 'irLux' in em: data['ir_lux'] = em['irLux']
        if 'uvLux' in em: data['uv_lux'] = em['uvLux']

        # Distance (RCWL9620, Ultrasonic)
        if 'distance' in em: data['distance_mm'] = em['distance']

        # Weather / Wind (DFROBOT_LARK, RAIN)
        # Note: These keys rely on recent protobuf definitions.
        if 'windSpeed' in em: data['wind_speed'] = em['windSpeed']
        if 'windDirection' in em: data['wind_direction'] = em['windDirection']
        # 'rainfall' is sometimes exposed differently, but 'rainfall' is the standard proto name
        if 'rainfall' in em: data['rainfall'] = em['rainfall']

    # 3. Power Metrics (INA219, INA260, INA3221 - Multi-channel)
    if 'powerMetrics' in node:
        pm = node['powerMetrics']
        # Channel 1
        if 'ch1Voltage' in pm: data['power_ch1_volts'] = pm['ch1Voltage']
        if 'ch1Current' in pm: data['power_ch1_amps'] = pm['ch1Current']
        # Channel 2
        if 'ch2Voltage' in pm: data['power_ch2_volts'] = pm['ch2Voltage']
        if 'ch2Current' in pm: data['power_ch2_amps'] = pm['ch2Current']
        # Channel 3
        if 'ch3Voltage' in pm: data['power_ch3_volts'] = pm['ch3Voltage']
        if 'ch3Current' in pm: data['power_ch3_amps'] = pm['ch3Current']

    # 4. Air Quality (Particulates - PMSA003I)
    if 'airQualityMetrics' in node:
        aq = node['airQualityMetrics']
        # Meshtastic uses standard keys for these in the proto
        if 'pm10Standard' in aq: data['aq_pm10'] = aq['pm10Standard'] # PM 1.0
        if 'pm25Standard' in aq: data['aq_pm25'] = aq['pm25Standard'] # PM 2.5
        if 'pm100Standard' in aq: data['aq_pm100'] = aq['pm100Standard'] # PM 10.0
        # Fallback for older keys if they exist
        if 'pm25' in aq and 'aq_pm25' not in data: data['aq_pm25'] = aq['pm25']
        if 'co2' in aq: data['aq_co2'] = aq['co2']

    # 5. Health Metrics (Heart Rate, SpO2 - MAX30102)
    if 'healthMetrics' in node:
        hm = node['healthMetrics']
        if 'heartRate' in hm: data['heart_rate'] = hm['heartRate']
        if 'spo2' in hm: data['spo2'] = hm['spo2']
        if 'temperature' in hm: data['body_temp'] = hm['temperature']

    # 6. Position (Lat/Lon/Alt)
    if 'position' in node:
        pos = node['position']
        if 'latitude' in pos and 'longitude' in pos:
            data['latitude'] = pos['latitude']
            data['longitude'] = pos['longitude']
        if 'altitude' in pos:
            data['altitude'] = pos['altitude']
        if 'satsInView' in pos:
            data['sats_in_view'] = pos['satsInView']

    return data

def main():
    parser = argparse.ArgumentParser()
    parser.add_argument("--ttl", type=int, default=3600, help="Ignore nodes not heard in X seconds (Default: 1 hour)")
    parser.add_argument("--port", type=str, default=None, help="Force specific COM port")
    args = parser.parse_args()

    interface = None
    try:
        # Auto-discovery logic handled by the library if port is None
        # We suppress stdout because the library prints "Connected to..."
        if args.port:
            log_err(f"Connecting to {args.port}...")
            interface = meshtastic.serial_interface.SerialInterface(args.port)
        else:
            log_err("Auto-detecting Meshtastic radio...")
            interface = meshtastic.serial_interface.SerialInterface()

        # Gather nodes
        nodes = interface.nodes
        if not nodes:
            log_err("No nodes found in DB.")
            print("[]") # Return empty JSON array
            return

        export_list = []

        for node_id, node_info in nodes.items():
            # 1. Check for zombie nodes
            if is_stale(node_info, args.ttl):
                continue

            # 2. Get readable name
            long_name = get_node_id(node_info)

            # 3. Flatten data
            flat_data = normalize_metrics(long_name, node_info)
            export_list.append(flat_data)

        # FINAL OUTPUT: Print strict JSON to stdout
        print(json.dumps(export_list))

    except PermissionError:
        log_err("Error: Permission denied. Is another app using the port?")
    except Exception as e:
        log_err(f"Critical Error: {e}")
        # We print empty JSON so Lighthouse doesn't crash, it just sees 0 ships
        print("[]")
    finally:
        if interface:
            interface.close()

if __name__ == "__main__":
    main()
