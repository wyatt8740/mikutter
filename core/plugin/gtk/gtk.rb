# -*- coding: utf-8 -*-

# RubyGnome2を用いてUIを表示するプラグイン

require "gtk2"
require File.expand_path File.join(File.dirname(__FILE__), 'mikutter_window')
require File.expand_path File.join(File.dirname(__FILE__), 'tab_container')

Plugin.create :gtk do
  @windows_by_slug = {}                  # slug => Gtk::MikutterWindow
  @panes_by_slug = {}                    # slug => Gtk::NoteBook
  @tabs_by_slug = {}                     # slug => Gtk::EventBox
  @timelines_by_slug = {}                # slug => Gtk::TimeLine
  @profiles_by_slug = {}                    # slug => Gtk::NoteBook
  @profiletabs_by_slug = {}                     # slug => Gtk::EventBox
  @tabchildwidget_by_slug = {}           # slug => Gtk::TabChildWidget
  @postboxes_by_slug = {}                # slug => Gtk::Postbox
  @tabs_promise = {}                     # slug => Deferred

  TABPOS = [Gtk::POS_TOP, Gtk::POS_BOTTOM, Gtk::POS_LEFT, Gtk::POS_RIGHT]

  # ウィンドウ作成。
  # PostBoxとか複数のペインを持つための処理が入るので、Gtk::MikutterWindowクラスを新設してそれを使う
  on_window_created do |i_window|
    notice "create window #{i_window.slug.inspect}"
    window = Gtk::MikutterWindow.new
    @windows_by_slug[i_window.slug] = window
    window.title = i_window.name
    window.set_size_request(240, 240)
    geometry = get_window_geometry(i_window.slug)
    window.set_default_size(*geometry[:size])
    window.move(*geometry[:position])
    window.signal_connect("destroy"){
      Delayer.freeze
      window.destroy
      Gtk::Object.main_quit
      # Gtk.main_quit
      false }
    window.ssc(:focus_in_event) {
      i_window.active!
      false
    }
    window.ssc('key_press_event'){ |widget, event|
      Plugin::GUI.keypress(Gtk::keyname([event.keyval ,event.state]), i_window) }
    window.show_all
  end

  # ペイン作成。
  # ペインはGtk::NoteBook
  on_pane_created do |i_pane|
    pane = create_pane(i_pane)
    pane.set_tab_border(0).set_group_id(0).set_scrollable(true)
    pane.set_tab_pos(TABPOS[UserConfig[:tab_position]])
    tab_position_hook_id = UserConfig.connect(:tab_position){ |key, val, before_val, id|
      notice "change tab pos to #{TABPOS[val]}"
      pane.set_tab_pos(TABPOS[val]) unless pane.destroyed? }
    pane.ssc(:page_reordered){ |this|
      notice "on_pane_created: page_reordered: #{i_pane.inspect}"
      window_order_save_request(i_pane.parent)
      false }
    pane.signal_connect(:page_added){ |this, tabcontainer|
      type_strict tabcontainer => Gtk::TabContainer
      notice "on_pane_created: page_added: #{i_pane.inspect}"
      window_order_save_request(i_pane.parent)
      i_tab = tabcontainer.i_tab
      next false if i_tab.parent == i_pane
      notice "on_pane_created: reparent"
      i_pane << i_tab
      false }
    # 子が無くなった時 : このpaneを削除
    pane.signal_connect(:page_removed){
      notice "on_pane_created: page_removed: #{i_pane.inspect}"
      Delayer.new{
        unless pane.destroyed?
          if pane.children.empty? and pane.parent
            UserConfig.disconnect(tab_position_hook_id)
            pane_order_delete(i_pane)
            pane.parent.remove(pane)
            window_order_save_request(i_pane.parent) end end }
      false }
  end

  # タブ作成。
  # タブには実体が無いので、タブのアイコンのところをGtk::EventBoxにしておいて、それを実体ということにしておく
  on_tab_created do |i_tab|
    tab = create_tab(i_tab)
    if @tabs_promise[i_tab.slug]
      @tabs_promise[i_tab.slug].call(tab)
      @tabs_promise.delete(i_tab.slug) end end

  on_profile_created do |i_profile|
    create_pane(i_profile) end

  on_profiletab_created do |i_profiletab|
    create_tab(i_profiletab) end

  # タブを作成する
  # ==== Args
  # [i_tab] タブ
  # ==== Return
  # Tab(Gtk::EventBox)
  def create_tab(i_tab)
    notice "create tab #{i_tab.slug.inspect}"
    tab = Gtk::EventBox.new.tooltip(i_tab.name)
    if i_tab.is_a? Plugin::GUI::Tab
      @tabs_by_slug[i_tab.slug] = tab
    elsif i_tab.is_a? Plugin::GUI::ProfileTab
      @profiletabs_by_slug[i_tab.slug] = tab end
    tab_update_icon(i_tab)
    tab.ssc(:focus_in_event) {
      i_tab.active!
      false
    }
    tab.ssc(:key_press_event){ |widget, event|
      Plugin::GUI.keypress(Gtk::keyname([event.keyval ,event.state]), i_tab) }
    tab.ssc(:button_press_event) { |this, e|
      if e.button == 3
        Plugin::GUI::Command.menu_pop(i_tab) end
      false }
    tab.ssc(:destroy){
      Plugin.call(:gui_destroy, i_tab)
      false }
    tab.show_all end

  # タイムライン作成。
  # Gtk::TimeLine
  on_timeline_created do |i_timeline|
    notice "create timeline #{i_timeline.slug.inspect}"
    timeline = Gtk::TimeLine.new
    @timelines_by_slug[i_timeline.slug] = timeline
    focus_in_event = lambda { |this, event|
      #notice "active set to #{i_timeline}"
      i_timeline.active!
      false }
    destroy_event = lambda{ |this|
      if not(timeline.tl.destroyed?) and this != timeline.tl
        timeline.tl.ssc(:focus_in_event, &focus_in_event)
        timeline.tl.ssc(:destroy, &destroy_event) end
      false }
    timeline.tl.ssc(:focus_in_event, &focus_in_event)
    timeline.tl.ssc(:destroy, &destroy_event)
    timeline.ssc('key_press_event'){ |widget, event|
      Plugin::GUI.keypress(Gtk::keyname([event.keyval ,event.state]), i_timeline) }
    timeline.ssc(:destroy){
      Plugin.call(:gui_destroy, i_timeline)
      false }
    timeline.show_all
  end

  on_gui_pane_join_window do |i_pane, i_window|
    puts "gui_pane_join_window #{i_pane.slug.inspect}, #{i_window.slug.inspect}"
    window = widgetof(i_window)
    pane = widgetof(i_pane)
    if pane.parent
      if pane.parent != window.panes
        notice "pane parent already exists. removing"
        pane.parent.remove(pane)
        notice "packing"
        window.panes.pack_end(pane, false).show_all
        notice "done" end
    else
      notice "pane doesn't have a parent"
      window.panes.pack_end(pane, false).show_all
    end
  end

  on_gui_tab_join_pane do |i_tab, i_pane|
    notice "gui_tab_join_pane(#{i_tab}, #{i_pane})"
    i_widget = i_tab.children.first
    notice "#{i_tab} children #{i_tab.children}"
    next if not i_widget
    widget = widgetof(i_widget)
    notice "widget: #{widget}"
    next if not widget
    tab = widgetof(i_tab)
    pane = widgetof(i_pane)
    old_pane = widget.get_ancestor(Gtk::Notebook)
    notice "pane: #{pane}, old_pane: #{old_pane}"
    if pane and old_pane and pane != old_pane
      notice "#{widget} removes by #{old_pane}"
      old_pane.remove_page(old_pane.page_num(widget))
      if tab.parent
        page_num = tab.parent.get_tab_pos_by_tab(tab)
        if page_num
          tab.parent.remove_page(page_num)
        else
          raise Plugin::Gtk::GtkError, "#{tab} not found in #{tab.parent}" end end
      notice "#{widget} pack to #{tab}"
      i_tab.children.each{ |i_child|
        w_child = widgetof(i_child)
        w_child.parent.remove(w_child)
        widget_join_tab(i_tab, w_child) }
      tab.show_all end
    window_order_save_request(i_pane.parent)
  end

  on_gui_timeline_join_tab do |i_timeline, i_tab|
    widget_join_tab(i_tab, widgetof(i_timeline)) end

  on_gui_profile_join_tab do |i_profile, i_tab|
    widget_join_tab(i_tab, widgetof(i_profile)) end

  on_gui_timeline_add_messages do |i_timeline, messages|
    gtk_timeline = widgetof(i_timeline)
    gtk_timeline.add(messages) if gtk_timeline and not gtk_timeline.destroyed? end

  on_gui_postbox_join_widget do |i_postbox|
    notice "create postbox #{i_postbox.slug.inspect}"
    postbox = @postboxes_by_slug[i_postbox.slug] = widgetof(i_postbox.parent).add_postbox(i_postbox)
    postbox.post.ssc(:focus_in_event) {
      i_postbox.active!
      false }
    postbox.post.ssc('key_press_event'){ |widget, event|
      Plugin::GUI.keypress(Gtk::keyname([event.keyval ,event.state]), i_postbox) }
    postbox.post.ssc(:destroy){
      Plugin.call(:gui_destroy, i_postbox)
      false }
  end

  on_gui_tab_change_icon do |i_tab|
    tab_update_icon(i_tab) end

  on_gui_contextmenu do |event, contextmenu|
    widget = widgetof(event.widget)
    if not widget.destroyed?
      Gtk::ContextMenu.new(*contextmenu).popup(widget, event) end end

  on_gui_timeline_move_cursor_to do |i_timeline, message|
    tl = widgetof(i_timeline)
    path, column = tl.cursor
    if path and column
      case message
      when :prev
        path.prev!
        tl.set_cursor(path, column, false)
      when :next
        path.next!
        tl.set_cursor(path, column, false)
      end
    end
  end

  on_gui_postbox_post do |i_postbox|
    postbox = widgetof(i_postbox)
    if postbox
      postbox.post_it end end

  on_gui_destroy do |i_widget|
    widget = widgetof(i_widget)
    if widget and not widget.destroyed?
      if i_widget.is_a? Plugin::GUI::Tab
        pane = widgetof(i_widget.parent)
        pane.n_pages.times{ |pagenum|
          if widget == pane.get_tab_label(pane.get_nth_page(pagenum))
            pane.remove_page(pagenum)
            break end }
      else
        widget.parent.remove(widget)
        widget.destroy end end end

  # 互換性のため
  on_mui_tab_regist do |container, name, icon|
    slug = name.to_sym
    i_tab = Plugin::GUI::Tab.instance(slug, name)
    i_tab.set_icon(icon).expand
    i_container = Plugin::GUI::TabChildWidget.instance
    @tabchildwidget_by_slug[i_container.slug] = container
    i_tab << i_container
    @tabs_promise[i_tab.slug] = (@tabs_promise[i_tab.slug] || Deferred.new).next{ |tab|
      widget_join_tab(i_tab, container.show_all) } end

  # Gtkオブジェクトをタブに入れる
  on_gui_nativewidget_join_tab do |i_tab, i_container, container|
    notice "nativewidget: #{container} => #{i_tab}"
    @tabchildwidget_by_slug[i_container.slug] = container
    widget_join_tab(i_tab, container.show_all) end

  on_gui_nativewidget_join_profiletab do |i_profiletab, i_container, container|
    notice "nativewidget: #{container} => #{i_profiletab}"
    @tabchildwidget_by_slug[i_container.slug] = container
    widget_join_tab(i_profiletab, container.show_all) end

  on_gui_window_rewindstatus do |i_window, text, expire|
    statusbar = @windows_by_slug[:default].statusbar
    cid = statusbar.get_context_id("system")
    mid = statusbar.push(cid, text)
    if expire != 0
      Reserver.new(expire){
        if not statusbar.destroyed?
          statusbar.remove(cid, mid) end } end end

  filter_gui_postbox_input_editable do |i_postbox, editable|
    postbox = widgetof(i_postbox)
    [i_postbox, postbox && postbox.post.editable?] end

  filter_gui_timeline_selected_messages do |i_timeline, messages|
    [i_timeline, messages + widgetof(i_timeline).get_active_messages] end

  filter_gui_timeline_selected_text do |i_timeline, message, text|
    timeline = widgetof(i_timeline)
    next [i_timeline, message, text] if not timeline
    record = timeline.get_record_by_message(message)
    next [i_timeline, message, text] if not record
    range = record.miracle_painter.textselector_range
    next [i_timeline, message, text] if not range
    [i_timeline, message, message.entity.to_s[range]]
  end

  filter_gui_destroyed do |i_widget|
    if i_widget.is_a? Plugin::GUI::Widget
      [widgetof(i_widget).destroyed?]
    else
      [i_widget] end end

  filter_gui_get_gtk_widget do |i_widget|
    [widgetof(i_widget)] end

  # タブ _tab_ に _widget_ を入れる
  # ==== Args
  # [i_tab] タブ
  # [widget] Gtkウィジェット
  def widget_join_tab(i_tab, widget)
    return false if not(widgetof(i_tab))
    i_pane = i_tab.parent
    pane = widgetof(i_pane)
    tab = widgetof(i_tab)
    notice "widget_join_tab: #{widget} join #{i_tab}"
    container_index = pane.get_tab_pos_by_tab(tab)
    if container_index
      container = pane.get_nth_page(container_index)
      if container
        return container.pack_start(widget, i_tab.pack_rule[container.children.size]) end end
    if tab.parent
      raise Plugin::Gtk::GtkError, "Gtk Widget #{widgetof(i_tab).inspect} of Tab(#{i_tab.slug.inspect}) has parent Gtk Widget #{tab.parent.inspect}" end
    container = Gtk::TabContainer.new(i_tab).show_all
    container.pack_start(widget, i_tab.pack_rule[container.children.size])
    index = i_pane.children.find_index{ |child| child.slug == i_tab.slug } || i_pane.children.size
    pane.insert_page_menu(index, container, tab)
    pane.set_tab_reorderable(container, true).set_tab_detachable(container, true)
    true end

  def tab_update_icon(i_tab)
    type_strict i_tab => Plugin::GUI::TabLike
    tab = widgetof(i_tab)
    tab.remove(tab.child) if tab.child
    if i_tab.icon.is_a?(String)
      tab.add(Gtk::WebIcon.new(i_tab.icon, 24, 24).show)
    else
      tab.add(Gtk::Label.new(i_tab.name).show) end
    self end

  def get_window_geometry(slug)
    type_strict slug => Symbol
    geo = at(:windows_geometry, {})
    if geo[slug]
      geo[slug]
    else
      size = [Gdk.screen_width/3, Gdk.screen_height*4/5]
      { size: size,
        position: [Gdk.screen_width - size[0], Gdk.screen_height/2 - size[1]/2] } end end

  # ペインを作成
  # ==== Args
  # [i_pane] ペイン
  # ==== Return
  # ペイン(Gtk::Notebook)
  def create_pane(i_pane)
    notice "create pane #{i_pane.slug.inspect}"
    pane = Gtk::Notebook.new
    if i_pane.is_a? Plugin::GUI::Pane
      @panes_by_slug[i_pane.slug] = pane
    elsif i_pane.is_a? Plugin::GUI::Profile
      @profiles_by_slug[i_pane.slug] = pane end
    pane.ssc('key_press_event'){ |widget, event|
      Plugin::GUI.keypress(Gtk::keyname([event.keyval ,event.state]), i_pane) }
    pane.ssc(:destroy){
      Plugin.call(:gui_destroy, i_pane)
      false }
    pane.show_all end

  # ウィンドウ内のペイン、タブの現在の順序を設定に保存する
  # ==== Args
  # [i_window] ウィンドウ
  def window_order_save_request(i_window)
    type_strict i_window => Plugin::GUI::Window
    notice "window_order_save_request: #{i_window.inspect}"
    Delayer.new do
      ui_tab_order = (UserConfig[:ui_tab_order] || {}).melt
      panes_order = {}
      i_window.children.each{ |i_pane|
        if i_pane.is_a? Plugin::GUI::Pane
          tab_order = []
          pane = widgetof(i_pane)
          pane.n_pages.times{ |page_num|
            i_widget = find_implement_widget_by_gtkwidget(pane.get_tab_label(pane.get_nth_page(page_num)))
            tab_order << i_widget.slug if i_widget }
          ui_tab_order[i_window.slug] = (ui_tab_order[i_window.slug] || {}).melt
          panes_order[i_pane.slug] = tab_order end }
      ui_tab_order[i_window.slug] = panes_order
      UserConfig[:ui_tab_order] = ui_tab_order
    end
  end

  # ペインを順序リストから削除する
  # ==== Args
  # [i_pane] ペイン
  def pane_order_delete(i_pane)
    order = UserConfig[:ui_tab_order].melt
    i_window = i_pane.parent
    order[i_window.slug] = order[i_window.slug].melt
    order[i_window.slug].delete(i_pane.slug)
    # UserConfig[:ui_tab_order] = order
  end

  # _cuscadable_ に対応するGtkオブジェクトを返す
  # ==== Args
  # [cuscadable] ウィンドウ、ペイン、タブ、タイムライン等
  # ==== Return
  # 対応するGtkオブジェクト
  def widgetof(cuscadable)
    type_strict cuscadable => :slug
    collection = if cuscadable.is_a? Plugin::GUI::Window
                   @windows_by_slug
                 elsif cuscadable.is_a? Plugin::GUI::Pane
                   @panes_by_slug
                 elsif cuscadable.is_a? Plugin::GUI::Tab
                   @tabs_by_slug
                 elsif cuscadable.is_a? Plugin::GUI::Profile
                   @profiles_by_slug
                 elsif cuscadable.is_a? Plugin::GUI::ProfileTab
                   @profiletabs_by_slug
                 elsif cuscadable.is_a? Plugin::GUI::Timeline
                   @timelines_by_slug
                 elsif cuscadable.is_a? Plugin::GUI::TabChildWidget
                   @tabchildwidget_by_slug
                 elsif cuscadable.is_a? Plugin::GUI::Postbox
                   @postboxes_by_slug end
    collection[cuscadable.slug]
  end

  # Gtkオブジェクト _widget_ に対応するウィジェットのオブジェクトを返す
  # ==== Args
  # [widget] Gtkウィジェット
  # ==== Return
  # _widget_ に対応するウィジェットオブジェクトまたは偽
  def find_implement_widget_by_gtkwidget(widget)
    type_strict widget => Gtk::Widget
    [
     [@windows_by_slug, Plugin::GUI::Window],
     [@panes_by_slug, Plugin::GUI::Pane],
     [@tabs_by_slug, Plugin::GUI::Tab],
     [@panes_by_slug, Plugin::GUI::Profile],
     [@tabs_by_slug, Plugin::GUI::ProfileTab],
     [@timelines_by_slug, Plugin::GUI::Timeline],
     [@tabchildwidget_by_slug, Plugin::GUI::TabChildWidget],
     [@postboxes_by_slug, Plugin::GUI::Postbox] ].each{ |collection, klass|
      slug, node = *collection.find{ |slug, node|
        node == widget }
      if slug
        return klass.instance(slug) end }
    false end
end

module Plugin::Gtk
  class GtkError < Exception
  end end