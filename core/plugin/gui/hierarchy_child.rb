# -*- coding: utf-8 -*-
# ウィンドウパーツ階層構造の子

module Plugin::GUI::HierarchyChild

  class << self
    def included(klass)
      klass.extend(Extended)
    end
  end

  attr_reader :parent

  # 親を _parent_ に設定
  # ==== Args
  # [parent] 親
  # ==== Return
  # self
  def set_parent(parent)
    type_strict parent => @parent_class
    return self if @parent == parent
    @parent.remove(self) if @parent
    @parent = parent
    self end

  def active_class_of(klass)
    self if is_a? klass end

  module Extended
    attr_reader :parent_class

    # 親クラスを設定する。親にはこのクラスのインスタンス以外認めない
    # ==== Args
    # [klass] 親クラス
    def set_parent_class(klass)
      @parent_class = klass end

    # 親クラスを再帰的にたどっていって、一番上の親クラスを返す
    def ancestor
      if @parent_class.respond_to? :ancestor
        @parent_class.ancestor
      else
        @parent_class end end

    # 現在アクティブなインスタンスを返す
    # ==== Return
    # アクティブなインスタンス又はnil
    def active
      widget = ancestor.active
      widget.active_class_of(self) if widget end
  end

end