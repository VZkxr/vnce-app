import os
import re
import subprocess
import shutil

def rename_and_set_title():
    current_dir = os.getcwd()

    # Pattern to match: Euphoria.SXXEXX.Title.1080p...-BLCK_STAR.mkv
    # Capturing groups:
    # 1: Season number (e.g., 01, 02)
    # 2: Episode number (e.g., 01)
    # 3: Episode title (e.g., Pilot)
    # Use re.DOTALL or similar if needed, but filenames are usually single line. 
    # Logic: Match until "1080p" to separate title from technical details.
    pattern = re.compile(r"Euphoria\.S(\d+)E(\d+)\.(.+?)\.1080p.*?-BLCK_STAR\.mkv", re.IGNORECASE)

    print("Running in:", current_dir)
    found_files = False

    for filename in os.listdir(current_dir):
        if not filename.endswith(".mkv"):
            continue

        match = pattern.match(filename)
        if match:
            found_files = True
            season_num_str = match.group(1)
            episode_num_str = match.group(2)
            episode_title_raw = match.group(3)

            # Convert numbers to int to remove leading zeros (e.g. '01' -> 1)
            season_num = int(season_num_str)
            episode_num = int(episode_num_str)

            # Replace dots with spaces in title just in case (e.g. "Some.Title" -> "Some Title")
            episode_title = episode_title_raw.replace('.', ' ')

            new_filename = f"T{season_num}.E{episode_num} - {episode_title}.mkv"
            new_title_metadata = f"T{season_num}.E{episode_num} - {episode_title}"

            print(f"Processing: {filename}")
            print(f" -> Rename directly to: {new_filename}")
            print(f" -> Set Title Metadata to: {new_title_metadata}")
            
            try:
                # Rename file
                os.rename(filename, new_filename)
                
                # Check for mkvpropedit command
                mkvpropedit_cmd = shutil.which('mkvpropedit')
                
                if not mkvpropedit_cmd:
                     possible_paths = [
                        r"C:\Program Files\MKVToolNix\mkvpropedit.exe",
                        r"C:\Program Files (x86)\MKVToolNix\mkvpropedit.exe"
                    ]
                     for p in possible_paths:
                        if os.path.exists(p):
                            mkvpropedit_cmd = p
                            break
                            
                if not mkvpropedit_cmd:
                     # Fallback to try running 'mkvpropedit' and let subprocess fail if not found
                     mkvpropedit_cmd = 'mkvpropedit'

                # Set metadata title using mkvpropedit
                # Command: mkvpropedit "filename.mkv" --edit info --set "title=Title"
                subprocess.run([
                    mkvpropedit_cmd, new_filename,
                    '--edit', 'info',
                    '--set', f'title={new_title_metadata}'
                ], check=True, stdout=subprocess.DEVNULL, stderr=subprocess.PIPE)
                
                print(" -> Success: Renamed and metadata updated.")
                
            except FileNotFoundError:
                print(f" -> Error: mkvpropedit not found (checked '{mkvpropedit_cmd}' and PATH). Please install MKVToolNix.")
            except subprocess.CalledProcessError as e:
                print(f" -> Error updating metadata: {e}")
            except OSError as e:
                print(f" -> Error renaming file: {e}")
            print("-" * 40)

    if not found_files:
        print("No matching files found. Ensure you are running this script inside the correct folder.")

if __name__ == "__main__":
    rename_and_set_title()
