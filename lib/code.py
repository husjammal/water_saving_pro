import time
import board
import digitalio
import analogio
import adafruit_sdcard
import storage
import adafruit_ble
from adafruit_ble.advertising.standard import ProvideServicesAdvertisement
from adafruit_ble.services.nordic import UARTService
import busio
import os
import supervisor
import rtc
import adafruit_apds9960.apds9960
import gc

# Disable auto-reload to prevent interruptions
supervisor.runtime.autoreload = False

# Initialize RTC
try:
    rtc_instance = rtc.RTC()
    # Set default time to 2023-01-01 00:00:00
    rtc_instance.datetime = time.struct_time((2023, 1, 1, 0, 0, 0, 0, -1, -1))
    print("RTC initialized")
except Exception as e:
    print("RTC initialization failed:", str(e))
    rtc_instance = None

# Initialize SPI for microSD card
try:
    spi = busio.SPI(board.SCK, MOSI=board.MOSI, MISO=board.MISO)
    cs = digitalio.DigitalInOut(board.D5)
    card_detect = digitalio.DigitalInOut(board.D9)
    card_detect.direction = digitalio.Direction.INPUT
    sd_mounted = False
except Exception as e:
    print("SPI initialization failed:", str(e))
    spi = None
    cs = None
    card_detect = None
    sd_mounted = False

try:
    if spi is not None:
        sdcard = adafruit_sdcard.SDCard(spi, cs)
        vfs = storage.VfsFat(sdcard)
        storage.mount(vfs, "/sd")
        sd_mounted = True
        print("SD card mounted")
    else:
        print("Warning: SD card operations unavailable due to SPI failure")
except Exception as e:
    print("SD card mount failed:", str(e))
    sd_mounted = False

# Initialize battery voltage monitoring
try:
    analog_in = analogio.AnalogIn(board.VOLTAGE_MONITOR)
    print("Battery voltage monitoring initialized")
except Exception as e:
    print("Battery voltage monitoring initialization failed:", str(e))
    analog_in = None

# Initialize APDS9960 proximity sensor
try:
    i2c = busio.I2C(board.SCL, board.SDA)
    sensor = adafruit_apds9960.apds9960.APDS9960(i2c)
    sensor.enable_proximity = True
    print(f"APDS9960 initialized: proximity_enabled={sensor.enable_proximity}, gain={sensor.proximity_gain}")
except Exception as e:
    print("APDS9960 initialization failed:", str(e))
    sensor = None

# BLE setup
try:
    ble = adafruit_ble.BLERadio()
    ble.name = "Adafruit-Feather"
    print("BLE radio initialized, name:", ble.name)
    uart = UARTService()
    advertisement = ProvideServicesAdvertisement(uart)
    advertisement.connectable = True
    print("UART service created")
except Exception as e:
    print("BLE initialization failed:", str(e))
    ble = None

# CSV file setup
csv_file = "/sd/data.csv"
time_offset = 0
tap_on_duration = 0
is_tap_on = False
was_tap_on = False
proximity_threshold = 1
BATCH_SIZE = 100
live_data_enabled = False
was_connected = False  # Track previous connection state

# Add a global flag for file transfer cancellation
cancel_file_transfer = False

# Initialize CSV file with headers if it doesn't exist
if sd_mounted:
    try:
        if "data.csv" not in os.listdir("/sd"):
            with open(csv_file, "w") as f:
                f.write("timestamp,water_flow_rate,battery_voltage,tap_on_duration\n")
            print("Initialized data.csv with headers")
    except Exception as e:
        print("Failed to initialize data.csv:", str(e))

# Function to get SD card and file status
def get_sd_status():
    try:
        sd_present = sd_mounted and card_detect.value  # Check if SD card is physically inserted
        file_exists = False
        file_size = 0
        last_modified = 0
        if sd_present:
            file_exists = "data.csv" in os.listdir("/sd")
            if file_exists:
                file_stat = os.stat(csv_file)
                file_size = file_stat[6]  # Size in bytes
                last_modified = file_stat[8]  # Last modified timestamp (mtime)
        return f"{1 if sd_present else 0},{1 if file_exists else 0},{file_size},{last_modified}"
    except Exception as e:
        print("Error in get_sd_status:", str(e))
        return "0,0,0,0"  # Return zeros on error

# Function to get current timestamp
def get_current_time():
    if rtc_instance is None:
        print("RTC not initialized, returning 0")
        return 0
    try:
        return int(time.time())
    except Exception as e:
        print("Error in get_current_time:", str(e))
        return 0

# Function to set RTC from sync timestamp
def set_rtc_time(sync_timestamp):
    global time_offset
    if rtc_instance is None:
        print("RTC not available, cannot set time")
        return False
    try:
        old_time = time.mktime(rtc_instance.datetime)
        new_time = time.localtime(sync_timestamp)
        rtc_instance.datetime = new_time
        time_offset = sync_timestamp - old_time
        print(f"UTC set time: {new_time.tm_year}-{new_time.tm_mon:02d}-{new_time.tm_mday:02d} {new_time.tm_hour:02d}:{new_time.tm_min:02d}:{new_time.tm_sec:02d}")
        return True
    except ValueError as e:
        print("Error setting UTC time:", str(e))
        return False

# Function to read battery voltage
def read_battery_voltage():
    if analog_in is None:
        return 0.0
    try:
        return (analog_in.value / 65535) * 3.3 * 2
    except Exception as e:
        print("Battery voltage read failed:", str(e))
        return 0.0

# Function to save to CSV
def save_to_csv(timestamp, flow_rate, battery_voltage, tap_duration):
    if sd_mounted:
        try:
            time.sleep(0.01)
            with open(csv_file, mode="a") as f:
                f.write(f"{timestamp},{flow_rate},{battery_voltage},{tap_duration}\n")
        except Exception as e:
            print("Failed to write CSV:", str(e))
    else:
        print("Cannot save to CSV: SD card not mounted")

# Function to send data over UART
def send_data_over_uart(timestamp, flow_rate, battery_voltage, tap_duration):
    if ble and ble.connected and live_data_enabled:
        try:
            data_line = f"{timestamp},{flow_rate},{battery_voltage},{tap_duration}"
            uart.write("SEND_START\n".encode())
            uart.write((data_line + "\n").encode())
            uart.write("SEND_END\n".encode())
            print(f"Sent via UART: {data_line}")
            time.sleep(0.01)
        except Exception as e:
            print("Failed to send UART data:", str(e))

# Function to collect and save data
def collect_and_save_data():
    global is_tap_on, was_tap_on, tap_on_duration
    try:
        current_time = get_current_time()
        battery_voltage = read_battery_voltage()
        flow_rate = 0.0
        if sensor:
            try:
                proximity = sensor.proximity
                if proximity > proximity_threshold and proximity <= 255:
                    flow_rate = (proximity / 255) * 2
                    is_tap_on = True
                else:
                    is_tap_on = False
            except Exception as e:
                print("Proximity sensor error:", str(e))
                is_tap_on = False

        if is_tap_on:
            tap_on_duration = 1
        elif was_tap_on and not is_tap_on:
            tap_on_duration = 0
        was_tap_on = is_tap_on

        save_to_csv(current_time, flow_rate, battery_voltage, tap_on_duration)
        send_data_over_uart(current_time, flow_rate, battery_voltage, tap_on_duration)
    except Exception as e:
        print("Error in collect_and_save_data:", str(e))

# Function to read CSV data with safe binary search
def read_csv_data(since_timestamp=None):
    if not sd_mounted:
        print("Cannot read CSV: SD card not mounted")
        yield []
        return

    try:
        file_size = os.stat(csv_file)[6]
        print(f"Reading CSV: {file_size:,} bytes")
        if file_size > 1024 * 1024:
            print("Warning: CSV file size exceeds 1 MB, consider truncating")

        BUFFER_SIZE = 2048
        BATCH_SIZE = 20
        row_count = 0
        valid_rows = 0
        debug_rows = 5
        chunk_times = []
        send_times = []
        search_limit = 20

        start_time = time.monotonic()

        with open(csv_file, "r") as f:
            header = f.readline().strip()
            print(f"Reading CSV, skipped header: {header}")
            start_offset = len(header)

            if since_timestamp is not None:
                low = start_offset
                high = file_size
                seen_offsets = set()
                iterations = 0
                while low < high and iterations < search_limit:
                    mid = (low + high) // 2
                    if mid in seen_offsets:
                        print(f"Binary search stuck at offset {mid:,}, falling back to linear scan")
                        break
                    seen_offsets.add(mid)
                    iterations += 1
                    try:
                        f.seek(mid)
                        f.readline()
                        mid = f.tell()
                        if mid >= file_size:
                            high = mid
                            continue
                        line = f.readline().strip()
                        if not line:
                            low = mid + 1
                            continue
                        if "," in line:
                            try:
                                timestamp = int(line.split(",")[0])
                                if iterations <= 3:
                                    print(f"Binary search at offset {mid:,}: timestamp={timestamp}, row={line}")
                                if timestamp < since_timestamp:
                                    low = mid + 1
                                else:
                                    high = mid
                            except (ValueError, IndexError):
                                low = mid + 1
                                continue
                        else:
                            low = mid + 1
                    except Exception as e:
                        print(f"Binary search error at offset {mid:,}: {str(e)}")
                        low = mid + 1
                        continue
                start_offset = low

            f.seek(start_offset)
            batch = []
            while True:
                try:
                    chunk_start = time.monotonic()
                    chunk = f.read(BUFFER_SIZE)
                    chunk_times.append(time.monotonic() - chunk_start)
                    if not chunk:
                        break
                    lines = chunk.split("\n")
                    for line in lines:
                        line = line.strip()
                        if not line:
                            continue
                        row_count += 1
                        if row_count <= debug_rows:
                            print(f"Row {row_count}: {line}")
                        if line.count(",") != 3:
                            print(f"Row {row_count} invalid: {line.count(',')} commas, row={line}")
                            continue
                        if since_timestamp is None:
                            batch.append(line)
                            valid_rows += 1
                        else:
                            try:
                                timestamp = int(line.split(",")[0])
                                if timestamp >= since_timestamp:
                                    batch.append(line)
                                    valid_rows += 1
                                else:
                                    print(f"Row {row_count} skipped: timestamp {timestamp} < {since_timestamp}")
                            except (ValueError, IndexError):
                                print(f"Row {row_count} invalid: unable to parse timestamp, row={line}")
                                continue
                        if len(batch) >= BATCH_SIZE:
                            send_start = time.monotonic()
                            yield batch
                            send_times.append(time.monotonic() - send_start)
                            batch = []
                            gc.collect()
                except Exception as e:
                    print(f"Error reading chunk at row ~{row_count:,}: {str(e)}")
                    continue
            if batch:
                send_start = time.monotonic()
                yield batch
                send_times.append(time.monotonic() - send_start)
                valid_rows += len(batch)

        elapsed = time.monotonic() - start_time
        avg_chunk_time = sum(chunk_times) / len(chunk_times) if chunk_times else 0
        avg_send_time = sum(send_times) / len(send_times) if send_times else 0
        gc.collect()
        print(f"Read completed: {row_count:,} rows processed, {valid_rows:,} valid, {elapsed:.2f}s")
        print(f"Avg chunk read time: {avg_chunk_time:.3f}s, chunks: {len(chunk_times)}")
        print(f"Avg send time: {avg_send_time:.5f}s")
        print(f"Free memory: {gc.mem_free():,} bytes")
    except Exception as e:
        print(f"Unexpected error reading CSV: {str(e)}")
        yield []

# Start advertising
if ble:
    try:
        print("Starting BLE advertising...")
        ble.start_advertising(advertisement, interval=0.1)
        print("Advertising started")
        print("Awaiting connection...")
    except Exception as e:
        print("BLE advertising error:", str(e))

# Main loop
last_collect_time = time.monotonic()
last_sync_timestamp = None
loop_count = 0
while True:
    try:
        loop_count += 1
        current_time = time.monotonic()

        # Collect and save data every second
        if current_time - last_collect_time >= 1.0:
            collect_and_save_data()
            last_collect_time = current_time

        # Handle BLE operations
        if ble:
            is_connected = ble.connected
            if is_connected:
                if not was_connected:
                    print("BLE connected!")
                    was_connected = True
                try:
                    if uart.in_waiting:
                        data = uart.read(uart.in_waiting).decode().strip()
                        print('Received raw data:', data)
                        print("Received:", data)

                        if data.startswith("SYNC:"):
                            try:
                                sync_timestamp = int(data.split(":")[1].strip())
                                if sync_timestamp == last_sync_timestamp:
                                    print("Duplicate SYNC timestamp, ignored")
                                    uart.write("OK\n".encode())
                                    continue
                                if set_rtc_time(sync_timestamp):
                                    last_sync_timestamp = sync_timestamp
                                    print(f"Time synced to: {sync_timestamp}")
                                    uart.write("OK\n".encode())
                                else:
                                    uart.write("ERROR: RTC set failed\n".encode())
                            except (ValueError, IndexError) as e:
                                print("Invalid SYNC data:", data, "Error:", str(e))
                                uart.write("ERROR: Invalid SYNC format\n".encode())

                        elif data == "PING":
                            print("Received PING")
                            uart.write("PONG\n".encode())

                        elif data == "GET_TIME":
                            print("Received GET_TIME")
                            current_time = get_current_time()
                            if current_time == 0:
                                uart.write("ERROR: RTC unavailable\n".encode())
                                print("RTC unavailable")
                            else:
                                uart.write(f"TIME:{current_time}\n".encode())
                                print(f"Sent TIME:{current_time}")

                        elif data.startswith("GET_DATA"):
                            print("Data request:", data)
                            since_timestamp = None
                            is_file_transfer = False
                            
                            # Parse the command properly
                            parts = data.split()
                            print(f"Parsed parts: {parts}")
                            
                            if len(parts) >= 3 and parts[1] == "since":
                                try:
                                    since_timestamp = int(parts[2])
                                    print(f"Filtering since: {since_timestamp}")
                                except (ValueError, IndexError) as e:
                                    print("Invalid GET_DATA format:", data, "Error:", str(e))
                                    uart.write("ERROR: Invalid GET_DATA format\n".encode())
                                    continue
                            
                            # Check if this is a file transfer request
                            if len(parts) >= 4 and parts[3] == "file":
                                is_file_transfer = True
                                print(f"File transfer mode detected: {is_file_transfer}")
                            
                            print(f"File transfer mode: {is_file_transfer}")
                            if is_file_transfer:
                                # File transfer mode - send entire CSV file
                                print("Starting file transfer mode")
                                if not sd_mounted:
                                    uart.write("ERROR: SD card not mounted\n".encode())
                                    continue
                                
                                try:
                                    file_size = os.stat(csv_file)[6]
                                    uart.write(f"FILE_SIZE:{file_size}\n".encode())
                                    print(f"Sent FILE_SIZE:{file_size}")
                                    
                                    uart.write("FILE_START\n".encode())
                                    with open(csv_file, "r") as f:
                                        chunk_size = 256  # Smaller chunks for text
                                        bytes_sent = 0
                                        cancel_file_transfer = False  # Reset before transfer
                                        while True:
                                            if cancel_file_transfer:
                                                print("File transfer cancelled by host")
                                                break
                                            chunk = f.read(chunk_size)
                                            if not chunk:
                                                break
                                            uart.write(chunk.encode())
                                            bytes_sent += len(chunk)
                                            print(f"Sent chunk: {len(chunk)} chars, total: {bytes_sent}/{file_size}")
                                            time.sleep(0.002)  # Small delay to prevent buffer overflow
                                    
                                    uart.write("FILE_END\n".encode())
                                    print(f"File transfer complete: {bytes_sent} bytes sent")
                                    cancel_file_transfer = False  # Reset after transfer
                                    
                                except Exception as e:
                                    print(f"File transfer error: {str(e)}")
                                    uart.write("ERROR: File transfer failed\n".encode())
                                    
                            else:
                                # Original line-by-line mode
                                # --- NEW: Count total rows to be sent ---
                                total_rows = 0
                                for batch in read_csv_data(since_timestamp):
                                    total_rows += len(batch)
                                uart.write(f"TOTAL_ROWS:{total_rows}\n".encode())
                                print(f"Sent TOTAL_ROWS:{total_rows}")
                                # Now send the data as before
                                sent_data = False
                                for batch in read_csv_data(since_timestamp):
                                    if not batch:
                                        continue
                                    uart.write("SEND_START\n".encode())
                                    for line in batch:
                                        try:
                                            uart.write((line + "\n").encode())
                                            print("Sending:", line)
                                            sent_data = True
                                            time.sleep(0.0001)
                                        except Exception as e:
                                            print("Failed to send line:", line, "Error:", str(e))
                                    uart.write("SEND_END\n".encode())
                                    time.sleep(0.005)
                                uart.write("END_OF_DATA\n".encode())
                                print("Sent END_OF_DATA, data sent:", sent_data)

                        elif data == "START_LIVE_DATA":
                            live_data_enabled = True
                            print("Live data enabled")
                            uart.write("OK\n".encode())

                        elif data == "STOP_LIVE_DATA":
                            live_data_enabled = False
                            print("Live data disabled")
                            uart.write("OK\n".encode())

                        elif data == "GET_SD_STATUS":
                            print("Received GET_SD_STATUS")
                            sd_status = get_sd_status()
                            uart.write("SEND_START\n".encode())
                            uart.write((sd_status + "\n").encode())
                            uart.write("SEND_END\n".encode())
                            print(f"Sent SD status: {sd_status}")

                        elif data == "CANCEL_TRANSFER":
                            print("Received CANCEL_TRANSFER command")
                            cancel_file_transfer = True
                            uart.write("OK\n".encode())

                        else:
                            print("Unknown command:", data)
                            uart.write("ERROR: Unknown command\n".encode())
                except Exception as e:
                    print("UART read error:", str(e))
            else:
                if was_connected:
                    print("BLE disconnected, restarting advertising...")
                    was_connected = False
                    try:
                        ble.stop_advertising()  # Ensure advertising is stopped
                        ble.start_advertising(advertisement, interval=0.1)
                        print("Advertising restarted")
                    except Exception as e:
                        print("BLE advertising restart failed:", str(e))
        else:
            print("BLE not initialized")
    except Exception as e:
        print("Main loop error:", str(e))
    time.sleep(0.01)
