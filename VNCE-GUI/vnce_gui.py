
import customtkinter as ctk
import tkinter as tk
from tkinter import filedialog, messagebox
import os
import threading
import sys
import subprocess
from PIL import Image, ImageTk

# --- Theme Configuration ---
ctk.set_appearance_mode("Dark")
ctk.set_default_color_theme("dark-blue")

class VNCEApp(ctk.CTk):
    def __init__(self):
        super().__init__()

        self.title("VNCE GUI")
        self.geometry("950x700")

        # --- Colors (VNCE Style) ---
        self.color_bg = "#1a1a1a"       # Dark background
        self.color_panel = "#2b2b2b"    # Panel background
        self.color_accent = "#c0392b"   # Red accent
        self.color_accent_hover = "#e74c3c" # Lighter red
        self.color_text = "#ecf0f1"     # Light gray/white text

        self.configure(fg_color=self.color_bg)

        # --- Shared State ---
        self.cwd_var = ctk.StringVar(value=os.getcwd())
        self.is_single_file_mode = False 
        self.active_processes = []
        
        # --- Window Protocol ---
        self.protocol("WM_DELETE_WINDOW", self.on_closing)
        
        # --- Layout ---
        self.grid_columnconfigure(1, weight=1)
        self.grid_rowconfigure(0, weight=1)

        # --- Components ---
        self.setup_sidebar()
        
        # Create Main Frames (Persistent)
        self.frames = {}
        for F in ("Home", "Renamer", "Converter"):
            frame = ctk.CTkFrame(self, fg_color=self.color_bg, corner_radius=0)
            self.frames[F] = frame
            # All frames stack on the same grid cell
            frame.grid(row=0, column=1, sticky="nsew", padx=10, pady=10)

        # Initialize content for each frame
        self.setup_home_frame(self.frames["Home"])
        self.setup_rename_frame(self.frames["Renamer"])
        self.setup_converter_frame(self.frames["Converter"])

        # Show default
        self.show_frame("Home")

    def setup_sidebar(self):
        self.sidebar = ctk.CTkFrame(self, width=200, corner_radius=0, fg_color=self.color_panel)
        self.sidebar.grid(row=0, column=0, sticky="nsew")
        self.sidebar.grid_rowconfigure(5, weight=1) 

        # Logo
        self.logo_label = ctk.CTkLabel(self.sidebar, text="VNCE\nGUI", font=("Roboto", 24, "bold"), text_color=self.color_accent)
        self.logo_label.grid(row=0, column=0, padx=20, pady=(20, 10))
        
        try:
            logo_path = os.path.join(os.getcwd(), "Multimedia", "logo.png")
            if not os.path.exists(logo_path): logo_path = "logo.png"
            if os.path.exists(logo_path):
                 img = Image.open(logo_path)
                 base_width = 160
                 w_percent = (base_width / float(img.size[0]))
                 h_size = int((float(img.size[1]) * float(w_percent)))
                 img = img.resize((base_width, h_size), Image.Resampling.LANCZOS)
                 self.logo_image = ctk.CTkImage(light_image=img, dark_image=img, size=(base_width, h_size))
                 self.logo_label.configure(image=self.logo_image, text="")
        except Exception: pass

        # Nav Buttons
        self.btn_home = self.create_nav_button("Home", "Home")
        self.btn_rename = self.create_nav_button("Renamer", "Renamer")
        self.btn_convert = self.create_nav_button("Converter", "Converter")
        self.create_nav_button("Exit", "Exit")

    def create_nav_button(self, text, frame_name):
        cmd = self.quit_app if frame_name == "Exit" else lambda: self.show_frame(frame_name)
        btn = ctk.CTkButton(self.sidebar, text=text, command=cmd,
                            fg_color="transparent", text_color=self.color_text,
                            hover_color=self.color_accent, anchor="w",
                            font=("Roboto", 14), height=40)
        # Determine row based on text for simplicity in this refactor
        rows = {"Home": 1, "Renamer": 2, "Converter": 3, "Exit": 4}
        btn.grid(row=rows.get(text, 5), column=0, padx=10, pady=5, sticky="ew")
        return btn

    def show_frame(self, name):
        # Raise the selected frame to top
        frame = self.frames[name]
        frame.tkraise()

    # --- Frame Setups ---

    def setup_home_frame(self, frame):
        frame.grid_columnconfigure(0, weight=1)
        
        ctk.CTkLabel(frame, text="Welcome to VNCE Automation", font=("Roboto", 20, "bold")).grid(row=0, column=0, pady=20, sticky="w")
        
        info = ("Select a tool from the sidebar to begin.\n\n"
                "- Renamer: Clean file names and standardise series.\n"
                "- Converter: Format conversion tools.")
        ctk.CTkLabel(frame, text=info, font=("Roboto", 14), justify="left").grid(row=1, column=0, sticky="w", padx=10)

        self.lbl_cwd = ctk.CTkLabel(frame, text=f"Current Directory: {self.cwd_var.get()}", text_color="gray", wraplength=600, justify="left")
        self.lbl_cwd.grid(row=2, column=0, sticky="w", padx=10, pady=(20,5))
        
        ctk.CTkButton(frame, text="Change Working Directory", command=self.pick_directory, 
                      fg_color=self.color_accent, hover_color=self.color_accent_hover).grid(row=3, column=0, sticky="w", padx=10)

    def setup_rename_frame(self, frame):
        frame.grid_columnconfigure(0, weight=1)
        frame.grid_rowconfigure(4, weight=1)

        ctk.CTkLabel(frame, text="File Renamer", font=("Roboto", 20, "bold")).grid(row=0, column=0, pady=10, sticky="w")
        
        # Mode
        f_mode = ctk.CTkFrame(frame, fg_color=self.color_panel)
        f_mode.grid(row=1, column=0, sticky="ew", padx=10, pady=(0,10))
        
        self.sw_rename = ctk.CTkSwitch(f_mode, text="Single File Mode", progress_color=self.color_accent, command=self.toggle_mode_rename)
        self.sw_rename.pack(side="left", padx=10, pady=10)
        
        self.lbl_rename_mode = ctk.CTkLabel(f_mode, text="Mode: Batch", text_color="gray")
        self.lbl_rename_mode.pack(side="left", padx=10)

        # Opts
        f_opts = ctk.CTkFrame(frame, fg_color=self.color_panel)
        f_opts.grid(row=2, column=0, sticky="ew", padx=10, pady=10)
        
        ctk.CTkLabel(f_opts, text="Operations:", font=("Roboto", 14, "bold")).grid(row=0, column=0, sticky="w", padx=10, pady=5)
        
        ctk.CTkButton(f_opts, text="Run Clean Names (MKV/MP4)", command=self.run_clean_names, 
                      fg_color=self.color_accent, hover_color=self.color_accent_hover).grid(row=1, column=0, sticky="w", padx=10, pady=5)
        
        ctk.CTkButton(f_opts, text="Run Movie Format", command=self.run_movie_format,
                      fg_color=self.color_accent, hover_color=self.color_accent_hover).grid(row=2, column=0, sticky="w", padx=10, pady=5)

        ctk.CTkButton(f_opts, text="Run Series Format", command=self.run_series_rename,
                      fg_color=self.color_accent, hover_color=self.color_accent_hover).grid(row=3, column=0, sticky="w", padx=10, pady=5)

        ctk.CTkLabel(frame, text="Activity Log:", font=("Roboto", 12)).grid(row=3, column=0, sticky="w", padx=10, pady=(10,0))
        self.log_rename = ctk.CTkTextbox(frame, height=300)
        self.log_rename.grid(row=4, column=0, sticky="nsew", padx=10, pady=5)
        self.log("Renamer ready.", self.log_rename)

    def setup_converter_frame(self, frame):
        frame.grid_columnconfigure(0, weight=1)
        frame.grid_rowconfigure(4, weight=1)

        ctk.CTkLabel(frame, text="Video Converter", font=("Roboto", 20, "bold")).grid(row=0, column=0, pady=10, sticky="w")
        
        # Mode
        f_mode = ctk.CTkFrame(frame, fg_color=self.color_panel)
        f_mode.grid(row=1, column=0, sticky="ew", padx=10, pady=(0,10))
        
        self.sw_convert = ctk.CTkSwitch(f_mode, text="Single File Mode", progress_color=self.color_accent, command=self.toggle_mode_convert)
        self.sw_convert.pack(side="left", padx=10, pady=10)
        
        self.lbl_convert_mode = ctk.CTkLabel(f_mode, text="Mode: Batch", text_color="gray")
        self.lbl_convert_mode.pack(side="left", padx=10)

        # Opts
        f_opts = ctk.CTkFrame(frame, fg_color=self.color_panel)
        f_opts.grid(row=2, column=0, sticky="ew", padx=10, pady=10)
        
        ctk.CTkLabel(f_opts, text="Conversions:", font=("Roboto", 14, "bold")).grid(row=0, column=0, sticky="w", padx=10, pady=5)
        
        ctk.CTkButton(f_opts, text="MKV to MP4", command=lambda: self.run_conversion("mkv_to_mp4"),
                      fg_color=self.color_accent, hover_color=self.color_accent_hover).grid(row=1, column=0, sticky="w", padx=10, pady=5)
        
        ctk.CTkButton(f_opts, text="MKV to MP4", command=lambda: self.run_conversion("mkv_to_mp4"),
                      fg_color=self.color_accent, hover_color=self.color_accent_hover).grid(row=1, column=0, sticky="w", padx=10, pady=5)
        
        ctk.CTkButton(f_opts, text="Convert to HLS (Auto)", command=lambda: self.run_conversion("smart_hls"),
                      fg_color=self.color_accent, hover_color=self.color_accent_hover).grid(row=2, column=0, sticky="w", padx=10, pady=5)

        ctk.CTkLabel(frame, text="Activity Log:", font=("Roboto", 12)).grid(row=3, column=0, sticky="w", padx=10, pady=(10,0))
        self.log_convert = ctk.CTkTextbox(frame, height=300)
        self.log_convert.grid(row=4, column=0, sticky="nsew", padx=10, pady=5)
        self.log("Converter ready.", self.log_convert)

    # --- Actions ---

    def pick_directory(self):
        d = filedialog.askdirectory()
        if d:
            os.chdir(d)
            self.cwd_var.set(d)
            self.lbl_cwd.configure(text=f"Current Directory: {d}")

    def toggle_mode_rename(self):
        val = self.sw_rename.get()
        self.is_single_file_mode = bool(val)
        # Sync other switch
        if val: self.sw_convert.select()
        else: self.sw_convert.deselect()
        self.update_mode_labels()

    def toggle_mode_convert(self):
        val = self.sw_convert.get()
        self.is_single_file_mode = bool(val)
        if val: self.sw_rename.select()
        else: self.sw_rename.deselect()
        self.update_mode_labels()

    def update_mode_labels(self):
        txt = "Mode: Single File (Select File)" if self.is_single_file_mode else "Mode: Batch (All files in folder)"
        self.lbl_rename_mode.configure(text=txt)
        self.lbl_convert_mode.configure(text=txt)

    def get_target(self):
        if self.is_single_file_mode:
            f = filedialog.askopenfilename(initialdir=self.cwd_var.get(), title="Select Video", filetypes=[("Video Files", "*.mkv *.mp4")])
            return f if f else None
        return "BATCH"

    def log(self, msg, widget):
        widget.insert("end", str(msg) + "\n")
        widget.see("end")

    def run_clean_names(self):
        tgt = self.get_target()
        if not tgt: return
        self.run_script("names_hls.py", tgt, self.log_rename)

    def run_series_rename(self):
        tgt = self.get_target()
        if not tgt: return
        self.run_script("mkv_renames_series.py", tgt, self.log_rename)

    def run_movie_format(self):
        tgt = self.get_target()
        if not tgt: return
        self.run_script("names_movie_format.py", tgt, self.log_rename)

    def run_conversion(self, mode):
        tgt = self.get_target()
        if not tgt: return
        
        script_map = {
            "mkv_to_mp4": "mkv_to_mp4_converter.py",
            "smart_hls": "smart_hls.py"
        }
        script = script_map.get(mode)
        
        # Args logic
        args = []
        input_str = None
        
        if tgt == "BATCH":
            if mode == "mkv_to_mp4": args.append("batch")
            elif mode == "smart_hls": args.append("batch")
        else:
            args.append(tgt)
            
        self.run_script(script, args, self.log_convert, input_str)

    def run_script(self, script_name, args, log_widget, input_str=None):
        self.log(f"Starting {script_name}...", log_widget)
        
        # Configure tags for colors if not already done
        if log_widget:
            log_widget.tag_config("HEADER", foreground="#FF00FF") # Magenta/Pink
            log_widget.tag_config("BLUE", foreground="#00BFFF")   # Deep Sky Blue
            log_widget.tag_config("GREEN", foreground="#00FF00")  # Lime Green
            log_widget.tag_config("WARNING", foreground="#FFD700")# Gold
            log_widget.tag_config("FAIL", foreground="#FF4500")   # Orange Red
            log_widget.tag_config("NORMAL", foreground="#ecf0f1") # Default White/Gray

        def task():
            try:
                # Resolve script path
                base_dir = os.path.dirname(os.path.abspath(__file__))
                path = os.path.join(base_dir, script_name)
                
                if not os.path.exists(path):
                     path = os.path.join(os.getcwd(), script_name)

                if not os.path.exists(path):
                    self.after(0, self.log, f"Error: Script '{script_name}' not found at {path}", log_widget)
                    return
                
                cmd = ["python", path]
                if isinstance(args, list): cmd.extend(args)
                elif args and args != "BATCH": cmd.append(args)

                process = subprocess.Popen(
                    cmd,
                    stdin=subprocess.PIPE if input_str else None,
                    stdout=subprocess.PIPE,
                    stderr=subprocess.STDOUT, # Merge stderr into stdout
                    text=True,
                    bufsize=1,
                    creationflags=subprocess.CREATE_NO_WINDOW if sys.platform == 'win32' else 0,
                    encoding='utf-8',
                    errors='replace'
                )
                
                self.active_processes.append(process)

                if input_str:
                    try:
                        process.stdin.write(input_str)
                        process.stdin.flush()
                    except: pass

                # ANSI Code Mapping
                # \033[95m -> HEADER
                # \033[94m -> BLUE
                # \033[92m -> GREEN
                # \033[93m -> WARNING
                # \033[91m -> FAIL
                # \033[0m  -> ENDC (Stop styling)

                for line in process.stdout:
                    clean_line = line.strip()
                    # Basic ANSI parsing
                    tag = "NORMAL"
                    if '\033[95m' in line: tag = "HEADER"
                    elif '\033[94m' in line: tag = "BLUE"
                    elif '\033[92m' in line: tag = "GREEN"
                    elif '\033[93m' in line: tag = "WARNING"
                    elif '\033[91m' in line: tag = "FAIL"
                    
                    # Remove ANSI codes for display
                    msg = line.replace('\033[95m', '').replace('\033[94m', '').replace('\033[92m', '').replace('\033[93m', '').replace('\033[91m', '').replace('\033[0m', '').strip()
                    
                    if msg: # Only log non-empty lines
                        self.after(0, self.log_tagged, msg, log_widget, tag)
                
                process.wait()
                self.after(0, self.log, f"Finished (Code {process.returncode})", log_widget)
                if process.returncode == 0:
                    self.after(0, lambda: messagebox.showinfo("Done", "Operation Complete"))
                else:
                    self.after(0, lambda: messagebox.showerror("Error", "Processed with errors"))

            except Exception as e:
                self.after(0, self.log, f"Error: {e}", log_widget)
            finally:
                if 'process' in locals():
                    if process in self.active_processes:
                        self.active_processes.remove(process)

        threading.Thread(target=task, daemon=True).start()

    def log_tagged(self, msg, widget, tag="NORMAL"):
        if widget:
            widget.insert("end", str(msg) + "\n", tag)
            widget.see("end")

    def on_closing(self):
        if self.active_processes:
            if messagebox.askokcancel("Quit", "There are active processes running. Do you want to kill them and quit?"):
                for p in self.active_processes:
                    try:
                        p.terminate()
                    except:
                        pass
                self.quit_app()
        else:
            self.quit_app()

    def quit_app(self):
        try:
            self.quit()
            self.destroy()
        except:
            pass
        finally:
            sys.exit(0)

if __name__ == "__main__":
    app = VNCEApp()
    app.mainloop()
