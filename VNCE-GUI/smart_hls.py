import os
import sys
import subprocess
from pathlib import Path

# ANSI Colors for consistent output
class Colors:
    HEADER = '\033[95m'
    BLUE = '\033[94m'
    GREEN = '\033[92m'
    WARNING = '\033[93m'
    FAIL = '\033[91m'
    ENDC = '\033[0m'

def run_script(script_name, args):
    """Runs a script using subprocess and streams output."""
    try:
        # Resolve script path
        base_dir = os.path.dirname(os.path.abspath(__file__))
        script_path = os.path.join(base_dir, script_name)
        
        if not os.path.exists(script_path):
             script_path = os.path.join(os.getcwd(), script_name)
        
        if not os.path.exists(script_path):
            print(f"{Colors.FAIL}Error: Script '{script_name}' not found.{Colors.ENDC}")
            return

        cmd = ["python", script_path] + args
        
        # We run properly, letting stdout flow to parent (which is vnce_gui usually)
        # Using subprocess.run will wait.
        subprocess.run(cmd, check=False) 
        
    except Exception as e:
        print(f"{Colors.FAIL}Error running {script_name}: {e}{Colors.ENDC}")

def process_batch():
    print(f"{Colors.HEADER}=== SMART HLS: BATCH MODE ==={Colors.ENDC}")
    
    # 1. MKV Conversion
    print(f"\n{Colors.BLUE}--- Checking for MKV files... ---{Colors.ENDC}")
    mkv_files = list(Path('.').glob('*.mkv'))
    if mkv_files:
        print(f"Found {len(mkv_files)} MKV files. Running MKV converter...")
        run_script("mkv_to_hls_converter.py", ["batch"])
    else:
        print("No MKV files found.")

    # 2. MP4 Conversion
    print(f"\n{Colors.BLUE}--- Checking for MP4 files... ---{Colors.ENDC}")
    mp4_files = list(Path('.').glob('*.mp4'))
    if mp4_files:
        print(f"Found {len(mp4_files)} MP4 files. Running MP4 converter...")
        run_script("mp4_to_hls_converter.py", ["batch"])
    else:
        print("No MP4 files found.")
        
    print(f"\n{Colors.GREEN}Batch processing complete.{Colors.ENDC}")

def process_single(filepath):
    print(f"{Colors.HEADER}=== SMART HLS: SINGLE FILE MODE ==={Colors.ENDC}")
    
    if not os.path.exists(filepath):
        print(f"{Colors.FAIL}File not found: {filepath}{Colors.ENDC}")
        return

    ext = os.path.splitext(filepath)[1].lower()
    
    if ext == ".mkv":
        print(f"{Colors.GREEN}Detected MKV. converting...{Colors.ENDC}")
        run_script("mkv_to_hls_converter.py", [filepath])
        
    elif ext == ".mp4":
        print(f"{Colors.GREEN}Detected MP4. converting...{Colors.ENDC}")
        run_script("mp4_to_hls_converter.py", [filepath])
        
    else:
        print(f"{Colors.WARNING}Unsupported extension: {ext}. Only .mkv and .mp4 are supported.{Colors.ENDC}")

def main():
    if len(sys.argv) > 1:
        arg = sys.argv[1]
        if arg.lower() == "batch":
            process_batch()
        else:
            process_single(arg)
    else:
        print("Usage: python smart_hls.py [batch|filename]")

if __name__ == "__main__":
    main()
