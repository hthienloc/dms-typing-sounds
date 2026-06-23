#!/usr/bin/env python3
import os
import sys
import json
import argparse
import subprocess

def main():
    parser = argparse.ArgumentParser(description="Slice Mechvibes sound pack into individual key audio files.")
    parser.add_argument("--pack-dir", required=True, help="Absolute path to the sound pack directory")
    parser.add_argument("--cache-dir", required=True, help="Absolute path to the cache output directory")
    args = parser.parse_args()

    pack_dir = os.path.abspath(args.pack_dir)
    cache_dir = os.path.abspath(args.cache_dir)
    config_path = os.path.join(pack_dir, "config.json")

    if not os.path.exists(config_path):
        print(f"Error: config.json not found in {pack_dir}", file=sys.stderr)
        sys.exit(1)

    try:
        with open(config_path, "r", encoding="utf-8") as f:
            config = json.load(f)
    except Exception as e:
        print(f"Error parsing config.json: {e}", file=sys.stderr)
        sys.exit(1)

    os.makedirs(cache_dir, exist_ok=True)

    key_define_type = config.get("key_define_type", "single")
    defines = config.get("defines", {})

    if not defines:
        print("Error: No 'defines' found in config.json", file=sys.stderr)
        sys.exit(1)

    if key_define_type == "single":
        sound_file_name = config.get("sound")
        if not sound_file_name:
            print("Error: 'sound' key missing for single define type", file=sys.stderr)
            sys.exit(1)

        sound_path = os.path.join(pack_dir, sound_file_name)
        if not os.path.exists(sound_path):
            print(f"Error: Sound file {sound_path} not found", file=sys.stderr)
            sys.exit(1)

        # Build single ffmpeg command to slice all outputs
        # To avoid argument length limits, we slice in one invocation
        cmd = ["ffmpeg", "-y", "-i", sound_path]
        for keycode, define in defines.items():
            if not define or len(define) < 2:
                continue
            offset_ms, duration_ms = define[0], define[1]
            out_file = os.path.join(cache_dir, f"{keycode}.wav")
            
            cmd.extend([
                "-ss", f"{offset_ms / 1000.0}",
                "-t", f"{duration_ms / 1000.0}",
                "-ar", "44100", "-ac", "1", "-sample_fmt", "s16",
                out_file
            ])

        print(f"Slicing {sound_path} to {cache_dir}...")
        res = subprocess.run(cmd, stdout=subprocess.DEVNULL, stderr=subprocess.PIPE)
        if res.returncode != 0:
            print(f"FFmpeg error: {res.stderr.decode('utf-8', errors='ignore')}", file=sys.stderr)
            sys.exit(res.returncode)

    elif key_define_type == "multi":
        print(f"Copying/converting multi-file sound pack from {pack_dir}...")
        for keycode, file_name in defines.items():
            if not file_name:
                continue
            src_path = os.path.join(pack_dir, file_name)
            if not os.path.exists(src_path):
                continue
            
            dest_path = os.path.join(cache_dir, f"{keycode}.wav")
            if os.path.exists(dest_path):
                os.remove(dest_path)
            
            _, ext = os.path.splitext(file_name)
            if ext.lower() == ".wav":
                try:
                    os.symlink(src_path, dest_path)
                except Exception:
                    import shutil
                    shutil.copy2(src_path, dest_path)
            else:
                # Transcode to wav using ffmpeg
                cmd = ["ffmpeg", "-y", "-i", src_path, dest_path]
                subprocess.run(cmd, stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL)

    # Create marker file
    try:
        with open(os.path.join(cache_dir, ".complete"), "w", encoding="utf-8") as f:
            f.write("1")
    except Exception as e:
        print(f"Warning: Could not write marker file: {e}", file=sys.stderr)

    print("Success: Sound pack prepared successfully.")

if __name__ == "__main__":
    main()
