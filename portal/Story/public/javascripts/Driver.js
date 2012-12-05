function Driver(name) {
  var self = this;
  self.name = name;
  self.start = 0;
  self.end = 7;
  self.current = [];
  
  self.init = function () {
    $(window).off('resize');
    $(window).resize(function() {
      if(this.resizeTO) clearTimeout(this.resizeTO);
      this.resizeTO = setTimeout(function() {
        $(this).trigger('resizeEnd');
      }, 500);
    });
    $(window).off('resizeEnd');
    $(window).bind('resizeEnd', function () {
      self.resize();
    });
    $(document).off('keydown');
    $(document).keydown(function (e) {
      if (e.which == 39) self.right();
      if (e.which == 37) self.left();
    });
    $('#panel-left').off('click');
    $('#panel-left').click(function () {
      self.left();
    });
    $('#panel-right').off('click');
    $('#panel-right').click(function () {
      self.right();
    });
    $('#panel-top').empty();
    
    self.add_context(new CloudAll(self, self.name));
  };
  self.swap_context = function (c) {
    $('#panel-top').children().empty();
    self.current = [];
    self.add_context(c);
  };
  self.add_context = function (c) {
    var txt = (self.current.length == 0 ? ' ' : ' / ') + c.nav;
    var sz = (self.current.length == 0 ? 40 : 30)
    $('<span/>', {text : txt})
    .addClass('fake-link')
    .css('font-size', sz)
    .click(function () {
      self.remove_context(c);
    })
    .appendTo('#panel-top');
    
    self.current.push(c);
    self.resize();
  };
  
  self.remove_context = function (c) {
    while (self.current[self.current.length-1].nav != c.nav) {
      $('#panel-top').children().slice(self.current.length-1).detach();
      self.current.pop();
    }
    self.resize();
  };
  
  self.resize = function () {
    var panel = $("#panel");
    panel.empty();
    panel.css('width', $(window).width() - 195);
    panel.css('height', $(window).width() - 25);
    self.current[self.current.length-1].resize();
  }
  self.left = function () {
    self.current[self.current.length-1].left();
  }
  
  self.right = function () {
    self.current[self.current.length-1].right();
  }

  self.init();
}