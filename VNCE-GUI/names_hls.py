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

def process_file(f):
    # Match pattern: "T1.E1 - Title.mkv" OR "T1.E1 Title.mp4"
    # User input: "T1.E1 Ya era hora.mp4"
    # Regex needs to be flexible with separator (space, dash, dot)
    # Try match: ^(T\d+\.E\d+)(?: - | |\.)(.+)(\.(mkv|mp4))$
    
    match = re.match(r"(T\d+\.E\d+)(?:[\s\.-]+)(.+)(\.(mkv|mp4))", f, re.IGNORECASE)
    
    if match:
        original_prefix = match.group(1) # T1.E1
        file_prefix = original_prefix.replace('.', '') # T1E1
        title = match.group(2)
        ext = match.group(3)
        
        clean_t = clean_text(title)
        new_name = f"{file_prefix}-{clean_t}{ext}"
        
        # Text file format: "T1E1-Sanitized_Name"
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
    else:
        print(f"Skipping '{f}' (does not match T#.E# pattern)")
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