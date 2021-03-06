#
#   ae-search-in-files.rb - Arcadia Ruby ide
#   by Antonio Galeone <antonio-galeone@rubyforge.org>
#

class SearchInFilesService < ArcadiaExt

  def on_before_build(_event)
    Arcadia.attach_listener(SearchInFilesListener.new(self),SearchInFilesEvent)
  end

end


class SearchInFilesListener
  def initialize(_service)
    @service = _service
    create_find
  end

  def on_before_search_in_files(_event)
    if _event.what.nil?
      @find.show
    end
  end
  
  #def on_search_in_files(_event)
    #Arcadia.new_msg(self, "... ti ho fregato!")
  #end

  #def on_after_search_in_files(_event)
  #end
  
  def create_find
    @find = FindFrame.new(@service.arcadia.layout.root)
    @find.on_close=proc{@find.hide}
    @find.hide
    @find.b_go.bind('1', proc{Thread.new{do_find}})
    @find.e_what_entry.bind_append('KeyRelease'){|e|
      case e.keysym
      when 'Return'
        do_find
        Tk.callback_break
      end
    }
    @find.title("Search in files")
  end
  private :create_find
  
  def do_find
    return if @find.e_what.text.strip.length == 0  || @find.e_filter.text.strip.length == 0  || @find.e_dir.text.strip.length == 0
    @find.hide
    if !defined?(@search_output)
      @search_output = SearchOutput.new(@service)
    else
      @service.frame.show
    end
    begin
      _search_title = 'search result for : "'+@find.e_what.text+'" in :"'+@find.e_dir.text+'"'+' ['+@find.e_filter.text+']'
      _filter = @find.e_dir.text+'/**/'+@find.e_filter.text
      _files = Dir[_filter]
      _node = @search_output.new_result(_search_title, _files.length)
      progress_stop=false
      @progress_bar = TkProgressframe.new(@service.arcadia.layout.root, _files.length)		  
      @progress_bar.title('Searching')
      @progress_bar.on_cancel=proc{progress_stop=true}
      #@progress_bar.on_cancel=proc{cancel}
      pattern = Regexp.new(@find.e_what.text)
      _files.each do |_filename|
          File.open(_filename) do |file|
            file.grep(pattern) do |line|
              @search_output.add_result(_node, _filename, file.lineno.to_s, line)
              break if progress_stop
            end
          end
          @progress_bar.progress
          break if progress_stop
      end
    rescue Exception => e
      Arcadia.console(self, 'msg'=>e.message, 'level'=>'error')
      #Arcadia.new_error_msg(self, e.message)
    ensure
      @progress_bar.destroy
    end

  end
  
  
end

class SearchOutput
  def initialize(_ext)
    @sequence = 0
    @ext = _ext
    left_frame = TkFrame.new(@ext.frame.hinner_frame, Arcadia.style('panel')).place('x' => '0','y' => '0','relheight' => '1','width' => '25')
    #right_frame = TkFrame.new(@ext.frame).place('x' => '25','y' => '0','relwidth' => '1', 'relheight' => '1', 'width' => '-25')
    @results = {}
    _open_file = proc do |tree, sel|
      n_parent, n = sel.split('@@@')
      Arcadia.process_event(OpenBufferEvent.new(self,'file'=>@results[n_parent][n][0], 'row'=>@results[n_parent][n][1]))  if n && @results[n_parent][n]
      #EditorContract.instance.open_file(self, 'file'=>@results[n_parent][n][0], 'line'=>@results[n_parent][n][1]) if n && @results[n_parent][n]
    end

    @tree = Tk::BWidget::Tree.new(@ext.frame.hinner_frame, Arcadia.style('treepanel')){
      #background '#FFFFFF'
      #relief 'flat'
      #showlines true
      #linesfill '#e7de8f'
      selectcommand _open_file 
      deltay 15
    }.place('x' => '25','y' => '0','relwidth' => '1', 'relheight' => '1', 'width' => '-40', 'height'=>'-15')
    #---- y scrollbar
    _yscrollcommand = proc{|*args| @tree.yview(*args)}
    _yscrollbar = TkScrollbar.new(@ext.frame.hinner_frame, Arcadia.style('scrollbar')){|s|
      #width 8
      command _yscrollcommand
    }.pack('side'=>'right', 'fill'=>'y')
    @tree.yscrollcommand proc{|first,last| _yscrollbar.set(first,last)}
    #---- x scrollbar
    _xscrollcommand = proc{|*args| @tree.xview(*args)}
    _xscrollbar = TkScrollbar.new(@ext.frame.hinner_frame, Arcadia.style('scrollbar')){|s|
      #width 8
      orient 'horizontal'
      command _xscrollcommand
    }.pack('side'=>'bottom', 'fill'=>'x')
    @tree.xscrollcommand proc{|first,last| _xscrollbar.set(first,last)}
    
    _proc_clear = proc{clear_tree}
    
    @button_u = Tk::BWidget::Button.new(left_frame, Arcadia.style('toolbarbutton')){
      image  TkPhotoImage.new('dat' => CLEAR_GIF)
      helptext 'Clear'
      foreground 'blue'
      command _proc_clear
      relief 'groove'
      pack('side' =>'top', 'anchor'=>'n',:padx=>0, :pady=>0)
    }
    
#    @found_color='#3f941b'
#    @not_found_color= 'red'
#    @item_color='#6fc875'
    @found_color=Arcadia.conf('hightlight.5.foreground')
    @not_found_color= Arcadia.conf('hightlight.6.foreground')
    @item_color=Arcadia.conf('treeitem.fill')
  end  
  
  def clear_tree
    @tree.delete(@tree.nodes('root'))
    @results.clear
  end
  
  def new_node_name
    @sequence = @sequence + 1
    return 'n'+@sequence.to_s
  end
  
  def new_result(_text, _length=0)
    @results.each_key{|key| @tree.close_tree(key)}
    _r_node = new_node_name
    @text_result = _text
    #_text = _text + ' { '+_length.to_s+' found }'
    #_length > 0 ? _color='#3f941b':_color = 'red'
    @tree.insert('end', 'root' ,_r_node, {
      'fill'=>@not_found_color,
      'open'=>true,
      'anchor'=>'w',
      'font' => "#{Arcadia.conf('treeitem.font')} bold",
      'text' =>  _text
    })
    Tk.update
    @results[_r_node]={}
    @count = 0
    @tree.set_focus
    return _r_node
  end
  
  def add_result(_node, _file, _line='', _line_text='')
    @count = @count+1
    @tree.itemconfigure(_node, 'fill'=>@found_color, 'text'=>@text_result+' { '+@count.to_s+' found }')
    _text = _file+':'+_line+' : '+_line_text
    _node_name = new_node_name
    @tree.insert('end', _node ,_node+'@@@'+_node_name, {
      'fill'=>@item_color,
      'anchor'=>'w',
      'font' => Arcadia.conf('treeitem.font'),
      'text' =>  _text.strip
    })
    @results[_node][_node_name]=[_file,_line]
    Tk.update
  end
  
end

class FindFrame < TkFloatTitledFrame
  attr_reader :e_what
  attr_reader :e_what_entry
  attr_reader :e_filter
  attr_reader :e_dir
  attr_reader :b_go
  def initialize(_parent)
    super(_parent)
    y0 = 10
    d = 23    
    TkLabel.new(self.frame, Arcadia.style('label')){
      text 'Find what:'
   	  place('x' => 8,'y' => y0,'height' => 19)
    }
    y0 = y0 + d
    @e_what = Tk::BWidget::ComboBox.new(self.frame, Arcadia.style('combobox')){
      editable true
      justify  'left'
      autocomplete 'true'
      expand 'tab'
      takefocus 'true'
      place('relwidth' => 1, 'width'=>-16,'x' => 8,'y' => y0,'height' => 19)
    }
    @e_what_entry = TkWinfo.children(@e_what)[0]
    @e_what_entry.bind_append("1",proc{Arcadia.process_event(InputEnterEvent.new(self,'receiver'=>@e_what_entry))})
    
    y0 = y0 + d
    TkLabel.new(self.frame, Arcadia.style('label')){
   	  text 'Files filter:'
   	  place('x' => 8,'y' => y0,'height' => 19)
    }
    y0 = y0 + d
   
    @e_filter = Tk::BWidget::ComboBox.new(self.frame, Arcadia.style('combobox')){
      editable true
      justify  'left'
      autocomplete 'true'
      expand 'tab'
      takefocus 'true'
      #pack('padx'=>10, 'fill'=>'x')
      place('relwidth' => 1, 'width'=>-16,'x' => 8,'y' => y0,'height' => 19)
    }
    @e_filter_entry = TkWinfo.children(@e_filter)[0]
    @e_filter_entry.bind_append("1",proc{Arcadia.process_event(InputEnterEvent.new(self,'receiver'=>@e_filter_entry))})

    @e_filter.text('*.rb')
    y0 = y0 + d

    TkLabel.new(self.frame, Arcadia.style('label')){
   	  text 'Directory:'
   	  place('x' => 8,'y' => y0,'height' => 19)
    }
    y0 = y0 + d

    _h_frame = TkFrame.new(self.frame, Arcadia.style('panel')).place('relwidth' => 1, 'width'=>-16,'x' => 8,'y' => y0,'height' => 19)
    @e_dir = Tk::BWidget::ComboBox.new(_h_frame, Arcadia.style('combobox')){
      editable true
      justify  'left'
      autocomplete 'true'
      expand 'tab'
      takefocus 'true'
      pack('fill'=>'x')
      #pack('fill'=>'x')
      #place('relwidth' => 1, 'width'=>-16,'x' => 8,'y' => y0,'height' => 19)
    }
    @e_dir.text(Dir.pwd)
    @b_dir = TkButton.new(@e_dir, Arcadia.style('button') ){
      compound  'none'
      default  'disabled'
      text  '...'
      pack('side'=>'right')
      #pack('side'=>'right','ipadx'=>5, 'padx'=>5)
    }.bind('1', proc{
         change_dir
         Tk.callback_break
    })
    
    y0 = y0 + d
    y0 = y0 + d
    @buttons_frame = TkFrame.new(self.frame, Arcadia.style('panel')).pack('fill'=>'x', 'side'=>'bottom')	

    @b_go = TkButton.new(@buttons_frame, Arcadia.style('button')){|_b_go|
      compound  'none'
      default  'disabled'
      text  'Find'
      #overrelief  'raised'
      #justify  'center'
      pack('side'=>'right','ipadx'=>5, 'padx'=>5)
    }
    place('x'=>100,'y'=>100,'height'=> 220,'width'=> 300)
  end

  def change_dir
    _d = Tk.chooseDirectory('initialdir'=>@e_dir.text,'mustexist'=>true)
    if _d && _d.strip.length > 0
      @e_dir.text(_d)
    end
  end
  
  def show
    super
    self.focus
    @e_what.focus
    @e_what_entry.selection_range(0,'end')
  end
end
