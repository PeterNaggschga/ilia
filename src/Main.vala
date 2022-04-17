using Gtk;

/**
 * Application entry point
 */
public static int main (string[] args) {
    Gtk.init (ref args);

    var arg_map = parse_args (args);
    if (arg_map.contains ("-h") || arg_map.contains ("--help")) print_help ();

    var page = arg_map.get ("-p") ?? "Apps";

    var window = new Ilia.DialogWindow (page);

    window.destroy.connect (Gtk.main_quit);
    initialize_style (window, arg_map);
    window.show_all ();

    // Use the Gdk window to grab global inputs.
    Gdk.Window gdkwin = window.get_window ();
    var seat = grab_inputs (gdkwin);

    if (seat == null) {
        stderr.printf ("Failed to aquire access to input devices, aborting.");
        return 1;
    } else {
        window.set_seat (seat);
    }

    // Handle mouse clicks by determining if a click is in or out of bounds
    // If we get a mouse click out of bounds of the window, exit.
    window.button_press_event.connect ((event) => {
        int window_width = 0, window_height = 0;
        window.get_size (out window_width, out window_height);

        int mouse_x = (int) event.x;
        int mouse_y = (int) event.y;

        var click_out_bounds = ((mouse_x < 0 || mouse_y < 0) || (mouse_x > window_width || mouse_y > window_height));

        if (click_out_bounds) {
            window.quit ();
        }

        return !click_out_bounds;
    });

    Gtk.main ();
    return 0;
}

private void initialize_style (Gtk.Window window, HashTable<string, string ? > arg_map) {
    try {
        if (arg_map.contains ("-t")) {

            var file = File.new_for_path (arg_map.get ("-t"));

            if (!file.query_exists ()) {
                printerr ("File '%s' does not exist.\n", file.get_path ());
                Process.exit (1);
            }
            Gtk.CssProvider css_provider = new Gtk.CssProvider ();
            css_provider.load_from_file (file);

            Gtk.StyleContext.add_provider_for_screen (Gdk.Screen.get_default (), css_provider, Gtk.STYLE_PROVIDER_PRIORITY_USER);
        } else if (!arg_map.contains ("-n")) {
            string default_css = """
                .root_box {
                    margin: 8px;
                }

                .filter_entry {
                    border: none;
                    background: none;
                }

                .notebook {
                    border: none;
                }
            """;
            Gtk.CssProvider css_provider = new Gtk.CssProvider ();
            css_provider.load_from_data (default_css);

            Gtk.StyleContext.add_provider_for_screen (Gdk.Screen.get_default (), css_provider, Gtk.STYLE_PROVIDER_PRIORITY_USER);
        }
    } catch (GLib.Error ex) {
        error ("Failed to initalize style: " + ex.message);
    }
}

// Grabs the input devices for a given window
// Some systems exhibit behavior such that keyboard / mouse cannot be reliably grabbed.
// As a workaround, this function will continue to attempt to grab these resources over an
// increasing time window and eventually give up and exit if ultimately unable to aquire
// the keyboard and mouse resources.
Gdk.Seat ? grab_inputs (Gdk.Window gdkwin) {
    var display = gdkwin.get_display (); // Gdk.Display.get_default();
    if (display == null) {
        stderr.printf ("Failed to get Display\n");
        return null;
    }

    var seat = display.get_default_seat ();
    if (seat == null) {
        stdout.printf ("Failed to get Seat from Display\n");
        return null;
    }

    int attempt = 0;
    Gdk.GrabStatus ? grabStatus = null;
    int wait_time = 1000;

    do {
        grabStatus = seat.grab (gdkwin, Gdk.SeatCapabilities.KEYBOARD | Gdk.SeatCapabilities.POINTER, true, null, null, null);
        if (grabStatus != Gdk.GrabStatus.SUCCESS) {
            attempt++;
            wait_time = wait_time * 2;
            GLib.Thread.usleep (wait_time);
        }
    } while (grabStatus != Gdk.GrabStatus.SUCCESS && attempt < 8);

    if (grabStatus != Gdk.GrabStatus.SUCCESS) {
        stderr.printf ("Aborting, failed to grab input: %d\n", grabStatus);
        return null;
    } else {
        return seat;
    }
}

void print_help () {
    stdout.printf ("Usage: ilia [-t stylesheet] [-n] [-p page]\n");
    stdout.printf ("\npages:\n");
    stdout.printf ("\t'apps' - launch desktop applications\n");
    stdout.printf ("\t'terminal' - launch a terminal command\n");
    stdout.printf ("\t'notifications' - launch notifications manager\n");
    stdout.printf ("\t'keybindings' - launch keybindings viewer\n");
    stdout.printf ("\t'textlist' - select an item from a specified list\n");
    stdout.printf ("\t'windows' - navigate to a window\n");
    stdout.printf ("\t'tracker' - search for files by content\n");
    stdout.printf ("\n\t -t: specify path to custom stylesheet.  -n: no custom styles\n");
    Process.exit (0);
}

/**
 * Convert ["-v", "-s", "asdf", "-f", "qwe"] => {("-v", null), ("-s", "adsf"), ("-f", "qwe")}
 * Populates key of "cmd" with first arg.
 * NOTE: Currently does not support quoted parameter values.
 */
HashTable<string, string ? > parse_args (string[] args) {
    var arg_hashtable = new HashTable<string, string ? >(str_hash, str_equal);

    if (args == null || args.length == 0) {
        return arg_hashtable;
    }

    string last_key = null;
    foreach (string token in args) {
        if (!arg_hashtable.contains ("cmd")) {
            arg_hashtable.set ("cmd", token);
        } else if (is_key (token)) {
            if (last_key != null) {
                arg_hashtable.set (last_key, null);
            }
            last_key = token;
        } else if (last_key != null) {
            arg_hashtable.set (last_key, token);
            last_key = null;
        } else {
            // ignore
        }
    }

    if (last_key != null) { // Trailing single param
        arg_hashtable.set (last_key, null);
    }
    /*
       foreach (var key in arg_hashtable.get_keys ()) {
        stdout.printf ("%s => %s\n", key, arg_hashtable.lookup(key));
       }
     */

    return arg_hashtable;
}

errordomain ArgParser {
    PARSE_ERROR
}

bool is_key (string inval) {
    return inval.has_prefix ("-");
}