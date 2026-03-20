import os
import re
import sys
import subprocess

def clean_movie_format(filename):
    """
    Cleans filename to 'Title (Year).ext' format.
    Returns (new_filename, title, year) or (None, None, None) if no match.
    """
    # Pattern: Title matches until Year.
    try:
        base_name, ext = filename.rsplit('.', 1)
    except ValueError:
        return None, None, None
    
    # Regex to find Year matches like .2024. or (2024) or space 2024 space/end
    # flexible for: T.i.t.l.e.2024.Tags... or Title (2024)
    # Group 1: Title (lazy)
    # Group 2: Separator
    # Group 3: Year
    match = re.search(r'^(.*?)([\.\(\s])(\d{4})([.\)\s]|$)', base_name)
    
    if match:
        title_raw = match.group(1)
        year = match.group(3)
        
        # Clean title: replace dots with spaces, remove potential trailing chars
        title_clean = title_raw.replace('.', ' ').strip()
        title_clean = title_clean.replace('_', ' ').strip()
        
        # Construct new name
        new_name = f"{title_clean} ({year}).{ext}"
        
        # Determine Title for metadata (Title only, no year usually? Or Title (Year)?)
        # User request: "ese mismo nombre debe ir dentro del metadato title" -> "El astronauta (2024)"
        metadata_title = f"{title_clean} ({year})"
        
        return new_name, metadata_title, year
        
    return None, None, None

def set_mkv_title(filepath, title):
    """
    Sets the Title metadata of an MKV file using mkvpropedit.
    """
    try:
        # Resolve mkvpropedit path
        mkvpropedit_cmd = "mkvpropedit"
        
        # Check standard location if not in PATH (common on Windows)
        std_path = r"C:\Program Files\MKVToolNix\mkvpropedit.exe"
        if os.path.exists(std_path):
             mkvpropedit_cmd = std_path
        
        # Construct command: mkvpropedit "file.mkv" --edit info --set "title=Title String"
        # Using list args for subprocess handles quoting automatically
        cmd = [
            mkvpropedit_cmd, 
            filepath, 
            "--edit", "info", 
            "--set", f"title={title}"
        ]
        
        # Run command, suppress output unless error
        result = subprocess.run(cmd, capture_output=True, text=True, encoding='utf-8')
        
        if result.returncode == 0:
            print(f"  [METADATA] Title set to '{title}'")
            return True
        else:
            print(f"  [METADATA ERROR] {result.stderr.strip()}")
            return False
            
    except FileNotFoundError:
        print("  [METADATA ERROR] 'mkvpropedit' not found in PATH.")
        return False
    except Exception as e:
        print(f"  [METADATA ERROR] {e}")
        return False

def process_file(f):
    if not f.lower().endswith(('.mkv', '.mp4')):
        return

    new_name, meta_title, year = clean_movie_format(f)
    if new_name:
        # Check if rename is needed
        final_path = f
        if new_name != f:
            try:
                os.rename(f, new_name)
                print(f"Renamed: '{f}' -> '{new_name}'")
                final_path = new_name
            except OSError as e:
                print(f"Error renaming '{f}': {e}")
                return
        else:
            print(f"Skipping rename (already correct): '{f}'")

        # Set Metadata (only for MKV usually, MP4 needs ffmpeg or other tools, 
        # but user specifically mentioned mkv examples and mkvpropedit implications)
        if final_path.lower().endswith('.mkv'):
            set_mkv_title(final_path, meta_title)
        else:
            print(f"  [METADATA] Skipping metadata for non-MKV file: {final_path}")

    else:
        print(f"Skipping '{f}' (could not extract Name/Year)")

def main():
    # Check for batch argument
    target_file = None

    if len(sys.argv) > 1:
        arg = sys.argv[1]
        if arg.lower() != "batch":
            target_file = arg

    if target_file:
         if os.path.exists(target_file):
             dirname, filename = os.path.split(target_file)
             if dirname: os.chdir(dirname)
             process_file(filename)
         else:
             print(f"File not found: {target_file}")
         return

    # Batch processing
    files = [f for f in os.listdir('.') if f.lower().endswith(('.mkv', '.mp4'))]
    print(f"Found {len(files)} video files.")

    for f in files:
        process_file(f)

if __name__ == "__main__":
    main()
