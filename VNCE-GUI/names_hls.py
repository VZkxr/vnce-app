import os
import re
import sys

def clean_text(text):
    # Remove vowels (both cases)
    text = re.sub(r'[aeiouAEIOUáéíóúÁÉÍÓÚ]', '', text)
    # Remove special chars
    text = text.replace('ñ', '').replace('Ñ', '')
    text = re.sub(r'[,!¡?¿\']', '', text)
    # Replace spaces with underscore
    text = text.strip().replace(' ', '_')
    # Remove repeated underscores
    text = re.sub(r'_+', '_', text)
    return text

def clean_text_short(text):
    # Specialized cleaner to shorten names:
    # 1. Replace spaces/dots with underscores
    text = re.sub(r'[\s\.]+', '_', text)
    # 2. Remove vowels (keep case)
    text = re.sub(r'[aeiouAEIOUáéíóúÁÉÍÓÚ]', '', text)
    # 3. Remove duplicates and leading/trailing underscores
    text = re.sub(r'_+', '_', text)
    return text.strip('_')

def process_file(f):
    # Match pattern: "T1.E1 - Title.mkv" OR "T1.E1 Title.mp4"
    match_series = re.match(r"(T\d+\.E\d+)(?:[\s\.-]+)(.+)(\.(mkv|mp4))", f, re.IGNORECASE)
    
    if match_series:
        original_prefix = match_series.group(1) # T1.E1
        file_prefix = original_prefix.replace('.', '') # T1E1
        title = match_series.group(2)
        ext = match_series.group(3)
        
        # Original clean_text for series (aggressive removal)
        # Note: Original code used a specific clean_text. Check if we should reuse/modify it.
        # For compatibility, let's keep the logic inline or simple
        clean_t = re.sub(r'[aeiouAEIOUáéíóúÁÉÍÓÚ]', '', title)
        clean_t = clean_t.replace('ñ', '').replace('Ñ', '')
        clean_t = re.sub(r'[,!¡?¿\']', '', clean_t)
        clean_t = clean_t.strip().replace(' ', '_')
        clean_t = re.sub(r'_+', '_', clean_t)
        
        new_name = f"{file_prefix}-{clean_t}{ext}"
        txt_entry = f"{file_prefix}-{clean_t}"
        
        if new_name != f:
            try:
                os.rename(f, new_name)
                print(f"Renamed: '{f}' -> '{new_name}'")
                return txt_entry
            except OSError as e:
                print(f"Error renaming '{f}': {e}")
        else:
            print(f"Skipping '{f}' (name matches, adding to list)")
            return txt_entry

    # New Logic: Movie Shortener
    # Pattern: Name (Year) or Name.Year...
    # Flexible match for Year
    try:
        base_name, ext = f.rsplit('.', 1)
    except ValueError:
        return None

    # Check for Year pattern to split name
    match_movie = re.search(r'^(.*?)[.(\s](\d{4})([.\)\s]|$)', base_name)
    
    if match_movie:
        title_raw = match_movie.group(1)
        year = match_movie.group(2)
        
        short_title = clean_text_short(title_raw)
        
        new_name = f"{short_title}-{year}.{ext}"
        
        if new_name != f:
             try:
                os.rename(f, new_name)
                print(f"Renamed: '{f}' -> '{new_name}'")
                return new_name # Return new name as entry
             except OSError as e:
                print(f"Error renaming '{f}': {e}")
        else:
            print(f"Skipping '{f}' (already correct)")
            return new_name

    print(f"Skipping '{f}' (no pattern match)")
    return None

def main():
    # Check for batch argument
    is_batch = False
    target_file = None

    if len(sys.argv) > 1:
        arg = sys.argv[1]
        if arg.lower() == "batch":
            is_batch = True
        else:
            target_file = arg

    if target_file:
         if os.path.exists(target_file):
             dirname, filename = os.path.split(target_file)
             if dirname: os.chdir(dirname)
             process_file(filename)
         else:
             print(f"File not found: {target_file}")
         return

    # Batch processing (default or explicit)
    files = [f for f in os.listdir('.') if f.lower().endswith(('.mkv', '.mp4'))]
    renamed_list = []
    
    print(f"Found {len(files)} video files.")

    for f in files:
        res = process_file(f)
        if res:
            renamed_list.append(res)
            
    # Write list
    output_file = "nombres.txt"
    if renamed_list:
        try:
            with open(output_file, "w", encoding="utf-8") as f:
                for name in renamed_list:
                    f.write(name + "\n")
            print(f"\nCreated '{output_file}' with {len(renamed_list)} entries.")
        except Exception as e:
            print(f"Error writing text file: {e}")
    else:
        print("\nNo files renamed or processed.")

if __name__ == "__main__":
    main()