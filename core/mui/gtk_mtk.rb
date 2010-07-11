# -*- coding:utf-8 -*-

require 'gtk2'

module Mtk
  def self.adjustment(name, config, min, max)
    container = Gtk::HBox.new(false, 0)
    container.pack_start(Gtk::Label.new(name), false, true, 0)
    adj = Gtk::Adjustment.new((UserConfig[config] or min), min*1.0, max*1.0, 1.0, 5.0, 0.0)
    spinner = Gtk::SpinButton.new(adj, 0, 0)
    spinner.wrap = true
    adj.signal_connect('value-changed'){ |widget, e|
      UserConfig[config] = widget.value.to_i
      false
    }
    container.pack_start(Gtk::Alignment.new(1.0, 0.5, 0, 0).add(spinner), true, true, 0)
  end

  def self.chooseone(label, config_key, values)
    container = Gtk::HBox.new(false, 0)
    input = Gtk::ComboBox.new(true)
    values.keys.sort.each{ |key|
      input.append_text(values[key])
    }
    input.signal_connect('changed'){ |widget|
      Gtk::Lock.synchronize do
        UserConfig[config_key] = values.keys.sort[widget.active]
      end
    }
    input.active = values.keys.sort.index((UserConfig[config_key] or 0))
    container.pack_start(Gtk::Label.new(label), false, true, 0)
    container.pack_start(Gtk::Alignment.new(1.0, 0.5, 0, 0).add(input), true, true, 0)
    return container
  end

  def self.boolean(key, label)
    if key.respond_to?(:call)
      proc = key
    else
      proc = lambda{ |new|
        if new === nil
          UserConfig[key]
        else
          UserConfig[key] = new end } end
    input = Gtk::CheckButton.new(label)
    input.signal_connect('toggled'){ |widget|
      proc.call(*[widget.active?, widget][0, proc.arity]) }
    input.active = proc.call(*[nil, input][0, proc.arity])
    return input
  end

  def self.default_or_custom(key, title, default_label, custom_label)
    group = default = Gtk::RadioButton.new(default_label)
    custom = Gtk::RadioButton.new(group, custom_label)
    input = Gtk::Entry.new
    default.active = !(input.sensitive = custom.active = UserConfig[key])
    default.signal_connect('toggled'){ |widget|
      UserConfig[key] = nil
      input.sensitive = !widget.active?
    }
    custom.signal_connect('toggled'){ |widget|
      UserConfig[key] = input.text
      input.sensitive = widget.active?
    }
    input.signal_connect('changed'){ |widget|
      UserConfig[key] = widget.text
    }
    self.group(title, default, Gtk::HBox.new(false, 0).add(custom).add(input))
  end

  def self.input(key, label, visibility=true, &callback)
    if key.respond_to?(:call)
      proc = key
    else
      proc = lambda{ |new|
        if new
          UserConfig[key] = new
        else
          UserConfig[key].to_s end } end
    container = Gtk::HBox.new(false, 0)
    input = Gtk::Entry.new
    input.text = proc.call(nil)
    input.visibility = visibility
    container.pack_start(Gtk::Label.new(label), false, true, 0)
    container.pack_start(Gtk::Alignment.new(1.0, 0.5, 0, 0).add(input), true, true, 0)
    input.signal_connect('changed'){ |widget|
      proc.call(widget.text) }
    callback.call(container, input) if block_given?
    return container
  end

  def self.keyconfig(title, key)
    keyconfig = Gtk::KeyConfig.new(title, UserConfig[key])
    container = Gtk::HBox.new(false, 0)
    container.pack_start(Gtk::Label.new(title), false, true, 0)
    container.pack_start(keyconfig, true, true, 0)
    keyconfig.change_hook = lambda{ |keycode|
      UserConfig[key] = keycode
    }
    return container
  end

  def self.group(title, *children)
    group = Gtk::Frame.new(title).set_border_width(8)
    box = Gtk::VBox.new(false, 0).set_border_width(4)
    group.add(box)
    children.each{ |w|
      box.pack_start(w, false)
    }
    group
  end

  def self.expander(title, expanded, *children)
    group = Gtk::Expander.new(title).set_border_width(8)
    group.expanded = expanded
    box = Gtk::VBox.new(false, 0).set_border_width(4)
    group.add(box)
    children.each{ |w|
      box.pack_start(w, false)
    }
    group
  end

  def self.fileselect(key, label, current=Dir.pwd)
    container = input = nil
    self.input(key, label){ |c, i|
      container = c
      input = i }
    button = Gtk::Button.new('参照')
    container.pack_start(button, false)
    button.signal_connect('clicked'){ |widget|
      dialog = Gtk::FileChooserDialog.new("Open File",
                                          widget.get_ancestor(Gtk::Window),
                                          Gtk::FileChooser::ACTION_OPEN,
                                          nil,
                                          [Gtk::Stock::CANCEL, Gtk::Dialog::RESPONSE_CANCEL],
                                          [Gtk::Stock::OPEN, Gtk::Dialog::RESPONSE_ACCEPT])
      dialog.current_folder = File.expand_path(current)
      if dialog.run == Gtk::Dialog::RESPONSE_ACCEPT
        UserConfig[key] = dialog.filename
        input.text = dialog.filename
      end
      dialog.destroy
    }
    container
  end

  def self._colorselect(key, label)
    color = UserConfig[key]
    button = Gtk::ColorButton.new((color and Gdk::Color.new(*color)))
    button.title = label
    button.signal_connect('color-set'){ |w|
      UserConfig[key] = w.color.to_a }
    button end

  def self._fontselect(key, label)
    button = Gtk::FontButton.new(UserConfig[key])
    button.title = label
    button.signal_connect('font-set'){ |w|
      UserConfig[key] = w.font_name }
    button end

  def self.fontselect(key, label)
    Gtk::HBox.new(false, 0).add(Gtk::Label.new(label).left).closeup(_fontselect(key, label))
  end

  def self.colorselect(key, label)
    Gtk::HBox.new(false, 0).add(Gtk::Label.new(label).left).closeup(_colorselect(key, label))
  end

  def self.fontcolorselect(font, color, label)
    self.fontselect(font, label).closeup(_colorselect(color, label))
  end

  def self.accountdialog_button(label, kuser, lvuser,  kpasswd, lvpasswd, &validator)
    btn = Gtk::Button.new(label)
    btn.signal_connect('clicked'){
      self.account_dialog(label, kuser, lvuser,  kpasswd, lvpasswd, &validator) }
    btn
  end

  def self.account_dialog_inner(kuser, lvuser,  kpasswd, lvpasswd, cancel=true)
    def entrybox(label, visibility=true, default="")
      container = Gtk::HBox.new(false, 0)
      input = Gtk::Entry.new
      input.text = default
      input.visibility = visibility
      container.pack_start(Gtk::Label.new(label), false, true, 0)
      container.pack_start(Gtk::Alignment.new(1.0, 0.5, 0, 0).add(input), true, true, 0)
      return container, input
    end
    box = Gtk::VBox.new(false, 8)
    user, user_input = entrybox(lvuser, true, (UserConfig[kuser] or ""))
    pass, pass_input = entrybox(lvpasswd, false)
    return box.closeup(user).closeup(pass), user_input, pass_input
  end

  def self.adi(symbol, label)
    input(lambda{ |new| UserConfig[symbol] }, label){ |c, i| yield(i) } end

  def self.account_dialog(label, kuser, lvuser,  kpasswd, lvpasswd, cancel=true, &validator)
    alert_thread = if(Thread.main != Thread.current) then Thread.current end
    dialog = Gtk::Dialog.new(label)
    dialog.window_position = Gtk::Window::POS_CENTER
    iuser = ipass = nil
    container = Gtk::VBox.new(false, 8).
      closeup(adi(kuser, lvuser){ |i| iuser = i }).
      closeup(adi(kpasswd, lvpasswd){ |i| ipass = i })
    dialog.vbox.pack_start(container, true, true, 30)
    dialog.add_button(Gtk::Stock::OK, Gtk::Dialog::RESPONSE_OK)
    dialog.add_button(Gtk::Stock::CANCEL, Gtk::Dialog::RESPONSE_CANCEL) if cancel
    dialog.default_response = Gtk::Dialog::RESPONSE_OK
    quit = lambda{
      dialog.hide_all.destroy
      Gtk.main_iteration_do(false)
      Gtk::Window.toplevels.first.show
      if alert_thread
        alert_thread.run
      else
        Gtk.main_quit
      end }
    dialog.signal_connect("response"){ |widget, response|
      if response == Gtk::Dialog::RESPONSE_OK
        if validator.call(iuser.text, ipass.text)
          UserConfig[kuser] = iuser.text
          UserConfig[kpasswd] = ipass.text
          quit.call
        else
          alert("#{lvuser}か#{lvpasswd}が違います")
        end
      elsif (cancel and response == Gtk::Dialog::RESPONSE_CANCEL) or
          response == Gtk::Dialog::RESPONSE_DELETE_EVENT
        quit.call
      end }
    dialog.signal_connect("destroy") {
      false
    }
    container.show
    dialog.show_all
    Gtk::Window.toplevels.first.hide
    if(alert_thread)
      Thread.stop
    else
      Gtk::main
    end
  end

  def self.alert(message)
    dialog = Gtk::MessageDialog.new(nil,
                                    Gtk::Dialog::DESTROY_WITH_PARENT,
                                    Gtk::MessageDialog::QUESTION,
                                    Gtk::MessageDialog::BUTTONS_CLOSE,
                                    message)
    dialog.run
    dialog.destroy
  end

end