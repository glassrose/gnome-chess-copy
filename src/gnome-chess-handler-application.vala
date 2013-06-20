/*
 * Copyright (C) 2012 Chandni Verma
 *
 * This program is free software; you can redistribute it and/or
 * modify it under the terms of the GNU General Public License as
 * published by the Free Software Foundation; either version 2 of the
 * License, or (at your option) any later version.
 *
 * This program is distributed in the hope that it will be useful,
 * but WITHOUT ANY WARRANTY; without even the implied warranty of
 * MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the GNU
 * General Public License for more details.
 *
 * You should have received a copy of the GNU General Public
 * License along with this program; if not, write to the
 * Free Software Foundation, Inc., 51 Franklin St, Fifth Floor,
 * Boston, MA  02110-1301  USA
 *
 * Author: Chandni Verma <chandniverma2112@gmail.com>
 */

public class HandlerApplication : Application
{
    private Gtk.Builder builder;

    /* Objects from gnome-chess-network-window.ui */
    private Gtk.Window? handler_window = null;
    private Gtk.Widget grid_main;
    private Gtk.Widget grid_contacts_presence_and_channels;

    private Gtk.Widget combobox_presence;
    private Gtk.Widget button_goa;
    private Gtk.Action radioaction_channel_list;
    private Gtk.Action radioaction_contact_list;
    private Gtk.Container scrolledwindow_list;
    private Gtk.Widget alignment_play;

    private Gtk.Widget contacts_box;
    private GamesContacts.IndividualStore? individual_store = null;
    private GamesContacts.IndividualManager? individual_manager = null;
    private GamesContacts.IndividualView? individual_view = null;
    private GamesContacts.LiveSearch? search_widget;

    private Gtk.Container scrolledwindow_channels;
    private Gtk.TreeView channel_view;
    private Gtk.TreeSelection channel_view_selection;

    /* Objects from gnome-chess-game-window.ui */
    private Gtk.Widget navigation_box;
    private Gtk.Widget view_box;
    private Gtk.Widget handler_menubar;

    private bool is_activated = false;
    private TelepathyGLib.SimpleHandler tp_handler;

    private enum ChannelsColumn
    {
        USER_ACTION_TIME,  /* tp-time of channel creation */
        TARGET_CONTACT,    /* target contact */
        CHANNEL,           /* tube channel */
        OUR_COLOUR_WHITE,  /* our piece color */
        PGN_GAME,
        HISTORY_MODEL,
        HISTORY_COMBO_ACTIVE_ITER,
        CHESS_GAME,
        CHESS_SCENE,
        INFO_BAR,
        GAME_NEEDS_SAVING,
        CHANNEL_APPROVED,
        SHOW_STATUS_SCREEN,
        STATUS_MESSAGE,
        NUM_COLS
    }

    /* Channels */
    Gtk.ListStore channels;
    Gtk.TreeIter? selected_channel_iter = null;
    HashTable <string, int32> channel_count;

    public HandlerApplication ()
    {
        Object (
            application_id: "org.gnome.gnome-chess.handler",
            flags: ApplicationFlags.FLAGS_NONE);

        chess_networking_init ();
        channels = new Gtk.ListStore (ChannelsColumn.NUM_COLS,
            typeof (int64),                  /* USER_ACTION_TIME */
            typeof (TelepathyGLib.Contact),  /* TARGET_CONTACT */
            typeof (TelepathyGLib.Channel),  /* CHANNEL */
            typeof (bool),                   /* OUR_COLOUR_WHITE */
            typeof (PGNGame),                /* PGN_GAME */
            typeof (Gtk.TreeModel),          /* HISTORY_MODEL */
            typeof (Gtk.TreeIter),           /* HISTORY_COMBO_ACTIVE_ITER */
            typeof (ChessGame),              /* CHESS_GAME */
            typeof (ChessScene),             /* CHESS_SCENE */
            typeof (Gtk.InfoBar),            /* INFO_BAR */
            typeof (bool),                   /* GAME_NEEDS_SAVING */
            typeof (bool),                   /* CHANNEL_APPROVED */
            typeof (bool),                   /* SHOW_STATUS_SCREEN */
            typeof (string)                  /* STATUS_MESSAGE */
            );

        assert (channels != null);
        channel_count = new HashTable <string, int32> (str_hash, str_equal);

        settings = new Settings ("org.gnome.gnome-chess");
        settings_common = new Settings ("org.gnome.gnome-chess.games-common");

        builder = new Gtk.Builder ();
        try
        {
            builder.add_from_file (Path.build_filename (Config.PKGDATADIR,
                "gnome-chess-network-window.ui", null));
        }
        catch (Error e)
        {
            warning ("Could not load UI: %s", e.message);
        }

        settings_common.changed.connect (settings_changed_cb);
    }

    private bool change_view (Gtk.TreeModel model, Gtk.TreePath path, Gtk.TreeIter channel_iter)
    {
        ChessGame? game = null;
        ChessScene? scene = null;

        model.@get (channel_iter, ChannelsColumn.CHESS_GAME, out game, ChannelsColumn.CHESS_SCENE, out scene);
        assert (game != null && scene != null);
        ChessView chess_view = (game as Object).get_data<ChessView> ("chess-view");

        if (chess_view != null)
        {
            if ((chess_view as Gtk.Widget).get_parent () == view_container)
                view_container.remove (chess_view);
            chess_view.destroy ();
        }
        if (settings_common.get_boolean ("show-3d"))
            chess_view = new ChessView3D ();
        else
            chess_view = new ChessView2D ();
        chess_view.set_size_request (300, 300);
        chess_view.scene = scene;
        if (channel_iter == selected_channel_iter)
            view_container.add (chess_view);
        chess_view.set_visible (true);

        return false;
    }

    private void settings_changed_cb (Settings settings_common, string key)
    {
        if (key == "show-3d")
        {
            channels.@foreach (change_view);
        }
    }

    private void clear_view_box (Gtk.Widget child)
    {
        (view_box as Gtk.Container).remove (child);
    }

    private void set_game_screen (bool show_status_screen, string message = "")
    {
        List view_box_children = (view_box as Gtk.Container).get_children ();

        if (view_box_children.length () > 0)
            (view_box as Gtk.Container).@foreach (clear_view_box);

        if (show_status_screen)
        {
            (view_box as Gtk.Box).pack_start (new Gtk.Label (message));

            /* Update menus' sensitivities */
            resign_menu.sensitive =
            save_menu.sensitive =
            save_as_menu.sensitive = false;
        }
        else
        {
            ChessGame game;
            bool game_needs_saving;
            ChessScene chess_scene;
            Gtk.InfoBar info_bar;
            Gtk.TreeModel history_model;

            assert (selected_channel_iter != null);
            channels.@get (selected_channel_iter,
                ChannelsColumn.CHESS_GAME, out game,
                ChannelsColumn.GAME_NEEDS_SAVING, out game_needs_saving,
                ChannelsColumn.CHESS_SCENE, out chess_scene,
                ChannelsColumn.INFO_BAR, out info_bar,
                ChannelsColumn.HISTORY_MODEL, out history_model);

            /* Place the selected channel's infobar into view_box */
            (view_box as Gtk.Box).pack_start (info_bar, false, true, 0);

            (view_box as Gtk.Box).pack_start (view_container, false, true, 0);
            (view_box as Gtk.Box).pack_start (navigation_box, false, true, 0);

            /* Place the selected channel's view into view_container */
            Gtk.Widget child = (view_container as Gtk.Bin).get_child ();
            if (child != null)
                view_container.remove (child);
            Gtk.Widget view = (game as Object).get_data<ChessView> ("chess-view");
            view_container.add (view);
            view.show ();

            /* Update menus' sensitivities */
            if (game_needs_saving)
            {
                resign_menu.sensitive = game.n_moves > 0;
                save_menu.sensitive = true;
                save_as_menu.sensitive = true;
            }

            /* Update history-combo's model */
            history_combo.set_model (history_model);

            /* Update history panel */
            update_history_panel (game, chess_scene, history_combo.model);

            white_time_label.queue_draw ();
            black_time_label.queue_draw ();
        }
    }

    private void show_game ()
    {
        TelepathyGLib.Contact remote_player;
        int64 action_time = -1;
        bool channel_approved;

        if (selected_channel_iter == null)
        {
            debug ("No channel selected");
            return;
        }

        channels.@get (selected_channel_iter,
            ChannelsColumn.TARGET_CONTACT, out remote_player,
            ChannelsColumn.USER_ACTION_TIME, out action_time,
            ChannelsColumn.CHANNEL_APPROVED, out channel_approved);

        assert (action_time != -1);

        debug ("Showing game with %s. Initiation timeframe: %lld", remote_player.identifier, action_time);

        if (!channel_approved)
        {
            string status_message = "Waiting for game request to be approved by %s".printf (remote_player.get_alias ());
            set_game_screen (true, status_message);
        }
        else
        {
            set_game_screen (false);
        }
    }

    private void channel_selection_changed_cb ()
    {
        Gtk.TreeIter? selected_channel_iter = null;

        if (! channel_view_selection.get_selected (null, out selected_channel_iter))
        {
            debug ("Couldn't obtain selected channel iterator");
            return;
        }

        this.selected_channel_iter = selected_channel_iter;

        show_game ();
    }

    private void channel_name_func (Gtk.TreeViewColumn tree_column, Gtk.CellRenderer cell, Gtk.TreeModel tree_model, Gtk.TreeIter iter)
    {
        string player_name;
        TelepathyGLib.Contact target_contact;
        int64 initiation_time;

        channels.@get (iter, ChannelsColumn.TARGET_CONTACT, out target_contact, ChannelsColumn.USER_ACTION_TIME, out initiation_time);

        player_name = target_contact.alias;
        (cell as Gtk.CellRendererText).text = "Game %d with %s".printf (channel_count.@get (target_contact.identifier), player_name);
    }

    private void create_handler_window ()
    {
        string [] objects_from_traditional_window =
          {
            "window_game_screen",
            "undo_move_image",
            "warning_image",
            "help_image"
          };
        handler_window = (Gtk.Window) builder.get_object
            ("window_networked_chess");
        handler_window.delete_event.connect (handler_window.hide_on_delete);

        grid_main = (Gtk.Widget) builder.get_object ("grid_main");
        grid_contacts_presence_and_channels = (Gtk.Widget) builder.get_object ("grid_contacts_presence_and_channels");
        combobox_presence = (Gtk.Widget) builder.get_object
            ("combobox_presence");
        button_goa = (Gtk.Widget) builder.get_object ("button_goa");
        radioaction_channel_list = (Gtk.Action) builder.get_object ("radioaction_channel_list");
        radioaction_contact_list = (Gtk.Action) builder.get_object ("radioaction_contact_list");
        scrolledwindow_list = (Gtk.Container) builder.get_object ("scrolledwindow_list");
        contacts_box = (Gtk.Widget) builder.get_object ("contacts_box");
        alignment_play = (Gtk.Widget) builder.get_object ("alignment_play");

        /* Add objects from gnome-chess-game-window.ui */
        try {
            builder.add_objects_from_file (Path.build_filename (Config.PKGDATADIR,
              "gnome-chess-game-window.ui", null),
              objects_from_traditional_window);

            handler_menubar = (Gtk.Widget) builder.get_object ("menubar");

            handler_menubar.unparent ();
            (grid_main as Gtk.Grid).attach (handler_menubar, 0, 0, 1, 1);

            save_menu = (Gtk.Widget) builder.get_object ("menu_save_item");
            save_as_menu = (Gtk.Widget) builder.get_object ("menu_save_as_item");
            fullscreen_menu = (Gtk.MenuItem) builder.get_object ("fullscreen_item");
            resign_menu = (Gtk.Widget) builder.get_object ("resign_item");

            view_box = (Gtk.Widget) builder.get_object ("view_box");
            view_box.reparent (alignment_play);

            view_container = (Gtk.Container) builder.get_object ("view_container");

            first_move_button = (Gtk.Widget) builder.get_object ("first_move_button");
            prev_move_button = (Gtk.Widget) builder.get_object ("prev_move_button");
            next_move_button = (Gtk.Widget) builder.get_object ("next_move_button");
            last_move_button = (Gtk.Widget) builder.get_object ("last_move_button");
            history_combo = (Gtk.ComboBox) builder.get_object ("history_combo");
            white_time_label = (Gtk.Widget) builder.get_object ("white_time_label");
            black_time_label = (Gtk.Widget) builder.get_object ("black_time_label");
            navigation_box = (Gtk.Widget) builder.get_object ("navigation_box");
            settings_common.bind ("show-history", navigation_box, "visible", SettingsBindFlags.DEFAULT);
        }
        catch (Error e)
        {
            warning ("Could not load UI: %s", e.message);
        }

        /* Connect signals of all objects to their respective handlers */
        builder.connect_signals (this);

        handler_window.title = _("Chess");

        prepare_contact_list ();

        scrolledwindow_channels = new Gtk.ScrolledWindow (null, null);
        channel_view = new Gtk.TreeView ();
        channel_view.model = channels;
        scrolledwindow_channels.add (channel_view);

        Gtk.CellRendererText text_renderer = new Gtk.CellRendererText ();
        channel_view.insert_column_with_data_func (-1, "", text_renderer, channel_name_func);

        channel_view_selection = channel_view.get_selection ();
        /* Enforce: user can't deselect a currently selected element except by selecting
         * another element*/
        channel_view_selection.set_mode (Gtk.SelectionMode.BROWSE);
        channel_view_selection.changed.connect (channel_selection_changed_cb);
        (channel_view as Gtk.Widget).show ();

        (scrolledwindow_channels as Gtk.Widget).expand = true;
        (scrolledwindow_channels as Gtk.Widget).show ();

        grid_main.show_all ();
    }

    private void prepare_contact_list ()
    {
        individual_manager =
            GamesContacts.IndividualManager.dup_singleton ();
        individual_store = new GamesContacts.IndividualStoreManager (
            individual_manager);
        individual_view = new GamesContacts.IndividualView (
            individual_store,
            GamesContacts.IndividualViewFeatureFlags.GROUPS_SAVE);

        /* Create searching capability for the treeview */
        search_widget = new GamesContacts.LiveSearch (
            individual_view as Gtk.Widget);
        individual_view.set_live_search (search_widget);

        /* Add filter for contacts capable of playing chess */
        individual_view.set_custom_filter ((model, iter, data)=>{
              return (data as GamesContacts.IndividualView).filter_default (
                  model, iter, GamesContacts.ActionType.PLAY_GLCHESS);
            });

        /* Evaluate contacts' presence using filter */
        individual_view.refilter ();

        /* Add to scrolled window and show */
        scrolledwindow_list.add (individual_view);
        scrolledwindow_list.show ();
        individual_view.show ();

        (contacts_box as Gtk.Container).add (search_widget);
    }

    [CCode (cname = "G_MODULE_EXPORT list_changed_cb", instance_pos=-1)]
    public void list_changed_cb (Gtk.RadioAction action, Gtk.RadioAction current_action)
    {
        if (action != current_action)
            return;

        if (current_action == radioaction_channel_list &&
            (grid_contacts_presence_and_channels as Gtk.Grid).get_child_at (0, 1) == contacts_box &&
            contacts_box.get_parent () == grid_contacts_presence_and_channels)
        {

            (grid_contacts_presence_and_channels as Gtk.Container).remove (contacts_box);
            (grid_contacts_presence_and_channels as Gtk.Grid).attach (scrolledwindow_channels, 0, 1, 1, 1);
        }
        else
        {
            if (current_action == radioaction_contact_list &&
                (grid_contacts_presence_and_channels as Gtk.Grid).get_child_at (0, 1) == scrolledwindow_channels &&
                (scrolledwindow_channels as Gtk.Widget).get_parent () == grid_contacts_presence_and_channels);
            {
                (grid_contacts_presence_and_channels as Gtk.Container).remove (scrolledwindow_channels);
                (grid_contacts_presence_and_channels as Gtk.Grid).attach (contacts_box, 0, 1, 1, 1);
            }
        }
    }

    [CCode (cname = "G_MODULE_EXPORT goa_clicked_cb", instance_pos=-1)]
    public void goa_clicked_cb (Gtk.Button button)
    {
    }

    [CCode (cname = "G_MODULE_EXPORT quit_cb", instance_pos = -1)]
    public override void quit_cb (Gtk.Widget widget)
    {
        quit_game ();
    }

    private bool save_game_and_remove_channel (Gtk.TreeModel model, Gtk.TreePath path, Gtk.TreeIter channel_iter)
    {
        TelepathyGLib.Channel? channel = null;
        int64 initiation_time = -1;
        ChessGame game;
        PGNGame pgn_game;
        bool game_needs_saving;

        channels.@get (channel_iter, ChannelsColumn.USER_ACTION_TIME, out initiation_time, ChannelsColumn.CHANNEL, out channel);

        var target_id = channel.target_contact.identifier;
        debug ("Removing chess tube channel with %s initiated at instance: %lld", target_id, initiation_time);

        /* Decrease channel count */
        var count = channel_count.@get (target_id);
        if (count == 1)
            channel_count.remove (target_id);
        else
            channel_count.@set (target_id, count-1);

        return false;
    }

    /* Quits the application */
    private void quit_game ()
    {
        Settings.sync ();

        if (channels != null)
            channels.@foreach (save_game_and_remove_channel);

        (handler_window as Gtk.Widget).destroy ();
    }

    private new void game_move_cb (ChessGame game, ChessMove move)
    {
        Gtk.TreeIter channel_iter;
        ChessView chess_view;
        PGNGame pgn_game;

        string channel_path_string = (game as Object).get_data<string> ("channel-path-string");
        channels.get_iter_from_string (out channel_iter, channel_path_string);
        chess_view = (game as Object).get_data<ChessView> ("chess-view");
        pgn_game = (game as Object).get_data<PGNGame> ("pgn-game");

        /* Need to save after each move */
        channels.@set (channel_iter, ChannelsColumn.GAME_NEEDS_SAVING, true);

        if (move.number > pgn_game.moves.length ())
            pgn_game.moves.append (move.get_san ());

        Gtk.ListStore model;
        ChessScene scene;
        channels.@get (channel_iter, ChannelsColumn.HISTORY_MODEL, out model, ChannelsColumn.CHESS_SCENE, out scene);

        Gtk.TreeIter iter;
        model.append (out iter);
        model.@set (iter, 1, move.number);
        set_move_text (iter, move, scene, model);

        /* Follow the latest move */
        if (move.number == game.n_moves && scene.move_number == -1)
            channels.@set (channel_iter, ChannelsColumn.HISTORY_COMBO_ACTIVE_ITER, iter);

        update_history_model (game, scene, model);

        /* UI updation */
        if (selected_channel_iter == channel_iter)
        {
            update_history_panel (game, scene, model);
            resign_menu.sensitive = game.n_moves > 0;
            save_menu.sensitive = true;
            save_as_menu.sensitive = true;
        }

        /* TODO: Acknowledge if opponent made this move */

        chess_view.queue_draw ();
    }

    private void fetch_players (DBusConnection conn,
        TelepathyGLib.DBusTubeChannel tube,
        Gtk.TreeIter channel_iter)
    {
        RemoteChessPlayer white, black;
        white = black = null;

        /* Asynchronously fetch player objects from connection. Create game once both are in hand */

        conn.get_proxy.begin<RemoteChessPlayerIface> (TelepathyGLib.CLIENT_BUS_NAME_BASE + "Gnome.Chess", "/org/freedesktop/Telepathy/Client/Gnome/Chess/ChessPlayer/White", DBusProxyFlags.DO_NOT_AUTO_START, null,
            (obj, res)=>{

                try {
                    white = (RemoteChessPlayer) conn.get_proxy.end<RemoteChessPlayerIface> (res);

                    if (white != null && black != null)
                        create_and_add_game (tube, channel_iter, white, black);
                }
                catch (IOError e)
                {
                   debug ("couldn't fetch the white player: %s\n", e.message);
                }
              }
            );

        conn.get_proxy.begin<RemoteChessPlayerIface> (TelepathyGLib.CLIENT_BUS_NAME_BASE + "Gnome.Chess", "/org/freedesktop/Telepathy/Client/Gnome/Chess/ChessPlayer/Black", DBusProxyFlags.DO_NOT_AUTO_START, null,
            (obj, res)=>{

                try {
                    black = (RemoteChessPlayer) conn.get_proxy.end<RemoteChessPlayerIface> (res);

                    if (white != null && black != null)
                        create_and_add_game (tube, channel_iter, white, black);
                }
                catch (IOError e)
                {
                   debug ("couldn't fetch the black player: %s\n", e.message);
                }
              }
            );
    }

    private void create_and_add_game (TelepathyGLib.DBusTubeChannel tube,
        Gtk.TreeIter channel_iter,
        RemoteChessPlayerIface white,
        RemoteChessPlayerIface black)
    {
        /* Create a new game with the offered parameters */
        Variant tube_params = tube.dup_parameters_vardict ();
        bool offerer_white, our_color_white;
        tube_params.lookup ("offerer-white", "b", out offerer_white);
        our_color_white = (tube as TelepathyGLib.Channel).requested ? offerer_white : !offerer_white;
        int32 duration;
        tube_params.lookup ("duration", "i", out duration);

        debug ("Creating a new chess match with our colour:%s and timeout duration:%s",
            our_color_white ? "white" : "black",
            duration > 0 ? duration.to_string () + " seconds" : "no limit");

        var pgn_game = new PGNGame ();
        var now = new DateTime.now_local ();
        var now_UTC = now.to_utc ();
        pgn_game.date = now.format ("%Y.%m.%d");
        pgn_game.time = now.format ("%H:%M:%S");
        pgn_game.utcdate = now_UTC.format ("%Y.%m.%d");
        pgn_game.utctime = now_UTC.format ("%H:%M:%S");
        if (duration > 0)
            pgn_game.time_control = "%d".printf (duration);

        Gtk.ListStore? history_model = null;
        history_model = new Gtk.ListStore (2, typeof (string), typeof (int));
        assert (history_model != null);
        history_model.insert_with_values (null, -1, 0, _("Game Start"), 1, 0);

        string fen = ChessGame.STANDARD_SETUP;
        string[] moves = new string[pgn_game.moves.length ()];
        var i = 0;
        foreach (var move in pgn_game.moves)
            moves[i++] = move;

        if (pgn_game.set_up)
        {
            if (pgn_game.fen != null)
                fen = pgn_game.fen;
            else
                warning ("Chess game has SetUp tag but no FEN tag");
        }

        var game = new ChessGame (fen, moves, (ChessPlayer) white, (ChessPlayer) black);
        (game as Object).set_data<PGNGame> ("pgn-game", pgn_game);
        (game as Object).set_data<string> ("channel-path-string", channels.get_string_from_iter (channel_iter));
        /* Associate history_model for access in scene_changed_cb */
        game.set_data<Gtk.TreeModel> ("history-model", history_model);

        if (pgn_game.time_control != null)
        {
            var controls = pgn_game.time_control.split (":");
            foreach (var control in controls)
            {
                /* We only support simple timeouts */
                var timeout_duration = int.parse (control);
                if (timeout_duration > 0)
                    game.clock = new ChessClock (timeout_duration, timeout_duration);
            }
        }

        game.moved.connect (game_move_cb);
        game.ended.connect (game_end_cb);
        if (game.clock != null)
            game.clock.tick.connect (game_clock_tick_cb);

        ChessScene scene = new ChessScene ();
        scene.changed.connect (scene_changed_cb);
        scene.choose_promotion_type.connect (show_promotion_type_selector);
        scene.game = game;
        settings_common.bind ("show-move-hints", scene, "show-move-hints", SettingsBindFlags.GET);
        settings_common.bind ("show-numbering", scene, "show-numbering", SettingsBindFlags.GET);
        settings_common.bind ("piece-theme", scene, "theme-name", SettingsBindFlags.GET);
        settings_common.bind ("show-3d-smooth", scene, "show-3d-smooth", SettingsBindFlags.GET);
        settings_common.bind ("move-format", scene, "move-format", SettingsBindFlags.GET);
        settings_common.bind ("board-side", scene, "board-side", SettingsBindFlags.GET);

        Gtk.InfoBar info_bar;

        info_bar = new Gtk.InfoBar ();
        var content_area = (Gtk.Container) info_bar.get_content_area ();
        var vbox = new Gtk.Box (Gtk.Orientation.VERTICAL, 6);
        vbox.show ();
        content_area.add (vbox);
        var info_title_label = new Gtk.Label ("");
        info_title_label.show ();
        vbox.pack_start (info_title_label, false, true, 0);
        vbox.hexpand = true;
        vbox.vexpand = false;
        var info_label = new Gtk.Label ("");
        info_label.show ();
        vbox.pack_start (info_label, true, true, 0);

        /* All info-bars are hidden when created with visibility updated as and when needed */
        info_bar.hide ();

        (game as Object).set_data<Gtk.InfoBar> ("info-bar", info_bar);
        (game as Object).set_data<Gtk.Label> ("info-title-label", info_title_label);
        (game as Object).set_data<Gtk.Label> ("info-label", info_label);

        ChessView chess_view;
        if (settings_common.get_boolean ("show-3d"))
            chess_view = new ChessView3D ();
        else
            chess_view = new ChessView2D ();
        chess_view.set_size_request (300, 300);
        /* This connects scene.changed() to a handler that draws view everytime scene changes */
        chess_view.scene = scene;

        (game as Object).set_data<ChessView> ("chess-view", chess_view);

        bool game_needs_saving = false;
        game.start ();

        if (game.result != ChessResult.IN_PROGRESS)
            game_end_cb (game);

        white_time_label.queue_draw ();
        black_time_label.queue_draw ();

        channels.@set (channel_iter,
            ChannelsColumn.OUR_COLOUR_WHITE, our_color_white,
            ChannelsColumn.PGN_GAME, pgn_game,
            ChannelsColumn.HISTORY_MODEL, history_model,
            ChannelsColumn.CHESS_GAME, game,
            ChannelsColumn.CHESS_SCENE, scene,
            ChannelsColumn.INFO_BAR, info_bar,
            ChannelsColumn.GAME_NEEDS_SAVING, game_needs_saving);
    }

    private void register_objects (DBusConnection connection,
        TelepathyGLib.DBusTubeChannel tube,
        Gtk.TreeIter channel_iter,
        string side)
    {
        debug ("Registering objects over dbus connection");

        ChessGame game;
        channels.@get (channel_iter, ChannelsColumn.CHESS_GAME, out game);

        Variant tube_params = tube.dup_parameters_vardict ();
        bool offerer_white = (tube_params.lookup_value ("offerer-white", VariantType.BOOLEAN)).get_boolean ();

        bool play_as_white;
        ChessPlayer my_player;
        if (side == "offerer")
        {
            if (offerer_white)
            {
                my_player = game.white;
                play_as_white = true;
            }
            else
            {
                my_player = game.black;
                play_as_white = false;
            }
        }
        else
        {
            if (offerer_white)
            {
                my_player = game.black;
                play_as_white = false;
            }
            else
            {
                my_player = game.white;
                play_as_white = true;
            }
        }

        try {
            if (play_as_white)
            {
                connection.register_object<RemoteChessPlayer> ("/org/freedesktop/Telepathy/Client/Gnome/Chess/ChessPlayer/White", (RemoteChessPlayer) my_player);
                debug ("White chess player registered");
            }
            else
            {
                connection.register_object<RemoteChessPlayer> ("/org/freedesktop/Telepathy/Client/Gnome/Chess/ChessPlayer/Black", (RemoteChessPlayer) my_player);
                debug ("Black chess player registered");
            }

        } catch (IOError e) {
            debug ("Could not register ChessPlayer object");
        }

    }

    private void offer_tube (TelepathyGLib.DBusTubeChannel tube,
        Gtk.TreeIter channel_iter)
    {
        DBusConnection? connection = null;
        bool play_as_white = settings_common.get_boolean ("play-as-white");
        Value colour_val = play_as_white;
        int32 duration = settings_common.get_int ("duration");
        Value duration_val = duration;

        HashTable<string, Value?>? tube_params = new HashTable<string, Value?> (str_hash, str_equal);
        tube_params.insert ("offerer-white", colour_val);
        tube_params.insert ("duration", duration_val);

        debug ("Offering tube with offerer-white:%s and duration:%ld",
        colour_val.get_boolean () ? "true" : "false", duration_val.get_int ());
        /* This hashtable is purely offerer defined and cast here is the secret gotcha */
        tube.offer_async.begin ((HashTable<void*, void*>?)tube_params,
            (obj, res)=>{
                try
                {
                    connection = tube.offer_async.end (res);
                }
                catch (Error e)
                {
                    debug ("Failed to offer tube to %s: %s",
                        (tube as TelepathyGLib.Channel).target_contact.identifier,
                        e.message);

                    channels.@set (channel_iter,
                        ChannelsColumn.SHOW_STATUS_SCREEN, true,
                        ChannelsColumn.STATUS_MESSAGE, "Failed to offer chess game channel to %s\n The error was: %s", (tube as TelepathyGLib.Channel).target_contact.identifier, e.message);

                    /* Nothing to do */
                    return;
                }

                assert (connection != null);

                debug ("Offered tube opened.");
                connection.notify["closed"].connect (
                    (s, p)=>{
                        debug ("Connection to %s closed unexpectedly",
                            (tube as
                            TelepathyGLib.Channel).target_contact.identifier);
                    }
                );

                /* First load player objects. Then wait on them for creating ChessGame */
                register_objects (connection, tube, channel_iter, "offerer");
                fetch_players (connection, tube, channel_iter);

                /* Now we can display the game */
                channels.@set (channel_iter, ChannelsColumn.CHANNEL_APPROVED, true);

                /* If this is the selected channel, update it's display since it has been approved */
                if (channel_iter == selected_channel_iter)
                    set_game_screen (false);

              }
            );

        /* This offered tube has not yet been approved by remote contact */
        channels.@set (channel_iter, ChannelsColumn.CHANNEL_APPROVED, false);
    }

    private void accept_tube (TelepathyGLib.DBusTubeChannel tube,
        Gtk.TreeIter channel_iter)
    {
        DBusConnection? connection = null;

        debug ("Accepting tube");
        tube.accept_async.begin (
            (obj, res)=>{
                try
                {
                    connection = tube.accept_async.end (res);
                }
                catch (Error e)
                {
                    debug ("Failed to accept tube from %s: %s",
                        (tube as TelepathyGLib.Channel).target_contact.identifier, e.message);

                    channels.@set (channel_iter,
                        ChannelsColumn.SHOW_STATUS_SCREEN, true,
                        ChannelsColumn.STATUS_MESSAGE, "Failed to accept chess game channel from %s\n The error was: %s", (tube as TelepathyGLib.Channel).target_contact.identifier, e.message);

                    /* Nothing to do */
                    return;
                }

                assert (connection != null);

                debug ("Accepted tube opened.");
                connection.notify["closed"].connect (
                    (s, p)=>{
                        debug ("Connection to %s closed unexpectedly",
                            (tube as
                            TelepathyGLib.Channel).target_contact.identifier);
                    }
                );

                /* First load player objects. Then wait on them for creating ChessGame */
                register_objects (connection, tube, channel_iter, "accepter");
                fetch_players (connection, tube, channel_iter);

                /* We can now display the game */
                channels.@set (channel_iter, ChannelsColumn.CHANNEL_APPROVED, true);

                /* If this is the selected channel, update it's display since it has been approved */
                if (channel_iter == selected_channel_iter)
                    set_game_screen (false);

              }
            );

        /* Channels at accepter end are never waiting for approval from anyone
         * but just for accept_async() to finish and call the callback */
        channels.@set (channel_iter, ChannelsColumn.CHANNEL_APPROVED, false);
    }

    private void close_channel (TelepathyGLib.Channel tube)
    {
        debug ("Closing channel.");

        (tube).close_async.begin ((obj, res)=>
            {
                try
                {
                    (tube).close_async.end (res);
                }
                catch (Error e)
                {
                    debug ("Couldn't close the channel: %s", e.message);
                }
            }
            );
    }

    private void tube_invalidated_cb (TelepathyGLib.Proxy tube_channel,
        uint domain,
        int code,
        string message)
    {
        debug ("Tube has been invalidated: %s", message);

        (channels as Gtk.TreeModel).@foreach ((model, path, iter)=>
            {
                TelepathyGLib.Channel stored_tube;
                int64 user_action_time;
                (channels as Gtk.TreeModel).@get (iter, ChannelsColumn.CHANNEL, out stored_tube,
                    ChannelsColumn.USER_ACTION_TIME, out user_action_time);

                if (stored_tube == tube_channel)
                {
                    debug ("Removing chess dbus-tube channel initiated at timeframe %lld with remote player %s",
                        user_action_time, stored_tube.target_contact.identifier);
                    channels.remove (iter);
                    return true;
                }

                return false;
            }
          );
    }

    public void handle_channels (TelepathyGLib.SimpleHandler handler,
        TelepathyGLib.Account account,
        TelepathyGLib.Connection conn,
        List<TelepathyGLib.Channel> channel_bundle,
        List<TelepathyGLib.ChannelRequest> requests,
        int64 action_time,
        TelepathyGLib.HandleChannelsContext context)
    {
        Error error = new TelepathyGLib.Error.NOT_AVAILABLE ("No channel to be handled");

        debug ("Handling channels");

        foreach (TelepathyGLib.Channel tube_channel in channel_bundle)
        {
          Gtk.TreeIter channel_iter;

          if (! (tube_channel is TelepathyGLib.DBusTubeChannel))
            continue;
          if ((tube_channel as TelepathyGLib.DBusTubeChannel).service_name !=
              TelepathyGLib.CLIENT_BUS_NAME_BASE + "Gnome.Chess")
            continue;

          /* Add channel to list of currently handled channels */
          channels.insert_with_values (out channel_iter, -1,
              ChannelsColumn.USER_ACTION_TIME, action_time,
              ChannelsColumn.TARGET_CONTACT, tube_channel.target_contact,
              ChannelsColumn.CHANNEL, tube_channel);

          debug ("Channel inserted into cache. Total channels: %d", channels.iter_n_children (null));

          var target_id = tube_channel.target_contact.identifier;
          if (channel_count.contains (target_id))
              channel_count.@set (target_id, channel_count.@get (target_id) + 1);
          else
              channel_count.insert (target_id, 1);

          debug ("We now hold %d channels with %s", channel_count.@get (target_id), target_id);

          /* If this is the first insertion, set it as selected */
          if (channels.iter_n_children (null) == 1)
              channel_view_selection.select_iter (channel_iter);

          if (tube_channel.requested)
          {
              /* We created this channel. Make a tube offer and wait for approval */
              offer_tube (tube_channel as TelepathyGLib.DBusTubeChannel, channel_iter);
          }
          else
          {
              /* This is an incoming channel request */
              accept_tube (tube_channel as TelepathyGLib.DBusTubeChannel, channel_iter);
          }

          (tube_channel as TelepathyGLib.Proxy).invalidated.connect (
              tube_invalidated_cb);

          context.accept ();
          /* Only one of accept() or fail() can be called on context */
          return;
        }

        debug ("Rejecting channels");
        context.fail (error);

        return;
    }

    public override void activate ()
    {
      if (!is_activated)
      {
          /* Create and register our telepathy client handler as a one-off */

          tp_handler =  new TelepathyGLib.SimpleHandler.with_am (
              TelepathyGLib.AccountManager.dup (),
              true,     /* Bypass approval */
              true,    /* Requests */
              "Gnome.Chess",
              false,    /* Uniquify name */
              handle_channels);

          var filter = new HashTable<string, Value?> (str_hash, str_equal);
          filter.insert (
              TelepathyGLib.PROP_CHANNEL_CHANNEL_TYPE,
              TelepathyGLib.IFACE_CHANNEL_TYPE_DBUS_TUBE);
          filter.insert (
              TelepathyGLib.PROP_CHANNEL_TARGET_HANDLE_TYPE,
              1);
          filter.insert (
              TelepathyGLib.PROP_CHANNEL_TYPE_DBUS_TUBE_SERVICE_NAME,
                TelepathyGLib.CLIENT_BUS_NAME_BASE + "Gnome.Chess");

          (tp_handler as TelepathyGLib.BaseClient).add_handler_filter (filter);

          try {
              (tp_handler as TelepathyGLib.BaseClient).register ();
          }
          catch (Error e) {
              debug ("Failed to register handler: %s", e.message);
          }

          debug ("Waiting for tube offer");

          is_activated = true;
      }

      /* Create and present Handler window */

      create_handler_window ();
      /* Associate the window to this application */
      handler_window.application = this;

      if (settings.get_boolean ("network-window-fullscreen"))
          handler_window.fullscreen ();
      else if (settings.get_boolean ("network-window-maximized"))
          handler_window.maximize ();

      handler_window.resize (settings.get_int ("network-window-width"),
          settings.get_int ("network-window-height"));

      handler_window.show_all ();

      handler_window.present ();
    }

    [CCode (cname = "G_MODULE_EXPORT network_window_configure_event_cb", instance_pos = -1)]
    public bool network_window_configure_event_cb (Gtk.Widget widget, Gdk.EventConfigure event)
    {
        if (!settings.get_boolean ("network-window-maximized") &&
            !settings.get_boolean ("network-window-fullscreen"))
        {
            settings.set_int ("network-window-width", event.width);
            settings.set_int ("network-window-height", event.height);
        }

        return false;
    }

    [CCode (cname = "G_MODULE_EXPORT network_window_window_state_event_cb", instance_pos = -1)]
    public bool network_window_window_state_event_cb (Gtk.Widget widget, Gdk.EventWindowState event)
    {
        if ((event.changed_mask & Gdk.WindowState.MAXIMIZED) != 0)
        {
            var is_maximized = (event.new_window_state & Gdk.WindowState.MAXIMIZED) != 0;
            settings.set_boolean ("network-window-maximized", is_maximized);
        }
        if ((event.changed_mask & Gdk.WindowState.FULLSCREEN) != 0)
        {
            bool is_fullscreen = (event.new_window_state & Gdk.WindowState.FULLSCREEN) != 0;
            settings.set_boolean ("network-window-fullscreen", is_fullscreen);
            fullscreen_menu.label = is_fullscreen ? Gtk.Stock.LEAVE_FULLSCREEN : Gtk.Stock.FULLSCREEN;
        }

        return false;
    }



    [CCode (cname = "G_MODULE_EXPORT new_game_cb", instance_pos = -1)]
    private new void new_game_cb (Gtk.Widget widget)
    {
    }

}


